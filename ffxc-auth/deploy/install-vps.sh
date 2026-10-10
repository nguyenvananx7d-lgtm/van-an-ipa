#!/usr/bin/env bash
# One-shot VPS setup for ffxc-auth (Ubuntu / Debian).
# Run as root:  bash install-vps.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo bash install-vps.sh)" >&2
  exit 1
fi

echo "==> Installing Docker + Compose plugin"
apt-get update -y
apt-get install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

echo "==> Opening ports 80/443 (and keeping SSH)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  yes | ufw enable || true
fi

echo
echo "Docker : $(docker --version)"
echo "Compose: $(docker compose version)"
echo
echo "Next steps:"
echo "  1) copy this project to /opt/ffxc-auth  (scp -r ffxc-auth root@<VPS-IP>:/opt/ffxc-auth)"
echo "  2) edit /opt/ffxc-auth/.env  -> set ADMIN_TOKEN and DOMAIN=auth.yourdomain.com"
echo "  3) cd /opt/ffxc-auth && docker compose -f deploy/docker-compose.yml up -d --build"
