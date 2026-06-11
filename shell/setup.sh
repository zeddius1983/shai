#!/usr/bin/env bash
# Shai Toolbox — cross-platform ZSH environment installer
#
# Usage:
#   Interactive (pick what to install):
#     ./shell/setup.sh
#
#   Silent — install everything:
#     ./shell/setup.sh --all
#     SETUP_SILENT=1 bash ./shell/setup.sh
#
#   Via curl (silent):
#     curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/shell/setup.sh | bash -s -- --all

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
# Package manager helpers
# ---------------------------------------------------------------------------

_ensure_brew() {
  if command -v brew >/dev/null 2>&1; then return; fi
  step "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session
  if [ -x "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

_brew() {
  local to_install=""
  for pkg in "$@"; do
    if ! brew ls --versions "$pkg" >/dev/null 2>&1; then
      to_install="$to_install $pkg"
    fi
  done
  if [ -n "$to_install" ]; then
    # shellcheck disable=SC2086
    brew install $to_install 2>/dev/null || true
  fi
}

_apt_update_done=0
_apt() {
  local to_install=""
  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      to_install="$to_install $pkg"
    fi
  done
  if [ -n "$to_install" ]; then
    if [ "$_apt_update_done" -eq 0 ]; then
      sudo apt-get update -q
      _apt_update_done=1
    fi
    # shellcheck disable=SC2086
    sudo apt-get install -y --no-install-recommends $to_install
  fi
}

_uninstall_pkg() {
  step "Uninstalling package: $*"
  case "$OS" in
    mac) brew uninstall "$@" 2>/dev/null || true ;;
    linux) sudo apt-get remove -y "$@" 2>/dev/null || true ;;
  esac
}

_add_apt_repo() {
  local name="$1" key_url="$2" repo_line="$3" list_file="$4"
  if [ -f "$list_file" ]; then return; fi
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL "$key_url" | gpg --dearmor | sudo tee /etc/apt/keyrings/"${name}".gpg >/dev/null
  echo "$repo_line" | sudo tee "$list_file" >/dev/null
  _apt_update_done=0   # force re-update after adding repo
}

# ---------------------------------------------------------------------------
# .zshrc idempotent patching
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
# Install functions — one per component
# ---------------------------------------------------------------------------

install_shai() {
  step "Installing shai..."
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi
  uv tool install "git+https://github.com/zeddius1983/shell-assistant.git" --force --refresh
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
  local bind="${SHAI_IMPLICIT_BIND:-}"
  if [ -z "$bind" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      printf "  %s " "$(cyan "Enter keybinding for shai implicit mode [default: ^@ (Ctrl+Space)]:")"
      read -r bind </dev/tty
    fi
    [ -z "$bind" ] && bind="^@"
  fi

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

install_starship() {
  step "Installing starship..."
  case "$OS" in
    mac)   _ensure_brew; _brew starship ;;
    linux) curl -sS https://starship.rs/install.sh | sh -s -- --yes ;;
  esac
  _zshrc_add "starship" 'eval "$(starship init zsh)"'
  # Copy starship.toml
  local toml_src
  toml_src="$(cd "$(dirname "$0")" && pwd)/starship.toml"
  if [ -f "$toml_src" ]; then
    mkdir -p "$HOME/.config"
    cp "$toml_src" "$HOME/.config/starship.toml"
    info "Copied starship.toml → ~/.config/starship.toml"
  else
    warn "starship.toml not found next to setup.sh — skipping config copy"
  fi
  ok "starship installed"
}

uninstall_starship() {
  step "Uninstalling starship..."
  if [ "$OS" = "mac" ]; then
    _uninstall_pkg starship
  else
    sudo rm -f /usr/local/bin/starship
  fi
  rm -f "$HOME/.config/starship.toml"
  _zshrc_remove "starship"
  ok "starship uninstalled"
}

install_eza() {
  step "Installing eza..."
  case "$OS" in
    mac) _ensure_brew; _brew eza ;;
    linux)
      _add_apt_repo "gierens" \
        "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" \
        "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        "/etc/apt/sources.list.d/gierens.list"
      _apt eza
      ;;
  esac
  _zshrc_add "eza" \
    "alias ls='eza --icons --group-directories-first'" \
    "alias ll='eza --icons --group-directories-first -l --git'" \
    "alias la='eza --icons --group-directories-first -la --git'" \
    "alias lt='eza --icons --tree --level=2'" \
    "alias lta='eza --icons --tree --level=2 -a'"
  ok "eza installed"
}

