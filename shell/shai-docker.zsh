# shai Docker integration for zsh
# No Python required — shai runs inside Docker.
#
# Usage: add to ~/.zshrc:
#   source /path/to/shai-docker.zsh
#
# Optional: set image name (default: ghcr.io/youruser/shai:latest)
#   export SHAI_IMAGE="ghcr.io/youruser/shai:latest"

# Only load in zsh
[ -n "$ZSH_VERSION" ] || return 0

_shai_dir="${0:A:h}"
if [ -f "$_shai_dir/shai-docker.sh" ]; then
    source "$_shai_dir/shai-docker.sh"
else
    source "./shai-docker.sh"
fi
