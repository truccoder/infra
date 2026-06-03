# SocialApp Infrastructure — Vietnix VPS

Deploy backend (Spring Boot) + web-ui (Next.js) lên Vietnix VPS.

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
| `SERVER_IP` | IP từ email Vietnix |
| `SERVER_USER` | `root` |
| `SERVER_PASSWORD` | Password từ email Vietnix |
| `GHCR_TOKEN` | GitHub PAT từ Step 2 |

Thêm riêng cho **web-ui**:

| Secret | Giá trị |
|---|---|
| `NEXT_PUBLIC_API_URL` | `http://<SERVER_IP>` |

### 4. Deploy

Push lên `main` theo thứ tự:

1. **Repo infra** trước → cài Docker + upload docker-compose + start databases
2. **Repo backend** → build image + deploy
3. **Repo web-ui** → build image + deploy

Hoặc trigger thủ công: Actions → Deploy → Run workflow

### 5. Verify

Mở browser: `http://<SERVER_IP>`

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

## Nếu có Domain

1. Edit `docker/Caddyfile` — thay `:80` bằng domain name
2. Trỏ DNS A record về Server IP
3. Push lên main → CI/CD tự deploy (Caddy tự cấp HTTPS)
