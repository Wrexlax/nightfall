# Fixes from the Steam Frame port that may be useful to the original Nightfall

A running list for the original developer and for anyone comparing this port
with upstream, offered in case it is useful. It covers problems that aren't
specific to the Frame: they turned up while porting and are in upstream
Nightfall or Meteor too. Add to it whenever a build fixes something that
isn't Frame-specific. The build or
Meteor revision that carries the fix is in brackets.

"Upstream" is tB0nE/nightfall; the port sits on its 0.9.0 tag.

## Fixed for every device

These changes are not behind a Steam Frame check, so a Quest build made from
this tree has them too.

- **Saved hosts had no name.** `add_host()` stored the pairing address as
  `hostname`, and `<hostname>` in the host's serverinfo was never read
  (`welcome_screen.gd` says so in a comment), so the server list could only
  show `ip:port`. The name is now read at the pairing check and at every
  stream start, and kept on the host record; it is never logged.
  `computer_manager.cpp` `_remember_host_name()`. A record also has a
  `name` of the user's own (`config_manager.cpp` `get_hosts()`), carried
  to the new record when a pairing replaces the old one. [6s]
- **The welcome page never showed the host's name or address.**
  `update_welcome_info()` looked for `WelcomeHostName` and `WelcomeHostIP`
  as direct children of the page; `build_welcome_screen()` puts them inside
  a box, so both lookups returned nothing and the labels stayed empty. [6s]
- **Connect forgot which host was meant.** Picking a host in the server
  list saves its `server_unique_id` to `last_connection.cfg` (added
  upstream on 2026-08-27 for hosts sharing an address), but
  `on_pair_pressed()` then rewrote the file with the address alone. After a
  restart the first host saved at that address was chosen. [6s]
- **Hosts sharing an address shared their settings.** `host_state.cfg` was
  keyed by the text of the address field, which for a paired host is its
  bare address: two hosts on one PC (different ports) read and overwrote
  one section, stream settings and screen layout both. Paired hosts are now
  keyed by `server_unique_id`, with the address section as the starting
  point. `SavedHosts.settings_section()`, `state_manager.gd`. [6s]
- **A saved host could not be removed on its own.** The only choice was
  "Clear Saved Servers", which dropped every pairing on a single press with
  no question asked. Each host now has Remove (two presses) and Rename.
  [6s]
- **Screens tab, Save added duplicate layout pictures.** Save stored the
  current arrangement even when it was already one of the pictures (the
  screens side by side gave a second side-by-side card). A grid arrangement
  that already exists is now selected instead.
  `MonitorPresets.find_same_grid_layout()`. [6r]
- **Applying a layout removed the virtual screens.** With real virtual
  displays in the stream, `apply_staged_monitor_config()` strips the
  client's stand-ins for virtual monitors before applying a layout that
  restarts nothing. The host's own virtual monitors (ids `v1`, `v2`) are
  not in that staged layout either, so they went too: the screens vanished
  and `main.layout` forgot them until their number was changed. They are
  now kept when their number is unchanged.
  `src/settings_controller.gd` `layout_without_placeholders()`. [6q]
- **A stream setting changed during a restart was dropped.**
  `_schedule_stream_restart()` returns when there is no stream, which is
  also the case while one is restarting. Cycling Bitrate (or Resolution,
  FPS, Codec) on past the 0.8 s pause therefore left the stream at the value
  the restart began with while the button showed the later one (seen on the
  Frame: button at 120, stream at 60 for three minutes). A request made
  during a restart is now kept and run once the stream is back.
  `src/settings_controller.gd` `on_session_phase()`. [6o]
- **Address keypad acted on the end of the text.** Digits and DEL on the
  welcome screen's keypad ignored the caret: pointing into the middle of an
  address and typing still added to the end. `src/welcome_screen.gd`. [5p]
  They ignored a highlight as well: the field drops it when a key takes
  the focus (`deselect_on_focus_loss_enabled`), so a key could never
  replace it. [8w]
