#!/usr/bin/env bash
set -euo pipefail

REPO_URL_DEFAULT="https://github.com/dcazrael/n8n-selfhost.git"
REF_DEFAULT="main"
INSTALL_DIR_DEFAULT="/opt/n8n-selfhost"

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

is_root() { [[ "$(id -u)" -eq 0 ]]; }

SUDO=""
if ! is_root; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    log_err "sudo is required when not running as root."
    exit 1
  fi
fi

need_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log_err "This installer supports Debian/Ubuntu (apt-get) only."
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
  $SUDO apt-get install -y ca-certificates curl git openssl micro
}

remove_conflicting_docker_pkgs() {
  # Ignore errors if packages do not exist
  $SUDO apt-get remove -y docker.io docker-compose docker-doc podman-docker containerd runc >/dev/null 2>&1 || true
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
    log_err "Unsupported OS: $OS_ID (expected debian or ubuntu)."
    exit 1
  fi

  $SUDO curl -fsSL "$repo_base/gpg" -o /etc/apt/keyrings/docker.asc
  $SUDO chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $repo_base $codename stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
}

install_docker_engine() {
  $SUDO apt-get update -y
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
}

clone_repo() {
  local repo_url="${REPO_URL:-$REPO_URL_DEFAULT}"
  local ref="${REF:-$REF_DEFAULT}"
  local install_dir="${INSTALL_DIR:-$INSTALL_DIR_DEFAULT}"

  log_step "Cloning repo"
  log_dim  "Repo: $repo_url"
  log_dim  "Ref:  $ref"
  log_dim  "Dir:  $install_dir"

  $SUDO mkdir -p "$install_dir" >/dev/null
  $SUDO chown -R "$(id -u):$(id -g)" "$install_dir" >/dev/null 2>&1 || true

  if [[ -d "$install_dir/.git" ]]; then
    git -C "$install_dir" fetch --all --prune --quiet
    git -C "$install_dir" checkout "$ref" --quiet
    git -C "$install_dir" pull --ff-only --quiet || true
  else
    git clone --depth 1 --branch "$ref" "$repo_url" "$install_dir" --quiet
  fi

  # ONLY the path on stdout
  printf '%s\n' "$install_dir"
}



run_repo_entrypoint() {
  local install_dir="$1"
  log_step "Running repo installer"
  exec bash -lc "cd '$install_dir' && chmod +x ./repo-install.sh ./configure.sh ./deploy/*.sh && ./repo-install.sh"
}

need_apt
load_os_release

log_step "Updating base system & installing prerequisites"
apt_update_upgrade
install_prereqs

log_step "Installing Docker from official Docker apt repository"
remove_conflicting_docker_pkgs
setup_docker_apt_repo
install_docker_engine

INSTALL_DIR="$(clone_repo)"
run_repo_entrypoint "$INSTALL_DIR"
