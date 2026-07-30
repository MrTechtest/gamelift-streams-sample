#!/usr/bin/env bash
# Launch script for Amazon GameLift Streams (executable launch path).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$HERE/libs:${LD_LIBRARY_PATH:-}"
# SDL video driver on the GameLift Streams Linux host is X11.
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"
exec "$HERE/bin/breakout" "$@"