- **A screen could be resized with no upper limit.** Dragging a corner only
  had a minimum. Past a certain size the corners, the grab bar and the icons
  are outside the view, the size is saved per host, and nothing in the menu
  could shrink it again. Width is now limited to three times the distance,
  and an oversized saved size is corrected on connecting.
  `src/vr_screen.gd` `max_width_at()`, `main.gd` `cap_screen_sizes()`. [5x]
- **A resting controller kept pointing (since 0.9).** `_prioritize_tab_overlay()`
  calls `force_raycast_update()` on the active ray every frame, and that
  works on a ray that has been switched off for a resting controller. So
  "resting (disabled)" never stopped the pointer, and upstream's own rest
  after four still seconds had no effect. `src/xr_interaction.gd`. [5m]
- **Script error at every quit.** The Meteor depth receiver's thread was
  never stopped before the scripts were unloaded ("Nonexistent function ''
  in base 'GDScript'", then "A Thread object is being destroyed without its
  completion"). `main.gd` `_exit_tree()`. [5j]
- **0.9.0 did not compile for non-Android targets.** Code in the native
  stream library sat outside its `#ifdef __ANDROID__`. [5a]
- **A settings row with every button hidden still showed its title and gap.**
  [5a]

- **A virtual screen switched off comes back at every stream start.** The
  Screens page stages its counts from 0 in each app run (`_staged_virtual_count`,
  `_last_applied_virtual_count`), whatever is saved for the host or live in the
  stream; `sync_staged_from_current_layout()` ("call whenever the Monitors tab
  is opened") is never called. With one virtual screen saved, setting Virtual
  to 0 and pressing Apply is "no change": the screen is removed on the headset
  only, the host isn't told, `virtual_display_count` stays 1 and the next
  launch asks for it again. The page now syncs when it opens, and Apply also
  compares with the saved count. `src/ui_controller.gd` `switch_tab()`,
  `src/settings_controller.gd` `virtual_count_changed()`. [7z]
- **A stream that isn't through Meteor is described as if it were.**
  `_meteor_address` in `src/stream_manager.gd` keeps the last Meteor found when
  a later launch's probe gets no answer, so `meteor_address()` is not empty for
  a stream that went straight to the host. [7z]

## Meteor (the PC helper): Quest users have these too

- **Sound stopped after about 30 seconds of PC silence and did not return.**
  Meteor's UDP relay closed a flow after 30 s without host traffic. It now
  closes a flow only when the client is quiet too. Upstream's 0.9.0 still has
  the fault. Meteor announces the fix as `quiet-flows`. [Meteor 0.1.2,
  0.9.0-sf1]
- **The headset microphone was written to the left channel only.** Announced
  as `mic-stereo`. [Meteor 0.1.3, 0.9.0-sf1]
- **An accepted microphone sender could lose its stream** to another sender
  mid-recording. The accepted sender keeps it while its packets continue.
  [Meteor 0.1.4, 0.9.0-sf1]
- **Microphone cut about 29 s into a recording** when a stale video flow
  closed. Fixed in the port by counting flows per client [Meteor 0.1.4];
  upstream made the same fix independently in 0.9.0.
- **Windows: no way to get the larger VDA depth model on most GPUs.** The
  tray never offers the Vulkan VDA download (Linux's does; the command line
  `--download-vda-vulkan 518` works), and the TensorRT download is refused on
  every GPU but the RTX 30 series because only that builder file's hash is
  pinned for Windows. Tray entries added and a script to measure the other
  hashes written (`meteor/tools/measure_tensorrt_builders.ps1`). [Meteor
  0.9.0-sf2: source only, not built or run yet]

- **Host depth stays silent until the client happens to ask for a
  keyframe.** Meteor's depth decoder starts only at a keyframe, and nothing
  asks the host for one when depth is turned on mid-stream ("Host depth" in
  the tray) or when a client's depth connection is made after the stream
  began. In a log of 2026-11-17 that took 12.5 minutes; "Reconnect Audio"
  hides it because a new stream begins with a keyframe. Fixed from the
  client's side on the Frame: it asks for a keyframe when the depth
  connection is up and no map has come for 2 s (then 8 s, 30 s).
  `src/depth_estimator.gd` `_ask_keyframe_if_silent()`; not behind a Frame
  check, but it needs the `request_keyframe()` binding added to the stream
  library in this port. [8a]

- **Connect pressed while Quick Start is connecting fails both.** Quick Start
  starts a stream a second after the welcome screen appears
  (`_try_auto_connect()`), and the Connect button starts another without
  looking (`on_pair_pressed()`). The host answers the second launch with
  "Another stream operation is still running", and the failure handler
  returns to the welcome screen, ending the first as well. Connect now
  leaves a connection that is under way alone, and Quick Start stands back
  if one was started by hand during its wait. Not behind a Frame check. [8c]

- **Media keys sent down a stream arrive in Windows as letters** (mute "d",
  volume down "c", volume up "b", previous "q", play/pause "g", next "p";
  seen on the headset in build 8h with Meteor's built-in host and with
  plain Vibepollo). `keyboard_update()` in the host's
  `src/platform/windows/input.cpp` turns every key into a scan code
  (`VK_TO_SCANCODE_MAP`) and sets `KEYEVENTF_EXTENDEDKEY` only for a fixed
  list that has no media key in it; a media key's scan code without the
  E0 prefix is a letter's. Nightfall's own keyboard has no media keys, so
  upstream doesn't show it, but `input_bridge.cpp` maps them and any
  client that sends them gets letters. The host's newest source sends
  them properly when its virtual keyboard device is in use
  (`vhf_keyboard_mouse_policy.h`, `consumer_usage`). The port goes around
  it: Meteor presses them on the PC. [headset 8j, Meteor 0.9.0-sf13]

- **Two copies of Meteor on one PC break pairing approval for one of
  them.** `host.toml` (which holds the host's web login) is shared by every
  copy, each copy's bundled host has its own login file. A copy whose host
  has no login file yet makes a new password and overwrites `host.toml`;
  the other copy's host then refuses the login Meteor uses to submit an
  approved PIN, and both the approval and the "Pair headset" window fail
  with "Cannot submit the PIN" although the host is running. Seen with the
  0.9.1-preview.2 portable zip run beside an installed 0.9.0. Meteor now
  compares the host's login with `host.toml` at start and sets it again
  when they differ. The message for a refused login is also the one for a
  host that isn't running; not changed. [Meteor 0.9.0-sf18]
- **A pairing request is easy to miss on Windows.** It is announced by a
  notification only, which Windows holds back during full-screen programs
  and Do Not Disturb, and it lasts 60 seconds. Meteor now also asks in a
  window that stays on top. [Meteor 0.9.0-sf17]

## The engine (Godot 4.7's OpenXR module)

- **A composition layer's swapchain image is taken every frame while the
  session isn't visible, and never handed back.** In session state
  SYNCHRONIZED, `OpenXRCompositionLayerExtension::CompositionLayer::
  on_pre_render()` still calls `update_and_acquire_swapchain()` for every
  layer whose viewport updates; the release belongs to composing a frame
  that is shown, which doesn't happen. Every later acquire fails with
  `ERROR: Condition "image_acquired" is true` (`openxr_api.cpp:186`): about
  1,000 lines a second with seven layers at 144 Hz. Seen on the Steam Frame
  with SteamVR's runtime; not checked on Quest, where the app is paused
  instead. Worked around in the app by holding the layers' viewports at
  "don't update" while not shown (`src/frame_session_watch.gd`, Frame only).
  The engine itself is unchanged. [8a]

## In the original too, fixed on the Frame only so far

The fix exists but is switched on for the Steam Frame alone. Each would help
on Quest as well.

- **The screen flew away when walking with the grab bar held.** Hand movement
  is multiplied (x6 sideways, x12 toward/away) and the hand moves with the
  body. The Frame's grab splits body movement from hand movement.
  `src/xr_interaction.gd` `_grab_step()`. [5b to 5e]
- **The keyboard could be flung away** when the other hand's trigger took
  over a grab. The hand that starts a grab keeps it. [3p]
- **Clicks in 3D landed beside the drawn cursor** (a fixed click bias).
  [2026-11-08, before the lettered 3-series]
- **Tilting a grabbed screen also pushes it.** The grab measures the
  controller's front end, which swings a few centimetres toward or away from
  you when the wrist bends; that is multiplied by 12 like a push. In a
  simulated 30 degree bend a screen 3 m away came 48 cm closer. On the Frame
  the part of each step that a wrist turn could have made is not counted.
  `src/xr_interaction.gd` `GRAB_WRIST_LEVER`. [5r]
- **The in-scene screen's minification filter is very heavy**: up to 16
  full YUV-to-colour samples per pixel. Measured on the Frame at about 3 ms
  of GPU time per frame for a large screen. `footprint_stream_fast()` in
  `stereo_screen_core.gdshaderinc` does the same job with four brightness
  reads, one read of the colour planes and one conversion. [5l, 5n, 5s]
- **PT Fade does nothing without equirect layers.** Upstream's fallback (the
  background's alpha) is ignored by Godot when the background is transparent.
  [5b, 5i]
- **Nothing shows that the stream is muted.** The Frame gets a red Stream tab
  and a Muted button. [5h]

## To re-check before reporting

- A connection timeout that was not cancelled when pairing started. Fixed in
  the port on 0.8.1 (APK fix2); not confirmed whether 0.9 still needs it.
- Typed text with non-ASCII characters cut short (a UTF-8 byte length). Fixed
  with voice typing [3s]; not confirmed that the fault was upstream's.
- A screen drawn in the 3D scene under Godot's Mobile renderer passes
  through a 10-bit linear buffer with twice the range: 8-bit tones below
  about 40 come out as only 12 levels (bands in shadows). The Frame build
  switches on `RenderingServer.material_set_use_debanding()` [5r]. Not
  checked whether a Quest build draws its screen in the scene often enough
  to matter (it normally uses composition layers).
- AI 3D tab: Hz Cap stays shown and adjustable while Meteor makes the depth
  on the PC, where it does nothing (it paces the on-headset model only;
  `stream_backend.set_depth_hz_cap`). Hidden on the Frame [6l]. Not checked
  how the Quest build presents it with host depth on.
- The depth channel's writes from Meteor to the headset stall for 250 to
  300 ms about every 7 s on Wi-Fi (Meteor's "Depth delivery gap" lines). Not
  investigated; may be the network only.
- Meteor (Windows): a click on *any* tray notification approves a pairing
  request that happens to be waiting (`tray_windows.rs`,
  `NIN_BALLOONUSERCLICK`: it approves `pairing.pending()` without checking
  that the notification clicked was the pairing one). Only the pairing
  notification exists today, so it is not reachable yet; found when a
  second notification was about to be added (2026-11-16), which was dropped
  for this reason. Worth a guard before anything else uses notifications.
- Meteor's "video tap" log line repeats twice a second with unchanged
  figures once a stream has stopped arriving (20 and more copies in a row in
  the 2026-11-16 log), and its "incomplete" figure can wrap
  below zero after a new stream starts on the same flow ("1583 frames,
  18446744073709551045 incomplete"). `meteor/src/video_tap.rs`,
  the figures since the last line. Not fixed; cosmetic.
- Meteor (Windows): the headset's microphone can reach Meteor and still not
  reach Windows for a whole stream, with nothing in Meteor's log. Seen twice
  on 2026-11-15 (once, and on the first stream after a headset restart).
  Second time, measured: the headset sent 100 packets a
  second with speech in them (peaks -5 to -16 dBFS), Meteor logged
  "Microphone stream from ...", "Mute microphone" was unticked, and Windows'
  level bar for CABLE Output stayed flat. A new stream (Reconnect Audio)
  cured it at once without Meteor being restarted, so the device Meteor
  writes to was alive and what was stuck belongs to one microphone
  connection. Cause not found by reading `meteor/src/mic.rs`; every path
  that plays silence or drops a frame there (a frame that fails to decode,
  a full queue to the audio thread, a full device buffer) is silent or logs
  at debug level only. Needs a line at info level when a live stream plays
  nothing but silence, then a second look.
