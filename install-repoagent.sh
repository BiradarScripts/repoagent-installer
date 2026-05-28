#!/usr/bin/env bash

BASE_REPO_URL="https://github.corp.ebay.com/madhapatil/RepoAgent.git"
WORKSPACE_DIR="$HOME/repoagent-workspace"

__REPOAGENT_SOURCED=0

if [ -n "${ZSH_VERSION:-}" ]; then
  case "$ZSH_EVAL_CONTEXT" in
    *:file*) __REPOAGENT_SOURCED=1 ;;
  esac
elif [ -n "${BASH_VERSION:-}" ]; then
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    __REPOAGENT_SOURCED=1
  fi
fi

finish_script() {
  local code="$1"

  if [ "$__REPOAGENT_SOURCED" = "1" ]; then
    return "$code"
  else
    exit "$code"
  fi
}

fail() {
  echo "ERROR: $*" >&2
  return 1
}

run() {
  echo
  echo "+ $*"
  "$@"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is not installed"
}

read_from_terminal() {
  local prompt="$1"
  local value=""

  if [ -r /dev/tty ]; then
    echo "$prompt" > /dev/tty
    IFS= read -r value < /dev/tty
  else
    echo "$prompt"
    IFS= read -r value
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
    run git -C "$repo_dir" pull --ff-only || return 1
  elif [ -e "$repo_dir" ]; then
    fail "$repo_dir already exists but is not a Git repository" || return 1
  else
    echo
    echo "Cloning: $repo_url"
    run git clone "$repo_url" "$repo_dir" || return 1
  fi
}

same_directory() {
  local first="$1"
  local second="$2"
  local first_real
  local second_real

  [ -d "$first" ] || return 1
  [ -d "$second" ] || return 1

  first_real="$(cd "$first" && pwd -P)" || return 1
  second_real="$(cd "$second" && pwd -P)" || return 1

  [ "$first_real" = "$second_real" ]
}

ensure_repoagent_uses_workspace_venv() {
  local repoagent_dir="$1"
  local workspace_venv_dir="$2"
  local repoagent_venv="$repoagent_dir/.venv"

  echo
  echo "Making RepoAgent use the workspace root venv..."

  if [ -e "$repoagent_venv" ] || [ -L "$repoagent_venv" ]; then
    if same_directory "$repoagent_venv" "$workspace_venv_dir"; then
      echo "RepoAgent .venv already points to workspace venv."
      return 0
    fi

    local backup="$repoagent_dir/.venv.repoagent-backup-$(date +%Y%m%d%H%M%S)"
    echo "Moving existing RepoAgent .venv to:"
    echo "$backup"
    mv "$repoagent_venv" "$backup" || return 1
  fi

  ln -s "$workspace_venv_dir" "$repoagent_venv" || return 1

  echo "RepoAgent .venv now points to:"
  echo "$workspace_venv_dir"
}

create_python_wrapper_for_make_setup() {
  local wrapper_dir="$1"
  local workspace_venv_dir="$2"
  local venv_python="$workspace_venv_dir/bin/python3"

  mkdir -p "$wrapper_dir" || return 1

  cat > "$wrapper_dir/python3" <<EOF
#!/usr/bin/env bash

if [ "\${1:-}" = "-m" ] && [ "\${2:-}" = "venv" ] && [ "\${3:-}" = ".venv" ]; then
  exit 0
fi

exec "$venv_python" "\$@"
EOF

  chmod +x "$wrapper_dir/python3" || return 1

  rm -f "$wrapper_dir/python"
  ln -s "$wrapper_dir/python3" "$wrapper_dir/python" || return 1
}

