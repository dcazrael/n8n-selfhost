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

load_os_release() {
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID:-}"
  OS_CODENAME="${VERSION_CODENAME:-}"
  UBUNTU_CODENAME_FALLBACK="${UBUNTU_CODENAME:-}"
}

apt_update_upgrade() {
  $SUDO apt-get update -y
  $SUDO apt-get upgrade -y
}

install_prereqs() {
  # Keep this list small and boring; add only what we actually need.
  # git is required for bootstrap clone. openssl for secret generation.
  $SUDO apt-get install -y ca-certificates curl git openssl micro
}

remove_conflicting_docker_pkgs() {
  # Per Docker docs: remove unofficial packages that can conflict. :contentReference[oaicite:1]{index=1}
  # Don't fail if some packages aren't installed.
  $SUDO apt-get remove -y \
    docker.io docker-compose docker-doc podman-docker containerd runc 2>/dev/null || true
}

setup_docker_apt_repo() {
  $SUDO install -m 0755 -d /etc/apt/keyrings

  local repo_base=""
  local codename=""

  if [[ "$OS_ID" == "debian" ]]; then
    repo_base="https://download.docker.com/linux/debian"
    codename="$OS_CODENAME"
  elif [[ "$OS_ID" == "ubuntu" ]]; then
    repo_base="https://download.docker.com/linux/ubuntu"
    codename="${UBUNTU_CODENAME_FALLBACK:-$OS_CODENAME}"
  else
    echo "ERROR: Unsupported OS ID: $OS_ID (expected debian or ubuntu)." >&2
    exit 1
  fi

  $SUDO curl -fsSL "$repo_base/gpg" -o /etc/apt/keyrings/docker.asc
  $SUDO chmod a+r /etc/apt/keyrings/docker.asc

  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $repo_base $codename stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
}

install_docker_engine() {
  apt_update_upgrade
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  $SUDO systemctl enable --now docker
}

# If we are running via curl|bash, clone first and rerun locally.
bootstrap_clone_if_needed() {
  if [[ "${N8N_SELFHOST_LOCAL:-}" == "1" ]]; then
    return 0
  fi

  if [[ -f "./deploy/docker-compose.yml" && -f "./configure.sh" ]]; then
    export N8N_SELFHOST_LOCAL=1
    return 0
  fi

  need_apt
  load_os_release

  echo "==> Updating base system & installing prerequisites..."
  apt_update_upgrade
  install_prereqs

  echo "==> Installing Docker from official Docker apt repository..."
  remove_conflicting_docker_pkgs
  setup_docker_apt_repo
  install_docker_engine

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
  load_os_release

  echo "==> Updating base system & installing prerequisites..."
  apt_update_upgrade
  install_prereqs

  echo "==> Installing Docker from official Docker apt repository..."
  remove_conflicting_docker_pkgs
  setup_docker_apt_repo
  install_docker_engine

  # Run configurator if .env is missing
  if [[ ! -f "./deploy/.env" ]]; then
    echo "==> No deploy/.env found. Running configurator..."
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
  echo "✅ Done"
  echo "n8n URL: https://$SUBDOMAIN.$DOMAIN_NAME"
  echo "Logs:    cd deploy && ./logs.sh"
}

bootstrap_clone_if_needed
main_install
