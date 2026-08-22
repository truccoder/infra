# Chuyển sang domain + HTTPS

> **Trạng thái: chưa áp dụng.** Dự án đã quyết định (2026-08-18) giữ HTTP trên IP trần, không dùng
> domain. Tài liệu này để dành cho lúc quyết định đó thay đổi — hạ tầng đã tham số hoá sẵn nên
> không phải sửa lại 10 chỗ, chỉ điền hai biến rồi làm theo thứ tự dưới đây.

Hiện deployment chạy HTTP thuần trên IP trần `14.225.217.4`. Nghĩa là JWT, mật khẩu đăng nhập và
authorization code của OAuth đi qua mạng ở dạng đọc được.

Một hệ quả đáng chú ý của việc không có domain: **chính sách OAuth của Google yêu cầu redirect URI
dùng `https://`, chỉ miễn trừ cho `http://localhost`.** Một URI dạng
`http://14.225.217.4/oauth/google/callback` thường bị Google Cloud Console từ chối khi đăng ký mới.
Nếu đăng nhập bằng Google đang không hoạt động trên deployment này, đó nhiều khả năng là nguyên
nhân, và cách sửa duy nhất là có domain + HTTPS. GitHub cho phép `http://` nên không vướng.

Toàn bộ hạ tầng đã được tham số hoá sẵn cho việc chuyển đổi này — không còn chỗ nào ghi cứng IP.
Việc còn lại là một quy trình có thứ tự, và **thứ tự là phần quan trọng nhất**: làm sai thứ tự thì
Caddy xin chứng chỉ thất bại rồi vào vòng lặp thử lại, hoặc người dùng nhận được link đặt lại mật
khẩu trỏ về địa chỉ không còn phục vụ.

## Việc phải làm trước

- Một tên miền bạn sở hữu và sửa được bản ghi DNS.
- Cổng 80 **và** 443 mở trên tường lửa VPS. Cổng 80 không được đóng kể cả sau khi có HTTPS —
  Let's Encrypt dùng nó cho thử thách xác thực, và mỗi lần gia hạn đều cần.
- Quyền sửa OAuth app trong Google Cloud Console và GitHub Developer Settings.

## Thứ tự

### 1. DNS trước tiên

Tạo bản ghi A trỏ domain về IP máy chủ, rồi **đợi cho tới khi phân giải được**:

```bash
dig +short socialapp.example.com
```

Phải trả về đúng IP máy chủ. Chưa đúng thì dừng ở đây. Caddy xin chứng chỉ bằng thử thách HTTP:
Let's Encrypt gọi ngược `http://<domain>/.well-known/acme-challenge/...`, nên DNS phải trỏ về máy
chủ trước. Chạy sớm chỉ tổ ăn rate limit của Let's Encrypt (5 lần thất bại mỗi giờ cho mỗi domain).

### 2. Đăng ký redirect URI mới, trước khi đổi cấu hình

Làm bước này **trước** bước 3, vì OAuth chấp nhận nhiều redirect URI cùng lúc. Thêm bản HTTPS mà
vẫn giữ bản HTTP cũ, thì trong lúc chuyển đổi không có khoảnh khắc nào đăng nhập bị hỏng.

Google Cloud Console → Credentials → OAuth 2.0 Client ID, thêm:

```
https://socialapp.example.com/oauth/google/callback
https://socialapp.example.com/v1/api/events/google/callback
```

GitHub → Settings → Developer settings → OAuth Apps, thêm:

```
https://socialapp.example.com/oauth/github/callback
https://socialapp.example.com/settings/github/callback
```

Hai đường dẫn GitHub phải là hai đường KHÁC NHAU. Một cái cho đăng nhập, một cái cho liên kết tài
khoản đã đăng nhập — code của GitHub chỉ dùng được một lần, nên dùng chung một callback thì luồng
đăng nhập tiêu mất code mà luồng liên kết đang cần (đây là lỗi B23a đã từng gặp).

