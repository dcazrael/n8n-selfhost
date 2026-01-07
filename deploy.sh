#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/deploy"
ENV_FILE="$DEPLOY_DIR/.env"

# Colors
if [[ "${NO_COLOR:-}" == "1" ]] || [[ ! -t 1 ]]; then
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
else
  C_RESET="\033[0m"; C_BLUE="\033[34m"; C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"
fi
log_step(){ echo -e "${C_BLUE}==> $*${C_RESET}" >&2; }
log_ok(){   echo -e "${C_GREEN}OK: $*${C_RESET}" >&2; }
log_err(){  echo -e "${C_RED}ERROR: $*${C_RESET}" >&2; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

log_step "Repo: $SCRIPT_DIR"

# Ensure expected structure
[[ -f "$DEPLOY_DIR/docker-compose.yml" ]] || { log_err "Missing deploy/docker-compose.yml"; exit 1; }

chmod +x "$SCRIPT_DIR/configure.sh" "$DEPLOY_DIR/"*.sh 2>/dev/null || true

if [[ ! -f "$ENV_FILE" ]]; then
  log_step "No deploy/.env found. Running configurator"
  "$SCRIPT_DIR/configure.sh"
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

log_step "Creating docker volumes"
$SUDO docker volume create "$TRAEFIK_VOLUME" >/dev/null
$SUDO docker volume create "$N8N_VOLUME" >/dev/null
$SUDO docker volume create "$REDIS_VOLUME" >/dev/null

log_step "Starting stack"
(cd "$DEPLOY_DIR" && $SUDO docker compose --env-file .env up -d)

log_ok "Done"
echo "n8n URL: https://$SUBDOMAIN.$DOMAIN_NAME"
echo "Logs: cd $DEPLOY_DIR && ./logs.sh"
