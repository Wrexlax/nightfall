#!/bin/bash
# Builds the Steam Frame package (NightfallFrame-<build>.tar.gz) from this tree.
#
#   steam-frame/build-frame.sh <build-name>          e.g.  build-frame.sh 5a
#
# Needs (see steam-frame/README.md for where each comes from):
#   FRAME_NATIVE  work folder for tools and build output      (default ~/native)
#   FRAME_SDK     Godot's aarch64 buildroot SDK, relocated     (default $FRAME_NATIVE/aarch64-godot-linux-gnu_sdk-buildroot)
#   VCPKG_ROOT    a bootstrapped vcpkg checkout                (default $FRAME_NATIVE/vcpkg)
#   GODOT         Godot 4.7 editor for this machine            (default: godot on PATH)
#   FRAME_ENGINE  Godot 4.7 linux arm64 debug export template  (default $FRAME_NATIVE/Nightfall.arm64;
#                 6f, and from 6h: the one built with steam-frame/engine/, see its README)
# Optional, for on-headset depth (without them the package has none):
#   $FRAME_NATIVE/litert/dist-arm64   from steam-frame/build-litert.sh arm64
#   FRAME_DEPTH_MODELS                the two ZipDepth models (default $FRAME_NATIVE/depth_models)
#   $FRAME_NATIVE/ncnn/dist-arm64     from steam-frame/build-ncnn.sh arm64, for the graphics-chip test,
#                                     with Meteor's EdgePad model (two .ncnn files) beside the ZipDepth ones
set -euo pipefail
BUILD="${1:?usage: build-frame.sh <build-name>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
export FRAME_NATIVE="${FRAME_NATIVE:-$HOME/native}"
export FRAME_SDK="${FRAME_SDK:-$FRAME_NATIVE/aarch64-godot-linux-gnu_sdk-buildroot}"
export VCPKG_ROOT="${VCPKG_ROOT:-$FRAME_NATIVE/vcpkg}"
export VCPKG_DISABLE_METRICS=1
GODOT="${GODOT:-$(command -v godot || true)}"
FRAME_ENGINE="${FRAME_ENGINE:-$FRAME_NATIVE/Nightfall.arm64}"
TC="$HERE/toolchain"
for f in "$FRAME_SDK/bin/aarch64-godot-linux-gnu-gcc" "$VCPKG_ROOT/vcpkg" "$GODOT" "$FRAME_ENGINE"; do
    [ -e "$f" ] || { echo "missing: $f (see steam-frame/README.md)" >&2; exit 1; }
done

echo "== 1/4 dependencies (vcpkg, arm64, static)"
( cd "$ROOT/addons/nightfall-stream" && "$VCPKG_ROOT/vcpkg" install \
    --triplet arm64-linux --host-triplet x64-linux \
    --overlay-triplets="$TC/triplets" --overlay-ports="$TC/overlay-ports" \
    --x-install-root="$FRAME_NATIVE/vcpkg_installed" \
    --x-buildtrees-root="$FRAME_NATIVE/vcpkg_buildtrees" \
    --downloads-root="$FRAME_NATIVE/vcpkg_downloads" )

echo "== 2/4 native library (libnightfall-stream, arm64)"
# pkg-config and X11 are kept away from the build machine's own libraries: the
# Frame build uses none of avahi, pipewire, systemd or X11.
mkdir -p "$FRAME_NATIVE/empty-pkgconfig"
PKG_CONFIG_LIBDIR="$FRAME_NATIVE/empty-pkgconfig" PKG_CONFIG_PATH= cmake \
    -S "$ROOT/addons/nightfall-stream" -B "$FRAME_NATIVE/build-ns" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE="$TC/toolchain-frame.cmake" \
    -DVCPKG_TARGET_TRIPLET=arm64-linux -DVCPKG_HOST_TRIPLET=x64-linux \
    -DVCPKG_OVERLAY_TRIPLETS="$TC/triplets" \
    -DVCPKG_INSTALLED_DIR="$FRAME_NATIVE/vcpkg_installed" -DVCPKG_MANIFEST_INSTALL=OFF \
    -DNIGHTFALL_PLATFORM=steamos -DCMAKE_DISABLE_FIND_PACKAGE_X11=ON
ninja -C "$FRAME_NATIVE/build-ns"
SO="$(ls "$FRAME_NATIVE"/build-ns/bin/steamos/libnightfall-stream*.so 2>/dev/null | head -1)"
[ -n "$SO" ] || { echo "no library produced" >&2; exit 1; }

