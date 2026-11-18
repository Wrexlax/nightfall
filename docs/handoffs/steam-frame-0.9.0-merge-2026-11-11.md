# Steam Frame port: merge onto upstream Nightfall 0.9.0 (2026-11-11)

Branch `frame-0.9` = upstream tag `v0.9.0` (77566e7) with `steam-frame-native`
(107 commits, last build 4i) merged in once. `steam-frame-native` and build 4i
stay as the fallback until a merged build passes the headset retest.

**Status (2026-11-12): built as package 5a; not yet run on the headset.**
The build environment was rebuilt from nothing (recipe:
`steam-frame/README.md`, script: `steam-frame/build-frame.sh`). What was and
wasn't checked is at the end.

## Conflicts (18 files, 53 spots) - how each was settled

Rule used: keep every confirmed Frame feature, take upstream's new code, and
where both sides solved the same problem keep one implementation.

| File | Outcome |
|---|---|
| `main.gd` | Both sides kept. Frame's `comp == null` guards sit in front of upstream's `pcvr_handover.menu_only` checks. `_process_button_input`: ButtonBindings still owns the buttons on the Frame; otherwise upstream's new `primary_controller_shortcuts.poll()`. Third cursor mode is labelled "PC Cursor" on the Frame, "Hidden" elsewhere. |
| `src/xr_interaction.gd` | Upstream's `_stereo_click_uv_x()` used at every click site, with the Frame's `_click_3d_bias()` (0 on the Frame) inside it. Frame's hand-ownership/borrowed-hand logic kept on top of upstream's `effective_primary_hand()`. Grab-bar reveal checks both hands (Frame) and knows `screen_tab` (upstream); upstream's "show the bar while pointing at the screen" is skipped on the Frame, where the bar only shows when pointing near it. |
| `src/menu_schema.gd` | Frame layout unchanged on the Frame (rows of five). Elsewhere upstream's layout. See "Menu" below. |
| `src/virtual_keyboard.gd` | Frame's Super-latch / Mic / Trackpad key logic kept, sending through upstream's `_send_key()`. |
| `src/ui_controller.gd` | Both sides' new functions kept. AI 3D lock state follows upstream (several screens no longer lock it). |
| `src/stream_manager.gd` | Upstream's static `pair_failure_message()` now also carries the Frame's plain-language pairing hints; shown on the server screen's own message line. |
| `src/screen_shortcut_bar.gd` | Upstream's dark backdrop behind the icons kept; hidden while the Frame's Gamepad lock shows the lone gamepad icon. |
| `src/depth_estimator.gd` | **Upstream taken; the Frame's own flip dropped** - see "Depth orientation". |
| `src/vr_screen.gd`, `state_manager.gd`, `settings_controller.gd`, `native_xr_renderer.gd`, `input_handler.gd`, `controller_mapper.gd`, `composition_layer_manager.gd` | Both sides kept (small). Primary Hand default stays Auto. |
| `meteor/src/proxy.rs`, `meteor/Cargo.toml`, `meteor/Cargo.lock` | Upstream taken. Upstream made the same per-client flow-count fix the port had. Meteor's version is upstream's 0.9.0. |

## Things the text merge did not flag, found by reading the result

1. **Tab number clash.** The Frame's Buttons tab was tab 7; upstream 0.9 uses 7
   for its PCVR page. Buttons is now `BUTTONS_TAB := 8`.
2. **Two AI 3D switches.** Both sides added an AI 3D on/off button to the AI 3D
   tab. Upstream's (`_ui_3d_enable_btn`) is kept; the Frame's is no longer created.
3. **Two "PC cursor follows the pointer" features.** Frame: Cursor Follow.
   Upstream: Follows Pointer. Each is shown only on its own platform, so the
   Frame keeps the tested one.
4. **Bezel and Double Click were in two places.** Bezel: Display row 1 on the
   Frame, Picture tab elsewhere. Double Click: upstream's Settings > Input row,
   hidden on the Frame as before.
5. **Curve rebuild ran twice.** Upstream now rebuilds a curved screen's mesh when
   its radius drifts 1%; the Frame already did this at 5% and then re-applies
   its in-scene curved screen. The Frame keeps only its own check.
6. **Depth orientation** (below).
7. **Meteor version check** (below).
8. Empty menu rows: a Settings row whose buttons are all hidden on this device
   now hides its title and gap too (the "Input" title would otherwise show
   with nothing under it on the Frame).

## Depth orientation - the one behaviour change to test first

