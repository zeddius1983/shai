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
  if command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null | grep -q "^shai "; then
    uv tool uninstall shai 2>/dev/null || true
    info "Deleted local Python tool: shai (via uv)"
  fi
  if _zshrc_has "shai"; then
    _zshrc_remove "shai"
    info "Removed local shell integration block from $ZSHRC"
  fi
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
  if _zshrc_has "shai-implicit"; then
    _zshrc_remove "shai-implicit"
    info "Removed implicit keybinding block from $ZSHRC"
  fi
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
        info "Removing Docker image: $image_to_remove..."
        if "$container_bin" rmi "$image_to_remove" 2>/dev/null; then
          info "Deleted Docker image: $image_to_remove"
        else
          info "Docker image $image_to_remove not found or already deleted from daemon"
        fi
      fi
    fi
  fi

  if _zshrc_has "shai-docker"; then
    _zshrc_remove "shai-docker"
    info "Removed Docker shell integration block from $ZSHRC"
  fi

  local docker_script="$HOME/.config/shai/shai-docker.sh"
  if [ -f "$docker_script" ]; then
    rm -f "$docker_script" 2>/dev/null || true
    info "Deleted Docker integration script: $docker_script"
  fi
  ok "shai Docker version uninstalled"
}

uninstall_all() {
  uninstall_shai_implicit
  uninstall_shai
  uninstall_shai_docker
}

_show_interactive_menu() {
  local installed="$1"
  local title="Shai Installer Menu"
  local uninstall_text="Uninstall Shai (Cleanup any leftovers)"
  if [ "$installed" -eq 1 ]; then
    uninstall_text="Uninstall Shai (Removes local & Docker versions)"
  fi

  local items=(
    "Install Shai locally (Requires uv/Python)"
    "Install Shai via Docker/Podman"
    "$uninstall_text"
    "Exit"
  )
  local num_items=${#items[@]}
  local cursor=0
  
  local TTY=""
  if true 2>/dev/null >/dev/tty && true 2>/dev/null </dev/tty; then
    TTY="/dev/tty"
  elif [ -t 0 ]; then
    TTY="stdin"
  else
    die "Installer running in non-interactive environment without terminal. Please specify installation mode via arguments (--local, --docker, --uninstall)."
  fi

  tui_print() {
    if [ "$TTY" = "/dev/tty" ]; then
      printf '%b' "$*" > /dev/tty
    else
      printf '%b' "$*"
    fi
  }

  tui_print_nl() {
    if [ "$TTY" = "/dev/tty" ]; then
      printf '%b\n' "$*" > /dev/tty
    else
      printf '%b\n' "$*"
    fi
  }

  # Hide cursor
  tui_print "\033[?25l"
  
  cleanup() {
    tui_print "\033[?25h"
  }
  trap cleanup EXIT

  # Initial print
  tui_print_nl ""
  tui_print_nl "  $(bold "$(cyan "$title")")"
  tui_print_nl "  $(dim "-------------------")"
  local i
  for ((i=0; i<num_items; i++)); do
    tui_print_nl ""
  done
  tui_print_nl "  $(dim "Use ↑/↓ or j/k to navigate, ENTER to select")"

  while true; do
    # Move cursor up to redraw items and help line
    tui_print "\033[$((num_items + 1))A"

    # Redraw items
    for ((i=0; i<num_items; i++)); do
      if [ "$i" -eq "$cursor" ]; then
        tui_print "\033[2K\r  $(cyan "$(bold "❯")")  $(cyan "$(bold "${items[$i]}")")\n"
      else
        tui_print "\033[2K\r     ${items[$i]}\n"
      fi
    done
    tui_print "\033[2K\r  $(dim "Use ↑/↓ or j/k to navigate, ENTER to select")\n"

    # Read keypress
    local char="" char2="" char3=""
    if [ "$TTY" = "/dev/tty" ]; then
      IFS= read -r -s -n1 char < /dev/tty
    else
      IFS= read -r -s -n1 char
    fi

    if [ "$char" = $'\033' ]; then
      if [ "$TTY" = "/dev/tty" ]; then
        IFS= read -r -s -n1 -t 0.1 char2 < /dev/tty || true
      else
        IFS= read -r -s -n1 -t 0.1 char2 || true
      fi
      if [ "$char2" = '[' ]; then
        if [ "$TTY" = "/dev/tty" ]; then
          IFS= read -r -s -n1 -t 0.1 char3 < /dev/tty || true
        else
          IFS= read -r -s -n1 -t 0.1 char3 || true
        fi
        case "$char3" in
          A) [ $cursor -gt 0 ] && cursor=$((cursor - 1)) ;;
          B) [ $cursor -lt $((num_items - 1)) ] && cursor=$((cursor + 1)) ;;
        esac
      fi
    elif [ "$char" = 'k' ]; then
      [ $cursor -gt 0 ] && cursor=$((cursor - 1))
    elif [ "$char" = 'j' ]; then
      [ $cursor -lt $((num_items - 1)) ] && cursor=$((cursor + 1))
    elif [ "$char" = $'\r' ] || [ "$char" = $'\n' ] || [ "$char" = '' ]; then
      break
    fi
  done

  # Show cursor
  tui_print "\033[?25h"
  trap - EXIT

  # Clear TUI lines from terminal
  tui_print "\033[2K\r"
  tui_print "\033[${num_items}A"
  for ((i=0; i<num_items; i++)); do
    tui_print "\033[2K\r\n"
  done
  tui_print "\033[$((num_items + 3))A"
  tui_print "\033[2K\r\n"
  tui_print "\033[2K\r\n"
  tui_print "\033[2K\r\n"
  tui_print "\033[3A"

  MENU_CHOICE=$((cursor + 1))
  return 0
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

    _show_interactive_menu "$installed"
    choice="$MENU_CHOICE"

    case "$choice" in
      1) mode="local" ;;
      2) mode="docker" ;;
      3) mode="uninstall" ;;
      4) echo "Exiting."; exit 0 ;;
      *) echo "Exiting."; exit 0 ;;
    esac
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
