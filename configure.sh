#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy"
ENV_FILE="$DEPLOY_DIR/.env"

mkdir -p "$DEPLOY_DIR"

# Make interactive prompts work even when run via: curl ... | bash
# If stdin is not a TTY, rebind stdin to /dev/tty.
if [[ ! -t 0 ]]; then
  if [[ -r /dev/tty ]]; then
    exec </dev/tty
  else
    echo "ERROR: No TTY available for interactive configuration." >&2
    echo "Run ./configure.sh from an interactive SSH terminal." >&2
    exit 1
  fi
fi

echo "== n8n self-host configurator ==" >&2
echo >&2

prompt() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local required="${4:-false}"
  local secret="${5:-false}"

  local input=""

  while true; do
    if [[ "$secret" == "true" ]]; then
      if [[ -n "$default" ]]; then
        read -r -s -p "$label [$default]: " input || true
        echo >&2
        input="${input:-$default}"
      else
        read -r -s -p "$label: " input || true
        echo >&2
      fi
    else
      if [[ -n "$default" ]]; then
        read -r -p "$label [$default]: " input || true
        input="${input:-$default}"
      else
        read -r -p "$label: " input || true
      fi
    fi

    if [[ "$required" == "true" && -z "$input" ]]; then
      echo "This value is required." >&2
      continue
    fi

    printf -v "$var_name" '%s' "$input"
    return 0
  done
}

yesno() {
  local label="$1"
  local default="${2:-y}" # y/n
  local input=""
  local def_show="y/N"
  [[ "$default" == "y" ]] && def_show="Y/n"

  while true; do
    read -r -p "$label ($def_show): " input || true
    input="${input:-$default}"
    case "$input" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) echo "Please enter y or n." >&2 ;;
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

prompt N8N_VERSION "n8n version (must match runners tag)" "2.2.4" false false
prompt DOMAIN_NAME "Domain (without https://)" "" true false
prompt SUBDOMAIN "Subdomain" "n8n" true false
prompt SSL_EMAIL "Let's Encrypt email" "" true false
prompt GENERIC_TIMEZONE "Timezone" "Europe/Berlin" false false
prompt VM_PUBLIC_IP "VM public IP (optional, only for DNS hint)" "" false false

echo >&2
echo "Docker volumes:" >&2
prompt TRAEFIK_VOLUME "Traefik volume name (ACME storage)" "traefik_data" true false
prompt N8N_VOLUME "n8n data volume name" "n8n_data" true false
prompt REDIS_VOLUME "Redis data volume name" "redis_data" true false

echo >&2
if yesno "Generate secrets automatically?" "y"; then
  N8N_ENCRYPTION_KEY="$(gen_secret)"
  N8N_RUNNERS_AUTH_TOKEN="$(gen_secret)"
  echo "OK: secrets generated." >&2
else
  prompt N8N_ENCRYPTION_KEY "N8N_ENCRYPTION_KEY (secret)" "" true true
  prompt N8N_RUNNERS_AUTH_TOKEN "N8N_RUNNERS_AUTH_TOKEN (secret)" "" true true
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

echo >&2
echo "Written: $ENV_FILE" >&2
echo >&2
echo "DNS note:" >&2
if [[ -n "${VM_PUBLIC_IP:-}" ]]; then
  echo "  Create/update an A record: ${SUBDOMAIN}.${DOMAIN_NAME} -> ${VM_PUBLIC_IP}" >&2
else
  echo "  Create/update an A record: ${SUBDOMAIN}.${DOMAIN_NAME} -> <YOUR_VM_PUBLIC_IP>" >&2
fi
echo "  TLS will fail until DNS points to the VM. Traefik will retry automatically once DNS is correct." >&2
