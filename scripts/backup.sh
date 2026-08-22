#!/usr/bin/env bash
#
# Sao lưu trạng thái có thể mất vĩnh viễn của deployment.
#
# Ba kho dữ liệu, ba mức rủi ro rất khác nhau:
#
#   Neo4j   — đồ thị bạn bè, và là NGUỒN SỰ THẬT của quan hệ bạn bè (Postgres chỉ giữ nhật ký
#             lời mời). Nằm trên docker volume của đúng một VPS.
#   MinIO   — toàn bộ ảnh đại diện, ảnh bìa và file sách người dùng đã tải lên. Cũng một volume,
#             cũng một VPS.
#   Postgres— nằm ở Supabase (được quản lý, có backup riêng theo gói dịch vụ). Vẫn dump ở đây vì
#             backup của gói miễn phí giữ rất ngắn, và vì phục hồi từ file của mình thì nhanh hơn
#             mở ticket.
#
# ⚠️ THƯ MỤC BACKUP MẶC ĐỊNH NẰM TRÊN CHÍNH MÁY CHỦ ĐÓ. Như vậy CHƯA phải sao lưu: hỏng ổ đĩa,
# xoá nhầm VPS, hay nhà cung cấp gặp sự cố là mất cả bản gốc lẫn bản sao. Đặt BACKUP_REMOTE để đẩy
# ra ngoài (xem cuối file) thì mới thành sao lưu thật.
#
# Cách chạy thủ công (trên máy chủ, sau khi workflow deploy của repo infra đã đẩy file lên):
#   bash /opt/socialapp/backup.sh
#
# Cách chạy hằng đêm (crontab -e trên máy chủ), 3 giờ sáng giờ Việt Nam:
#   0 3 * * *  bash /opt/socialapp/backup.sh >> /var/log/socialapp-backup.log 2>&1
#
# ─── PHỤC HỒI ────────────────────────────────────────────────────────────────────────────────
# Một bản sao lưu chưa từng phục hồi thử thì chưa biết có dùng được không. Hãy diễn tập một lần.
#
#   Neo4j (đổi tên bản cần phục hồi thành neo4j.dump trước — lệnh load tìm đúng tên đó):
#     docker compose -f docker-compose.prod.yml stop neo4j
#     docker run --rm --user root --entrypoint neo4j-admin \
#       -v socialapp_neo4j_data:/data -v /opt/socialapp/backups:/backups neo4j:5.20 \
#       database load neo4j --from-path=/backups --overwrite-destination=true
#     docker compose -f docker-compose.prod.yml start neo4j
#
#     Vòng dump rồi load này đã được chạy thử trọn vẹn một lần: dump một đồ thị có sẵn quan hệ,
#     load sang một volume trắng, khởi động lại và truy vấn thấy đúng các quan hệ ban đầu.
#
#   MinIO:
#     docker run --rm -v "$PWD/backups/minio-<ngày>:/restore" --network <mạng> minio/mc sh -c \
#       "mc alias set m http://minio:9000 \$USER \$PASS && mc mirror /restore/books m/books"
#
#   Postgres:
#     psql "<chuỗi kết nối Supabase>" < backups/postgres-<ngày>.sql
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Bố cục file khác nhau giữa repo và máy chủ, nên phải dò chứ không giả định.
#
# Trong repo:     docker/docker-compose.prod.yml, scripts/backup.sh
# Trên máy chủ:   mọi thứ nằm phẳng ở /opt/socialapp, vì bước scp trong workflow deploy của repo
#                 infra dùng `strip_components: 1` nên tiền tố thư mục bị cắt bỏ.
#
# Ghi cứng một trong hai đường dẫn nghĩa là script chạy được ở chỗ này và hỏng ở chỗ kia — mà nơi
# nó thật sự cần chạy là máy chủ.
if [ -f docker-compose.prod.yml ]; then
  ROOT_DIR="$PWD"                      # máy chủ: /opt/socialapp
  COMPOSE_FILE="docker-compose.prod.yml"
  ENV_FILE=".env"
elif [ -f ../docker/docker-compose.prod.yml ]; then
  ROOT_DIR="$(cd .. && pwd)"           # repo
  COMPOSE_FILE="docker/docker-compose.prod.yml"
  ENV_FILE="docker/.env"
else
  echo "Không tìm thấy docker-compose.prod.yml ở cả hai bố cục quen thuộc." >&2
  exit 1
fi
cd "$ROOT_DIR"

BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
STAMP="$(date +%Y%m%d-%H%M)"

# Đọc credential từ chính .env mà compose dùng, để không có bản sao thứ hai của mật khẩu.
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
fi

mkdir -p "$BACKUP_DIR"
echo "==> Sao lưu vào $BACKUP_DIR (giữ lại $RETENTION_DAYS ngày)"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

# ─── Neo4j ───────────────────────────────────────────────────────────────────────────────────
# neo4j-admin KHÔNG dump được database đang gắn vào một server đang chạy — đó là giới hạn của
# công cụ, không phải lựa chọn ở đây. Backup online là tính năng của bản Enterprise; bản Community
# thì phải dừng dịch vụ.
#
# Đánh đổi được chấp nhận có ý thức: khoảng 30 giây mà danh sách bạn bè và gợi ý kết bạn trả về
# lỗi, một lần mỗi đêm vào giờ thấp điểm. Phương án thay thế là chép volume trong lúc đang ghi,
# cho ra một bản sao có thể hỏng mà không ai biết cho tới lúc cần phục hồi — im lặng và tệ hơn nhiều.
echo "==> Neo4j (dừng dịch vụ khoảng 30 giây)"
NEO4J_VOLUME="$(compose ps -q neo4j | xargs -r docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}')"
if [ -z "$NEO4J_VOLUME" ]; then
  echo "    !! Không tìm thấy volume /data của neo4j, bỏ qua"
