# shai Docker integration — works in bash and zsh
#
# Add to ~/.zshrc or ~/.bashrc / ~/.bash_profile:
#   source /path/to/shai/shell/shai-docker.sh
#
# Override the image:
#   export SHAI_IMAGE="ghcr.io/youruser/shai:latest"

if [ "$(uname)" = "Darwin" ]; then
    _shai_cache_dir="$HOME/Library/Caches/shai"
else
    _shai_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/shai"
fi
_shai_context_file="$_shai_cache_dir/context"
_shai_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/shai"
SHAI_IMAGE="${SHAI_IMAGE:-ghcr.io/youruser/shai:latest}"

# Collect host system info once at source time and export for the container
_shai_collect_host_info() {
    local _uname
    _uname="$(uname)"

    if [ "$_uname" = "Darwin" ]; then
        local _ver
        _ver="$(sw_vers -productVersion 2>/dev/null)"
        export SHAI_HOST_OS="macOS ${_ver}"
        local _mem_bytes
        _mem_bytes="$(sysctl -n hw.memsize 2>/dev/null)"
        export SHAI_HOST_MEM="$(( _mem_bytes / 1073741824 )) GB"
    else
        local _pretty
        _pretty="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"')"
        export SHAI_HOST_OS="${_pretty:-Linux}"
        local _kb
        _kb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)"
        export SHAI_HOST_MEM="$(( _kb / 1048576 )) GB"
    fi

    export SHAI_HOST_ARCH="$(uname -m)"
    export SHAI_HOST_SHELL="$(${SHELL} --version 2>&1 | head -1)"

    local _pkg=""
    for _m in brew apt dnf pacman zypper apk; do
        command -v "$_m" > /dev/null 2>&1 && _pkg="${_pkg:+$_pkg, }$_m"
    done
    export SHAI_HOST_PKG="$_pkg"
    export SHAI_HOST_CONFIG_DIR="$_shai_config_dir"
    export SHAI_HOST_CACHE_DIR="$_shai_cache_dir"
}
_shai_collect_host_info

_shai_save_context() {
    local exit_code=$?
    mkdir -p "$_shai_cache_dir"

    local last_cmd
    last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')

    # Don't overwrite context when the last command was shai itself —
    # keep the previous command's context so 'shai help' sees the real error
    local _cmd_name="${SHAI_CMD_NAME:-shai}"
    case "$last_cmd" in
        "$_cmd_name"*) return $exit_code ;;
    esac

    if [ -n "$TMUX" ]; then
        tmux capture-pane -p -S -200 2>/dev/null > "$_shai_context_file"
    else
        {
            echo "$ ${last_cmd}"
            [ "$exit_code" -ne 0 ] && echo "[exited with code $exit_code]"
        } > "$_shai_context_file"
    fi
    return $exit_code
}

# Register the precmd/PROMPT_COMMAND hook for the current shell
if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _shai_save_context
elif [ -n "$BASH_VERSION" ]; then
    if [[ "$PROMPT_COMMAND" != *"_shai_save_context"* ]]; then
        PROMPT_COMMAND="_shai_save_context${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    fi
fi

# Build the base docker run command into an array
_shai_docker_cmd() {
    local _container_bin="docker"
    if ! command -v docker >/dev/null 2>&1; then
        if command -v podman >/dev/null 2>&1; then
            _container_bin="podman"
        else
            echo "Error: Neither docker nor podman was found in PATH." >&2
            return 1
        fi
    fi
    local _stdin_flag=()
    [ -t 0 ] || _stdin_flag=(-i)
    echo_cmd=("$_container_bin" run --rm "${_stdin_flag[@]}"
        -e OPENAI_API_KEY
        -e ANTHROPIC_API_KEY
        -e TERM
        -e COLORTERM
        -e SHAI_HOST_OS
        -e SHAI_HOST_ARCH
        -e SHAI_HOST_SHELL
        -e SHAI_HOST_MEM
        -e SHAI_HOST_PKG
        -e SHAI_HOST_CONFIG_DIR
        -e SHAI_HOST_CACHE_DIR
        -v "${_shai_config_dir}:/home/shai/.config/shai:ro"
        -v "${_shai_cache_dir}:/home/shai/.cache/shai:ro"
        "$SHAI_IMAGE"
    )
}

