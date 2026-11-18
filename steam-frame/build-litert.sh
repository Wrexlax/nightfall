#!/bin/bash
# Builds LiteRT (TensorFlow Lite) 2.21.0's C API with its XNNPACK delegate as
# one static archive, for on-headset depth on the Steam Frame
# (addons/nightfall-stream/src/video/frame_depth_engine.h).
#
#   steam-frame/build-litert.sh arm64     the Frame (cross-compiled, as the rest)
#   steam-frame/build-litert.sh x64       this machine, for frame_depth_test
#
# Output, outside this tree (the Frame build picks it up from there):
#   $FRAME_NATIVE/litert/dist-<arch>/lib/libnightfall_litert.a
#   $FRAME_NATIVE/litert/dist-<arch>/include/...
#
# Needs git, cmake, ninja and, for arm64, FRAME_SDK as in build-frame.sh.
# First run: about 600 MB of sources and, on two cores, 45 minutes a build.
#
# The recipe follows Moonlight XR for Frame's depth/tools/build-litert.sh
# (GPLv3), which worked out the options and the trick of merging only the
# archives the C API really uses. What differs here: everything is fetched
# with git at the commits LiteRT pins (this build machine can reach GitHub
# through git only: no archive downloads, no gitlab, no googleapis), and it
# cross-compiles with the Frame toolchain.
set -euo pipefail
ARCH="${1:?usage: build-litert.sh arm64|x64}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FRAME_NATIVE="${FRAME_NATIVE:-$HOME/native}"
export FRAME_SDK="${FRAME_SDK:-$FRAME_NATIVE/aarch64-godot-linux-gnu_sdk-buildroot}"
R="$FRAME_NATIVE/litert"
D="$R/deps"
SRC="$R/src/tensorflow"
B="$R/build-$ARCH"
OUT="$R/dist-$ARCH"
JOBS="${JOBS:-$(nproc)}"
mkdir -p "$D" "$R/src"

# One dependency at one commit or tag, through git.
fetch() {   # fetch <folder> <repository> <commit-or-tag>
    [ -d "$D/$1/.git" ] && return 0
    rm -rf "$D/$1"; mkdir -p "$D/$1"
    ( cd "$D/$1" && git init -q . && git remote add origin "$2" \
        && git fetch -q --depth 1 origin "$3" && git checkout -q FETCH_HEAD ) \
        || { rm -rf "$D/$1"; echo "could not fetch $1 ($2 $3)" >&2; exit 1; }
    echo "fetched $1"
}

echo "== 1/5 sources"
if [ ! -d "$SRC/.git" ]; then
    # Only the parts LiteRT's own CMake build reads: 300 MB instead of 1.5 GB.
    git clone -q --depth 1 --branch v2.21.0 --filter=blob:none --sparse \
        https://github.com/tensorflow/tensorflow.git "$SRC"
    ( cd "$SRC" && git sparse-checkout set tensorflow/lite tensorflow/core/public tensorflow/compiler/mlir/lite third_party )
    # The C API needs none of these, and they would pull in protobuf (and a
    # protoc for this machine): the profiling and benchmark protos, the
    # example protos, the benchmark tool and the label_image example.
    sed -i -E 's@^add_subdirectory\(\$\{TFLITE_SOURCE_DIR\}/(profiling/proto|tools/benchmark/proto|tools/benchmark|examples/label_image)\)@# (Frame build) &@; s@^add_subdirectory\(\$\{TF_SOURCE_DIR\}/core/example @# (Frame build) &@' \
        "$SRC/tensorflow/lite/CMakeLists.txt"
