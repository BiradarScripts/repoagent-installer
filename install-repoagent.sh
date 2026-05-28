#!/usr/bin/env bash
set -e

BASE_REPO_URL="https://github.corp.ebay.com/madhapatil/RepoAgent.git"
WORKSPACE_DIR="$HOME/repoagent-workspace"

abort() {
  echo "ERROR: $*" >&2
  exit 1
}

run() {
  echo
  echo "+ $*"
  "$@" || abort "Command failed: $*"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || abort "$1 is not installed"
}

read_from_terminal() {
  local prompt="$1"
  local value

  if [ -r /dev/tty ]; then
    echo "$prompt" > /dev/tty
    read -r value < /dev/tty
  else
    echo "$prompt"
    read -r value
  fi

  printf "%s" "$value"
}

normalize_repo_url() {
  local url="${1%/}"
  url="${url%%/tree/*}"
  printf "%s" "$url"
}

repo_name_from_url() {
  local url
  url="$(normalize_repo_url "$1")"

  local name="${url##*/}"
  name="${name%.git}"

  printf "%s" "$name"
}

clone_or_update_repo() {
  local repo_url="$1"
  local repo_dir="$2"

  if [ -d "$repo_dir/.git" ]; then
    echo
    echo "Repo already exists. Updating: $repo_dir"
    run git -C "$repo_dir" pull --ff-only
  elif [ -e "$repo_dir" ]; then
    abort "$repo_dir already exists but is not a Git repository"
  else
    echo
    echo "Cloning: $repo_url"
    run git clone "$repo_url" "$repo_dir"
  fi
}

find_repoagent_venv() {
  local repoagent_dir="$1"

  if [ -f "$repoagent_dir/.venv/bin/activate" ]; then
    printf "%s" "$repoagent_dir/.venv/bin/activate"
    return 0
  fi

  local found
  found="$(find "$repoagent_dir" -maxdepth 5 -type f -path "*/bin/activate" 2>/dev/null | head -n 1 || true)"

  if [ -n "$found" ]; then
    printf "%s" "$found"
    return 0
  fi

  return 1
}

main() {
  need_command git
  need_command python3
  need_command make

  echo
  echo "Checking access to RepoAgent..."

  if ! git ls-remote "$BASE_REPO_URL" >/dev/null 2>&1; then
    echo
    echo "Could not access:"
    echo "$BASE_REPO_URL"
    echo
    echo "Make sure you are on eBay VPN/network and have GitHub Enterprise access."
    abort "RepoAgent access check failed"
  fi

  CLIENT_REPO_URL="$(read_from_terminal 'Paste the client repo GitHub URL:')"
  CLIENT_REPO_URL="$(normalize_repo_url "$CLIENT_REPO_URL")"

  if [ -z "$CLIENT_REPO_URL" ]; then
    abort "Client repo URL cannot be empty"
  fi

  BASE_REPO_NAME="$(repo_name_from_url "$BASE_REPO_URL")"
  CLIENT_REPO_NAME="$(repo_name_from_url "$CLIENT_REPO_URL")"

  echo
  echo "Workspace:   $WORKSPACE_DIR"
  echo "Base repo:   $BASE_REPO_NAME"
  echo "Client repo: $CLIENT_REPO_NAME"

  mkdir -p "$WORKSPACE_DIR"
  cd "$WORKSPACE_DIR"

  WORKSPACE_ROOT="$(pwd)"
  BASE_REPO_DIR="$WORKSPACE_ROOT/$BASE_REPO_NAME"
  CLIENT_REPO_DIR="$WORKSPACE_ROOT/$CLIENT_REPO_NAME"

  clone_or_update_repo "$BASE_REPO_URL" "$BASE_REPO_NAME"
  clone_or_update_repo "$CLIENT_REPO_URL" "$CLIENT_REPO_NAME"

  echo
  echo "Entering RepoAgent..."
  cd "$BASE_REPO_DIR"

  echo
  echo "Running make setup in RepoAgent..."
  run make setup

  echo
  echo "Finding RepoAgent virtual environment..."

  if ! VENV_ACTIVATE="$(find_repoagent_venv "$BASE_REPO_DIR")"; then
    abort "Could not find RepoAgent virtual environment after make setup"
  fi

  echo
  echo "Activating RepoAgent virtual environment..."
  # shellcheck disable=SC1090
  source "$VENV_ACTIVATE"

  echo
  echo "Checking repo-warden..."
  run repo-warden --help

  echo
  echo "Going back to workspace root..."
  cd "$WORKSPACE_ROOT"

  echo
  echo "Entering client repo..."
  cd "$CLIENT_REPO_DIR"

  echo
  echo "Ready."
  echo "Current directory:"
  pwd
  echo
  echo "Virtualenv:"
  echo "$VIRTUAL_ENV"
  echo
  echo "repo-warden:"
  command -v repo-warden

  exec "${SHELL:-/bin/zsh}" -i
}

main "$@"
