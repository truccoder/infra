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
-- BA CỘT cần bước này, không phải một. Bản đầu của script chỉ xử lý t_users.profile_picture_url;
-- hai cột kia xuất hiện sau và im lặng nằm ngoài:
--
--     t_users.profile_picture_url   ProfileService
--     t_users.cover_image_url       ProfileService — cột thêm ở V68
--     t_posts.images                MediaService — MẢNG jsonb các URL tuyệt đối
--
-- Sách thì KHÔNG cần: t_books lưu object key chứ không lưu URL (đổi ở V44) và backend ký lại link
-- mỗi lần đọc, nên chúng tự bám theo cấu hình mới.
--
-- CÁCH CHẠY (cắt sang domain elitenexus.id.vn, 2026-08-31 — các hàng cũ trỏ về IP VPS trước đó):
--   psql "<chuỗi kết nối Supabase>" \
--     -v old_url="'http://14.225.217.4:9000'" \
--     -v new_url="'https://files.elitenexus.id.vn'" \
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
SELECT (SELECT count(*) FROM socialapp.t_users
         WHERE profile_picture_url LIKE :old_url || '%') AS anh_dai_dien,
       (SELECT count(*) FROM socialapp.t_users
         WHERE cover_image_url LIKE :old_url || '%')      AS anh_bia,
       (SELECT count(*) FROM socialapp.t_posts
         WHERE images::text LIKE '%' || :old_url || '%')  AS bai_co_anh,
       :old_url AS dia_chi_cu,
       :new_url AS dia_chi_moi;

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

UPDATE socialapp.t_users
   SET cover_image_url = :new_url || substring(cover_image_url from length(:old_url) + 1),
       updated_at = now()
 WHERE cover_image_url LIKE :old_url || '%';

-- t_posts.images là MẢNG jsonb, nên phải tháo ra, viết lại từng phần tử, rồi gom lại. Chạy
-- replace() trên cả chuỗi jsonb thì nhanh hơn nhưng cũng đụng vào tên object nào tình cờ chứa
-- địa chỉ cũ — cùng lý do đã tránh replace() ở trên.
UPDATE socialapp.t_posts p
   SET images = rewritten.arr,
       updated_at = now()
  FROM (
        SELECT t.id,
               jsonb_agg(
                   CASE WHEN img #>> '{}' LIKE :old_url || '%'
                        THEN to_jsonb(:new_url || substring(img #>> '{}' from length(:old_url) + 1))
                        ELSE img
                   END
                   ORDER BY ord
               ) AS arr
          FROM socialapp.t_posts t,
               LATERAL jsonb_array_elements(t.images) WITH ORDINALITY AS e(img, ord)
         WHERE t.images IS NOT NULL
           AND t.images::text LIKE '%' || :old_url || '%'
         GROUP BY t.id
       ) AS rewritten
 WHERE p.id = rewritten.id;

-- ── Bước 3: kiểm tra lại trước khi commit ───────────────────────────────────────────────────
-- Kỳ vọng: cả ba con số đều bằng 0.
SELECT (SELECT count(*) FROM socialapp.t_users
         WHERE profile_picture_url LIKE :old_url || '%') AS con_sot_anh_dai_dien,
       (SELECT count(*) FROM socialapp.t_users
         WHERE cover_image_url LIKE :old_url || '%')      AS con_sot_anh_bia,
       (SELECT count(*) FROM socialapp.t_posts
         WHERE images::text LIKE '%' || :old_url || '%')  AS con_sot_anh_bai_viet;

-- Hài lòng thì:
COMMIT;
-- Không hài lòng thì: ROLLBACK;
