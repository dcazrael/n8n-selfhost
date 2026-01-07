#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy"
ENV_FILE="$DEPLOY_DIR/.env"

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "==> No deploy/.env found. Running configurator..."
  "$ROOT_DIR/configure.sh"
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

echo "==> Creating docker volumes..."
$SUDO docker volume create "$TRAEFIK_VOLUME" >/dev/null
$SUDO docker volume create "$N8N_VOLUME" >/dev/null
$SUDO docker volume create "$REDIS_VOLUME" >/dev/null

echo "==> Starting stack..."
(cd "$DEPLOY_DIR" && $SUDO docker compose --env-file .env up -d)

echo
echo "Done"
echo "n8n URL: https://$SUBDOMAIN.$DOMAIN_NAME"
echo "Logs:    cd $DEPLOY_DIR && ./logs.sh"
