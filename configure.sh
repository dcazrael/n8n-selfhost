#!/usr/bin/env bash
set -euo pipefail

# Use /dev/tty for interactive prompts (works even when running via curl|bash)
PROMPT_FD=0
if [[ -r /dev/tty ]]; then
  exec 3</dev/tty
  PROMPT_FD=3
fi


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy"
ENV_FILE="$DEPLOY_DIR/.env"

mkdir -p "$DEPLOY_DIR"

prompt() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local secret="${4:-false}"
  local input=""

  if [[ "$secret" == "true" ]]; then
    if [[ -n "$default" ]]; then
      read -r -s -p "$label [$default]: " input
      echo
      input="${input:-$default}"
    else
      while [[ -z "$input" ]]; do
        read -r -s -p "$label: " input
        echo
      done
    fi
  else
    if [[ -n "$default" ]]; then
      read -r -p "$label [$default]: " input
      input="${input:-$default}"
    else
      read -r -p "$label: " input
    fi
  fi

  printf -v "$var_name" '%s' "$input"
}

yesno() {
  local label="$1"
  local default="${2:-y}" # y/n
  local input=""
  local def_show="y/N"
  [[ "$default" == "y" ]] && def_show="Y/n"

  while true; do
    read -r -p "$label ($def_show): " input
    input="${input:-$default}"
    case "$input" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) echo "Please enter y or n." ;;
    esac
  done
}

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d '\n'
  else
    head -c 32 /dev/urandom | base64 | tr -d '\n'
  fi
}

echo "== n8n self-host configurator =="

prompt N8N_VERSION "n8n version (must match runners tag)" "2.2.4"
prompt DOMAIN_NAME "Domain (without https://)" ""
prompt SUBDOMAIN "Subdomain" "n8n"
prompt SSL_EMAIL "Let's Encrypt email" ""
prompt GENERIC_TIMEZONE "Timezone" "Europe/Berlin"
prompt VM_PUBLIC_IP "VM public IP (optional, used only for DNS instructions)" ""

echo
echo "Docker volumes:"
prompt TRAEFIK_VOLUME "Traefik volume name (ACME storage)" "traefik_data"
prompt N8N_VOLUME "n8n data volume name" "n8n_data"
prompt REDIS_VOLUME "Redis data volume name" "redis_data"

echo
if yesno "Generate secrets automatically?" "y"; then
  N8N_ENCRYPTION_KEY="$(gen_secret)"
  N8N_RUNNERS_AUTH_TOKEN="$(gen_secret)"
  echo "OK: secrets generated."
else
  prompt N8N_ENCRYPTION_KEY "N8N_ENCRYPTION_KEY (secret)" "" "true"
  prompt N8N_RUNNERS_AUTH_TOKEN "N8N_RUNNERS_AUTH_TOKEN (secret)" "" "true"
fi

cat > "$ENV_FILE" <<EOF
# Versions
N8N_VERSION=$N8N_VERSION

# Domain / TLS
DOMAIN_NAME=$DOMAIN_NAME
SUBDOMAIN=$SUBDOMAIN
SSL_EMAIL=$SSL_EMAIL

# Timezone
GENERIC_TIMEZONE=$GENERIC_TIMEZONE

# Secrets
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_RUNNERS_AUTH_TOKEN=$N8N_RUNNERS_AUTH_TOKEN

# Volumes
TRAEFIK_VOLUME=$TRAEFIK_VOLUME
N8N_VOLUME=$N8N_VOLUME
REDIS_VOLUME=$REDIS_VOLUME
EOF

echo
echo "Written: $ENV_FILE"
echo
echo "DNS note:"
if [[ -n "${VM_PUBLIC_IP:-}" ]]; then
  echo "  Create/update an A record: ${SUBDOMAIN}.${DOMAIN_NAME} -> ${VM_PUBLIC_IP}"
else
  echo "  Create/update an A record: ${SUBDOMAIN}.${DOMAIN_NAME} -> <YOUR_VM_PUBLIC_IP>"
fi
echo "  TLS will fail until DNS points to the VM. Traefik will retry automatically once DNS is correct."
