#!/usr/bin/env bash
set -euo pipefail

REPO_URL_DEFAULT="https://github.com/dcazrael/n8n-selfhost.git"
REF_DEFAULT="main"
INSTALL_DIR_DEFAULT="/opt/n8n-selfhost"

# Colors (whole line)
if [[ "${NO_COLOR:-}" == "1" ]] || [[ ! -t 1 ]]; then
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""
else
  C_RESET="\033[0m"; C_BLUE="\033[34m"; C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"; C_DIM="\033[2m"
fi
log_step(){ echo -e "${C_BLUE}==> $*${C_RESET}" >&2; }
log_ok(){   echo -e "${C_GREEN}OK: $*${C_RESET}" >&2; }
log_err(){  echo -e "${C_RED}ERROR: $*${C_RESET}" >&2; }
log_dim(){  echo -e "${C_DIM}$*${C_RESET}" >&2; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || { log_err "sudo not found"; exit 1; }
  SUDO="sudo"
fi

command -v apt-get >/dev/null 2>&1 || { log_err "apt-get not found (Debian/Ubuntu only)"; exit 1; }

# OS detection
# shellcheck disable=SC1091
source /etc/os-release
OS_ID="${ID:-}"
CODENAME="${VERSION_CODENAME:-}"
if [[ "$OS_ID" == "ubuntu" ]]; then
  CODENAME="${UBUNTU_CODENAME:-$CODENAME}"
fi

log_step "Updating base system & installing prerequisites"
$SUDO apt-get update -y
$SUDO apt-get upgrade -y
$SUDO apt-get install -y ca-certificates curl git openssl micro

log_step "Installing Docker (official apt repo)"
$SUDO apt-get remove -y docker.io docker-compose docker-doc podman-docker containerd runc >/dev/null 2>&1 || true
$SUDO install -m 0755 -d /etc/apt/keyrings

if [[ "$OS_ID" == "debian" ]]; then
  REPO_BASE="https://download.docker.com/linux/debian"
elif [[ "$OS_ID" == "ubuntu" ]]; then
  REPO_BASE="https://download.docker.com/linux/ubuntu"
else
  log_err "Unsupported OS: $OS_ID (expected debian or ubuntu)"
  exit 1
fi

$SUDO curl -fsSL "$REPO_BASE/gpg" -o /etc/apt/keyrings/docker.asc
$SUDO chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $REPO_BASE $CODENAME stable" \
  | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

$SUDO apt-get update -y
$SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
$SUDO systemctl enable --now docker >/dev/null 2>&1 || true

repo_url="${REPO_URL:-$REPO_URL_DEFAULT}"
ref="${REF:-$REF_DEFAULT}"
install_dir="${INSTALL_DIR:-$INSTALL_DIR_DEFAULT}"

log_step "Cloning repo"
log_dim  "Repo: $repo_url"
log_dim  "Ref:  $ref"
log_dim  "Dir:  $install_dir"

$SUDO mkdir -p "$install_dir"
$SUDO chown -R "$(id -u):$(id -g)" "$install_dir" >/dev/null 2>&1 || true

if [[ -d "$install_dir/.git" ]]; then
  git -C "$install_dir" fetch --all --prune --quiet
  git -C "$install_dir" checkout "$ref" --quiet
  git -C "$install_dir" pull --ff-only --quiet || true
else
  git clone --depth 1 --branch "$ref" "$repo_url" "$install_dir" --quiet
fi

log_step "Running deploy script"
exec bash -lc "cd '$install_dir' && chmod +x ./deploy.sh ./configure.sh ./deploy/*.sh && ./deploy.sh"