uninstall_eza() {
  step "Uninstalling eza..."
  _uninstall_pkg eza
  _zshrc_remove "eza"
  ok "eza uninstalled"
}

install_bat() {
  step "Installing bat..."
  case "$OS" in
    mac) _ensure_brew; _brew bat ;;
    linux)
      _apt bat
      # Ubuntu names it batcat; create symlink
      if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
      fi
      ;;
  esac
  _zshrc_add "bat" \
    "alias cat='bat'" \
    "alias less='bat'"
  ok "bat installed"
}

uninstall_bat() {
  step "Uninstalling bat..."
  _uninstall_pkg bat batcat
  sudo rm -f /usr/local/bin/bat
  _zshrc_remove "bat"
  ok "bat uninstalled"
}

install_delta() {
  step "Installing git-delta..."
  case "$OS" in
    mac) _ensure_brew; _brew git-delta ;;
    linux) _apt git-delta ;;
  esac
  git config --global core.pager "delta"
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.light false
  git config --global merge.conflictstyle diff3
  git config --global diff.colorMoved default
  _zshrc_add "delta" ""
  ok "git-delta installed"
}

uninstall_delta() {
  step "Uninstalling git-delta..."
  _uninstall_pkg git-delta
  git config --global --unset core.pager || true
  git config --global --unset interactive.diffFilter || true
  git config --global --unset delta.navigate || true
  git config --global --unset delta.light || true
  git config --global --unset merge.conflictstyle || true
  git config --global --unset diff.colorMoved || true
  _zshrc_remove "delta"
  ok "git-delta uninstalled"
}

install_zoxide() {
  step "Installing zoxide..."
  case "$OS" in
    mac) _ensure_brew; _brew zoxide ;;
    linux) _apt zoxide ;;
  esac
  _zshrc_add "zoxide" 'eval "$(zoxide init zsh)"'
  ok "zoxide installed"
}

uninstall_zoxide() {
  step "Uninstalling zoxide..."
  _uninstall_pkg zoxide
  _zshrc_remove "zoxide"
  ok "zoxide uninstalled"
}

install_fzf() {
  step "Installing fzf..."
  case "$OS" in
    mac) _ensure_brew; _brew fzf ;;
    linux) _apt fzf ;;
  esac
  # Fetch key-binding scripts (Ubuntu strips /usr/share/doc)
  curl -sSLo "$HOME/.fzf-key-bindings.zsh" \
    https://raw.githubusercontent.com/junegunn/fzf/master/shell/key-bindings.zsh
  curl -sSLo "$HOME/.fzf-completion.zsh" \
    https://raw.githubusercontent.com/junegunn/fzf/master/shell/completion.zsh
  _zshrc_add "fzf" \
    'source "$HOME/.fzf-key-bindings.zsh"' \
    'source "$HOME/.fzf-completion.zsh"'
  ok "fzf installed"
}

uninstall_fzf() {
  step "Uninstalling fzf..."
  _uninstall_pkg fzf
  rm -f "$HOME/.fzf-key-bindings.zsh" "$HOME/.fzf-completion.zsh"
  _zshrc_remove "fzf"
  ok "fzf uninstalled"
}

install_atuin() {
  step "Installing atuin..."
  case "$OS" in
    mac) _ensure_brew; _brew atuin ;;
    linux) bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)" ;;
  esac
  _zshrc_add "atuin" 'eval "$(atuin init zsh)"'
  ok "atuin installed"
}

uninstall_atuin() {
  step "Uninstalling atuin..."
  if [ "$OS" = "mac" ]; then
    _uninstall_pkg atuin
  else
    rm -rf "$HOME/.atuin" "$HOME/.local/share/atuin" /usr/local/bin/atuin 2>/dev/null || true
  fi
  _zshrc_remove "atuin"
  ok "atuin uninstalled"
}

install_direnv() {
  step "Installing direnv..."
  case "$OS" in
    mac) _ensure_brew; _brew direnv ;;
    linux) _apt direnv ;;
  esac
  _zshrc_add "direnv" 'eval "$(direnv hook zsh)"'
  ok "direnv installed"
}

uninstall_direnv() {
  step "Uninstalling direnv..."
  _uninstall_pkg direnv
  _zshrc_remove "direnv"
  ok "direnv uninstalled"
}