else
  compose stop neo4j
  # Dùng lại đúng image của service để phiên bản neo4j-admin khớp định dạng dữ liệu trên đĩa.
  #
  # `--user root --entrypoint neo4j-admin` là bắt buộc, không phải cho gọn.
  #
  # Entrypoint của image neo4j tự hạ quyền về user `neo4j` (uid 7474) kể cả khi container được
  # chạy bằng root, nên tiến trình dump không ghi được vào thư mục mount từ máy chủ (thư mục đó do
  # root tạo) và thất bại với `AccessDeniedException: /backups`. Gọi thẳng neo4j-admin để bỏ qua
  # đoạn hạ quyền đó. Đã thử đủ ba biến thể: không cờ nào thì hỏng, thêm mỗi `--user root` vẫn
  # hỏng, phải bỏ qua cả entrypoint mới chạy được.
  docker run --rm --user root --entrypoint neo4j-admin \
    -v "$NEO4J_VOLUME:/data" \
    -v "$BACKUP_DIR:/backups" \
    neo4j:5.20 \
    database dump neo4j --to-path=/backups --overwrite-destination=true
  # Dump ra tên cố định neo4j.dump; đổi tên để mỗi đêm là một bản riêng.
  mv "$BACKUP_DIR/neo4j.dump" "$BACKUP_DIR/neo4j-$STAMP.dump"
  compose start neo4j
  echo "    xong: neo4j-$STAMP.dump ($(du -h "$BACKUP_DIR/neo4j-$STAMP.dump" | cut -f1))"
fi

# ─── MinIO ───────────────────────────────────────────────────────────────────────────────────
# Không cần dừng: object storage ghi từng object một, nên bản mirror cùng lắm là thiếu file vừa
# được tải lên trong lúc chạy, chứ không bị hỏng file nào.
echo "==> MinIO"
NETWORK="$(compose ps -q minio | xargs -r docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$NETWORK" ]; then
  echo "    !! MinIO không chạy, bỏ qua"
else
  MINIO_OUT="$BACKUP_DIR/minio-$STAMP"
  mkdir -p "$MINIO_OUT"
  docker run --rm --network "$NETWORK" \
    -v "$MINIO_OUT:/backup" \
    --entrypoint sh minio/mc:latest -c "
      set -e
      mc alias set src http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' >/dev/null
      for bucket in profile-pictures books book-covers; do
        mc ls src/\$bucket >/dev/null 2>&1 || continue
        mc mirror --quiet --overwrite src/\$bucket /backup/\$bucket
      done
    "
  tar -C "$BACKUP_DIR" -czf "$MINIO_OUT.tar.gz" "minio-$STAMP"
  rm -rf "$MINIO_OUT"
  echo "    xong: minio-$STAMP.tar.gz ($(du -h "$MINIO_OUT.tar.gz" | cut -f1))"
fi

# ─── Postgres (Supabase) ─────────────────────────────────────────────────────────────────────
# Chỉ dump schema socialapp — phần còn lại của database là bảng nội bộ của Supabase, phục hồi
# được từ phía họ và không thuộc về ứng dụng này.
echo "==> Postgres"
if [ -z "${DB_PASSWORD:-}" ]; then
  echo "    !! Thiếu DB_PASSWORD trong $ENV_FILE, bỏ qua"
else
  # pg_dump chạy trong container để không phụ thuộc vào phiên bản client cài trên máy chủ; phiên
  # bản lệch nhau là lỗi "server version mismatch" rất hay gặp.
  docker run --rm -e PGPASSWORD="$DB_PASSWORD" postgres:16 \
    pg_dump \
      --host=aws-1-ap-south-1.pooler.supabase.com \
      --port=5432 \
      --username=postgres.rjauctcerrnmacrhaixx \
      --dbname=postgres \
      --schema=socialapp \
      --no-owner --no-privileges \
    > "$BACKUP_DIR/postgres-$STAMP.sql"
  gzip -f "$BACKUP_DIR/postgres-$STAMP.sql"
  echo "    xong: postgres-$STAMP.sql.gz ($(du -h "$BACKUP_DIR/postgres-$STAMP.sql.gz" | cut -f1))"
fi

# ─── Dọn bản cũ ──────────────────────────────────────────────────────────────────────────────
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'neo4j-*.dump' -o -name 'minio-*.tar.gz' -o -name 'postgres-*.sql.gz' \) \
  -mtime "+$RETENTION_DAYS" -print -delete

# ─── Đẩy ra ngoài máy chủ ────────────────────────────────────────────────────────────────────
# Đây là bước biến "một bản sao trên cùng cái đĩa sắp hỏng" thành sao lưu thật. Đặt BACKUP_REMOTE
# thành một đích của rclone (Google Drive, S3, Backblaze...) đã cấu hình sẵn trên máy chủ.
if [ -n "${BACKUP_REMOTE:-}" ]; then
  echo "==> Đồng bộ ra $BACKUP_REMOTE"
  rclone sync "$BACKUP_DIR" "$BACKUP_REMOTE" --stats-one-line
else
  echo "==> BACKUP_REMOTE chưa đặt — bản sao chỉ nằm trên chính máy chủ này."
  echo "    Mất máy chủ là mất luôn bản sao. Xem phần đầu file."
fi

echo "==> Hoàn tất."
