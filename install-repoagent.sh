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

  # If someone pastes a GitHub browser URL like /tree/main, remove that part
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

activate_repoagent_venv_if_found() {
  local repoagent_dir="$1"

  if [ -f "$repoagent_dir/.venv/bin/activate" ]; then
    echo
    echo "Activating RepoAgent virtual environment..."
    # shellcheck disable=SC1090
    source "$repoagent_dir/.venv/bin/activate"
    echo "Active venv: $VIRTUAL_ENV"
  elif [ -f "$WORKSPACE_DIR/.venv/bin/activate" ]; then
    echo
    echo "Activating workspace virtual environment..."
    # shellcheck disable=SC1090
    source "$WORKSPACE_DIR/.venv/bin/activate"
    echo "Active venv: $VIRTUAL_ENV"
  else
    echo
    echo "No .venv found after make setup. Continuing with current shell environment."
  fi
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
    echo "Make sure you are on eBay network/VPN and have GitHub Enterprise access."
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

  clone_or_update_repo "$BASE_REPO_URL" "$BASE_REPO_NAME"
  clone_or_update_repo "$CLIENT_REPO_URL" "$CLIENT_REPO_NAME"

  echo
  echo "Entering RepoAgent..."
  cd "$WORKSPACE_ROOT/$BASE_REPO_NAME"

  echo
  echo "Running RepoAgent setup..."
  run make setup

  activate_repoagent_venv_if_found "$WORKSPACE_ROOT/$BASE_REPO_NAME"

  echo
  echo "Checking repo-warden..."
  run repo-warden --help

  echo
  echo "Going back to workspace root..."
  cd "$WORKSPACE_ROOT"

  echo
  echo "Entering client repo..."
  cd "$WORKSPACE_ROOT/$CLIENT_REPO_NAME"

  echo
  echo "Done."
  echo "You are now inside the client repo:"
  pwd

  if [ -n "${VIRTUAL_ENV:-}" ]; then
    echo
    echo "Virtual environment is active:"
    echo "$VIRTUAL_ENV"
  fi

  echo
  echo "Opening shell here..."
  exec "${SHELL:-/bin/bash}"
}

main "$@"