install_glow() {
  step "Installing glow..."
  case "$OS" in
    mac) _ensure_brew; _brew glow ;;
    linux)
      _add_apt_repo "charm" \
        "https://repo.charm.sh/apt/gpg.key" \
        "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        "/etc/apt/sources.list.d/charm.list"
      _apt glow
      ;;
  esac
  _zshrc_add "glow" ""
  ok "glow installed"
}

uninstall_glow() {
  step "Uninstalling glow..."
  _uninstall_pkg glow
  _zshrc_remove "glow"
  ok "glow uninstalled"
}

install_ripgrep() {
  step "Installing ripgrep (rg)..."
  case "$OS" in
    mac) _ensure_brew; _brew ripgrep ;;
    linux) _apt ripgrep ;;
  esac
  _zshrc_add "ripgrep" ""
  ok "ripgrep installed"
}

uninstall_ripgrep() {
  step "Uninstalling ripgrep..."
  _uninstall_pkg ripgrep
  _zshrc_remove "ripgrep"
  ok "ripgrep uninstalled"
}

install_fd() {
  step "Installing fd..."
  case "$OS" in
    mac) _ensure_brew; _brew fd ;;
    linux)
      _apt fd-find
      if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
      fi
      ;;
  esac
  _zshrc_add "fd" ""
  ok "fd installed"
}

uninstall_fd() {
  step "Uninstalling fd..."
  _uninstall_pkg fd fd-find
  sudo rm -f /usr/local/bin/fd
  _zshrc_remove "fd"
  ok "fd uninstalled"
}

install_vim() {
  step "Installing vim..."
  case "$OS" in
    mac) _ensure_brew; _brew vim ;;
    linux) _apt vim ;;
  esac
  # Basic vim config with syntax highlighting
  {
    printf 'syntax on\n'
    printf 'set background=dark\n'
    printf 'set number\n'
  } >> "$HOME/.vimrc" 2>/dev/null || true
  _zshrc_add "vim" "alias vi='vim'"
  ok "vim installed"
}

uninstall_vim() {
  step "Uninstalling vim..."
  _uninstall_pkg vim
  _zshrc_remove "vim"
  ok "vim uninstalled"
}

install_zsh_plugins() {
  step "Installing ZSH plugins (autosuggestions + syntax highlighting)..."
  case "$OS" in
    mac)
      _ensure_brew
      _brew zsh-autosuggestions zsh-syntax-highlighting
      local brew_prefix
      brew_prefix="$(brew --prefix)"
      _zshrc_add "zsh-plugins" \
        "source ${brew_prefix}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
        "source ${brew_prefix}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
      ;;
    linux)
      _apt zsh-autosuggestions zsh-syntax-highlighting
      _zshrc_add "zsh-plugins" \
        "source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
        "source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
      ;;
  esac
  ok "ZSH plugins installed"
}

uninstall_zsh_plugins() {
  step "Uninstalling ZSH plugins..."
  _uninstall_pkg zsh-autosuggestions zsh-syntax-highlighting
  _zshrc_remove "zsh-plugins"
  ok "ZSH plugins uninstalled"
}

# ---------------------------------------------------------------------------
# Interactive menu (pure POSIX shell — no whiptail/dialog needed)
# ---------------------------------------------------------------------------

# Menu entries: "key|label|description" OR "H|Header Title"
MENU_ENTRIES=(
  "H|🧠 Shai Configuration"
  "shai|shai|AI shell assistant and toolbox core"
  "shai-implicit|shai implicit mode|Run shai on current buffer with custom hotkey"
  "H|"
  "H|🚀 Terminal Utilities"
  "starship|starship|Fast, customizable prompt"
  "eza|eza|Modern ls with icons and git info"
  "bat|bat|Syntax-highlighted cat and less replacement"
  "delta|git delta|Syntax-highlighting pager for git diffs"
  "H|"
  "H|📂 Navigation & Finding"
  "zoxide|zoxide|Smarter cd that learns your paths"
  "fzf|fzf|Fuzzy finder for files, history, and more"
  "fd|fd|Fast and user-friendly find alternative"
  "ripgrep|ripgrep (rg)|Blazing fast grep alternative"
  "H|"
  "H|🛠  Productivity"
  "atuin|atuin|Shell history with search and sync"
  "direnv|direnv|Auto-load project .env files"
  "glow|glow|Render markdown in the terminal"
  "vim|vim|Vi editor with syntax highlighting"
  "zsh-plugins|ZSH plugins|Autosuggestions + syntax highlighting"
)

