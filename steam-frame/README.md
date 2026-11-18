# Steam Frame build

Everything needed to turn this tree into the package that installs on the
Frame. Written 2026-11-12 after the build environment had to be rebuilt from
nothing in a new workspace.

```
steam-frame/build-frame.sh 5a      ->  $FRAME_NATIVE/NightfallFrame-phase5a.tar.gz
```

## What goes into a package

| Part | Where it comes from |
|---|---|
| `Nightfall.arm64` | Up to 6e, and 6g: Godot 4.7-stable's **official** Linux arm64 *debug* export template, unmodified (inside `Godot_v4.7-stable_export_templates.tpz` on Godot's GitHub releases, as `linux_debug.arm64`). 6f, and every build from 6h, use the same source built here with the patches in [`engine/`](engine/README.md), passed as `FRAME_ENGINE`. |
| `Nightfall.pck` | `godot --export-pack NightfallSteamFrame` (preset in `export_presets.cfg`, feature tag `steamframe`). Needs the Godot 4.7 editor for the build machine. |
| `addons/.../libnightfall-stream.linux.template_debug.arm64.so` | `addons/nightfall-stream` cross-compiled with `NIGHTFALL_PLATFORM=steamos`. Named "debug" because the debug engine template asks for that name; it is a Release build. |
| `nightfall.sh`, `install.sh`, `steam_cef.py`, art, licences, ... | `steam-frame/package/` |
| `VERSION` | the build name given to the script |

## Tools

- **Compiler and sysroot:** Godot's buildroot SDK,
  `aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2` from
  github.com/godotengine/buildroot, release `godot-2023.08.x-4` (GCC 13.2,
  glibc 2.28). Unpack it and run its `relocate-sdk.sh` once.
- **vcpkg** (github.com/microsoft/vcpkg, bootstrapped). The baseline is pinned
  in `addons/nightfall-stream/vcpkg-configuration.json`.
- **Godot 4.7-stable editor**, **cmake**, **ninja**, **pkg-config**, **perl**.

## Dependencies and how their sources are fetched

FFmpeg 7.1.2, OpenSSL 3.6.0, curl 8.17.0, Opus 1.5.2, zlib 1.3.1, simde,
godot-cpp 4.4 and moonlight-common-c are built by vcpkg as static, position
independent arm64 libraries and linked into the one `.so`.

`toolchain/overlay-ports/` holds copies of the vcpkg ports with one change:
sources are fetched with `vcpkg_from_git` at a pinned commit instead of
`vcpkg_from_github`'s archive download. The workspace this was set up in
could reach GitHub through git and release downloads but not its `/archive/`
URLs. The commit each version tag resolved to is in
`toolchain/source-pins.txt`; git checks the content against that commit ID.
`pkgconf` is a placeholder that runs the build machine's own `pkg-config`.
On a machine with normal internet access these overlays can simply be
dropped (`--overlay-ports` removed) to use vcpkg's own ports.

## Notes

- The Frame build deliberately finds none of avahi, pipewire, systemd or X11
  (`PKG_CONFIG_LIBDIR` points at an empty folder, X11 lookup is disabled), so
  the library depends only on glibc, libstdc++ and libgcc - same as build 4i.
- `toolchain/toolchain-frame.cmake` sets `-fPIC` for everything; without it
  the static libraries can't be linked into the shared library.

## Records kept with the port

- `CHANGELOG.md`: every build handed over for testing, newest first. Add an
  entry with each build.
- `UPSTREAM-FIXES.md`: faults found in the original Nightfall or Meteor while
  porting, and whether the fix applies to every device. Add to it whenever a
  build fixes something that isn't Frame-specific.

## Logs and privacy

- The app's own logs (`~/Games/NightfallFrame/logs/` on the headset) are
  written as they come and stay on the headset.
- The copy meant for sending (`~/Downloads/Nightfall-logs/`) goes through
  `package/share_log.py`, which masks network addresses, ids, keys and
  names. `python3 steam-frame/test_share_log.py` checks what it masks and
  what it leaves alone; add a case there whenever a new kind of detail turns
  up in a log.
- New log lines: never a PC's name, a PIN, a key or a certificate, and
  nothing that was said to voice typing. Addresses and ids are tolerated in
  the app's own log because the cleaner covers them, not as a habit.

## On-headset depth (AI 3D without Meteor)

From build 6x the Frame can make AI 3D's depth itself:
`addons/nightfall-stream/src/video/frame_depth_engine.h` runs a ZipDepth
model on the processor with LiteRT (TensorFlow Lite) and XNNPACK, and takes
its pictures straight from the video decoder. Meteor's depth still comes
first when the PC offers it.

To build it:

1. `steam-frame/build-litert.sh arm64` once (about 45 minutes on two cores).
   It leaves `$FRAME_NATIVE/litert/dist-arm64/`, which the library's CMake
   build finds by itself. Without it the build works as before and the
   package has no on-headset depth.
2. Put the two models in `$FRAME_NATIVE/depth_models/`:
   `zipdepth_512x288_fp16.tflite` and `zipdepth_256_int8dr.tflite`, from
   Moonlight XR for Frame's `assets/depth/`
   (github.com/simplysanatori/moonlight-xr-steam-frame); they are Sean
   Gilleece's Moonlight XR conversions of ZipDepth, the same files as in
   github.com/Gilleece/moonlight-android-xr. `build-frame.sh`
   checks them against `depth-models.sha256` and puts them in the package's
   `depth_models/` folder. ZipDepth is Fabio Tosi's, MIT licensed.

3. For the test choice "Headset: GPU" (the depth model on the graphics
   chip): `steam-frame/build-ncnn.sh arm64` once (about 25 minutes). It
   fetches ncnn at the revision upstream pins, applies
   `ncnn-low-priority.patch` (the one change to ncnn; the file says why) and
   leaves `$FRAME_NATIVE/ncnn/dist-arm64/`. The model is Meteor's
   `zipdepth_wide_512x288.ncnn.param` and `.bin` (from a Meteor install's
   `share/nightfall-meteor/models`), also in `$FRAME_NATIVE/depth_models/`,
   checked against `depth-models-gpu.sha256`. Without ncnn the build works
   and the choice is not offered.

To test it without a headset: `build-litert.sh x64`, then configure the
library for this machine with `-DFRAME_LITERT_DIR=$FRAME_NATIVE/litert/dist-x64
-DNIGHTFALL_BUILD_FRAME_DEPTH_TEST=ON` (and, after `build-ncnn.sh x64`,
`-DFRAME_NCNN_DIR=$FRAME_NATIVE/ncnn/dist-x64`) and run
`frame_depth_test $FRAME_NATIVE/depth_models`. It checks the picture shrink,
the smoothing, and that each model loads and puts a floor's near end nearer
than the sky. Its timings are this machine's, not the headset's.
