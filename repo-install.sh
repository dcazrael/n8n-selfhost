#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy"
ENV_FILE="$DEPLOY_DIR/.env"

# --- Colors (disable by setting NO_COLOR=1) ---
if [[ "${NO_COLOR:-}" == "1" ]] || [[ ! -t 1 ]]; then
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""
else
  C_RESET="\033[0m"
  C_BLUE="\033[34m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_RED="\033[31m"
  C_DIM="\033[2m"
fi

# Whole-line colored logs, always to STDERR (so command substitution stays clean)
log_step() { echo -e "${C_BLUE}==> $*${C_RESET}" >&2; }
log_ok()   { echo -e "${C_GREEN}OK: $*${C_RESET}" >&2; }
log_warn() { echo -e "${C_YELLOW}WARN: $*${C_RESET}" >&2; }
log_err()  { echo -e "${C_RED}ERROR: $*${C_RESET}" >&2; }
log_dim()  { echo -e "${C_DIM}$*${C_RESET}" >&2; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  log_step "No deploy/.env found. Running configurator"
  "$ROOT_DIR/configure.sh"
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

echo
log_ok "Done"
echo "n8n URL: https://$SUBDOMAIN.$DOMAIN_NAME"
echo "Logs:    cd $DEPLOY_DIR && ./logs.sh"
