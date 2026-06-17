#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "[!] .env belum ada. Copy dari .env.example dulu:"
  echo "    cp .env.example .env && nano .env"
  exit 1
fi

# shellcheck source=/dev/null
source .env

if [[ -z "${TRAEFIK_DASHBOARD_HOST:-}" || -z "${TRAEFIK_DASHBOARD_PASS:-}" ]]; then
  echo "[!] TRAEFIK_DASHBOARD_HOST dan TRAEFIK_DASHBOARD_PASS wajib di .env"
  exit 1
fi

# Generate htpasswd
USER="${TRAEFIK_DASHBOARD_USER:-admin}"
mkdir -p secrets
# Gunakan openssl buat htpasswd format bcrypt-ish (Traefik support md5,sha,bcrypt)
HASH="$(openssl passwd -apr1 "${TRAEFIK_DASHBOARD_PASS}")"
printf '%s:%s\n' "$USER" "$HASH" > secrets/htpasswd
chmod 600 secrets/htpasswd

# Update dynamic.yml dengan host dari env
sed -i "s/TRAEFIK_DASHBOARD_HOST_PLACEHOLDER/${TRAEFIK_DASHBOARD_HOST}/g" traefik/dynamic.yml 2>/dev/null || true

# Pull & run
docker compose pull
docker compose up -d --remove-orphans

echo "[✓] Infra stack deployed. Dashboard: https://${TRAEFIK_DASHBOARD_HOST}"
