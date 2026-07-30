#!/usr/bin/env bash
# Compiles breakout.c and assembles a SELF-CONTAINED folder in ./dist that can
# be uploaded to Amazon GameLift Streams as an application build.
#
# Layout produced:
#   dist/
#   ├── run-game.sh      <- executable launch path you give to create-application
#   ├── bin/breakout     <- the compiled game
#   └── libs/*.so*       <- bundled shared libraries (SDL2 + its deps)
#
# The launch script sets LD_LIBRARY_PATH to the bundled libs so the game does
# not depend on anything extra being pre-installed on the streaming host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST/bin" "$DIST/libs"

echo ">> Compiling breakout.c ..."
cc -O2 -o "$DIST/bin/breakout" "$ROOT/breakout.c" \
    $(pkg-config --cflags --libs sdl2) -lm

echo ">> Collecting shared library dependencies ..."
# Copy every non-glibc shared object the binary needs into libs/.
# We skip the dynamic loader and the core glibc libraries, which are always
# present and version-locked to the OS on the streaming host (also Ubuntu 22.04).
ldd "$DIST/bin/breakout" | awk '/=> \//{print $3}' | while read -r lib; do
    base="$(basename "$lib")"
    case "$base" in
        libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|ld-linux*|linux-vdso*)
            continue ;;
    esac
    cp -Lv "$lib" "$DIST/libs/" || true
done

# Also pull SDL2's own runtime .so explicitly in case it was resolved via a symlink.
for f in /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0*; do
    [ -e "$f" ] && cp -Lv "$f" "$DIST/libs/" || true
done

cat > "$DIST/run-game.sh" <<'LAUNCH'
#!/usr/bin/env bash
# Launch script for Amazon GameLift Streams (executable launch path).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$HERE/libs:${LD_LIBRARY_PATH:-}"
# SDL video driver on the GameLift Streams Linux host is X11.
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"
exec "$HERE/bin/breakout" "$@"
LAUNCH
chmod +x "$DIST/run-game.sh"

echo ">> Build complete. Contents of dist/:"
find "$DIST" -maxdepth 2 -print | sed "s#$DIST#dist#"
echo
echo ">> Executable launch path to use in create-application:  run-game.sh"
