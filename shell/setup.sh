#!/usr/bin/env bash
# Shai Toolbox — ZSH environment installer for shai
#
# Usage:
#   Install (installs shai and shai-implicit):
#     ./shell/setup.sh
#
#   Uninstall:
#     ./shell/setup.sh --uninstall
#
#   Via curl:
#     curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh | bash
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours & output helpers
# ---------------------------------------------------------------------------

bold()    { printf '\033[1m%s\033[0m' "$*"; }
green()   { printf '\033[32m%s\033[0m' "$*"; }
yellow()  { printf '\033[33m%s\033[0m' "$*"; }
red()     { printf '\033[31m%s\033[0m' "$*"; }
cyan()    { printf '\033[36m%s\033[0m' "$*"; }
dim()     { printf '\033[2m%s\033[0m' "$*"; }

step()  { printf '\n%s %s\n' "$(bold '==>')" "$*"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s\n' "$(green "✓ $*")"; }
warn()  { printf '    %s\n' "$(yellow "Warning: $*")"; }
die()   { printf '\n%s %s\n\n' "$(red 'Error:')" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

OS=""
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      OS="linux"
    else
      die "Only Debian/Ubuntu Linux is supported. Install packages manually."
    fi
    ;;
  *) die "Unsupported OS: $(uname -s)" ;;
esac

# ---------------------------------------------------------------------------
# .zshrc patching
# ---------------------------------------------------------------------------

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
_ZSHRC_BACKED_UP=0

_backup_zshrc() {
  if [ "$_ZSHRC_BACKED_UP" -eq 1 ]; then return; fi
  if [ -f "$ZSHRC" ]; then
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    cp -p "$ZSHRC" "$ZSHRC.$ts.bak"
    info "Created backup: $ZSHRC.$ts.bak"
  fi
  _ZSHRC_BACKED_UP=1
}

_zshrc_has() { grep -qF "shai-toolbox: $1" "$ZSHRC" 2>/dev/null; }

_zshrc_add() {
  local key="$1"; shift
  if _zshrc_has "$key"; then
    info "$(dim "~/.zshrc[$key] already present — skipping")"
    return
  fi
  _backup_zshrc
  {
    printf '\n# -- shai-toolbox: %s --\n' "$key"
    printf '%s\n' "$@"
    printf '# -- end shai-toolbox: %s --\n' "$key"
  } >> "$ZSHRC"
  info "Added $key to ~/.zshrc"
}

_zshrc_remove() {
  local key="$1"
  if ! _zshrc_has "$key"; then return; fi
  _backup_zshrc
  local tmp
  tmp="$(mktemp)"
  # Delete lines from start marker to end marker inclusive
  sed "/# -- shai-toolbox: ${key} --/,/# -- end shai-toolbox: ${key} --/d" "$ZSHRC" > "$tmp"
  mv "$tmp" "$ZSHRC"
  info "Removed $key from ~/.zshrc"
}

# ---------------------------------------------------------------------------
# Install / Uninstall actions
# ---------------------------------------------------------------------------

install_shai() {
  step "Installing shai..."
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi

  local git_url="git+https://github.com/zeddius1983/shell-assistant.git"
  if [ -n "${REPO_URL:-}" ]; then
    if [[ "$REPO_URL" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(.+)$ ]]; then
      local owner="${BASH_REMATCH[1]}"
      local repo="${BASH_REMATCH[2]}"
      local ref="${BASH_REMATCH[3]}"
      git_url="git+https://github.com/${owner}/${repo}.git@${ref}"
      info "Installing from custom git target: $git_url"
    fi
  fi

  uv tool install "$git_url" --force --refresh
  export PATH="$(uv tool dir 2>/dev/null | sed 's|/tools$|/bin|'):$HOME/.local/bin:$PATH"
  # Evaluate the shell script path at install time and trim whitespace
  # (some environments produce a leading newline from click.echo)
  local _shai_path
  _shai_path="$(command shai --shell-path zsh 2>/dev/null | xargs)"
  if [ -z "$_shai_path" ]; then
    warn "Could not determine shai shell integration path — add manually: source \"\$(shai --shell-path zsh)\""
  else
    _zshrc_add "shai" "source \"$_shai_path\""
  fi
  ok "shai installed"
}

uninstall_shai() {
  step "Uninstalling shai..."
  uv tool uninstall shai 2>/dev/null || true
  _zshrc_remove "shai"
  ok "shai uninstalled"
}

install_shai_implicit() {
  local bind="${SHAI_IMPLICIT_BIND:-^@}"

  step "Installing shai implicit mode (binding: $bind)..."
  _zshrc_add "shai-implicit" \
    "function _shai_implicit_mode() {" \
    "  if [[ -n \"\${BUFFER}\" ]]; then" \
    "    BUFFER=\"shai \${BUFFER}\"" \
    "    CURSOR=\${#BUFFER}" \
    "    zle accept-line" \
    "  fi" \
    "}" \
    "zle -N _shai_implicit_mode" \
    "bindkey '$bind' _shai_implicit_mode"
  ok "shai implicit mode installed"
}

uninstall_shai_implicit() {
  step "Uninstalling shai implicit mode..."
  _zshrc_remove "shai-implicit"
  ok "shai implicit mode uninstalled"
}

install_shai_docker() {
  local tag="$1"
  step "Installing shai via Docker (tag: $tag)..."

  # Verify docker/podman is available
  local container_bin=""
  if command -v docker >/dev/null 2>&1; then
    container_bin="docker"
  elif command -v podman >/dev/null 2>&1; then
    container_bin="podman"
  else
    die "Neither docker nor podman was found. Please install one of them before setting up the Docker version."
  fi

  # Determine default registry/image based on REPO_URL
  local registry="ghcr.io"
  local owner="zeddius1983"
  local repo="shai"
  if [ -n "${REPO_URL:-}" ]; then
    if [[ "$REPO_URL" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(.+)$ ]]; then
      owner="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]}"
    fi
  fi

  local image="${registry}/${owner}/${repo}:${tag}"
  info "Pulling Docker image: $image..."
  if ! "$container_bin" pull "$image"; then
    warn "Failed to pull image $image. It might not exist yet or you may need to docker login. Sourcing setup will pull it dynamically on first run."
  fi

  local docker_script="$HOME/.config/shai/shai-docker.sh"
  mkdir -p "$HOME/.config/shai"

  # Retrieve shai-docker.sh
  if [ -n "${REPO_URL:-}" ]; then
    info "Downloading shai-docker.sh from $REPO_URL/shell/shai-docker.sh..."
    if ! curl -sSLo "$docker_script" "$REPO_URL/shell/shai-docker.sh"; then
      die "Failed to download shai-docker.sh from $REPO_URL"
    fi
  else
    # Running locally or fallback
    local local_script="$(dirname "$0")/shai-docker.sh"
    if [ -f "$local_script" ]; then
      cp "$local_script" "$docker_script"
    else
      info "Downloading default shai-docker.sh..."
      if ! curl -sSLo "$docker_script" "https://raw.githubusercontent.com/zeddius1983/shai/main/shell/shai-docker.sh"; then
        die "Failed to download shai-docker.sh"
      fi
    fi
  fi
  chmod +x "$docker_script"

  # Patch .zshrc
  _zshrc_add "shai-docker" \
    "export SHAI_IMAGE=\"$image\"" \
    "source \"$docker_script\""

  ok "shai Docker version installed"
}

uninstall_shai_docker() {
  step "Uninstalling shai Docker version..."

  # Remove image if found in ZSHRC
  if [ -f "$ZSHRC" ]; then
    local image_to_remove
    image_to_remove=$(grep -oE "export SHAI_IMAGE=\"[^\"]+\"" "$ZSHRC" | cut -d'"' -f2 || true)
    if [ -n "$image_to_remove" ]; then
      local container_bin=""
      if command -v docker >/dev/null 2>&1; then
        container_bin="docker"
      elif command -v podman >/dev/null 2>&1; then
        container_bin="podman"
      fi
      if [ -n "$container_bin" ]; then
        step "Removing Docker image: $image_to_remove..."
        "$container_bin" rmi "$image_to_remove" || true
      fi
    fi
  fi

  _zshrc_remove "shai-docker"
  rm -f "$HOME/.config/shai/shai-docker.sh" 2>/dev/null || true
  ok "shai Docker version uninstalled"
}

uninstall_all() {
  uninstall_shai_implicit
  uninstall_shai
  uninstall_shai_docker
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local mode=""
  local tag="latest"
  local choice=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --uninstall) mode="uninstall" ;;
      --local) mode="local" ;;
      --docker) mode="docker" ;;
      --tag)
        shift
        tag="$1"
        ;;
    esac
    shift
  done

  # Touch ~/.zshrc if not present
  touch "$ZSHRC"

  # If no mode is specified, run interactively
  if [ -z "$mode" ]; then
    # Detect if any version is installed
    local installed=0
    if _zshrc_has "shai" || _zshrc_has "shai-implicit" || _zshrc_has "shai-docker" || command -v shai >/dev/null 2>&1; then
      installed=1
    fi

    echo "============================================="
    echo "       Shai Toolbox Installer Menu"
    echo "============================================="
    echo "Please select an option:"
    echo "  1) Install Shai locally (Requires uv/Python)"
    echo "  2) Install Shai via Docker/Podman"
    if [ "$installed" -eq 1 ]; then
      echo "  3) Uninstall Shai (Removes local & Docker versions)"
    else
      echo "  3) Uninstall Shai (Cleanup any leftovers)"
    fi
    echo "  4) Exit"
    echo "============================================="

    while true; do
      printf "Enter selection [1-4]: "
      if [ -t 0 ]; then
        read -r choice
      elif [ -c /dev/tty ]; then
        read -r choice < /dev/tty
      else
        die "Installer running in non-interactive environment without terminal. Please specify installation mode via arguments (--local, --docker, --uninstall)."
      fi

      case "$choice" in
        1) mode="local"; break ;;
        2) mode="docker"; break ;;
        3) mode="uninstall"; break ;;
        4) echo "Exiting."; exit 0 ;;
        *) echo "Invalid option. Please enter 1, 2, 3, or 4." ;;
      esac
    done
  fi

  if [ "$mode" = "uninstall" ]; then
    uninstall_all
  elif [ "$mode" = "local" ]; then
    install_shai
    install_shai_implicit
  elif [ "$mode" = "docker" ]; then
    # Prompt for docker tag if interactive, or use provided/default
    if [ "$tag" = "latest" ]; then
      # Only prompt if we run interactively (indicated by no arguments originally passed)
      if [ -n "${choice:-}" ]; then
        printf "Enter Docker image tag [default: latest]: "
        local user_tag=""
        if [ -t 0 ]; then
          read -r user_tag
        elif [ -c /dev/tty ]; then
          read -r user_tag < /dev/tty
        fi
        if [ -n "$user_tag" ]; then
          tag="$user_tag"
        fi
      fi
    fi
    install_shai_docker "$tag"
  fi

  printf '\n%s\n\n' "$(green "$(bold '✓ All done!')")"
  printf 'Reload your shell to apply changes:\n'
  printf '  %s\n\n' "$(bold "source $ZSHRC")"
}

main "$@"
