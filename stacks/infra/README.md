# 🌐 Infrastructure Stack

Docker Compose stack untuk reverse proxy + auto-update.

## Services

| Service | Image | Purpose |
|---------|-------|---------|
| `traefik` | `traefik:v3.2` | Reverse proxy + TLS (Let's Encrypt) |
| `watchtower` | `containrrr/watchtower` | Auto-update container dengan label `com.centurylinklabs.watchtower.enable=true` |

## Deploy

```bash
cd /root/repos/atlas-platform/stacks/infra
cp .env.example .env
# edit .env
bash deploy.sh
```

## Environment Variables

| Var | Default | Keterangan |
|-----|---------|------------|
| `ACME_EMAIL` | `admin@example.com` | Email Let's Encrypt |
| `TRAEFIK_DASHBOARD_HOST` | `dash.localhost` | Host dashboard Traefik |
| `TRAEFIK_DASHBOARD_USER` | `admin` | Username dashboard |
| `TRAEFIK_DASHBOARD_PASS` | `change-me-now` | Password dashboard |

## Notes

- Dashboard hanya aktif kalau `TRAEFIK_DASHBOARD_HOST` resolve ke VPS.
- Gunakan UFW untuk buka port 80/443 kalau belum terbuka.
