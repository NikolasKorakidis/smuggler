#!/usr/bin/env bash
# Builds JSBSim (static) and the Godot extension into game/bin/.
# Usage: scripts/build_extension.sh [debug|release|all]   (default: debug)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT="$ROOT/extensions/jsbsim_gd"
WHICH="${1:-debug}"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

git -C "$ROOT" submodule update --init --depth 1

if [[ ! -f "$EXT/build/jsbsim/src/libJSBSim.a" ]]; then
  cmake -S "$EXT/thirdparty/jsbsim" -B "$EXT/build/jsbsim" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_PYTHON_MODULE=OFF -DBUILD_DOCS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
fi
cmake --build "$EXT/build/jsbsim" --target libJSBSim -j"$JOBS"

build() {
  (cd "$EXT" && scons -j"$JOBS" platform=macos arch=arm64 target="$1" disable_exceptions=no macos_deployment_target=12.0)
}
case "$WHICH" in
  debug)   build template_debug ;;
  release) build template_release ;;
  all)     build template_debug; build template_release ;;
  *) echo "usage: $0 [debug|release|all]"; exit 1 ;;
esac
ls -la "$ROOT/game/bin"
