# shai Docker integration for bash
# No Python required — shai runs inside Docker.
#
# Usage: add to ~/.bashrc:
#   source /path/to/shai-docker.bash
#
# Optional: set image name (default: ghcr.io/zeddius1983/shell-assistant:latest)
#   export SHAI_IMAGE="ghcr.io/zeddius1983/shell-assistant:latest"

# Only load in bash
[ -n "$BASH_VERSION" ] || return 0

_shai_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_shai_dir/shai-docker.sh" ]; then
    source "$_shai_dir/shai-docker.sh"
else
    source "./shai-docker.sh"
fi
