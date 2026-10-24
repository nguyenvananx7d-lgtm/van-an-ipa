#!/usr/bin/env bash
# One command to bring the TLS relay up on a VPS that already has this repo.
#   bash deploy/install-relay.sh [/opt/ffxc-auth]
# Idempotent: safe to re-run after a pull.
set -euo pipefail

ROOT="${1:-/opt/ffxc-auth}"
DOMAIN_VALUE="${DOMAIN:-}"

if [ ! -d "$ROOT" ]; then
  echo "repo not found at $ROOT" >&2
  echo "copy it first:  scp -r ffxc-auth root@<vps>:/opt/ffxc-auth" >&2
  exit 1
fi
cd "$ROOT"

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Docker missing, running the base VPS setup"
  bash deploy/install-vps.sh
fi

if [ ! -f .env ]; then
  touch .env
  echo "==> created $ROOT/.env"
fi

# Relay settings. The auth service reads the same file, so append only what is
# missing instead of rewriting someone's tuned values.
add_env() {
  key="$1"; value="$2"
  grep -q "^${key}=" .env || printf '%s=%s\n' "$key" "$value" >> .env
}

add_env RELAY_PORT 1299
add_env RELAY_ADMIN_PORT 8080
add_env RELAY_DATA_DIR data
add_env RELAY_PROFILE_NAME "Nimbus Relay"
if [ -n "$DOMAIN_VALUE" ]; then
  add_env RELAY_PUBLIC_HOST "$DOMAIN_VALUE"
elif ! grep -q '^RELAY_PUBLIC_HOST=' .env; then
  PUBLIC_IP="$(curl -fsS https://api.ipify.org || true)"
  add_env RELAY_PUBLIC_HOST "${PUBLIC_IP:-127.0.0.1}"
fi

# 1299 is the port the device's tunnel or Wi-Fi proxy dials; 8080 stays private
# behind Caddy and is only opened when someone wants LAN-only testing.
if command -v ufw >/dev/null 2>&1; then
  ufw allow 1299/tcp || true
fi

echo "==> building and starting"
docker compose -f deploy/docker-compose.yml up -d --build
echo
docker compose -f deploy/docker-compose.yml ps
echo

HOST_VALUE="$(grep '^RELAY_PUBLIC_HOST=' .env | tail -n1 | cut -d= -f2-)"
cat <<EOF
Relay is up.

  Profile (open in Safari on the phone):
    https://${HOST_VALUE}/relay/profile.mobileconfig

  Dashboard (rules are applied here, no restart):
    https://${HOST_VALUE}/relay/

  In the app, Setting -> Relay, enter:
    https://${HOST_VALUE}/relay

  Then on the phone: Settings -> General -> VPN & Device Management -> install,
  and Settings -> General -> About -> Certificate Trust Settings -> enable full trust.

  Proxy port for a tunnel: ${HOST_VALUE}:1299
EOF