On 0.8.1 the port flipped Meteor's depth map at upload on the Frame, because
Depth View was upside down without it. Upstream 0.9 found the root cause: the
legacy shaders' Depth View flipped its own read, while the real 3D warp read
the map as stored. So with the flip, Depth View looked right and the warp was
using a vertically mirrored map. Upstream fixed it in the shaders
(`depth_bottom_first`); the Frame uses those legacy shaders (the native
renderer is off there).

The merge therefore follows upstream: no flip on the Frame, and the Frame's
curved-screen Depth View reads the map the same way the flat one now does.
Expected on the headset: Depth View upright on flat and curved screens, and
3D that matches the picture better than before. If Depth View is upside down
instead, restore the Frame flip in `_apply_meteor_map()`.

## Meteor

- The merged headset code still speaks the same depth and microphone protocol
  as the port's Meteor 0.1.4, so 0.1.4 can stay on the PC for the first test.
- Upstream's official Meteor 0.9.0 does **not** have the port's "quiet flows"
  fix (audio lost after ~30 s of PC silence). The old test "Meteor >= 0.1.2"
  would have wrongly trusted it. Now: Meteor built from this tree lists
  `"fixes": ["quiet-flows", "mic-stereo"]` in its discovery reply; the headset
  sends audio through Meteor only when it sees `quiet-flows` or a 0.1.2-0.1.x
  port build, and otherwise uses the direct-audio workaround.
- Meteor in this tree = upstream 0.9.0 + quiet flows + stereo mic + the mic
  "sender keeps its stream" rule. Not compiled here.

## Menu (Frame)

- Display row 1: Passthrough, SBS, AI 3D, Curve, Bezel. Row 2: Background,
  Ambient, Color, Glow Strength, Glow Size. (unchanged)
- Picture row 2: Sharpen, Flat Screen, **PT Fade** (new from upstream: darkens
  passthrough behind the screen; default Off).
- Control row 1: Cursor Type, Cursor Follow, Pointer Ray, Cursor Steady,
  Cursor Off Screen. (unchanged)
- Screens tab (upstream's multi-screen / browser tab) stays hidden on the
  Frame. Bringing virtual monitors to the Frame is separate follow-up work.

## New upstream behaviour now active on the Frame (untested there)

- `controller_hand_policy`: with only one controller present, it becomes the
  pointing hand regardless of Primary Hand.
- `startup_hand_fallback`: only acts when hand tracking reports hands; it
  should stay idle on the Frame.
- PCVR handover, wristwatch, browser screens: gated on upstream Meteor / Android.
- Connection start-up and shutdown fixes in the native stream code.

## Not done

- Headset retest of 5a against the backlog's confirmed features.
- Meteor from this tree has not been compiled (the PC keeps the port's 0.1.4).
- Translations for the port's own menu text and tooltips: `test_localization`
  fails on exactly those (a known "before 1.0" item, not a merge break).
- Upstream's three new engine patches (`patches/godot-4.7-*`) are not in the
  engine the Frame uses (Godot's stock 4.7 arm64 debug template); two are
  small OpenXR fixes, one is for the native renderer the Frame doesn't use.

## Checks that were run (2026-11-12, on an x86-64 machine, no headset)

- **Build:** the native library compiles and links for arm64 from this tree.
  It needs the same system libraries and glibc level (2.28) as 4i's; the
  package has the same file list as 4i, the same engine binary, and no test,
  tool or doc files in the data pack.
- **Upstream's GDScript suite:** 58 of 59 test scripts pass (57 without the
  native library, plus `test_native_stream_shutdown` with an x86-64 build of
  it). The one failure is `test_localization`, see above.
- **App start, desktop test mode** (`--nf-no-xr`, headless): every script
  loads; no script errors at startup on the normal path or with the Steam
  Frame path forced on (a scratch copy with the arm64 check patched).
- **Menu smoke test** through the dev bridge: every tab opened and every
  option pressed once, on both paths. Frame layout confirmed: 1400 px menu,
  rows of five, Buttons tab present and opening as an ordinary tab, Screens
  hidden, PT Fade on Picture, one AI 3D switch. The only script errors were
  from `main.comp` being null, which is how this test mode runs (the
  composition manager is created during XR start-up); they occur identically
  on the normal path.
- Not checkable without a headset: anything that needs an XR session or a
  stream - layers, the curved screen, depth and 3D, pointer and grab
  behaviour, audio, microphone, voice typing.
