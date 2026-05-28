#!/usr/bin/env bash
set -e

BASE_REPO_URL="https://github.corp.ebay.com/madhapatil/RepoAgent.git"
WORKSPACE_DIR="$HOME/repoagent-workspace"
CORP_PYPI_URL="https://artifactory.corp.ebay.com/artifactory/api/pypi/pypi-coreai/simple"

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

open_final_shell() {
  local client_dir="$1"
  local workspace_venv_activate="$2"

  echo
  echo "Opening final shell in client repo with workspace venv active..."

  if command -v zsh >/dev/null 2>&1; then
    local zsh_dir
    zsh_dir="$(mktemp -d /tmp/repoagent-zsh-XXXXXX)"

    cat > "$zsh_dir/.zshrc" <<EOF
source "$workspace_venv_activate"
cd "$client_dir"
EOF

    exec env ZDOTDIR="$zsh_dir" zsh -i
  else
    local bash_rc
    bash_rc="$(mktemp /tmp/repoagent-bash-XXXXXX)"

    cat > "$bash_rc" <<EOF
source "$workspace_venv_activate"
cd "$client_dir"
EOF

    exec bash --rcfile "$bash_rc" -i
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
  WORKSPACE_VENV_DIR="$WORKSPACE_ROOT/.venv"
  WORKSPACE_VENV_ACTIVATE="$WORKSPACE_VENV_DIR/bin/activate"
  BASE_REPO_DIR="$WORKSPACE_ROOT/$BASE_REPO_NAME"
  CLIENT_REPO_DIR="$WORKSPACE_ROOT/$CLIENT_REPO_NAME"

  clone_or_update_repo "$BASE_REPO_URL" "$BASE_REPO_NAME"
  clone_or_update_repo "$CLIENT_REPO_URL" "$CLIENT_REPO_NAME"

  echo
  echo "Creating workspace-level virtual environment..."

  if [ ! -d "$WORKSPACE_VENV_DIR" ]; then
    run python3 -m venv "$WORKSPACE_VENV_DIR"
  else
    echo "Workspace venv already exists. Reusing:"
    echo "$WORKSPACE_VENV_DIR"
  fi

  echo
  echo "Activating workspace venv..."
  # shellcheck disable=SC1090
  source "$WORKSPACE_VENV_ACTIVATE"

  echo
  echo "Active venv:"
  echo "$VIRTUAL_ENV"

  echo
  echo "Upgrading workspace venv tooling..."
  run python -m pip install --upgrade pip setuptools wheel

  echo
  echo "Entering RepoAgent..."
  cd "$BASE_REPO_DIR"

  echo
  echo "Running make setup in RepoAgent..."
  run make setup

  echo
  echo "Re-activating workspace venv after make setup..."
  # shellcheck disable=SC1090
  source "$WORKSPACE_VENV_ACTIVATE"

  echo
  echo "Ensuring repo-warden is installed in workspace venv..."
  run python -m pip install -e . --extra-index-url "$CORP_PYPI_URL"

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
  echo "Active venv:"
  echo "$VIRTUAL_ENV"
  echo
  echo "repo-warden:"
  command -v repo-warden

  open_final_shell "$CLIENT_REPO_DIR" "$WORKSPACE_VENV_ACTIVATE"
}

main "$@"
