#!/usr/bin/env bash

BASE_REPO_URL="https://github.corp.ebay.com/madhapatil/RepoAgent.git"
WORKSPACE_DIR="$HOME/repoagent-workspace"

abort() {
  echo "ERROR: $*" >&2
  return 1 2>/dev/null || exit 1
}

run() {
  echo
  echo "+ $*"
  "$@" || abort "Command failed: $*"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || abort "$1 is not installed"
}

repo_name_from_url() {
  local url="${1%/}"
  local name="${url##*/}"
  name="${name%.git}"
  printf "%s" "$name"
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

main() {
  need_command git
  need_command python3

  CLIENT_REPO_URL="$(read_from_terminal 'Paste the client repo GitHub URL:')"

  if [ -z "$CLIENT_REPO_URL" ]; then
    abort "Client repo URL cannot be empty"
  fi

  BASE_REPO_NAME="$(repo_name_from_url "$BASE_REPO_URL")"
  CLIENT_REPO_NAME="$(repo_name_from_url "$CLIENT_REPO_URL")"

  echo
  echo "Workspace:   $WORKSPACE_DIR"
  echo "Base repo:   $BASE_REPO_NAME"
  echo "Client repo: $CLIENT_REPO_NAME"

  mkdir -p "$WORKSPACE_DIR" || abort "Could not create workspace directory"
  cd "$WORKSPACE_DIR" || abort "Could not enter workspace directory"

  WORKSPACE_ROOT="$(pwd)"

  clone_or_update_repo "$BASE_REPO_URL" "$BASE_REPO_NAME"
  clone_or_update_repo "$CLIENT_REPO_URL" "$CLIENT_REPO_NAME"

  echo
  echo "Setting up virtual environment..."

  if [ ! -d ".venv" ]; then
    run python3 -m venv .venv
  else
    echo ".venv already exists. Reusing it."
  fi

  # shellcheck disable=SC1091
  source "$WORKSPACE_ROOT/.venv/bin/activate" || abort "Could not activate virtual environment"

  echo
  echo "Virtual environment activated:"
  echo "$VIRTUAL_ENV"

  echo
  echo "Installing RepoAgent base repository..."

  cd "$WORKSPACE_ROOT/$BASE_REPO_NAME" || abort "Could not enter base repo"

  run python -m pip install --upgrade pip setuptools wheel
  run python -m pip install -e .
  run repo-warden --help

  echo
  echo "Moving to client repo..."

  cd "$WORKSPACE_ROOT/$CLIENT_REPO_NAME" || abort "Could not enter client repo"

  echo
  echo "Done."
  echo "Current directory:"
  pwd
  echo
  echo "Python:"
  which python
}

IS_SOURCED=0
if [ -n "$BASH_VERSION" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  IS_SOURCED=1
fi

main "$@"
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  if [ "$IS_SOURCED" -eq 1 ]; then
    return "$STATUS"
  else
    exit "$STATUS"
  fi
fi

if [ "$IS_SOURCED" -eq 0 ]; then
  echo
  echo "Opening a shell here so you stay inside the client repo with venv active..."
  exec "${SHELL:-/bin/bash}"
fi
