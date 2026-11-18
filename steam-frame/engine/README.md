# The engine in the Steam Frame package

From build 6h the package's `Nightfall.arm64` is Godot 4.7-stable built here
with the patches in this folder, not Godot's official download. (6f was the
first try; 6g went back to the official engine for one build.)

## What it is for, and what it costs

Foveated rendering on the Frame needs the fix in patch 0001. With it the
driver (Mesa Turnip) may draw the scene in its tiled mode, which foveation
needs and which is slow for Nightfall's scene when nothing is foveated.
Measured on the headset, curved screen 7.6 m wide at 6 m, fade 50%, glow on,
3408 per eye:

| Engine | Foveation | GPU time per frame |
|---|---|---|
| official | none possible | 6.2 ms |
| patched | off, driver left to choose | 12.6 to 13.4 ms |
| patched | Low / Medium / High, set at start | 7.4 / 7.2 / 7.2 ms |
| patched | High, PT Fade 0% | 6.3 ms |
| patched | any level after a second change while running | 14 to 15 ms (foveation no longer applied) |

So the driver is asked for direct drawing whenever Advanced > Foveation is
Off: through Turnip's switches file (`TU_DEBUG_FILE`, switch `sysmem`,
docs.mesa3d.org/drivers/freedreno.html), which the driver re-reads while
running, so the choice can follow the option (6k; 6h and 6j used
`TU_AUTOTUNE_ALGO=prefer_sysmem` at launch). A change of level rebuilds the
eye pictures (see `SettingsController.apply_foveation`): the engine asks for
the runtime's foveation only when a swapchain is created with the level
above 0, and a level changed on a live swapchain stopped foveation in 6f. That table is from 6f and 6h, which turned out to be running Godot's own
fixed-centre density map (the level was set after the swapchain existed).
With SteamVR's eye-tracked map in use (6k), curved screen 8.7 m wide at 6 m:
High 5.0 ms, Medium 6.3 ms, Off 8.3 ms. The drawn fade's pixel pattern
showed as a brightness and hue step at the edge of the sharp area; with PT
Fade at 0% the foveation could not be seen at all. Patch 0003 replaces
the drawn fade.

SteamVR starts every app with `TU_AUTOTUNE_FLAGS=preempt_optimize`, which
Mesa's page says forces the tiled mode when the compositor is kept waiting.

## The patches

| Patch | What | Keep until |
|---|---|---|
| `0001-by-region-subpass-dependencies.patch` | Godot PR 124811, unchanged | a Godot release contains it |
| `0002-temporary-diagnostics.patch` | log lines only: what the runtime answers for the eye gaze pose (`OpenXR: eye gaze reading: ...`); whether each swapchain is created with the runtime's foveation; whose density map is in use; what the runtime reports for the eye-tracked sharp area; once a second, how the runtime paces the app's frames (`OpenXR: frame pacing: ...`) and how long each call into the runtime took per frame (`OpenXR: frame parts: ...`) | the questions they answer are settled; then drop it |
| `0003-background-opacity-in-xr.patch` | PT Fade: in the stereo (XR) picture, a transparent background drawn with a custom background colour keeps that colour's opacity | Godot offers the same; not proposed upstream yet |
| `0004-no-debug-suffix-in-the-title.patch` | The window's title is the project's name, without the " (DEBUG)" that a debug export template adds (at start in `main/main.cpp`, and again whenever the title is refreshed in `scene/main/window.cpp`). The title is the name SteamOS shows for the running app, and the Frame build is released on a debug template. An app cannot undo it: its own `window_set_title` is overwritten at the next refresh (tried in 8z) | the Frame build moves to a release template |

The engine can go back to Godot's official template once 0001 is released
and 0003 is either upstream or no longer wanted.

### 0001: why foveation needs it

On the Frame, stock Godot 4.7 draws the 3D scene in "subpasses" whose
dependencies lack `VK_DEPENDENCY_BY_REGION_BIT`. The Frame's graphics driver
(Mesa Turnip) then cannot keep them in its tiled mode, and outside that mode
foveated rendering does nothing. Reported as Godot issue 124141; the fix is
Godot pull request 124811 by David Snopek, one added line, not yet merged or
released when this was written (2026-11-14).

### 0003: why PT Fade needs it

Passthrough shows wherever the eye picture is transparent, so a background
of black at 40% opacity would be a 40% fade. Stock Godot's Mobile renderer
can't deliver that: it clears a transparent viewport's background to fully
transparent whatever the background colour says, and its 3D buffer has only
2 bits of alpha (clear, a third, two thirds, solid). Until 6k the fade was
therefore drawn: a dark shell around the viewer with a pixel pattern to
imitate the in-between opacities, which cost frame time, showed faint rings,
and showed a brightness step at the edge of the foveated area. That code was
removed in 6m (see `src/passthrough_fade.gd` before it), so **without this
patch there is no PT Fade on the Frame**.

The patch leaves the 3D buffer alone and hands the background colour's
opacity to the tonemapper, the last step, which writes to the 8-bit eye
picture: `alpha = mix(background_opacity, 1, alpha)`. That equals a black
surface of that opacity behind everything else, costs nothing, and has every
step. It applies only where all of these hold, so nothing else changes:
the viewport is transparent, the picture is stereo (XR), and the
environment's background is a custom colour. Not done for SMAA, whose
intermediate buffer is 10-bit again (Nightfall on the Frame offers FXAA).

### The build's name

The build is given a name, `nightfall<N>`, with N the number of the last
patch it carries (`BUILD_NAME` below). The app reads it
(`FrameEngine.patch_level()`, `src/frame_engine.gd`) and uses what that
engine can do; on any other engine it keeps to what stock Godot does (no
PT Fade). **When a patch is added, raise the number in the build command
and add a constant in `frame_engine.gd`.**

## How it is built

```
git clone --depth 1 --branch 4.7-stable https://github.com/godotengine/godot.git godot-4.7
git clone --depth 1 --branch 4.8.1 https://github.com/SCons/scons.git scons   # where pip can't install it
cd godot-4.7
git apply ../nightfall/steam-frame/engine/*.patch
PATH="$FRAME_SDK/bin:$PATH" BUILD_NAME=nightfall4 python3 ../scons/scripts/scons.py \
    platform=linuxbsd arch=arm64 target=template_debug production=yes lto=none -j2
# -> bin/godot.linuxbsd.template_debug.arm64  (already stripped)
FRAME_ENGINE=$PWD/bin/godot.linuxbsd.template_debug.arm64 ../nightfall/steam-frame/build-frame.sh 6l
```

`FRAME_SDK` is the same Godot buildroot SDK the native library is built with
(see `../README.md`). 36 minutes on two cores for the first build; a changed
file takes a minute or two.

Shader changes can be checked before a headset run by compiling the shader
with the engine's own copy of glslang (`thirdparty/glslang`); the engine
compiles its shaders on the device, so a mistake in one would otherwise show
first as a black picture there. 0003's shader was checked this way in all
eight of its variants.

## Differences from the official template

- No Wayland support (`wayland-scanner` was not on the build machine). The
  Frame runs Nightfall under X11.
- No AccessKit screen-reader driver (its libraries were not fetched).
- No link-time optimisation (`lto=none`; the official build uses full LTO,
  which needs more memory than the build machine had). Slightly slower code.
- It reports itself as `4.7.stable.nightfall4` (6l to 8z: `nightfall3`; 6h to
  6k: `custom_build`).

Godot is MIT-licensed; a modified engine may be shipped. Say so wherever the
port is shared.