### 3. Đổi cấu hình trên máy chủ

Sửa `/opt/socialapp/.env`:

```
PUBLIC_BASE_URL=https://socialapp.example.com
PUBLIC_DOMAIN=socialapp.example.com
```

Rồi áp dụng:

```bash
cd /opt/socialapp
docker compose -f docker-compose.prod.yml up -d caddy backend
docker compose -f docker-compose.prod.yml logs -f caddy
```

Nhật ký của Caddy phải hiện việc lấy chứng chỉ thành công. Lần đầu mất khoảng vài chục giây.

### 4. Kiểm tra

```bash
curl -I https://socialapp.example.com/v1/api/posts/public   # 200, và có chứng chỉ hợp lệ
curl -I http://socialapp.example.com                        # 308, chuyển hướng sang https
```

Kiểm tra thêm bằng tay, vì đây là những thứ curl không thấy:

- Đăng nhập bằng Google và bằng GitHub.
- Bấm "quên mật khẩu", mở mail, xác nhận link trong mail bắt đầu bằng `https://` và mở được.

### 5. Dọn redirect URI cũ

Sau khi mọi thứ chạy ổn định vài ngày, xoá các redirect URI `http://14.225.217.4/...` khỏi console
Google và GitHub. Để lại là giữ một đường vào qua HTTP thuần mà không ai để ý.

---

## Bước tuỳ chọn: đưa MinIO ra sau proxy

Việc này **không bắt buộc** để có HTTPS, và nên làm thành một lần riêng sau khi domain đã ổn định.

Hiện MinIO publish thẳng cổng 9000. Chỉ bucket `profile-pictures` là public-read (ảnh đại diện,
vốn đã công khai trong sản phẩm); sách và ảnh bìa là private, phát qua presigned URL. Nên việc mở
cổng này không phải lỗ hổng — nhưng nó là một cổng HTTP thuần còn sót lại sau khi phần còn lại đã
lên HTTPS.

**Bắt buộc dùng hostname riêng, không dùng đường dẫn con.** Presigned URL ký trên cả host lẫn
đường dẫn đầy đủ, nên thêm tiền tố `/files` là hỏng toàn bộ chữ ký, và link tải sách chết hết.

1. Thêm bản ghi A cho `files.socialapp.example.com` trỏ về cùng IP.
2. Bỏ comment khối MinIO trong `docker/Caddyfile`, và đặt trong `.env`:
   ```
   MINIO_PUBLIC_DOMAIN=files.socialapp.example.com
   MINIO_PUBLIC_URL=https://files.socialapp.example.com
   ```
3. **Viết lại URL ảnh đại diện đã lưu trong database.** Đây là bước hay bị quên, và bỏ qua nó thì
   ảnh đại diện của mọi người dùng cũ thành ảnh vỡ — server không báo lỗi gì, vì server không phải
   bên đi tải ảnh:
   ```bash
   psql "<chuỗi kết nối Supabase>" \
     -v old_url="'http://14.225.217.4:9000'" \
     -v new_url="'https://files.socialapp.example.com'" \
     -f scripts/rewrite-minio-urls.sql
   ```
   Script chạy trong transaction, in ra số hàng sẽ đổi và vài ví dụ trước khi commit.
4. Bỏ `ports: - "9000:9000"` khỏi service `minio` trong compose, rồi `up -d minio caddy`.
5. Kiểm tra: mở một hồ sơ có ảnh đại diện, và bấm tải thử một cuốn sách đã mua.

---

## Nếu phải quay lui

Đổi `PUBLIC_BASE_URL` và `PUBLIC_DOMAIN` trong `.env` về giá trị cũ rồi `up -d caddy backend`.
Redirect URI cũ vẫn còn đăng ký (nếu chưa làm bước 5), nên OAuth vẫn chạy. Chứng chỉ đã cấp không
mất đi đâu — bật lại domain sau đó Caddy dùng lại chứng chỉ trong volume `caddy_data`, không phải
xin mới.