fi
# The commits are the ones in tensorflow/lite/tools/cmake/modules/*.cmake and
# XNNPACK's cmake/Download*.cmake at these versions. Eigen and KleidiAI come
# from their GitHub mirrors (upstream: gitlab.com, gitlab.arm.com).
fetch abseil-cpp  https://github.com/abseil/abseil-cpp       d38452e1ee03523a208362186fd42248ff2609f6
fetch cpuinfo     https://github.com/pytorch/cpuinfo         8a9210069b5a37dd89ed118a783945502a30a4ae
fetch eigen       https://github.com/eigen-mirror/eigen      dcbaf2d608f306450f1e74949eb87e9a22a7ef4b
fetch farmhash    https://github.com/google/farmhash         0d859a811870d10f53a594927d0d0b97573ad06d
fetch fft2d       https://github.com/petewarden/OouraFFT     v1.0
fetch flatbuffers https://github.com/google/flatbuffers      v25.9.23
fetch fp16        https://github.com/Maratyszcza/FP16        0a92994d729ff76a58f692d3028ca1b64b145d91
fetch gemmlowp    https://github.com/google/gemmlowp         16e8662c34917be0065110bfcd9cc27d30f52fdf
fetch ml_dtypes   https://github.com/jax-ml/ml_dtypes        00d98cd92ade342fef589c0470379abb27baebe9
fetch neon2sse    https://github.com/intel/ARM_NEON_2_x86_SSE a15b489e1222b2087007546b4912e21293ea86ff
fetch ruy         https://github.com/google/ruy              3286a34cc8de6149ac6844107dfdffac91531e72
fetch xnnpack     https://github.com/google/XNNPACK          25b42dfddb0ee22170d73ff0d4b333ea1e6edfeb
fetch fxdiv       https://github.com/Maratyszcza/FXdiv       b408327ac2a15ec3e43352421954f5b1967701d1
fetch pthreadpool https://github.com/google/pthreadpool      0e6ca13779b57d397a5ba6bfdcaa8a275bc8ea2e
fetch kleidiai    https://github.com/ARM-software/kleidiai   63205aa90afa6803d8f58bc3081b69288e9f1906

CROSS=()
CC=cc; CXX=c++; AR=ar; RANLIB=ranlib
if [ "$ARCH" = arm64 ]; then
    echo "== 2/5 flatc for this machine (the cross build runs it)"
    if [ ! -x "$R/host-tools/flatc" ]; then
        cmake -G Ninja -S "$D/flatbuffers" -B "$R/build-flatc" -DCMAKE_BUILD_TYPE=Release \
            -DFLATBUFFERS_BUILD_TESTS=OFF -DFLATBUFFERS_BUILD_FLATLIB=OFF -DFLATBUFFERS_BUILD_FLATHASH=OFF >/dev/null
        ninja -C "$R/build-flatc" flatc >/dev/null
        mkdir -p "$R/host-tools" && cp "$R/build-flatc/flatc" "$R/host-tools/"
    fi
    CROSS=(-DCMAKE_TOOLCHAIN_FILE="$HERE/toolchain/toolchain-frame.cmake" -DTFLITE_HOST_TOOLS_DIR="$R/host-tools")
    CC="$FRAME_SDK/bin/aarch64-godot-linux-gnu-gcc"; CXX="$FRAME_SDK/bin/aarch64-godot-linux-gnu-g++"
    AR="$FRAME_SDK/bin/aarch64-godot-linux-gnu-ar"; RANLIB="$FRAME_SDK/bin/aarch64-godot-linux-gnu-ranlib"
else
    echo "== 2/5 (nothing extra for this machine's own build)"
    CROSS=(-DCMAKE_POSITION_INDEPENDENT_CODE=ON)
fi

echo "== 3/5 configure ($ARCH)"
if [ ! -f "$B/build.ninja" ]; then
    # TENSORFLOW_SOURCE_DIR matters: without it the build fetches a different
    # TensorFlow for its headers (Moonlight XR's note). FULLY_DISCONNECTED and
    # the SOURCE_DIRs keep every dependency to the folders fetched above.
    cmake -G Ninja -S "$SRC/tensorflow/lite/c" -B "$B" "${CROSS[@]}" \
        -DCMAKE_BUILD_TYPE=Release -DTENSORFLOW_SOURCE_DIR="$SRC" -DTFLITE_C_BUILD_SHARED_LIBS=OFF \
        -DTFLITE_ENABLE_XNNPACK=ON -DTFLITE_ENABLE_GPU=OFF -DTFLITE_ENABLE_NNAPI=OFF \
        -DTFLITE_ENABLE_EXTERNAL_DELEGATE=OFF -DABSL_PROPAGATE_CXX_STD=ON \
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
        -DFETCHCONTENT_SOURCE_DIR_ABSEIL-CPP="$D/abseil-cpp" -DFETCHCONTENT_SOURCE_DIR_EIGEN="$D/eigen" \
        -DFETCHCONTENT_SOURCE_DIR_FARMHASH="$D/farmhash" -DFETCHCONTENT_SOURCE_DIR_FFT2D="$D/fft2d" \
        -DFETCHCONTENT_SOURCE_DIR_FLATBUFFERS="$D/flatbuffers" -DFETCHCONTENT_SOURCE_DIR_GEMMLOWP="$D/gemmlowp" \
        -DFETCHCONTENT_SOURCE_DIR_CPUINFO="$D/cpuinfo" -DFETCHCONTENT_SOURCE_DIR_ML_DTYPES="$D/ml_dtypes" \
        -DFETCHCONTENT_SOURCE_DIR_RUY="$D/ruy" -DFETCHCONTENT_SOURCE_DIR_XNNPACK="$D/xnnpack" \
        -DFETCHCONTENT_SOURCE_DIR_FP16_HEADERS="$D/fp16" -DFETCHCONTENT_SOURCE_DIR_NEON2SSE="$D/neon2sse" \
        -DPTHREADPOOL_SOURCE_DIR="$D/pthreadpool" -DFXDIV_SOURCE_DIR="$D/fxdiv" -DCPUINFO_SOURCE_DIR="$D/cpuinfo" \
        -DFP16_SOURCE_DIR="$D/fp16" -DKLEIDIAI_SOURCE_DIR="$D/kleidiai" >"$R/configure-$ARCH.log" 2>&1 \
        || { tail -20 "$R/configure-$ARCH.log"; exit 1; }
