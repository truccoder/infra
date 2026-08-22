-- =============================================================================================
-- Viết lại địa chỉ MinIO đã bị ghi cứng trong t_users.profile_picture_url.
--
-- CHẠY KHI: đổi MINIO_PUBLIC_URL — tức là khi chuyển sang domain, bật HTTPS, hoặc đưa MinIO ra
-- sau Caddy thay vì publish thẳng cổng 9000.
--
-- Vì sao cần: ProfileService ghép URL tuyệt đối tại thời điểm upload
--
--     ${minio.url}/profile-pictures/<object-key>
--
-- rồi lưu nguyên chuỗi đó vào database. Đổi cấu hình chỉ ảnh hưởng tới ảnh upload SAU đó; những
-- hàng đã có vẫn trỏ về địa chỉ cũ. Nếu địa chỉ cũ không còn phục vụ, toàn bộ ảnh đại diện của
-- người dùng cũ thành ảnh vỡ — và không có gì báo lỗi ở phía server, vì server không phải là bên
-- đi tải ảnh đó.
--
-- Chỉ ảnh đại diện cần bước này. Sách và ảnh bìa lưu OBJECT KEY chứ không lưu URL (xem V44), và
-- link được ký lại mỗi lần đọc, nên chúng tự bám theo cấu hình mới.
--
-- CÁCH CHẠY:
--   psql "<chuỗi kết nối Supabase>" \
--     -v old_url="'http://14.225.217.4:9000'" \
--     -v new_url="'https://files.socialapp.example.com'" \
--     -f scripts/rewrite-minio-urls.sql
--
-- Không có dấu / ở cuối mỗi giá trị, vì phần sau nó luôn bắt đầu bằng `/profile-pictures/`.
-- =============================================================================================

\if :{?old_url}
\else
  \echo 'Thiếu tham số. Xem hướng dẫn ở đầu file.'
  \quit
\endif

BEGIN;

-- ── Bước 1: xem trước sẽ đụng vào bao nhiêu hàng ────────────────────────────────────────────
-- Đọc con số này trước khi commit. Bằng 0 nghĩa là old_url không khớp gì cả — thường là do gõ sai
-- cổng hoặc thừa dấu / ở cuối, chứ không phải vì không có ảnh nào.
SELECT count(*) AS so_hang_se_doi,
       :old_url AS dia_chi_cu,
       :new_url AS dia_chi_moi
  FROM socialapp.t_users
 WHERE profile_picture_url LIKE :old_url || '%';

-- Vài ví dụ, để mắt thường xác nhận phần đuôi giữ nguyên.
SELECT id,
       profile_picture_url AS truoc,
       :new_url || substring(profile_picture_url from length(:old_url) + 1) AS sau
  FROM socialapp.t_users
 WHERE profile_picture_url LIKE :old_url || '%'
 LIMIT 5;

-- ── Bước 2: viết lại ────────────────────────────────────────────────────────────────────────
-- Dùng substring theo độ dài tiền tố chứ không dùng replace(): replace() thay MỌI lần xuất hiện
-- của chuỗi cũ ở bất kỳ đâu trong giá trị, kể cả khi nó tình cờ nằm trong tên object.
UPDATE socialapp.t_users
   SET profile_picture_url = :new_url || substring(profile_picture_url from length(:old_url) + 1),
       updated_at = now()
 WHERE profile_picture_url LIKE :old_url || '%';

-- ── Bước 3: kiểm tra lại trước khi commit ───────────────────────────────────────────────────
-- Kỳ vọng: 0 hàng còn mang địa chỉ cũ.
SELECT count(*) AS con_sot_dia_chi_cu
  FROM socialapp.t_users
 WHERE profile_picture_url LIKE :old_url || '%';

-- Hài lòng thì:
COMMIT;
-- Không hài lòng thì: ROLLBACK;
