# Chuyển sang domain + HTTPS

> **Trạng thái: đã áp dụng (2026-08-31).** Deployment chạy trên VPS `3.105.195.84` với domain
> `elitenexus.id.vn` + HTTPS (Caddy tự cấp Let's Encrypt), và MinIO sau proxy tại
> `files.elitenexus.id.vn`. Các giá trị thật đến từ GitHub Secrets — xem "Secrets phải đặt" bên
> dưới. Tài liệu này giữ lại làm runbook cho lần cắt domain kế tiếp và cho việc quay lui.
>
> VPS trước đó: `14.225.217.4` (HTTP thuần, quyết định 2026-08-18, nay đã bỏ). Các hàng URL ảnh
> trong database vẫn còn trỏ về IP đó cho tới khi chạy bước viết lại ở dưới.

Trước khi cắt sang domain, deployment chạy HTTP thuần trên IP trần. Nghĩa là JWT, mật khẩu đăng
nhập và authorization code của OAuth đi qua mạng ở dạng đọc được — đó là lý do phải chuyển.

Một hệ quả đáng chú ý của việc không có domain: **chính sách OAuth của Google yêu cầu redirect URI
dùng `https://`, chỉ miễn trừ cho `http://localhost`.** Một URI dạng
`http://3.105.195.84/oauth/google/callback` thường bị Google Cloud Console từ chối khi đăng ký mới.
Có domain + HTTPS là cách duy nhất để đăng nhập bằng Google chạy được. GitHub cho phép `http://`
nên không vướng.

Toàn bộ hạ tầng đã được tham số hoá — không còn chỗ nào ghi cứng IP.
Việc còn lại là một quy trình có thứ tự, và **thứ tự là phần quan trọng nhất**: làm sai thứ tự thì
Caddy xin chứng chỉ thất bại rồi vào vòng lặp thử lại, hoặc người dùng nhận được link đặt lại mật
khẩu trỏ về địa chỉ không còn phục vụ.

## Secrets phải đặt (cả 3 repo hoặc riêng infra)

Trong repo **infra** (Settings → Secrets and variables → Actions):

| Secret | Giá trị |
|---|---|
| `SERVER_IP` | `3.105.195.84` |
| `SERVER_PASSWORD` | mật khẩu VPS mới |
| `PUBLIC_BASE_URL` | `https://elitenexus.id.vn` |
| `PUBLIC_DOMAIN` | `elitenexus.id.vn` |
| `MINIO_PUBLIC_URL` | `https://files.elitenexus.id.vn` |
| `MINIO_PUBLIC_DOMAIN` | `files.elitenexus.id.vn` |

Trong repo **backend** và **web-ui**: cập nhật `SERVER_IP` = `3.105.195.84` và `SERVER_PASSWORD`.
`NEXT_PUBLIC_API_URL` của web-ui để TRỐNG (frontend gọi API cùng origin qua Caddy) — không đổi.

## Việc phải làm trước

- Một tên miền bạn sở hữu và sửa được bản ghi DNS.
- Cổng 80 **và** 443 mở trên tường lửa VPS. Cổng 80 không được đóng kể cả sau khi có HTTPS —
  Let's Encrypt dùng nó cho thử thách xác thực, và mỗi lần gia hạn đều cần.
- Quyền sửa OAuth app trong Google Cloud Console và GitHub Developer Settings.

## Thứ tự

### 1. DNS trước tiên

Tạo bản ghi A trỏ domain về IP máy chủ, rồi **đợi cho tới khi phân giải được**:

```bash
dig +short elitenexus.id.vn
```

Phải trả về đúng IP máy chủ. Chưa đúng thì dừng ở đây. Caddy xin chứng chỉ bằng thử thách HTTP:
Let's Encrypt gọi ngược `http://<domain>/.well-known/acme-challenge/...`, nên DNS phải trỏ về máy
chủ trước. Chạy sớm chỉ tổ ăn rate limit của Let's Encrypt (5 lần thất bại mỗi giờ cho mỗi domain).

### 2. Đăng ký redirect URI mới, trước khi đổi cấu hình

Làm bước này **trước** bước 3, vì OAuth chấp nhận nhiều redirect URI cùng lúc. Thêm bản HTTPS mà
vẫn giữ bản HTTP cũ, thì trong lúc chuyển đổi không có khoảnh khắc nào đăng nhập bị hỏng.

Google Cloud Console → Credentials → OAuth 2.0 Client ID, thêm:

```
https://elitenexus.id.vn/oauth/google/callback
https://elitenexus.id.vn/v1/api/events/google/callback
```

GitHub → Settings → Developer settings → OAuth Apps, thêm:

```
https://elitenexus.id.vn/oauth/github/callback
https://elitenexus.id.vn/settings/github/callback
```

Hai đường dẫn GitHub phải là hai đường KHÁC NHAU. Một cái cho đăng nhập, một cái cho liên kết tài
khoản đã đăng nhập — code của GitHub chỉ dùng được một lần, nên dùng chung một callback thì luồng
đăng nhập tiêu mất code mà luồng liên kết đang cần (đây là lỗi B23a đã từng gặp).

### 3. Đổi cấu hình

**Đường chuẩn:** đặt/cập nhật các secret ở bảng "Secrets phải đặt" trong repo infra, rồi chạy
workflow **Deploy Infra Config** (Actions → Run workflow). Workflow dựng lại `/opt/socialapp/.env`
từ secrets, upload `docker-compose.prod.yml` + `Caddyfile` mới (đã bật khối MinIO), rồi
`docker compose up -d`. Bước kiểm tra cổng 80 ở cuối workflow phải xanh.

`MINIO_PUBLIC_DOMAIN` giờ nằm ở nhóm secret BẮT BUỘC của workflow — thiếu nó thì deploy dừng và
`.env` cũ được giữ nguyên (khối MinIO trong Caddyfile đã bật, một giá trị rỗng sẽ làm sập Caddy).

**Trên máy chủ (nếu sửa tay):**

```bash
cd /opt/socialapp
# .env phải có cả 4: PUBLIC_BASE_URL, PUBLIC_DOMAIN, MINIO_PUBLIC_URL, MINIO_PUBLIC_DOMAIN
docker compose -f docker-compose.prod.yml up -d caddy backend
docker compose -f docker-compose.prod.yml logs -f caddy
```

Nhật ký của Caddy phải hiện việc lấy chứng chỉ thành công cho **cả** `elitenexus.id.vn` lẫn
`files.elitenexus.id.vn`. Lần đầu mất khoảng vài chục giây.

Sau lần cắt domain đầu tiên, chạy một lần để MinIOBucketInitializer đặt lại policy public-read khi
Caddy đã sẵn sàng (lần chạy lúc backend khởi động thất bại vì Caddy chưa lên — chỉ log ERROR, không
fatal):

```bash
docker compose -f docker-compose.prod.yml restart backend
```

### 4. Kiểm tra

```bash
curl -I https://elitenexus.id.vn/v1/api/posts/public   # 200, và có chứng chỉ hợp lệ
curl -I http://elitenexus.id.vn                        # 308, chuyển hướng sang https
```

Kiểm tra thêm bằng tay, vì đây là những thứ curl không thấy:

- Đăng nhập bằng Google và bằng GitHub.
- Bấm "quên mật khẩu", mở mail, xác nhận link trong mail bắt đầu bằng `https://` và mở được.

### 5. Dọn redirect URI cũ

Sau khi mọi thứ chạy ổn định vài ngày, xoá các redirect URI `http://3.105.195.84/...` khỏi console
Google và GitHub. Để lại là giữ một đường vào qua HTTP thuần mà không ai để ý.

---

## MinIO sau proxy (đã bật trong lần cắt domain này)

Khối MinIO trong `docker/Caddyfile` đã được bỏ comment: MinIO phục vụ qua `files.elitenexus.id.vn`
thay vì cổng 9000 trần. Lý do phải làm cùng lúc với domain: trang chạy HTTPS, mà trình duyệt chặn
ảnh `http://` trên trang `https://` (mixed content) — để MinIO ở `http://<ip>:9000` là ảnh đại diện
vỡ hết.

**Bắt buộc dùng hostname riêng, không dùng đường dẫn con.** Presigned URL ký trên cả host lẫn
đường dẫn đầy đủ, nên thêm tiền tố `/files` là hỏng toàn bộ chữ ký, và link tải sách chết hết.

1. Thêm bản ghi A cho `files.elitenexus.id.vn` trỏ về `3.105.195.84` (cùng lúc với bản ghi cho
   `elitenexus.id.vn` ở bước 1).
2. Đặt secret `MINIO_PUBLIC_DOMAIN=files.elitenexus.id.vn` và `MINIO_PUBLIC_URL=https://files.elitenexus.id.vn`.
   Khối MinIO trong Caddyfile đã bật sẵn trong repo; workflow deploy ghi hai biến này vào `.env`.
3. **Viết lại URL ảnh đã lưu trong database** (3 cột: `t_users.profile_picture_url`,
   `t_users.cover_image_url`, `t_posts.images`). Bỏ qua bước này thì ảnh của mọi người dùng cũ
   thành ảnh vỡ — server không báo lỗi gì, vì server không phải bên đi tải ảnh. `old_url` là địa
   chỉ MinIO của VPS CŨ mà các hàng hiện đang trỏ tới:
   ```bash
   psql "<chuỗi kết nối Supabase>" \
     -v old_url="'http://14.225.217.4:9000'" \
     -v new_url="'https://files.elitenexus.id.vn'" \
     -f scripts/rewrite-minio-urls.sql
   ```
   Script chạy trong transaction, in ra số hàng sẽ đổi và vài ví dụ trước khi commit.
4. Xác nhận ảnh đại diện hiện được và link tải sách chạy qua hostname mới, rồi mới bỏ
   `ports: - "9000:9000"` khỏi service `minio` trong compose và `up -d minio caddy`. Cho tới lúc đó
   cổng 9000 giữ mở làm đường quay lui nhanh.

---

## Nếu phải quay lui

- **Ảnh MinIO hỏng qua hostname mới:** đổi `MINIO_PUBLIC_URL` về `http://3.105.195.84:9000` (cổng
  9000 vẫn mở), chạy lại `rewrite-minio-urls.sql` theo chiều ngược, `up -d backend`. Trang chính
  vẫn HTTPS; chỉ ảnh về HTTP tạm thời.
- **Toàn bộ domain:** đổi `PUBLIC_BASE_URL` và `PUBLIC_DOMAIN` về giá trị cũ, comment lại khối MinIO
  trong `Caddyfile` (hoặc gỡ secret `MINIO_PUBLIC_DOMAIN` — nhưng lúc đó phải comment khối, không
  thì Caddy sập), rồi `up -d caddy backend`. Redirect URI cũ vẫn còn đăng ký (nếu chưa làm bước 5)
  nên OAuth vẫn chạy. Chứng chỉ đã cấp nằm trong volume `caddy_data` — bật lại domain sau đó Caddy
  dùng lại, không xin mới.