fi

echo "== 4/5 build ($ARCH, $JOBS at a time)"
ninja -C "$B" -j"$JOBS" tensorflowlite_c >"$R/build-$ARCH.log" 2>&1 || { grep -B2 -A12 "FAILED\|error:" "$R/build-$ARCH.log" | head -60; exit 1; }

echo "== 5/5 one archive and its headers"
# Which of the hundred-odd archives a program using the C API and XNNPACK
# really takes from: link a probe against all of them and ask the linker.
P="$R/probe-$ARCH"
rm -rf "$OUT" "$P" && mkdir -p "$OUT/lib" "$OUT/include" "$P"
cat > "$P/probe.c" <<'C'
#include "tensorflow/lite/c/c_api.h"
#include "tensorflow/lite/delegates/xnnpack/xnnpack_delegate.h"
int main(void) {
    TfLiteXNNPackDelegateOptions o = TfLiteXNNPackDelegateOptionsDefault();
    TfLiteDelegate* d = TfLiteXNNPackDelegateCreate(&o);
    TfLiteInterpreterOptions* opt = TfLiteInterpreterOptionsCreate();
    TfLiteInterpreterOptionsAddDelegate(opt, d);
    TfLiteInterpreterOptionsSetNumThreads(opt, 2);
    TfLiteInterpreterOptionsSetErrorReporter(opt, 0, 0);
    TfLiteModel* m = TfLiteModelCreate("", 0);
    TfLiteInterpreter* in = TfLiteInterpreterCreate(m, opt);
    TfLiteInterpreterAllocateTensors(in);
    TfLiteInterpreterInvoke(in);
    TfLiteTensor* t = TfLiteInterpreterGetInputTensor(in, 0);
    const TfLiteTensor* u = TfLiteInterpreterGetOutputTensor(in, 0);
    int n = TfLiteTensorNumDims(t) + TfLiteTensorDim(t, 0) + (int)TfLiteTensorType(u) + (int)TfLiteTensorByteSize(u);
    TfLiteTensorData(t);
    TfLiteInterpreterDelete(in); TfLiteInterpreterOptionsDelete(opt); TfLiteModelDelete(m);
    TfLiteXNNPackDelegateDelete(d);
    return TfLiteVersion()[0] + n;
}
C
"$CC" -O2 -c "$P/probe.c" -I"$SRC" -o "$P/probe.o" -H 2>&1 | grep -o "$SRC/[^ ]*\.h" | sort -u > "$P/headers.txt"
ALL=$(find "$B" -name "*.a" | sort)
# shellcheck disable=SC2086
"$CXX" -o "$P/probe" "$P/probe.o" -Wl,--start-group $ALL -Wl,--end-group \
    -static-libstdc++ -static-libgcc -lpthread -ldl -lm -Wl,--trace 2>&1 \
    | grep "^$B" | sed -E 's/\(.*//' | sort -u > "$P/used.txt"
[ -s "$P/used.txt" ] || { echo "the probe did not link" >&2; exit 1; }
{
    echo "CREATE $OUT/lib/libnightfall_litert.a"
    while read -r a; do echo "ADDLIB $a"; done < "$P/used.txt"
    echo "SAVE"; echo "END"
} | "$AR" -M
"$RANLIB" "$OUT/lib/libnightfall_litert.a"
while read -r h; do
    rel="${h#"$SRC"/}"
    mkdir -p "$OUT/include/$(dirname "$rel")"
    cp "$h" "$OUT/include/$rel"
done < "$P/headers.txt"
cp "$SRC/LICENSE" "$OUT/LICENSE.tensorflow"
echo "LiteRT v2.21.0 $ARCH: $(wc -l < "$P/used.txt") archives merged, $(du -h "$OUT/lib/libnightfall_litert.a" | cut -f1)" | tee "$OUT/VERSION"