main() {
  need_command git || return 1
  need_command python3 || return 1
  need_command make || return 1

  echo
  echo "Checking access to RepoAgent..."

  if ! git ls-remote "$BASE_REPO_URL" >/dev/null 2>&1; then
    echo
    echo "Could not access:"
    echo "$BASE_REPO_URL"
    echo
    echo "Make sure you are on eBay VPN/network and have GitHub Enterprise access."
    return 1
  fi

  CLIENT_REPO_URL="$(read_from_terminal 'Paste the client repo GitHub URL:')"
  CLIENT_REPO_URL="$(normalize_repo_url "$CLIENT_REPO_URL")"

  if [ -z "$CLIENT_REPO_URL" ]; then
    fail "Client repo URL cannot be empty" || return 1
  fi

  BASE_REPO_NAME="$(repo_name_from_url "$BASE_REPO_URL")"
  CLIENT_REPO_NAME="$(repo_name_from_url "$CLIENT_REPO_URL")"

  echo
  echo "Workspace:   $WORKSPACE_DIR"
  echo "Base repo:   $BASE_REPO_NAME"
  echo "Client repo: $CLIENT_REPO_NAME"

  mkdir -p "$WORKSPACE_DIR" || return 1
  cd "$WORKSPACE_DIR" || return 1

  WORKSPACE_ROOT="$(pwd)"
  WORKSPACE_VENV_DIR="$WORKSPACE_ROOT/.venv"
  WORKSPACE_VENV_ACTIVATE="$WORKSPACE_VENV_DIR/bin/activate"
  BASE_REPO_DIR="$WORKSPACE_ROOT/$BASE_REPO_NAME"
  CLIENT_REPO_DIR="$WORKSPACE_ROOT/$CLIENT_REPO_NAME"
  WRAPPER_DIR="$WORKSPACE_ROOT/.repoagent-wrapper-bin"

  clone_or_update_repo "$BASE_REPO_URL" "$BASE_REPO_NAME" || return 1
  clone_or_update_repo "$CLIENT_REPO_URL" "$CLIENT_REPO_NAME" || return 1

  echo
  echo "Creating workspace root venv..."

  if [ ! -f "$WORKSPACE_VENV_ACTIVATE" ]; then
    run python3 -m venv "$WORKSPACE_VENV_DIR" || return 1
  else
    echo "Workspace venv already exists:"
    echo "$WORKSPACE_VENV_DIR"
  fi

  echo
  echo "Activating workspace root venv..."
  . "$WORKSPACE_VENV_ACTIVATE" || return 1
  hash -r 2>/dev/null || true

  echo
  echo "Active venv:"
  echo "$VIRTUAL_ENV"

  echo
  echo "Upgrading pip tooling in workspace venv..."
  run python -m pip install --upgrade pip setuptools wheel || return 1

  ensure_repoagent_uses_workspace_venv "$BASE_REPO_DIR" "$WORKSPACE_VENV_DIR" || return 1
  create_python_wrapper_for_make_setup "$WRAPPER_DIR" "$WORKSPACE_VENV_DIR" || return 1

  echo
  echo "Entering RepoAgent..."
  cd "$BASE_REPO_DIR" || return 1

  echo
  echo "Running make setup in RepoAgent using workspace root venv..."
  PATH="$WRAPPER_DIR:$PATH" make setup || return 1

  echo
  echo "Re-activating workspace root venv..."
  . "$WORKSPACE_VENV_ACTIVATE" || return 1
  hash -r 2>/dev/null || true

  echo
  echo "Checking repo-warden..."
  run repo-warden --help || return 1

  echo
  echo "Going back to workspace root..."
  cd "$WORKSPACE_ROOT" || return 1

  echo
  echo "Entering client repo..."
  cd "$CLIENT_REPO_DIR" || return 1

  echo
  echo "Ready."
  echo "Current directory:"
  pwd
  echo
  echo "Active venv:"
  echo "$VIRTUAL_ENV"
  echo
  echo "Python:"
  command -v python
  echo
  echo "repo-warden:"
  command -v repo-warden
  echo

  return 0
}

main
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  finish_script "$STATUS"
fi

if [ "$__REPOAGENT_SOURCED" != "1" ]; then
  echo "Opening an interactive shell with the workspace venv still active..."
  exec "${SHELL:-/bin/zsh}" -i
fi
