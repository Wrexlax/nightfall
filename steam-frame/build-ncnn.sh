#!/bin/bash
# Builds ncnn (Tencent's neural network runtime) with its Vulkan backend as a
# static library, for running a depth model on the Steam Frame's graphics chip.
#
#   build-ncnn.sh arm64    for the headset (cross-compiled, Frame toolchain)
#   build-ncnn.sh x64      for tests on this machine (no graphics chip needed:
#                          ncnn falls back to the processor)
#
# The revision is the one upstream Nightfall pins for its desktop Linux build
# (addons/nightfall-stream/CMakeLists.txt), whose models and output were
# checked against it. Everything comes from GitHub by git: this build machine
# reaches nothing else. ncnn brings its own Vulkan loader and headers
# (simplevk) and its shader compiler (glslang, a submodule), so nothing of the
# headset's system is needed to build, and nothing but its Vulkan driver to run.
#
# Result: $FRAME_NATIVE/ncnn/dist-<arch>/{lib,include}
set -eu
ARCH="${1:-arm64}"
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${FRAME_NATIVE:?set FRAME_NATIVE to the folder that holds the tools of the Frame build}"
export FRAME_SDK="${FRAME_SDK:-$FRAME_NATIVE/aarch64-godot-linux-gnu_sdk-buildroot}"
NCNN_COMMIT=6c52e59dfb610cbd77946bea19099aaf96f8dcc1
R="$FRAME_NATIVE/ncnn"
mkdir -p "$R"

if [ ! -d "$R/src/.git" ]; then
    git clone --filter=blob:none https://github.com/Tencent/ncnn.git "$R/src"
fi
# Back to the pinned revision's own files first, so that the patch below is
# applied once however often this script runs.
git -C "$R/src" checkout -q -- src/gpu.cpp 2>/dev/null || true
git -C "$R/src" checkout -q "$NCNN_COMMIT"
git -C "$R/src" submodule update --init --depth 1 glslang
# The one change to ncnn itself; the patch file says why.
git -C "$R/src" apply "$HERE/ncnn-low-priority.patch"

CROSS=()
case "$ARCH" in
    arm64) CROSS=(-DCMAKE_TOOLCHAIN_FILE="$HERE/toolchain/toolchain-frame.cmake") ;;
    x64) ;;
    *) echo "usage: build-ncnn.sh arm64|x64" >&2; exit 2 ;;
esac

# Only what a depth model needs: no tools, examples or tests; no OpenMP (one
# more library to carry, and the graphics chip does the work).
cmake -G Ninja -S "$R/src" -B "$R/build-$ARCH" "${CROSS[@]}" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$R/dist-$ARCH" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DNCNN_VULKAN=ON -DNCNN_SIMPLEVK=ON -DNCNN_SYSTEM_GLSLANG=OFF \
    -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_BENCHMARK=OFF \
    -DNCNN_BUILD_TESTS=OFF -DNCNN_SHARED_LIB=OFF -DNCNN_OPENMP=OFF \
    -DNCNN_PYTHON=OFF -DNCNN_INSTALL_SDK=ON
cmake --build "$R/build-$ARCH"
cmake --install "$R/build-$ARCH"
echo "ncnn for $ARCH: $R/dist-$ARCH"