# 'shai do <task>' — ask LLM for a command, confirm, execute on host
_shai_do() {
    mkdir -p "$_shai_config_dir" "$_shai_cache_dir"

    local _container_bin="docker"
    if ! command -v docker >/dev/null 2>&1; then
        if command -v podman >/dev/null 2>&1; then
            _container_bin="podman"
        else
            echo "Error: Neither docker nor podman was found in PATH." >&2
            return 1
        fi
    fi

    local _cmd=("$_container_bin" run --rm
        -e OPENAI_API_KEY
        -e ANTHROPIC_API_KEY
        -e TERM
        -e COLORTERM
        -e SHAI_HOST_OS
        -e SHAI_HOST_ARCH
        -e SHAI_HOST_SHELL
        -e SHAI_HOST_MEM
        -e SHAI_HOST_PKG
        -e SHAI_HOST_CONFIG_DIR
        -e SHAI_HOST_CACHE_DIR
        -v "${_shai_config_dir}:/home/shai/.config/shai:ro"
        -v "${_shai_cache_dir}:/home/shai/.cache/shai:ro"
        "$SHAI_IMAGE"
        do
    )

    # Capture full LLM response
    local response
    response=$("${_cmd[@]}" "$@" 2>&1)

    # Display with glow if available, otherwise plain
    if command -v glow > /dev/null 2>&1; then
        printf '%s\n' "$response" | glow -
    else
        printf '%s\n' "$response"
    fi

    # Extract first ```bash ... ``` block
    local extracted_cmd
    extracted_cmd=$(printf '%s\n' "$response" | awk '/^```bash$/{found=1;next} found && /^```/{exit} found{print}')

    if [ -z "$extracted_cmd" ]; then
        printf '\n\033[33mNo executable command found in response.\033[0m\n'
        return 1
    fi

    # Warn on destructive patterns
    local dangerous=0
    case "$extracted_cmd" in
        *"rm "*|*"rm -"*|"rm "*) dangerous=1 ;;
    esac
    case "$extracted_cmd" in
        *"sudo "*|*" dd "*|*"dd if"*|*"mkfs"*|*"| sh"*|*"| bash"*|*"chmod -R"*|*"chown -R"*) dangerous=1 ;;
    esac

    # Warn on macOS-incompatible GNU patterns the LLM may have generated
    local compat_warn=""
    if [ "$(uname)" = "Darwin" ]; then
        case "$extracted_cmd" in
            *"-printf"*)    compat_warn='find -printf is GNU only. Use -exec stat -f instead.' ;;
        esac
        case "$extracted_cmd" in
            *"--sort="*)    compat_warn='ps --sort is GNU only. Use ps aux | sort -k4 -rn instead.' ;;
        esac
        case "$extracted_cmd" in
            *"sed -i '"*)   compat_warn="sed -i requires an empty string on macOS: sed -i '' ..." ;;
        esac
        case "$extracted_cmd" in
            *"stat --format"*) compat_warn='stat --format is GNU only. Use stat -f on macOS.' ;;
        esac
    fi

    printf '\n'
    [ "$dangerous" -eq 1 ] && printf '\033[33m⚠  Warning: command may be destructive\033[0m\n'
    [ -n "$compat_warn" ] && printf '\033[33m⚠  Compatibility: %s\033[0m\n' "$compat_warn"
    printf '\033[1mRun? [Y/e/n]\033[0m  '

    local answer
    read -r answer
    case "$answer" in
        y|Y|"")
            printf '\n'
            eval "$extracted_cmd"
            ;;
        e|E)
            printf 'Edit: '
            if [ -n "$ZSH_VERSION" ]; then
                local edited="$extracted_cmd"
                vared edited
                printf '\n'
                eval "$edited"
            else
                local edited
                read -e -i "$extracted_cmd" -r edited
                eval "$edited"
            fi
            ;;
        *)
            printf 'Cancelled.\n'
            ;;
    esac
}

# Internal function — called via the noglob alias below
_shai() {
    mkdir -p "$_shai_config_dir" "$_shai_cache_dir"

    # Capture fresh context right now — before Docker starts and before any shai
    # output appears on screen. This prevents the context from going stale when
    # the user only runs shai commands (the precmd hook skips those).
    if [ -n "$TMUX" ]; then
        tmux capture-pane -p -S -200 2>/dev/null > "$_shai_context_file"
    fi

    # Dispatch 'do' subcommand to host-side executor
    if [ "$1" = "do" ]; then
        shift
        _shai_do "$@"
        return
    fi

    local _container_bin="docker"
    if ! command -v docker >/dev/null 2>&1; then
        if command -v podman >/dev/null 2>&1; then
            _container_bin="podman"
        else
            echo "Error: Neither docker nor podman was found in PATH." >&2
            return 1
        fi
    fi

    local _tty_flags=()
    [ -t 0 ] && _tty_flags+=(-i)
    [ -t 1 ] && _tty_flags+=(-t)

    # Build docker command as an array to avoid any glob re-expansion
    local _cmd=("$_container_bin" run --rm "${_tty_flags[@]}")
    _cmd+=(
        -e OPENAI_API_KEY
        -e ANTHROPIC_API_KEY
        -e TERM
        -e COLORTERM
        -e SHAI_HOST_OS
        -e SHAI_HOST_ARCH
        -e SHAI_HOST_SHELL
        -e SHAI_HOST_MEM
        -e SHAI_HOST_PKG
        -e SHAI_HOST_CONFIG_DIR
        -e SHAI_HOST_CACHE_DIR
        -v "${_shai_config_dir}:/home/shai/.config/shai:ro"
        -v "${_shai_cache_dir}:/home/shai/.cache/shai:ro"
        "$SHAI_IMAGE"
    )

    "${_cmd[@]}" "$@"
}

# noglob prevents zsh from expanding ?, *, ! etc. before passing args to shai
SHAI_CMD_NAME="${SHAI_CMD_NAME:-shai}"
if [ -n "$ZSH_VERSION" ]; then
    eval "alias ${SHAI_CMD_NAME}='noglob _shai'"
else
    eval "${SHAI_CMD_NAME}() { _shai \"\$@\"; }"
fi