echo "== 3/4 data pack (Godot export)"
# The package someone unpacks holds three things to look at (install.sh,
# uninstall.sh, README.txt) and one folder, "files", with everything else,
# so that it is obvious what to click. install.sh copies "files" to ~/Games/NightfallFrame,
# where the layout is as it always was.
PACKAGE="$FRAME_NATIVE/package/NightfallFrame"
OUT="$PACKAGE/files"
rm -rf "$FRAME_NATIVE/package"; mkdir -p "$OUT/addons/nightfall-stream/bin/linux"
"$GODOT" --headless --xr-mode off --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --xr-mode off --path "$ROOT" --export-pack NightfallSteamFrame "$OUT/Nightfall.pck"
[ -s "$OUT/Nightfall.pck" ] || { echo "export failed" >&2; exit 1; }

echo "== 4/4 package"
# The engine looks for the library under the name of its own kind: "debug"
# for a debug export template (FRAME_ENGINE_KIND unset), "release" for a
# release one. The library itself is the same Release build either way.
KIND="${FRAME_ENGINE_KIND:-debug}"
case "$KIND" in debug|release) ;; *) echo "FRAME_ENGINE_KIND must be debug or release" >&2; exit 1;; esac
cp "$SO" "$OUT/addons/nightfall-stream/bin/linux/libnightfall-stream.linux.template_$KIND.arm64.so"
"$FRAME_SDK/bin/aarch64-godot-linux-gnu-strip" --strip-unneeded "$OUT/addons/nightfall-stream/bin/linux/libnightfall-stream.linux.template_$KIND.arm64.so"
cp "$FRAME_ENGINE" "$OUT/Nightfall.arm64"
cp -a "$HERE/package/." "$OUT/"
# On-headset depth: its models go next to the program (depth_models/), where
# the native library looks. Like Nightfall's other models they are not kept in
# git; they are Moonlight XR's ZipDepth exports (from Moonlight XR for Frame's
# assets/depth/, the same files as in Moonlight XR itself),
# checked here against the hashes in depth-models.sha256. Only when the
# library was built with the depth engine (build-litert.sh).
if [ -f "$FRAME_NATIVE/litert/dist-arm64/lib/libnightfall_litert.a" ]; then
    MODELS="${FRAME_DEPTH_MODELS:-$FRAME_NATIVE/depth_models}"
    ( cd "$MODELS" && sha256sum --quiet -c "$HERE/depth-models.sha256" ) \
        || { echo "depth models missing or not the expected files in $MODELS (see steam-frame/README.md)" >&2; exit 1; }
    mkdir -p "$OUT/depth_models"
    cut -d' ' -f3 "$HERE/depth-models.sha256" | while read -r model; do cp "$MODELS/$model" "$OUT/depth_models/"; done
    # The graphics-chip test (build-ncnn.sh): upstream Nightfall's own EdgePad
    # export in ncnn's format, as Meteor's installer puts it on the PC
    # (share/nightfall-meteor/models). Only when that engine was built too.
    if [ -f "$FRAME_NATIVE/ncnn/dist-arm64/lib/libncnn.a" ]; then
        ( cd "$MODELS" && sha256sum --quiet -c "$HERE/depth-models-gpu.sha256" ) \
            || { echo "graphics-chip depth model missing or not the expected files in $MODELS" >&2; exit 1; }
        cut -d' ' -f3 "$HERE/depth-models-gpu.sha256" | while read -r model; do cp "$MODELS/$model" "$OUT/depth_models/"; done
    fi
fi
# Nightfall's own licence (the GNU GPL, version 3), which this port is under
# too; the LICENSE-*.txt files beside it are for what the port adds.
cp "$ROOT/LICENSE" "$OUT/LICENSE-nightfall.txt"
printf '%s' "$BUILD" > "$OUT/VERSION"
chmod +x "$OUT"/*.sh "$OUT/Nightfall.arm64"
mv "$OUT/install.sh" "$OUT/uninstall.sh" "$OUT/README.txt" "$PACKAGE/"
tar -C "$FRAME_NATIVE/package" -czf "$FRAME_NATIVE/NightfallFrame-phase$BUILD.tar.gz" NightfallFrame
echo "done: $FRAME_NATIVE/NightfallFrame-phase$BUILD.tar.gz"
