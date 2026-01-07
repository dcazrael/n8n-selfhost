#!/usr/bin/env bash
set -euo pipefail

REPO_URL_DEFAULT="https://github.com/dcazrael/n8n-selfhost.git"
REF_DEFAULT="main"
INSTALL_DIR_DEFAULT="/opt/n8n-selfhost"

is_root() { [[ "$(id -u)" -eq 0 ]]; }

SUDO=""
if ! is_root; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: sudo is required when not running as root." >&2
    exit 1
  fi
fi

need_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: This installer currently supports Debian/Ubuntu (apt-get)." >&2
    exit 1
  fi
}

install_packages() {
  $SUDO apt-get update -y
  $SUDO apt-get install -y ca-certificates curl openssl micro git docker.io docker-compose-plugin
}

enable_docker() {
  $SUDO systemctl enable --now docker
}

# If we are running from a non-repo context (curl|bash), clone first.
bootstrap_clone_if_needed() {
  if [[ "${N8N_SELFHOST_LOCAL:-}" == "1" ]]; then
    return 0
  fi

  # Detect whether we are already in the repo by presence of deploy/docker-compose.yml
  if [[ -f "./deploy/docker-compose.yml" && -f "./configure.sh" ]]; then
    export N8N_SELFHOST_LOCAL=1
    return 0
  fi

  need_apt
  install_packages

  local repo_url="${REPO_URL:-$REPO_URL_DEFAULT}"
  local ref="${REF:-$REF_DEFAULT}"
  local install_dir="${INSTALL_DIR:-$INSTALL_DIR_DEFAULT}"

  echo "==> Cloning repo"
  echo "    Repo: $repo_url"
  echo "    Ref:  $ref"
  echo "    Dir:  $install_dir"

  $SUDO mkdir -p "$install_dir"
  $SUDO chown -R "$(id -u):$(id -g)" "$install_dir" || true

  if [[ -d "$install_dir/.git" ]]; then
    git -C "$install_dir" fetch --all --prune
    git -C "$install_dir" checkout "$ref"
    git -C "$install_dir" pull --ff-only || true
  else
    git clone --depth 1 --branch "$ref" "$repo_url" "$install_dir"
  fi

  echo "==> Re-running installer from cloned repo..."
  export N8N_SELFHOST_LOCAL=1
  exec bash "$install_dir/install.sh"
}

main_install() {
  need_apt
  install_packages
  enable_docker

  # Run configurator if .env is missing
  if [[ ! -f "./deploy/.env" ]]; then
    chmod +x ./configure.sh
    ./configure.sh
  fi

  # Load env
  set -a
  # shellcheck disable=SC1091
  source "./deploy/.env"
  set +a

  echo "==> Creating docker volumes..."
  $SUDO docker volume create "$TRAEFIK_VOLUME" >/dev/null
  $SUDO docker volume create "$N8N_VOLUME" >/dev/null
  $SUDO docker volume create "$REDIS_VOLUME" >/dev/null

  echo "==> Starting stack..."
  (cd deploy && $SUDO docker compose --env-file .env up -d)

  echo
  echo "Done"
  echo "n8n URL: https://$SUBDOMAIN.$DOMAIN_NAME"
  echo "Logs:    cd deploy && ./logs.sh"
}

bootstrap_clone_if_needed
main_install