_show_menu() {
  local n=${#MENU_ENTRIES[@]}
  # selected_N variables hold 0/1 for each entry based on active state
  local i=0
  while [ $i -lt $n ]; do
    local type="$(echo "${MENU_ENTRIES[$i]}" | cut -d'|' -f1)"
    if [ "$type" = "H" ]; then
      eval "selected_$i=-1"
    else
      if _zshrc_has "$type"; then eval "selected_$i=1"
      else eval "selected_$i=0"; fi
    fi
    i=$((i + 1))
  done

  local cursor=0
  while [ $cursor -lt $n ]; do
    local sel; eval "sel=\$selected_$cursor"
    if [ "$sel" -ne -1 ]; then break; fi
    cursor=$((cursor + 1))
  done

  # All display/input goes through /dev/tty so it still shows when stdout is
  # redirected to a temp file for capturing the selections.
  local TTY=/dev/tty
  tput civis 2>/dev/null >&"$TTY" || true
  local old_stty
  old_stty="$(stty -g 2>/dev/null < "$TTY" || echo '')"
  stty -echo -icanon min 1 time 0 < "$TTY" 2>&1 || true

  _menu_render() {
    # Move up only over the dynamic section (n items + blank + help)
    printf '\033[%dA' "$((n + 2))" > "$TTY" 2>/dev/null || true
    local j=0
    while [ $j -lt $n ]; do
      local type label desc sel check
      type="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f1)"
      eval "sel=\$selected_$j"
      if [ "$type" = "H" ]; then
        label="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f2)"
        if [ -z "$label" ]; then
          printf '\033[2K\r\n' > "$TTY"
        else
          printf '\033[2K\r  %s\n' "$(bold "$(cyan "$label")")" > "$TTY"
        fi
      else
        label="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f2)"
        desc="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f3)"
        if [ "$j" -eq "$cursor" ]; then
          if [ "$sel" -eq 1 ]; then
            check="$(cyan '❯') $(green '◉')"
            label="$(cyan "$(bold "$label")")"
          else
            check="$(cyan '❯') $(dim '◯')"
            label="$(cyan "$(bold "$label")")"
          fi
        else
          if [ "$sel" -eq 1 ]; then
            check="  $(green '◉')"
          else
            check="  $(dim '◯')"
          fi
        fi
        printf '\033[2K\r %s  %s  %s  %s\n' "$check" "$label" "$(dim '—')" "$(dim "$desc")" > "$TTY"
      fi
      j=$((j + 1))
    done
    printf '\033[2K\r\n\033[2K\r  %s\n' "$(dim 'SPACE toggle · ENTER confirm · a select all · n deselect all · q quit')" > "$TTY"
  }

  # Print static header once (not part of the re-render loop)
  printf '\n  %s\n' "$(bold 'Shai Toolbox Setup')" > "$TTY"
  printf '  %s\n\n' "$(dim '──────────────────────────────────────')" > "$TTY"

  # Reserve n+2 lines for the dynamic section (items + blank + help)
  seq 1 $((n + 2)) | while read -r _; do printf '\n' > "$TTY"; done
  _menu_render

  while true; do
    local char
    IFS= read -r -s -n1 char < "$TTY" || true

    if [ "$char" = $'\x1b' ]; then
      IFS= read -r -s -n1 -t 0.1 char2 < "$TTY" || true
      if [ "$char2" = '[' ]; then
        IFS= read -r -s -n1 -t 0.1 char3 < "$TTY" || true
        case "$char3" in
          A) 
            local tmp=$cursor
            while [ $tmp -gt 0 ]; do
              tmp=$((tmp - 1))
              local sel; eval "sel=\$selected_$tmp"
              if [ "$sel" -ne -1 ]; then cursor=$tmp; break; fi
            done
            ;;
          B) 
            local tmp=$cursor
            while [ $tmp -lt $((n - 1)) ]; do
              tmp=$((tmp + 1))
              local sel; eval "sel=\$selected_$tmp"
              if [ "$sel" -ne -1 ]; then cursor=$tmp; break; fi
            done
            ;;
        esac
      fi
    elif [ "$char" = ' ' ]; then
      local cur_sel
      eval "cur_sel=\$selected_$cursor"
      if [ "$cur_sel" -ne -1 ]; then eval "selected_$cursor=$(( 1 - cur_sel ))"; fi
    elif [ "$char" = 'a' ]; then
      local k=0; while [ $k -lt $n ]; do local s; eval "s=\$selected_$k"; [ "$s" -ne -1 ] && eval "selected_$k=1"; k=$((k+1)); done
    elif [ "$char" = 'n' ]; then
      local k=0; while [ $k -lt $n ]; do local s; eval "s=\$selected_$k"; [ "$s" -ne -1 ] && eval "selected_$k=0"; k=$((k+1)); done
    elif [ "$char" = $'\r' ] || [ "$char" = $'\n' ] || [ "$char" = '' ]; then
      break
    elif [ "$char" = 'q' ]; then
      stty "$old_stty" < "$TTY" 2>&1 || true
      tput cnorm 2>/dev/null > "$TTY" || true
      printf '\n\nAborted.\n' > "$TTY"
      exit 0
    fi
    _menu_render
  done

  stty "$old_stty" < "$TTY" 2>&1 || true
  tput cnorm 2>/dev/null > "$TTY" || true
  printf '\n' > "$TTY"

  # Emit selected keys to stdout (captured by the caller via temp file)
  local k=0
  while [ $k -lt $n ]; do
    local sel type
    eval "sel=\$selected_$k"
    type="$(echo "${MENU_ENTRIES[$k]}" | cut -d'|' -f1)"
    if [ "$sel" -eq 1 ] && [ "$type" != "H" ]; then
      echo "$type"
    fi
    k=$((k + 1))
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {

  local silent=0 uninstall=0
  for arg in "$@"; do
    case "$arg" in
      --all|-a)     silent=1 ;;
      --uninstall)  uninstall=1 ;;
    esac
  done
  [ "${SETUP_SILENT:-0}" = "1" ] && silent=1

  # Touch ~/.zshrc if not present
  touch "$ZSHRC"

  local to_install
  to_install=""

  # Record initial installed state BEFORE menu interacts
  local n=${#MENU_ENTRIES[@]}
  local i=0
  while [ $i -lt $n ]; do
    local type="$(echo "${MENU_ENTRIES[$i]}" | cut -d'|' -f1)"
    if [ "$type" = "H" ]; then
      i=$((i + 1))
      continue
    fi
    if _zshrc_has "$type"; then
      eval "INITIAL_STATE_$(echo "$type" | tr '-' '_')=1"
    else
      eval "INITIAL_STATE_$(echo "$type" | tr '-' '_')=0"
    fi
    i=$((i + 1))
  done

  if [ "$uninstall" -eq 1 ]; then
    info "$(yellow "Uninstall mode: removing all installed shai components...")"
    to_install=""
  elif [ "$silent" -eq 1 ]; then
    info "$(yellow "Silent mode: selecting all components")"
    to_install="shai shai-implicit starship eza bat delta zoxide fzf atuin direnv glow ripgrep fd vim zsh-plugins"
  else
    # Check we have a real TTY for the interactive menu
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      warn "No TTY detected (running via pipe?). Switching to --all mode."
      to_install="shai shai-implicit starship eza bat delta zoxide fzf atuin direnv glow ripgrep fd vim zsh-plugins"
    else
      local _menu_tmp
      _menu_tmp="$(mktemp)"
      _show_menu > "$_menu_tmp"
      to_install="$(cat "$_menu_tmp")"
      rm -f "$_menu_tmp"
    fi
  fi

  # Diff-based execution engine
  i=0
  while [ $i -lt $n ]; do
    local type="$(echo "${MENU_ENTRIES[$i]}" | cut -d'|' -f1)"
    if [ "$type" = "H" ]; then
      i=$((i + 1))
      continue
    fi
    local key="$type"
    local safe_key
    safe_key="$(echo "$key" | tr '-' '_')"

    local was_installed
    eval "was_installed=\$INITIAL_STATE_$safe_key"

    local is_selected=0
    for comp in $to_install; do
      if [ "$comp" = "$key" ]; then is_selected=1; break; fi
    done

    if [ "$was_installed" -eq 0 ] && [ "$is_selected" -eq 1 ]; then
      "install_$safe_key"
    elif [ "$was_installed" -eq 1 ] && [ "$is_selected" -eq 0 ]; then
      "uninstall_$safe_key"
    fi
    
    i=$((i + 1))
  done

  printf '\n%s\n\n' "$(green "$(bold '✓ All done!')")"
  printf 'Reload your shell to apply changes:\n'
  printf '  %s\n\n' "$(bold "source $ZSHRC")"
}

main "$@"
