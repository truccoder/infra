# SocialApp Infrastructure

Deploy backend (Spring Boot) + web-ui (Next.js).

**Production hiện tại:** VPS `3.105.195.84`, domain `https://elitenexus.id.vn` (HTTPS qua Caddy +
Let's Encrypt), MinIO sau proxy tại `files.elitenexus.id.vn`. Quy trình cắt domain / quay lui:
`docs/domain-cutover.md`.

## Architecture

```
                    Internet
                       │
                   ┌───▼───┐
                   │ Caddy  │  :80 / :443
                   │ Proxy  │
                   └───┬───┘
              ┌────────┴────────┐
         /v1/*│                 │ /*
        ┌─────▼─────┐   ┌──────▼──────┐
        │  Backend   │   │   Web UI    │
        │ :8080      │   │   :3000     │
        └─────┬──────┘   └─────────────┘
              │
    ┌─────────┼──────────┬──────────┬──────────┐
    │         │          │          │          │
┌───▼──┐ ┌───▼──┐ ┌─────▼─┐ ┌─────▼────┐ ┌───▼──┐
│Postgr│ │Redis │ │ Neo4j │ │OpenSearch│ │MinIO │
└──────┘ └──────┘ └───────┘ └──────────┘ └──────┘
```

**VPS**: Vietnix Cheap 2 — 2 vCPU, 4 GB RAM, 40 GB SSD

---

## Setup

### 1. Mua VPS Vietnix

Sau khi thanh toán, Vietnix gửi email chứa: **IP**, **username**, **password**.

### 2. Tạo GitHub PAT (cho GHCR)

GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token:
- Scope: `read:packages`, `write:packages`
- Copy token

### 3. Cấu hình GitHub Secrets

Thêm vào **cả 3 repo** (backend, web-ui, infra):

| Secret | Giá trị |
|---|---|
| `SERVER_IP` | `3.105.195.84` |
| `SERVER_USER` | `root` |
| `SERVER_PASSWORD` | Password của VPS |
| `GHCR_TOKEN` | GitHub PAT từ Step 2 |

Riêng repo **infra** cần thêm (xem `docker/.env.example` cho danh sách đầy đủ):

| Secret | Giá trị |
|---|---|
| `PUBLIC_BASE_URL` | `https://elitenexus.id.vn` |
| `PUBLIC_DOMAIN` | `elitenexus.id.vn` |
| `MINIO_PUBLIC_URL` | `https://files.elitenexus.id.vn` |
| `MINIO_PUBLIC_DOMAIN` | `files.elitenexus.id.vn` |

Web-ui **không** cần `NEXT_PUBLIC_API_URL` — frontend gọi API cùng origin qua Caddy (`/v1/*`), nên
build-arg đó để trống trong `.github/workflows/deploy.yml` của repo web-ui.

### 4. Deploy

Push lên `main` theo thứ tự:

1. **Repo infra** trước → cài Docker + upload docker-compose + start databases
2. **Repo backend** → build image + deploy
3. **Repo web-ui** → build image + deploy

Hoặc trigger thủ công: Actions → Deploy → Run workflow

### 5. Verify

Mở browser: `https://elitenexus.id.vn`

```bash
dig +short elitenexus.id.vn          # -> 3.105.195.84
dig +short files.elitenexus.id.vn    # -> 3.105.195.84
curl -I https://elitenexus.id.vn/v1/api/posts/public   # 200, chứng chỉ hợp lệ
```

---

## File Structure

```
infra/
├── docker/
│   ├── docker-compose.prod.yml  # All services
│   └── Caddyfile                # Reverse proxy routing
├── .github/
│   └── workflows/
│       └── deploy.yml           # Upload configs + restart
└── README.md
```

---

## CI/CD Flow

```
# Code changes (backend hoặc web-ui)
Push to main → Build Docker image (x86) → Push to GHCR → SSH deploy

# Config changes (infra)
Push to main → Upload docker-compose + Caddyfile → Restart services
```

---

## Useful Commands

```bash
# SSH vào server
ssh root@<SERVER_IP>

cd /opt/socialapp
docker compose -f docker-compose.prod.yml ps              # xem status
docker compose -f docker-compose.prod.yml logs -f backend  # xem logs
docker compose -f docker-compose.prod.yml restart backend  # restart 1 service
```

---

## Domain + HTTPS

Đã áp dụng — `elitenexus.id.vn` + `files.elitenexus.id.vn`. Địa chỉ site của Caddy và mọi URL
người dùng thấy đều dựng từ secrets (`PUBLIC_DOMAIN`, `PUBLIC_BASE_URL`, `MINIO_PUBLIC_*`), không
ghi cứng trong file nào. Đổi domain hoặc VPS, và cách quay lui: **`docs/domain-cutover.md`**.
