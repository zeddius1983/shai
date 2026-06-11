#!/usr/bin/env bash
# shai installer
#
# Usage:
#   Install:    bash setup.sh
#   Uninstall:  bash setup.sh --uninstall
#
#   Via curl:
#     curl -fsSL https://raw.githubusercontent.com/zeddius1983/shai/main/install.sh | bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }

step()  { printf '\n%s %s\n' "$(bold '==>')" "$*"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s\n' "$(green "✓ $*")"; }
warn()  { printf '    %s\n' "$(yellow "Warning: $*")"; }
die()   { printf '\n%s %s\n\n' "$(red 'Error:')" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

case "$(uname -s)" in
  Darwin|Linux) ;;
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
  sed "/# -- shai-toolbox: ${key} --/,/# -- end shai-toolbox: ${key} --/d" "$ZSHRC" > "$tmp"
  mv "$tmp" "$ZSHRC"
  info "Removed $key from ~/.zshrc"
}

# ---------------------------------------------------------------------------
# Install / Uninstall
# ---------------------------------------------------------------------------

install_shai() {
  step "Installing shai..."

  if ! command -v uv >/dev/null 2>&1; then
    info "uv not found — installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi

  local git_url="git+https://github.com/zeddius1983/shai.git"
  if [ -n "${REPO_URL:-}" ]; then
    if [[ "$REPO_URL" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(.+)$ ]]; then
      local owner="${BASH_REMATCH[1]}"
      local repo="${BASH_REMATCH[2]}"
      local ref="${BASH_REMATCH[3]}"
      git_url="git+https://github.com/${owner}/${repo}.git@${ref}"
      info "Installing from: $git_url"
    fi
  fi

  uv tool install "$git_url" --force --refresh
  export PATH="$(uv tool dir 2>/dev/null | sed 's|/tools$|/bin|'):$HOME/.local/bin:$PATH"

  local _shai_path
  _shai_path="$(command shai --shell-path zsh 2>/dev/null | xargs)"
  if [ -z "$_shai_path" ]; then
    warn "Could not determine shell integration path — add manually: source \"\$(shai --shell-path zsh)\""
  else
    _zshrc_remove "shai"
    _zshrc_add "shai" "source \"$_shai_path\""
  fi

  ok "shai installed"
}

install_shai_implicit() {
  local bind="${SHAI_IMPLICIT_BIND:-^@}"
  step "Installing implicit mode (Ctrl+Space → shai)..."
  _zshrc_remove "shai-implicit"
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
  ok "implicit mode installed"
}

uninstall_shai() {
  step "Uninstalling shai..."
  if command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null | grep -q "^shai "; then
    uv tool uninstall shai 2>/dev/null || true
    info "Removed shai (via uv)"
  fi
  _zshrc_remove "shai"
  ok "shai uninstalled"
}

uninstall_shai_implicit() {
  step "Uninstalling implicit mode..."
  _zshrc_remove "shai-implicit"
  ok "implicit mode uninstalled"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local uninstall=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --uninstall) uninstall=1 ;;
      *) die "Unknown argument: $1. Usage: setup.sh [--uninstall]" ;;
    esac
    shift
  done

  touch "$ZSHRC"

  if [ "$uninstall" -eq 1 ]; then
    uninstall_shai_implicit
    uninstall_shai
  else
    install_shai
    install_shai_implicit
  fi

  printf '\n%s\n\n' "$(green "$(bold '✓ Done!')")"
  printf 'Reload your shell:\n'
  printf '  %s\n\n' "$(bold "source $ZSHRC")"
}

main "$@"
