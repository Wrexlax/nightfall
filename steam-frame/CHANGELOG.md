# Nightfall for Steam Frame: change log

Every build of the port, newest first. One entry per build that was handed
over for testing; add the next one at the top. Faults that belong to the
original Nightfall or Meteor are also listed in `UPSTREAM-FIXES.md`.

Builds 5a onward sit on upstream Nightfall 0.9.0 (branch `frame-0.9`).
Builds up to 4i sat on 0.8.1 (branch `steam-frame-native`).

## On upstream 0.9.0

### 9a (2026-11-18): "Nightfall", without "(DEBUG)"
Everything in 8z; Meteor stays 0.9.0-sf19. The build the preview is
published from.
- **The app is called "Nightfall" in SteamOS.** The Frame build runs on a
  debug export template of Godot, and Godot adds " (DEBUG)" to the window's
  title in such builds: once at start (`main/main.cpp`) and again every
  time the title is refreshed, for instance when the menu's language is
  applied (`scene/main/window.cpp`, `_update_displayed_title`). 8z set the
  title from the app at start, which the next refresh overwrote. The
  engine build of this port now leaves the suffix out in both places
  (`steam-frame/engine/0004-no-debug-suffix-in-the-title.patch`; the
  engine names itself `nightfall4`). It is otherwise the engine every
  build since 6l has run on: 28 of its source files were compiled again
  (the two changed ones and those that hold the engine's name). Checked
  here: the text "(DEBUG)" is no longer in the engine's file (it was).
  **Not seen on a headset.**
- 8z's own title line is taken out again, having done nothing.
- **Confirmed on the headset: SteamOS shows "Nightfall".**
- On the fork (github.com/Wrexlax/nightfall, branch `steam-frame-preview`)
  the port's README is the top-level `README.md`, where a visitor lands;
  the original's is kept as `README-original.md`. It was
  `steam-frame/RELEASE-README.md` until then.
- Release README, after 9a was built: "Two extras on the PC" says what the
  headset's microphone and Game Controller mode need there and where to
  get them (VB-CABLE; ViGEmBus 1.17 or newer), since Meteor's Setup
  installs neither. To go into the package's own README with the next
  build.
- README, also after 9a was built: "The buttons as they come" (what each
  controller button does on a first start, and how the trigger, grip and
  stick move, roll, push away and resize a screen), and "What frame rate
  to expect" (what held in our tests at 90 and 144 fps, and that a color
  camera at its 5K setting hitches at 144 where 2.5K did not).
- Confirmed on the headset and the PC: the default buttons, replacing a
  highlighted part of the address, Meteor 0.9.0-sf19 from its Setup, and
  the Licences entries.
- `test_frame_8z.gd` checks the patch and the recipe. Full test run: 86 of
  86.

### 8z (2026-11-18) with Meteor 0.9.0-sf19
Everything in 8y.
- **Tried and not enough: the app setting its own window title**, to be
  called "Nightfall" in SteamOS and not "Nightfall (DEBUG)". It still said
  "(DEBUG)" on the headset. See 9a.
- **No controller button starts empty.** Both bumpers: Right Click. View
  (left): Nightfall Menu. Left stick click: Ctrl (hold), as the right one,
  so holding it and pushing the stick zooms. They started with nothing on
  them, which on a first look reads as broken. A saved layout is not
  touched; Profiles > Default and Reset Buttons give the new ones.
  `ButtonBindings.CONTROLS`.
- **8y and Meteor sf18 on a new install, confirmed:** installing, pairing
  through Meteor's window, this port's first-install settings, the
  headset's depth models offered, voice commands.
- **Where the port lives is said everywhere**: source and problem reports
  at github.com/Wrexlax/nightfall, in the release README, the package's
  README, the app's Licences page and Meteor's installer (its publisher
  and support links, which were left empty until there was a page).
- **Meteor sf19: the exe no longer carries the build PC's folder names.**
  A program keeps the paths of the source files it was built from, and
  Rust's libraries are downloaded into the account's own folder: the exe
  held `C:\Users\<account>\.cargo\...` 456 times. The build script now
  has them downloaded to a folder without a name in it
  (`%PUBLIC%\nf-cargo`) and has the compiler write the account's folder as
  `~`; it then looks for the account's name in the exe and refuses to make
  an installer from an exe that has it. Nothing else in Meteor changes
  from sf18. `tools/build_meteor_fix.ps1`, `build_frame_installer.ps1`.
  Written without a Windows PC to run it on; **confirmed on the first
  build on the test PC**: the script's check passed, and looked at again
  from outside it, the exe holds the account's name 0 times (456 before)
  and the neutral folder's 456 times, and no file staged for the installer
  holds it.
- The installer script writes the Setup's SHA-256 to a file beside it, for
  `SHA256SUMS.txt`.
- `build-frame.sh` can package either kind of engine
  (`FRAME_ENGINE_KIND=release` names the stream library for a release
  export template), and the installer removes the library of the other
  kind when one build is installed over the other.
- Last look for anything private in what is published (every tracked file,
  text and binary, and the package): none of the values taken out earlier,
  no account or chat names, no times of day; two more leftovers replaced
  (two log file ids in this change log, a clock time in a test).
- Meteor's own readme in the Setup says at its top that this is the port's
  build and where its page is.
- `test_frame_8z.gd`. Full test run: 86 of 86.

### 8y (2026-11-18): credit where it belongs
Works exactly as 8x; only the Licences page's text changes.
- **The two LiteRT depth models are credited to Moonlight XR (Sean
  Gilleece), whose conversions of ZipDepth they are.** They were credited
  to Moonlight XR for Frame, where this port got them. Checked: both files
  are byte for byte the ones in Moonlight XR's own repository (added there
  on 2026-09-30, with the scripts that build them), and Moonlight XR for
  Frame's credits say the same.
- **Moonlight XR for Frame's entry says what is its**: the V4L2 video
  decoder and `steam_cef.py` (both first appear in that project's history,
  2026-10-10), and that this port's launcher script and LiteRT build recipe
  started from its ones.
- **The port's own entry names the Godot fix it carries**: David Snopek's
  pull request 124811 for foveated rendering on the Steam Frame.
- Looked up for the display-rate credit: Valve's developer pages document
  `vrpreferences.json` (read at install or when SteamVR starts) and say
  nothing of changing an app's rate while it runs; doing that with
  SteamVR's `vrcmd` tool was read in Moonlight XR for Frame's source.
- `test_licences.gd` checks the three entries. Full test run: 85 of 85.

### 8x (2026-11-18): 8w with the last of the wording tidied
Works exactly as 8w. The change log, the upstream list and the notes inside
the code no longer quote what was said in testing or say who asked for
what (see 8w); two of those notes are in `install.sh`, which ships in the
package, so the package was made again to match the published source.

### 8w (2026-11-18): the address field replaces what is highlighted; the files to be published tidied
Everything in 8v.
- **Connect by hand: a key takes the place of what is highlighted in the
  address.** Cause: pressing a key on the keypad takes the focus from the
  field, and a text field drops its highlight when it loses the focus, so by
  the time the key acted there was nothing highlighted and it went in at the
  caret. The field now keeps its highlight, a key replaces it, and DEL removes
  it. Nothing highlighted: at the caret, as before. `WelcomeScreen.typed()`,
  `deleted()`; `test_frame_8w.gd` fails with the one line taken out. Upstream
  has the same field.
- **This change log, `UPSTREAM-FIXES.md` and the notes inside the code are
  written for publication.** They no longer describe anyone's home or
  network, give times of day, quote what was said in testing, or say who
  asked for what; the reason for a change is given as a plain sentence.
  What the tests showed is kept, said in general terms ("where the Wi-Fi
  roams to another access point"). A few example values in tests that
  came from real logs are made-up ones now. One comment in `share_log.py`,
  which ships in the package, is among the changes.
- Release README: a "Fixed along the way" section, the screen on the
  ceiling, the grab bar that hides itself, and "native" said against the
  Android app (the original's own Frame build is native too).
- Full test run: 85 of 85.

### 8v (2026-11-18): Shift, Ctrl and Alt for one key or locked; the keyboard's side grabs
Everything in 8u (not installed yet). Install 8v instead.
- **Shift, Ctrl and Alt on Nightfall's keyboard work as on a phone's.** One
  press: down for the next key, then up by itself. A second press: locked,
  shown brighter with a white edge, until pressed again. Held with one hand
  while the other types: down for as long as it is held, like a real one.
  Ctrl, then Shift, then S is one chord, and both go up after it; the same
  after one of the Win panel's shortcuts. Until now every press toggled, so
  Shift stayed on until pressed again. Caps and the Windows key are unchanged,
  and so is every other device's keyboard. `VirtualKeyboard._press_modifier`,
  `_modifiers_after_key`.
- **The expanded side of the keyboard can be grabbed around its keys.**
  The strip under the pad, arrows, number pad, media and Win keys did
  nothing (the whole side counted as "not an empty spot"), and under the
  pad a click there started the trackpad (everything below the tabs
  counted as the pad). Now only the pad's own area is the trackpad, and
  anywhere beside the keys that isn't a key, a tab or the pad grabs the
  keyboard like the rest of it (`_in_trackpad`, `is_empty_spot`).
- **Confirmed on the headset and in its log:** the app reports
  `~/.local/share/NightfallFrame` as its settings folder and went straight to
  streaming with the paired PC; the button mapping (B: Depth View) and the
  glow settings were as left; a changed setting survived a restart; Ctrl then
  C copies and Ctrl is off afterwards; the strip under every panel grabs the
  keyboard. A latched Windows key shows the one-key color, which is right: it
  holds for one key press only.
- `test/test_frame_8v.gd`; suite 84 of 84 (two of upstream's keyboard tests
  failed on the first attempt, because their stand-in for the app has no
  Steam Frame flag; the keyboard now goes by its own). **Not seen on a
  headset.**

### 8u (2026-11-18): a settings folder of this port's own
- **Settings, pairings, buttons and profiles are kept in
  `~/.local/share/NightfallFrame`.** Until now they were in Godot's default
  folder for a project named "Nightfall"
  (`~/.local/share/godot/app_userdata/Nightfall`), which the original
  Nightfall's Steam Frame build uses too: on 2026-11-18, after that build had
  been tried on the same headset, this port started with its settings, and its
  first-install defaults didn't apply because a settings file was there. Set
  in the package's `override.cfg` (Godot's custom user folder), so the project
  itself and other platforms' builds are unchanged.
- **The earlier settings are carried over once**, by the launcher, at the
  first start after updating: copied (the old folder is left as it is),
  without logs and caches, and only when the settings there are this
  port's (its own options all begin with `frame_`; the original's build
  writes none). Otherwise this port starts as on a new install.
- The launcher reads Logging and Foveation from the new folder only; the
  installer looks there first for the menu's language; the uninstaller
  removes the new folder, and the old one only when its settings are this
  port's. `WHERE-THINGS-ARE.txt` and the READMEs say so. The log's first
  lines name the folder in use (`[SETTINGS]`, `[BUILD] settings folder`).
- Tried here: Godot with the same two settings in an `override.cfg` puts
  `user://` in `~/.local/share/NightfallFrame`; the launcher with a
  stand-in for the app in a pretend home folder: earlier settings of this
  port's carried over (logs and caches left out), a second start copying
  nothing and keeping a change made since, the original build's settings
  not carried over, and an empty home. **Not seen on a headset: that the
  exported app takes the folder from `override.cfg` there**; the first log
  line shows it.
- The READMEs: the release page's README written and reviewed
  (`steam-frame/RELEASE-README.md`: highlights, install by double-clicking
  `install.sh`, pairing in detail, "Make it yours", known limits, planned),
  and the package's `README.txt` brought in line.

### 8t (2026-11-18): Head Lock and Bezel change places
Bezel is set once and left alone, while Head Lock is used often, so the two
change places.
- **Head Lock is on the Display tab**, last in its first row (Passthrough,
  SBS, AI 3D, Curve, Head Lock), where Bezel was.
- **Bezel is in Advanced Settings > View & Feel**, in the place Head Lock had
  (Recenter, Bezel, Vibration, Icon Backdrop). General was the first thought,
  but it already has its five (with Camera FPS Limit showing), and a sixth
  would start a second row. View & Feel holds the other "how it looks"
  options.
- Both keep their tooltips and voice commands. `MenuSchema.FRAME_MOVES`;
  moves are now made before the regrouping, so a moved-in option gets the
  place the table names and a moved-out one leaves no empty row.
- Also in this build, from 8s's log: the short picture stops as the
  adapter goes out of range are there on "Wi-Fi only" as well (2, 2, 3
  and 1 s) and were 1 s each on Multi-Link. They belong to the Wi-Fi's
  weak signal before, and the change-over at, a roam between access
  points; not to the adapter's link. Nothing changed for it.

### 8s (2026-11-18): the licence check, and small things from testing
Headset only; Meteor stays 0.9.0-sf18 (built and running on the PC).
- **The Licences page lists what the Steam Frame build contains.** Checked
  against the 8r package: nine entries describe parts that are not in it
  and are no longer shown on the Frame (ALVR; the browser's ad blocker and
  its filter lists; the PyroWave codec with Granite and volk, which is
  Quest-only; the OpenXR Vendors plugin and Meta's headers; LiteRT's GPU
  delegate headers). Other devices' pages are unchanged
  (`Licences.NOT_ON_FRAME`). Versions on the page compared with what was
  built: FFmpeg 7.1.2 (the library reports Lavc 61.19), OpenSSL 3.6.0,
  curl 8.17.0, Opus 1.5.2, zlib 1.3.1, SIMDe 0.8.2, godot-cpp 4.4,
  whisper.cpp 1.9.5 (vendored at d1be6fd), all as stated; LiteRT's
  version (2.21.0) added. **Still open:** the port's own entry says its
  source "is published with each release"; the link goes in when there is
  one.
- **The stream library is already stripped** (the "trim the size"
  question): 41 MB with no debug data and no symbol table. Its size is
  FFmpeg, ncnn with glslang, whisper.cpp and LiteRT. Nothing to gain there.
- **Pressing Logging says when it takes effect**: "Logging starts the next
  time Nightfall starts. Restart Nightfall to log this session's problem." (or
  "...stops..."), in 20 languages; nothing is said when the choice is what the
  run is already doing. Before, a test run went unlogged because Reset
  Settings had switched Logging off and nothing said a restart was needed.
- **The uninstaller's question names button mappings**, which went with the
  settings on 2026-11-18, unexpectedly.
- **The cleaner for SteamOS's own logs** (`collect-steamos-logs.sh`) now
  masks other devices' Steam names and numbers ("from client <id>
  (<name>)"), found in the logs of 2026-11-18.
- From the same session, about the PC's adapter dropping out on Multi-Link
  (8r, sf18): the stream stays up over Wi-Fi with a 1 to 3 s stop of the
  picture, 1 s even where the Wi-Fi does not roam (three tries); on 2026-11-16
  the same test gave only a brief stutter of a couple of frames. To be
  compared on "Wi-Fi only" before anything is changed. And once **the Steam
  client itself crashed** in the second the adapter's link dropped
  (`steam.service: Main process exited, code=dumped, status=11/SEGV` in
  SteamOS's journal) and came back with a menu whose Resume and Exit did
  nothing; Nightfall kept running and was left through its own menu. Valve's
  fault; noted for the README.

### Meteor 0.9.0-sf18 (2026-11-18): approving a pairing works after another Meteor has run
- **Found with sf17's first run:** the new window appeared, Yes was chosen,
  and pairing still failed; the "Pair headset" window then said "Cannot submit
  the PIN. Check that Meteor's built-in host is running". The host was
  running. Meteor approves a pairing by logging into its host's web interface
  with the password in `host.toml`, and that password was no longer the
  host's. Cause: `host.toml` is one file for every copy of Meteor on the PC,
  while each copy's host keeps its own login file. The original's portable
  Meteor, run from Downloads the same day, found no login file for *its* host,
  made a new password and wrote it to `host.toml`; from then on the installed
  host refused Meteor's login. Checked on the PC without showing either
  password: same user name, different password. The host's log shows no PIN
  arriving in those minutes.
- **Meteor now checks at start that its host's login is the one in
  `host.toml` and sets it again when it isn't** (`meteor/src/host/mod.rs`,
  `login_differs`: user name, salt and SHA-256 as the host stores them).
  A login file it can't read that way is left alone. Upstream has the
  same fault; see `UPSTREAM-FIXES.md`.
- By hand, for a Meteor without this: empty the password in `host.toml`
  (`password = ""`) and restart Meteor; it then makes a new one and sets
  it on the host.
- **Confirmed on the PC and in Meteor's log:** with `host.toml`'s password
  emptied and Meteor restarted, the next request was approved with Yes in
  sf17's window and the stream started ten seconds later; 8r's PIN screen
  showed its line about Meteor asking on the PC.
- sf17's window itself: appeared in front, with the PIN. Also learned: a
  headset the host already knows is never asked for a PIN, so no window
  appears; remove it under Clients on the host's page to pair again.
- **Not explained:** Meteor shut down in an orderly way once, 56 seconds after
  a pairing request and with sf17's window presumably showing. The log has the
  line that Quit writes; what set it off is not known.
- Not compiled here (needs the crates on the test PC).

### 8r (2026-11-18) with Meteor 0.9.0-sf17: pairing that can't be missed
From testing on 2026-11-18: after an uninstall and reinstall, four pairing
requests in a row reached Meteor and sat "awaiting desktop approval" for their
minute with nothing on the PC's screen saying so; pairing went through in the
end by the host's own web page. The "Pair headset" window was confusing and
seemed to do nothing, and the process needed explaining in detail.
- **Meteor (Windows) opens a window when a headset asks to pair**, in front
  of everything: the PIN, "If that is the PIN you see in your headset,
  choose Yes", Yes / No. Until now there was only a notification, which
  Windows holds back during full-screen programs and Do Not Disturb, and
  the tray menu's "Approve pairing", which nobody knows to look for. Both
  remain. `meteor/src/desktop_windows.rs` (`ask_to_pair`). **Not compiled
  here and never run**: it is one call to Windows' own message box, whose
  signature was read in the windows-sys documentation.
- **Nightfall's PIN screen says what to do on the PC**, under the PIN, and
  changes with the stage: at first where to type the PIN on a host's web
  page; once Meteor has taken the request, "Nightfall Meteor on your PC is
  asking: choose Yes in its window. No window? Right-click the Meteor icon
  by the clock and choose Approve pairing."; after Meteor's minute, that
  the request ran out and what to do. The two later headings were English
  only ("Approve pairing in Meteor on your PC", "Approval expired...");
  they are shorter now and, with the three help lines, in all 20
  languages (drafts; measured to fit). `WelcomeScreen.set_pin_stage`,
  `test/test_frame_8r.gd`. **Not seen on a headset or in a picture.**
- Read in the source for this: Meteor's pairing code on Windows is the
  same in the original's 0.9.0 and 0.9.1-preview.2, and the same as this
  port's. The port a host's web page is on differs per PC: Meteor's host
  takes the first free of 47989, 49989, 51989, 53989 (the web page is one
  higher), so a PC that also runs another Sunshine gets 49989 and 49990.
- Also confirmed then: Reset Settings brought back the port's first-install
  settings after the original's Steam Frame build had left its own settings
  file in the shared folder; sf16 runs, with its log cleaned.

### Meteor 0.9.0-sf16 (2026-11-18): Meteor's log is cleaned as it is written
The privacy pass, PC side. Headset build stays 8q. Source only; built on the
PC.
- **Meteor's log no longer holds network addresses or the Windows account
  name.** `meteor.log` is the file people attach when something is wrong, and
  nearly every line of it named the headset's or the PC's address (one day's
  log: 20,971 addresses in 25,667 lines, and the account name 243 times in
  folder paths). Everything is now cleaned on its way into the file
  (`meteor/src/logfile.rs`, `masked`): an IPv4 address keeps only its last
  number (`x.x.x.50`: enough to tell the headset's Wi-Fi address from its
  adapter address), an IPv6 address its last group, a hardware address
  nothing, and `C:\Users\name\`, `/home/name/`, `/Users/name/` become
  `...\~\`. Left as they are: 127.0.0.1, 0.0.0.0, ports, clock times, and
  version numbers such as the one in NVIDIA's package name. Run over that real
  log here: no address and no account name left, nothing else altered. **Logs
  written before sf16 are not rewritten**: `meteor.log` and `meteor.log.1`
  from earlier still hold addresses until they are deleted or rolled over. The
  bundled host (Sunshine / Vibepollo) keeps a log of its own, which this does
  not touch.
- **Meteor's firewall notices say "headset" where they said "Quest"** (tray
  menu and log, Windows and Linux); "Windows Firewall is blocking the Quest"
  came up with a Steam Frame on 2026-11-18.
- Checked here: the cleaning code and its tests compiled and run on their own,
  with the file-writing part. Meteor as a whole is compiled on the test PC.

### Results of 2026-11-18 (8q, Meteor sf15, and the original Meteor 0.9.1-preview.2)
No new build. From a test session, the headset's log and Meteor's.
- **Confirmed:** sf15 built at the first attempt; Multi-Link, Adapter first
  and Wi-Fi only as before; Media tab and Mute light; Foveation follows the
  eyes (what is looked at is never pixelated; High obvious at the edge of
  vision, Low hard to see); Foveation's new tooltip; no eye points in the log.
- **Stream Link through the original Meteor works** (8o's change). His Meteor's log: "video multipath: ... is another path of ...";
  the headset's: both links carrying the stream, the adapter's copy first
  for about 90%, packets lost on Wi-Fi delivered by the adapter. Microphone
  and Meteor's depth worked; the Media tab was gone, as expected.
- **Where his differs, seen once:** the Wi-Fi went silent for about 50 s
  (a roam between access points) while the adapter's link was still up at
  full speed. The stream ended after 3 s, because his multipath carries
  picture and sound only and the controls stay on Wi-Fi; Nightfall's fifth
  retry got through when Wi-Fi returned. This port's Meteor sends the
  controls over both links for this case (sf8); the same test was not
  repeated on sf15 then.
- The original was run from its portable zip in Downloads, not installed,
  so this port's install was never touched (two tray icons at once: both
  exes running). Its "Windows Firewall is blocking the Quest" notice was
  about its own host program in Downloads, which has no firewall rule.
  The same check is in this port's Meteor and says "Quest" too: to reword.

### 8q (2026-11-18): Foveation's tooltip says where it applies
Everything in 8p and 8o (neither installed). Install 8q instead.
- **Foveation's tooltip.** The second line now says both: "Only affects a
  curved or 3D Scene screen. A flat Layer screen is unchanged, and Off is
  faster." It replaces "For very large curved screens: on a flat screen Off is
  faster. The picture blinks when it changes." In all 20 languages (drafts),
  each measured to fit the bar's two lines; the four CJK fonts rebuilt.

### 8p (2026-11-18): the last trace of eye direction out of the log
Everything in 8o (never installed), plus this. Install 8p instead of 8o.
- **8n's claim was not complete.** The first 8n log had no
  gaze line of the app's or of the engine's eye reading, as intended, but
  with Foveation on the engine build prints a second line of its own about
  once a second: `OpenXR: eye-tracked foveation state: valid, centres (x, y)
  (x, y)`, the two points the sharp area is centred on, which is where the
  eyes point (132 lines in that log). The launcher's log filter now cuts
  that line off before "centres": whether the state is valid is kept, the
  points are not (`cap_log.py`; the 8n log put through it again: none
  left). Like the other line, it goes for good when the engine is next
  rebuilt without patch 0002.
- The once-a-second `[FRAME-COST]` line said "N deg from gaze". That figure
  is the angle between the screen and where the **head** points; it never
  came from the eye tracker. It now reads "N deg from straight ahead".
- From the same log, on what Foveation does (only visible with Curve or Flat
  Screen: 3D Scene, and the blink on changing it only there): that is how it
  is built. Foveation thins the eye pictures, which hold the 3D scene; a flat
  Layer screen is handed to SteamVR as a picture of its own and is not in
  them. Median drawing time per frame in this log: screen in the scene, Off
  5.6 ms, High 4.2 ms; flat Layer screen, Off 1.7 ms, Low 3.3 ms, High 2.7 ms.
  So it saves time on a screen in the scene and costs time on a flat Layer
  screen, as the tooltip says. The engine's line showed the eye-tracked state
  valid throughout and the centres moving, so it does follow the eyes.

### 8o (2026-11-18): Stream Link with the original Meteor
So that this port also works with the original Meteor. Headset only.
- **Multi-Link works through the original Nightfall Meteor from 0.9.1.** Its
  author added the same idea there under the name multipath: Meteor copies
  the picture and sound to every address that sends a stream's own ping.
  This port's pings carry two extra bytes (the Stream Link choice), which
  his Meteor does not take for pings, and his Meteor has no list of fixes
  to say what it can do, so the headset never asked. Now a Meteor of
  version 0.9.1 or later without this port's "second-link" is sent plain
  pings over the adapter's link (`StreamManager.offers_second_link`,
  `speaks_plain_second_link`; the stream library could do this already).
  With it: **Multi-Link** = picture and sound over both links; **Wi-Fi
  only** = one link; **Adapter first** works as Multi-Link (his Meteor
  cannot send over the adapter alone; the log says so). Not with it: the
  choice in Meteor's tray menu, controls, microphone and depth over both
  links, the media keys, Mute lit: those need this port's Meteor.
- **Sound goes through the original Meteor from 0.9.1** and no longer
  around it. His 0.9.1 has the fix for sound stopping after the PC was
  silent (his commit b7dc8c4), so the detour this port takes with his
  0.9.0 isn't needed, and the sound gets both links too.
- Read in his source at `v0.9.1-preview.2` (`meteor/src/proxy.rs`), **not
  run**: nothing here has streamed through his Meteor. One session with
  `Nightfall-Meteor-0.9.1-preview.2-Setup-x64.exe` installed is the test.
- With this port's own Meteor nothing changes.
- `test/test_frame_8o.gd`; suite 82 of 82.

### Meteor 0.9.0-sf15 (2026-11-18): Stream Link copies stay at home; TensorRT download for every NVIDIA generation
PC side only; the headset build stays 8n. Source only; built on the PC.
- **Stream Link hardening, step two of three.** Meteor sends a second copy
  of the stream to the address a second-link request comes from. It now
  does that only for a home-network address: the private ranges
  (10.x, where the wireless adapter's link is; 172.16 to 172.31;
  192.168.x), link-local (169.254.x), the carrier and VPN-mesh range
  (100.64.0.0/10), this PC itself, and the IPv6 equivalents. A request
  from any other address is refused, and Meteor's log says so once per
  address, not once per packet (`meteor/src/proxy.rs`:
  `second_link_address_ok`, `refused_first_time`, both checked where the
  video/audio ping and the control trailer open a second link).
  Chosen over "the same subnet as one of the PC's adapters" because it
  needs no per-system adapter listing and protects the same thing: no copy
  of the stream leaves for an address on the internet.
  Still open before 1.0: step one (a request cannot be replayed) and step
  three (Meteor proves it holds its key).
- **TensorRT VDA download for every NVIDIA generation on Windows.** Upstream
  pinned one builder file (RTX 30); any other card got "No verified TensorRT
  download for this GPU". All seven of NVIDIA's builder files are now pinned
  in `meteor/src/download.rs` (compute capability 7.5, 8.0, 8.6, 8.9, 9.0,
  10.0, 12.0: RTX 20 and GTX 16 up to RTX 50, and the data-centre generations
  between), with the SHA-256 and sizes measured on the test PC by
  `tools/measure_tensorrt_builders.ps1`, NVIDIA's signature valid on each. The
  file for RTX 30 came out identical to upstream's. **Tried on a real card:
  RTX 30 (upstream) and, on 2026-11-18, an RTX 5090** (the builder file
  downloaded, both engines built, about 2.5 ms a depth step at 143 steps a
  second in Meteor's log). The other five are pinned and untried. AMD and
  Intel cards don't use TensorRT; they use the Vulkan models, whose downloads
  have no per-card files.
- Checked here: the two new address functions and their tests compiled and
  passed on their own. Meteor as a whole is compiled on the test PC.

### 8n (2026-11-17): the privacy pass, part one
Decided: the published source starts from one clean snapshot, without the
port's step-by-step history (which holds addresses from a real network in old
test data).
- **Where the eyes point is no longer logged.** Builds 6e to 8m wrote the
  gaze direction once a second and the eye tracker's raw reading to the
  log, a diagnostic from getting eye tracking to work, promised to come
  out again. Gone from the app (`src/eye_gaze.gd` now logs only whether
  eye tracking is available). The engine build prints a line of its own
  with the tracker's reading (`steam-frame/engine`, patch 0002); the
  launcher's log filter now leaves that line out (`cap_log.py`), until the
  engine is next rebuilt without it.
- **Examples in the documentation and tests use made-up addresses.** The
  log cleaner's example address, a hardware address and a PC name in its
  tests were replaced with invented ones.
- Looked for in the tree and not found: a Windows user name, e-mail addresses
  other than those in licence texts, the adapter-link addresses (replaced on
  2026-11-16).
- Kept on purpose: the once-a-second performance lines (frame cost, depth
  timing, network, power). They hold no personal data, they are what a
  problem report needs, and with Logging off (the default on a new
  install) none of them is written.
- Not done yet: Meteor's own log on the PC (it writes addresses);
  the clean snapshot itself.

### 8m (2026-11-17)
- **The installer's last window has a "Speech models" button**, beside
  "Restart now" and "Later". It asks again which language you will speak and
  which sizes you want, whatever is installed, and removes nothing. In 8l the
  question was only asked while the chosen kind's models were incomplete, so
  with both English models installed there was no way to get the multilingual
  ones, short of deleting the language file and both English model files. The
  ordinary install stays as quiet as before. (`install.sh --speech-models`;
  the button runs the installed copy with that.) Tried with a stand-in for the
  windows: quiet first pass with both English models there, button, both
  questions, last window again.
- The last window no longer says voice typing "was not installed" or "is
  off" because of the kind asked about this time, while models of the
  other kind are installed.
- Confirmed on the headset: the three buttons, both questions, and back to the
  last window afterwards, also when the questions are closed.
- 8l tried on the headset: English commands and voice typing work as before;
  with the multilingual model and the menu in Spanish, a menu command ran
  (plain and after "Nightfall"), dictation came out in Spanish, and the Voice
  Commands list was in Spanish. English spoken while the menu is in Spanish is
  written as Spanish: the model is told which language to listen for. Key
  names in the list ("Backspace", "Ctrl+A") are English in every language,
  like Nightfall's keyboard.

### 8l (2026-11-17)
Voice typing and voice commands in the menu's language. The design is written
down in `steam-frame/i18n/VOICE.md`. Headset only; Meteor stays 0.9.0-sf14.
- **Dictation in the menu's language.** The installer's speech models were
  English-only. It now asks which language you will speak: English (the
  same models as before) or another (Whisper's multilingual models, the
  same two sizes, 142 and 466 MB; their SHA-1 taken from whisper.cpp's own
  list). It preselects by the menu's language, or the headset's, and stays
  silent once the models of the kind you chose are both installed.
  Nightfall loads the kind the menu's language calls for and tells a
  multilingual model which language to listen for; changing the menu's
  language switches at once. With the menu in another language and only
  English models installed, a notice says voice typing hears English only
  until the other model is installed. `VoiceTyping.model_choice()`,
  `language_changed()`.
- **Every menu button has its voice command in all 20 languages**, by the
  name the menu shows: "Rahmen aus", "Cadre désactivé", "ベゼル オフ". The
  menu's translated names and values are read off the menu itself, so
  nothing had to be written per button.
- **A "pack" per language** (`locale/voice/<code>.json`, 20 of them) holds
  what the menu doesn't: the words for on, off and next; 44 fixed commands
  (recenter, menu and keyboard, head lock, volume, the sliders with a
  number, the PC keys from select all to page down); and the words used
  while typing (clear, submit, new line, new paragraph, parentheses). What
  was said is put into the English command vocabulary and the two engines
  that already existed run on it unchanged (`VoicePacks.to_english()`).
  Japanese, Chinese and Korean, where words aren't spaced as the model
  writes them, are cut into known words first. Chinese packs know both
  scripts. What is typed is never altered.
- **The Voice Commands list is in the menu's language**: the menu rule
  shown on the menu's own names, the pack's commands, the typing words.
  It is rebuilt when the language changes. The popup after a command
  shows the command in that language too.
- Checked here: every one of the 1,607 phrases in the 20 packs leads to
  the command it is filed under, written plain and as the speech model
  writes (capital, full stop): 3,214 trials; each language's own words for
  on, off and next find a menu button by its translated name; no phrase
  filed under two commands; the four fonts for Japanese, Korean and
  Chinese hold every character of their packs; the installer's new
  question with a stand-in for its window. `test/test_frame_8l.gd`.
- **Not checked, and it matters:** nothing here has been heard by a speech
  model. Every pack is a draft by Claude with no native speaker's review;
  how Whisper's multilingual Base and Small write short commands in each
  language is unknown, and the Base model is noticeably weaker outside
  English. Numbers are understood as digits only ("volume 80" as the
  model usually writes it, not "achtzig"). A few confirmations and the
  two "isn't available" / "can be" replies are still English.
- **Curved Filter's tooltip breaks before "Fast:"**, in all 20 languages;
  German's and Dutch's first lines shortened to fit.
- 8k and Meteor sf14 confirmed: the build worked; Mute lights and goes dark,
  also when the PC is muted from Windows; a held volume key repeats and stops;
  one press is one step; the installer's wording is right.

### 8k (2026-11-17) with Meteor 0.9.0-sf14
The media panel finished, before release preparation.
- **Mute is lit while the PC is muted.** Meteor asks Windows' default sound
  output whether it is muted and tells the streaming headset: in its answer to
  each media key it presses (80 ms after the press, so Windows has acted on
  it) and on the page the headset already reads every two seconds, so muting
  on the PC itself shows too, within two seconds. Needs Meteor 0.9.0-sf14;
  with sf13 the keys work and Mute is never lit. `media_keys::muted()`
  (through the `windows` crate that the microphone's audio library already
  brings in; one line added to `Cargo.toml` and to `Cargo.lock`),
  `StreamManager.pc_muted()`. **Meteor's side is not compiled here; this part
  talks to Windows' audio interfaces and has never run.** If it cannot tell,
  it says nothing and the key simply stays unlit.
- **A held volume key repeats**: after 0.45 s, then about eight steps a
  second, until the trigger is let go. Headset only.
- 8j and Meteor sf13 confirmed: Meteor compiled on the PC at the first
  attempt; the Media tab appeared in a running stream the moment Meteor was
  updated (the stream reconnected by itself); volume, mute, play/pause and
  stop act on the PC; next and previous work in a music app (Netflix ignores
  them); "=" and the number pad type correctly; no Media tab on plain
  Sunshine. **Reset Settings: Nightfall restarted by itself** (exit code 75 in
  the log), with Logging off afterwards as designed.

### 8j (2026-11-17) with Meteor 0.9.0-sf13
After a run of 8i: the panel is remembered (back on Arrows after an exit and a
reconnect), four tabs fill the strip, End works, Logging Off wrote no log (the
logs sent end with the click on "Logging Off"; nothing from the run after it),
and the installer with a model deleted asked and downloaded.
- **The Media tab is back, and its keys are pressed by Meteor on the PC.**
  Sent down the stream they arrive as letters (8i, below), so the headset now
  asks Meteor instead: `POST /meteor/media?key=mute` (volume-down, volume-up,
  previous, play-pause, next, stop) on the port Meteor already answers the
  headset on, and Meteor presses that key by its Windows key code. Meteor does
  it **only for an address that has a stream running through it**, and only
  those seven keys; anything else is refused. The tab shows while the stream's
  Meteor says it can ("media-keys": Meteor 0.9.0-sf13 on Windows) and goes
  away otherwise, so with plain Sunshine, or an older Meteor, there are four
  tabs as in 8i. One press is one step; holding does not repeat. **Not built
  in: Mute lighting up while Windows is muted** (Meteor would have to read
  Windows' mute state; a second step). **Meteor's side has not been compiled
  as a whole** (that only happens on the PC); the new file and the new logic
  were compiled and run here on their own. `meteor/src/media_keys.rs`,
  `discovery.rs` (`media_key_answer`), `VirtualKeyboard.MEDIA_KEY_NAMES`,
  `StreamManager.press_media_key()`.
- **Reset Settings restarts Nightfall by itself.** Before, it closed Nightfall
  without saying so and left you to start it again. Nightfall closes with exit
  code 75 and its launcher, seeing that number, starts it again (at most three
  times in a row). The texts say "restarts" in all 20 languages. Tried with a
  stand-in for the app; **not seen on a headset: whether SteamVR takes the
  second start without a hitch.**
- **Number pad: "=" where Backspace was.** The keyboard's own Backspace is
  right beside it, and an equals sign was missing.
- **Installer: "On-headset voice typing"** in the speech-model question and in
  the last window (Windows' own voice typing can be used as well); the
  question now says what the Mic key does without a model.

### 8i (2026-11-17)
After a run of 8h: the Expand key and its panels work well, tabs and labels
easy to hit and read, Reset Settings worked, the installer asked nothing
(right: both speech models were installed), the "Already connecting" notice
went by itself. Headset only; Meteor stays 0.9.0-sf12.
- **The keyboard comes back on the panel you left it on.** 8h always came back
  on the trackpad, whatever panel was showing at exit. The keyboard is built
  before the saved settings are loaded, and only the open/closed state was
  read again when the keyboard is brought up; the panel now is too
  (`_side_from_settings()`). My 8h test built the keyboard by hand with the
  setting already in place, so it could not see this; 8i's test builds first
  and loads after.
- **Number pad: the digits are always digits.** They were the real number
  pad's keys, which Windows turns into arrows and Home/End while Num Lock is
  off, which is confusing. The digits and the point now send the main
  keyboard's digits and point; / * - + and Enter are still the number pad's
  (those don't depend on Num Lock). The Num key is gone; Backspace is in its
  place. One thing lost: a game that tells number-pad digits from the top
  row's will see the top row's.
- **The Media tab is hidden until its keys can work.** In 8h they typed
  letters: Mute "d", Vol - "c", Vol + "b", Prev "q", Play "g", Next "p".
  Cause, read in the host's source (tB0nE/Vibepollo,
  `src/platform/windows/input.cpp`, `keyboard_update`; the same code as
  Sunshine's): the host turns every key into a scan code and marks only a
  fixed list as "extended"; the media keys are not on it, and without the mark
  their scan codes are those letters' (mute E0 20 becomes 20, "d"). Nothing
  sent from the headset changes that. The host's newest source has a second
  route (a virtual keyboard device) that does send media keys properly;
  neither host on the test PC behaves that way yet. The panel and its keys
  stay in the code behind `media_keys_work`. Plan: Meteor presses the keys
  itself on the PC, which also lets Mute show its state.
- **Advanced Settings > About > Logging: On / Off.** Off: no log of the run,
  no copy in Downloads, no audio snapshot, and Nightfall writes none of its
  own; only `logs/last-run.txt` (start, end, exit code). **Off on a new
  install and after Reset Settings; on for an install from before the option
  existed**, so nothing changes for whoever is testing now. The launcher reads
  the saved choice when Nightfall starts, so a change shows from the next
  start (the tooltip says so). An empty file named `logging-on` in the install
  folder turns logging on whatever is saved, for when Nightfall doesn't reach
  its menu. Label and two tooltips in 20 languages. Tried here with a stand-in
  for the app: nothing saved, saved off, saved off with the file, saved
  without the line, saved on.
- Not changed: the "Already connecting" notice stays; it now only shows for
  four seconds. Reset Settings still closes Nightfall: the settings it resets
  are read at start.

### 8h (2026-11-17)
Three things for this build (Reset Settings, the keyboard's Expand key, and
the installer's choices), plus what had been waiting since 8g. Headset only;
Meteor stays 0.9.0-sf12.
- **The keyboard's "Trackpad" key is now "Expand".** It opens the same area
  beside the keys as before, now with five tabs along its top: **Pad** (the
  trackpad, as it was, a little shorter), **Arrows** (the four arrows, Ins,
  Del, Home, End, PgUp, PgDn), **123** (a number pad laid out like a real one,
  with Num Lock), **Media** (previous, play/pause, next, volume down, mute,
  volume up, stop: the PC's own media keys) and **Win** (snap left and right,
  maximize, minimize, move the window to the monitor on the left or right,
  Task View, screenshot, clipboard history, emoji). The panel last used is
  remembered (`keyboard_panel`), as is whether the area is open. The key reads
  "Expand" when the area is closed and "Hide" when it is open. Tabs are never
  sent to the PC. Hidden panels' keys do not answer the pointer. Away from the
  Steam Frame nothing changes (the area is the trackpad only).
  `VirtualKeyboard.PANEL_KEYS`, `set_panel()`; `test_frame_8h.gd` (layout,
  label fit, both hands, chords, remembered panel). Not seen on a headset yet.
  Two things to know: the number pad's digits depend on the PC's Num Lock,
  like a real one (the "Num" key flips it); "Minimize" is Win+Down, which on a
  maximized window first makes it smaller and minimizes on the second press.
  "My keys" (a panel of your own) is for after 1.0. Key labels are in English,
  like the rest of the keyboard.
- **Reset Settings** (Advanced Settings > General). Two presses within six
  seconds: the first shows what will happen, the second writes Nightfall's
  fresh-install settings and closes Nightfall. Kept: paired PCs, button
  mappings and profiles, language, gamepad layout, speech models, Meteor
  pairing, custom monitor layouts. Reset: the settings in the menu, the per-PC
  stream settings (resolution, FPS, bitrate and so on), and the saved places
  of the screen, menu and keyboard. The next start behaves like a first start
  (screen 7.5 m wide at 6 m). `StateManager.reset_to_defaults()`,
  `SettingsController.reset_settings()`, `FrameDefaults.keep_across_reset()`;
  five strings in 20 languages.
- **The installer asks which speech models to download.** It checks what is
  installed first (each file against its SHA-1) and says so in the question:
  both models, Base only, or none. Only what is missing is downloaded, nothing
  is ever deleted, the last answer is selected next time, and with both
  installed nothing is asked. `--models=both|base|none` answers ahead of time;
  closing the question downloads nothing this time. With no model the final
  window says voice typing wasn't installed and how to add it. Tried here with
  a stand-in for the question window (base, none, the flag, the question
  closed); **the real window has not been seen on a headset.**
- **"Already connecting to your PC..." goes away by itself** after four
  seconds. In 8g it stayed on the welcome screen behind the stream and was
  still there after the next disconnect.
  `WelcomeScreen.show_passing_notice()`.
- 8g confirmed on the headset and in its log: Connect by hand connects every
  time, Quick Start with Connect pressed gives the notice and then the stream,
  the Meteor suggestion shows on plain Sunshine, one click hides it, and it
  stays hidden on the next connection.
- Package: Nightfall's own licence (GPL v3) is in it as
  `LICENSE-nightfall.txt`; `WHERE-THINGS-ARE.txt` gives today's sizes and
  three depth models (it said 125 MB and two). The README's rewrite is part
  of the release preparation.

### 8g (2026-11-17)
Two faults of that day's own builds, found on 8e.
- **Connect works again when pressed by hand** (8c to 8f: every press gave the
  "already connecting" notice and no connection). 8c's check for a second
  launch sat inside `on_pair_pressed()`, but the welcome screen's Connect
  button puts the session into "connecting" itself (it arms the ten-second
  timeout) before calling it. So every press looked like a second launch, was
  left alone, and timed out: eight times in a row in one log. It went
  unnoticed for three builds because Quick Start was doing the connecting. The
  check now sits in the button's handler, before the timeout is armed
  (`StreamManager.launch_in_flight()`), counts only a launch that has really
  begun, and gives up after ten seconds so a launch that never answers can't
  keep Connect shut. A test reads the handler to make sure the question comes
  first.
- **The Meteor suggestion on the AI 3D page can be clicked away** (in 8e a
  click on it only moved the menu). A click on anything in the menu that isn't
  a button grabs the menu (`XRInteraction._ui_point_is_empty()`), and the note
  was a label. A button now lies over it while the suggestion shows. Tested on
  the real `UIController`: shown, pressed, hidden for good, saved.
- From the same log (build 8e): the keyboard flickered
  once while a 2560x1440 stream at 144 from plain Sunshine ran with
  the headset making its own depth. The display was running at 72 Hz then
  (display period 13.89 ms for the last minutes of the run) with the graphics
  chip at 83 to 95 C, so SteamVR had halved Nightfall's rate. Noted, not
  changed.

### 8f (2026-11-17)
- **The package you unpack is simple to read.** Top level: `install.sh`,
  `uninstall.sh`, `README.txt` and one folder, `files`, with everything else
  (the app, its libraries, depth models, art, licences, helper scripts).
  Before: 26 entries side by side. What gets installed in
  `~/Games/NightfallFrame` is laid out exactly as before, so nothing the app
  or the Steam shortcut looks for has moved, and an install over an older
  build works as usual. `install.sh` run from the installed folder (to fetch a
  speech model again) works as before too. The README begins with what the
  four things are.
- **`install-files-only.sh` is gone** (it would only confuse), from the
  package and from an existing install. What it did is still there for whoever
  needs it: `install.sh --leave-shortcut`.

### 8e (2026-11-17)
- **A first start on the Frame begins with settings chosen for newcomers**, so
  that a fresh install isn't confusing. Applied once, when no saved state
  exists; anyone with settings keeps them. Different from before: AI 3D on,
  Bezel off, Color Blue, FPS 90, Cursor Type PC Cursor, Cursor Follow
  Standard, Cursor Steady High, Icon Backdrop off, Vibration Clicks + Hover,
  Start Distance 6 m, screen 7.5 m wide, Curve flat, Menu & Keyboard Follow
  off, Speech Model the larger one when it is installed, Keyboard Mic Key
  Windows when no speech model is installed. `src/frame_defaults.gd`; the rest
  of the list was already the default and a test now says so. Start Distance's
  default and marked spot move from 2.25 m to 6 m (tooltip in 21 languages).
  **Not seen on a headset: it only happens on a first start.** Still to check:
  that a first stream takes the PC's own resolution where the host reports one
  (HD otherwise).
- **The AI 3D page suggests Meteor when the stream doesn't use it**, and the
  suggestion can be clicked away for good: "For sharper 3D that is lighter on
  the headset, install Nightfall Meteor on your PC. Until then the headset's
  own model is in use. Click this note to hide it for good." Until now someone
  without Meteor got the headset's depth and no word that Meteor exists. 20
  translations.
- **The menu and keyboard start in spots found comfortable in daily use.**
  Read from the 8d log (`[SPOTS] Saved default menu and keyboard spot. menu
  [-0.873, -0.446, -0.796, 0.861, -0.356], keyboard [0.107, -0.567, -0.857,
  -0.023, -0.441]`), rounded, and made the built-in spots (`FRAME_MENU_SPOT`,
  `FRAME_KEYBOARD_SPOT` in `main.gd`): the menu off to the left and turned
  toward you, the keyboard 0.86 m ahead instead of 0.55 m. They apply to a new
  install and to "Original Default"; a saved spot still wins.
- **Picture tab reordered.** Top row: Brightness,
  Contrast, Gamma, Sharpen, Foveation. Bottom row: Flat Screen, Flat Screen
  Detail, Curved Filter, PT Fade. `MenuSchema.FRAME_PICTURE_GROUPS`.
- 8d's log, after the nose piece was seated and the
  headset restarted: not one "not shown" line in eight and a half minutes.

### 8d (2026-11-17)
After a look at 8c: "Already connecting to your PC" is clearer and works;
Stream Link on the Stream tab, Reconnect Stream and its tooltip, Cursor
Position in General, Commands on and off, "disable bezel" / "enable bezel" all
confirmed.
- **Controls: Pointer Ray is last in the top row, above Controller Models.**
  Top row: Cursor Type, Cursor Follow, Cursor Steady, Cursor Off Screen,
  Pointer Ray.
- **Voice Commands list: nothing is cut off on the right.** The list is two
  pairs of columns; a long line widened its whole column and pushed the
  right-hand pair off the page ("Load one of your sa"), and 8c's longer
  rows made it worse. Every cell now keeps to its width and wraps.
- **The log says where the saved menu and keyboard spots are**, at start and
  on Save As Default (`[SPOTS] ... menu [x, y, z, yaw, pitch], keyboard
  [...]`). The spots preferred after daily use (keyboard and menu a little
  further away) are to become Nightfall's own defaults; the numbers are only
  on the headset, so this build reads them out and the next one can adopt
  them.
- **The dark blips are the headset's own, and now explained as far as the logs
  go.** 8c's short `[SESSION]` lines put three of them, each 507 to 514 ms,
  within two seconds of the moments called out while wearing the headset.
  SteamOS's own logs show the same instants in the eye tracking service: "HMD
  off, stopping eye tracking" and "HMD on, starting eye tracking" about 510 ms
  apart. So the headset decides for half a second that it has been taken off,
  and the displays go dark as they do then. Nightfall kept drawing at 144 Hz
  throughout (display period 6.94 ms in all 452 one-second readings; the
  compositor still reports 144 Hz preferred). Why the headset thinks so is not
  in the logs.

### 8c (2026-11-17)
After a first look at 8b (Meteor sf12, now installed from the port's own Setup
file: one entry in Windows' app list, pairing kept, depth and microphone
working). Meteor stays 0.9.0-sf12.
- **"Launch failed: Another stream operation is still running" at every start
  is gone.** Both logs show the cause: Quick Start is on, so Nightfall
  connects by itself a second after the welcome screen appears; Connect
  pressed meanwhile sent a second launch to the PC, its host refused it, and
  that failure took the first launch down too. Connect now leaves a connection
  that is being made alone ("Already connecting to your PC..."), and Quick
  Start stands back if Connect was pressed during its one-second wait.
  `StreamManager.connection_under_way()`. Upstream has the same two paths.
- **Stream Link is on the Stream tab**, in the row with Codec, Reconnect
  Stream and Volume. `MenuSchema.FRAME_MOVES`.
- **AI 3D's Cursor Position no longer has a category to itself**: it is in
  General. Advanced Settings is now View & Feel, Screen Position, Menu &
  Keyboard Position, Voice & Microphone, Connection, General, About.
- **Reconnect Audio is now Reconnect Stream**, which is what it does:
  "Restarts the stream, to get sound or depth back if either has stopped
  coming through." Translated in all 20 languages. By voice both names work.
- **Voice Commands list: says that every menu button has a command.** It
  always did (commands are read off the menu's buttons each time, so Stream
  Link, Commands and the rest got theirs by themselves), but the list only
  showed four examples. Added rows: "enable bezel / disable bezel", "turn
  bezel off / switch bezel on", "stream link wi-fi only". Each example was
  run through the matcher before it went in.
- **A blip of not being shown gets one short log line** instead of the long
  pair: `[SESSION] hh:mm:ss Nightfall was not shown for a moment (N ms)`. The
  8a and 8b logs have six of them (VISIBLE to SYNCHRONIZED and back inside a
  second), and the displays were seen to go dark for an instant about four
  times the same day, on SteamOS's desktop as well, so they come from the
  headset and not from Nightfall; the line is the only trace of them. The long
  pair is written once it has lasted a second.
- Confirmed in 8a's log: the headset came off eight times
  for 1 to 22 s, no `image_acquired` error at all, 2.5 MB of log; Reconnect
  Audio with Multi-Link brought picture, sound, controls, microphone and
  depth back on both links within a second (Meteor's log).

### 8b (2026-11-17)
Everything in 8a, which had been delivered but not yet installed, plus the
following. Install this one instead of 8a. Meteor stays 0.9.0-sf12.
- **Advanced Settings regrouped.** On the Frame: View & Feel (Recenter, Head
  Lock, Vibration, Icon Backdrop), Screen Position, Menu & Keyboard Position,
  Voice & Microphone (two rows: Voice Commands, Commands, Require 'Nightfall',
  Confirm Commands; Speech Model, Faster Voice Typing, Keyboard Mic Key,
  Microphone), Connection (Stream Link first), AI 3D (Cursor Position),
  General (Language, Stats, Camera FPS Limit), About (Licences). Stream Link
  leaves "Display", the microphone joins the voice options, and diagnostics
  move from the top to General. `MenuSchema.FRAME_SETTINGS_GROUPS` and
  `regroup_for_frame()`: upstream's rows are built as before and regrouped, so
  off the Frame nothing changes, and an option the table doesn't name keeps
  its old row. Two differences from the proposal: About stays its own last row
  (the Licences page opens under it), and Cursor Position stays in Advanced
  Settings (the AI 3D page isn't built from this table).
- **Commands: On / Off.** Off: nothing said is run as a command, neither
  Nightfall's commands nor menu options by name nor "clear" and "submit";
  everything is typed. The Voice Commands list says so while it is off.
  Tooltip per choice. `AppSettings.voice_commands`, saved.
- **Notices and popups translated: 43 of them, in all 20 languages**
  (drafts). The start-up and update notices, Meteor's depth going and
  coming back, Stream Link and adapter notices, reconnecting, Head Lock,
  Game Controller mode, the monitor layout messages and every voice typing
  notice. A notice that is one fixed text is translated by its label, as
  upstream's status line already was; the nine with a blank to fill in
  (a build number, a count, an error) now go through `Localization.t()`
  first. **Still English:** the voice commands' own confirmations ("Select
  all (Ctrl+A)", "Curve 40%."), the color camera notices (built from
  fragments), the Voice Commands list, the Buttons tab, and option values.
- **Licences page: what the port added.** New entries: Nightfall for Steam
  Frame (an unofficial port, GPL v3), Moonlight XR for Frame (the V4L2
  decoder, GPL v3; the two LiteRT depth models were listed under it too until
  8y, wrongly), whisper.cpp 1.9.5 with a
  note on the Whisper speech models the installer downloads, glslang (with
  ncnn). ZipDepth's note mentions the Frame's models. The package already
  carried these texts as files; the page in the app did not show them.
  **Not done:** checking every version on the page against what the Frame
  build really contains, and leaving out what it doesn't (ALVR, the
  browser's ad blocker).
- Tests: `test/test_frame_8b.gd` (the groups, nothing lost in regrouping,
  upstream's rows untouched off the Frame, the Commands switch, every notice
  translated with the same blanks and at most four lines in the panel).

### 8a (2026-11-17) with Meteor 0.9.0-sf12
First release-prep build. Headset: two faults from one log, Head Lock's
tooltip, the installer's download, and the translations below. Meteor: one
security fix.
- **Meteor's depth comes back within seconds of "Host depth" being turned on
  again.** Log of 2026-11-17: after Host depth off and on, the headset
  reconnected and no map came for 12.5 minutes; the
  headset's own model filled in, so nothing looked wrong. Meteor's depth
  decoder can only start at a keyframe (`depth.rs`: "pending: next
  keyframe/stream") and the PC sends one only when asked. The headset now
  asks (`LiRequestIdrFrame`, newly bound as `request_keyframe()`) when
  Meteor's depth is connected and no map has come for 2 s, again at 8 s and
  at 30 s, then leaves it. One log line per ask: `[METEOR] ... Host depth is
  connected but no map has come for N s: asked the PC for a keyframe`.
  `src/depth_estimator.gd` `_ask_keyframe_if_silent()`. This is also why
  Reconnect Audio used to "fix" depth: a new stream begins with a keyframe.
- **No error flood while the headset is off.** Same log: 763,949 lines of
  `ERROR: Condition "image_acquired" is true` (`openxr_api.cpp:186`), about
  1,000 a second, 89 MB in 23 minutes, in the two stretches where the
  headset lay on the desk. While SteamVR isn't showing the app (OpenXR
  session state SYNCHRONIZED) the engine still takes the next picture of
  each composition layer every frame and hands none back. It only takes one
  for a layer whose viewport is set to update
  (`openxr_composition_layer_extension.cpp` `on_pre_render()`), so while the
  app isn't shown the layers' viewports are held at "don't update" in the
  renderer, each frame just before it draws (`RenderingServer.frame_pre_draw`),
  and given their own modes back when it is shown again.
  `src/frame_session_watch.gd`.
- **One note in the log each way, and the once-a-second readings pause in
  between**: `[SESSION] hh:mm:ss Nightfall is not being shown (the headset is
  off, or something else is in front)...` and `...is being shown again after
  11 min (4,620 once-a-second lines were held back)`. Everything that isn't a
  periodic reading is still written.
- **The log can't grow without limit.** The launcher passes the app's output
  through `cap_log.py`: a block of up to four lines that repeats is written
  once with a count, and the file stops at 256 MB with a line saying so.
  An 89 MB log comes to 5.5 MB through it. Without python3
  on the headset the launcher writes the log as before.
- **Head Lock's tooltip says what the current choice does**, like the other
  choice buttons, instead of one four-line text the bar cut off. Three
  tooltips (Off, Level, Tilt), each two lines, in all 20 languages. The
  triple apostrophes around 'recenter' in Recenter's tooltip (a quoting slip
  of 2026-11-10) are gone too.
- **Installer: the model download shows its progress, carries on where it
  stopped, and a failure is the first thing the last window says.** The two
  speech models (142 MB and 466 MB) are the only downloads. Before: one
  notification, then minutes of nothing; an interrupted download started
  over next time; and "couldn't be downloaded" sat in the middle of the
  final window. Now a window with a progress bar (kdialog, where the headset
  has it; the notification otherwise), `curl -C -` on the kept `.partial`
  file, a partial that turns out complete is checked and used, and a failed
  required model puts "VOICE TYPING IS OFF: ..." at the top of the final
  window. A file that fails its SHA-1 check is still deleted, never used.
  Tried here with local files (fresh, resumed, already complete, damaged,
  missing); **the progress window itself has not been seen on a headset.**
- **Meteor sf12: a finished stream's bytes can no longer open a second
  link.** Every stream has 16 bytes that its pings carry; a ping with those
  bytes from another address opens the second link, and copies of the
  stream go there. When a new stream began from the same address and port
  as an earlier one, the earlier stream's bytes stayed good for as long as
  the connection lived. They are now dropped, with the second link they
  opened, the moment the new stream's first ping arrives. Upstream found the
  same in its own multipath and fixed it on 2026-11-16 (243cfdf).
  `meteor/src/proxy.rs` `earlier_payloads()`. Compiled only as a separate
  piece here; the whole of Meteor is compiled on the PC.
- **Meteor's build script: the last step can't be passed by unnoticed.** On
  2026-11-17 the build finished, the "Type YES" question went unanswered,
  the old Meteor stayed installed and the new exe was then started from its
  build folder, where it has no depth files and no host. The question now
  stands under a banner, takes "yes" or "y" as well, and a no says in yellow
  that nothing was replaced and not to run the exe from the build folder.
- **A script that makes one Setup file for this port's Meteor**
  (`meteor/tools/build_frame_installer.ps1`): a full installer to release,
  rather than a build script. It is upstream's own installer recipe
  (`Meteor.iss`, Inno Setup 7) with this port's exe; same name and folder as
  upstream's Meteor, so either installs over the other. Everything but the exe
  comes from the Meteor 0.9 installed on the PC. **Nothing is copied by
  folder**: the installed folder also holds the PC's own host settings, a
  private key, pairing state, session history and logs (`runtime\host\config`,
  found when listing it). The bundled host and runtime are copied file by file
  from upstream's `manifest.json`, each checked against its size and SHA-256
  (all 281 match on the test PC); the rest is a fixed list of names; and the
  staged copy is searched for anything that looks like settings, keys or logs
  before the installer is made. `Meteor.iss` takes the publisher, links and
  file name as options (upstream's own build is unchanged); the port's
  installer carries no links yet. The version now lives in
  `meteor/tools/frame-version.txt`, read by both scripts;
  `build_meteor_fix.ps1 -BuildOnly` builds without touching the install.
  **First run on the test PC, 2026-11-17: worked.** Inno Setup 7.1.1; 281
  runtime files "all as upstream shipped them"; 352 files staged, 262 MB;
  `Nightfall-Meteor-0.9.0-sf12-SteamFrame-Setup-x64.exe`, 86,221,241 bytes
  (upstream's own 0.9.0 installer is 86,181,716). Checked again from outside
  the script: nothing from `config`, no key, log or database in the staged
  copy, and its exe is the installed sf12. The Setup file itself has not been
  run yet.
- Tests: `test/test_frame_8a.gd` (the keyframe asks, the session watch),
  the tooltip fit test in `test_frame_7z.gd`, one Rust test in `proxy.rs`.
  Suite 77 of 77.

From the release-prep list, written before this build and now in it:
- **Translations of the Frame's menu: drafts in all 20 languages.** Measured
  with the Frame's menu: 118 strings had no translation in any language (37
  button names and section titles, 46 menu tooltips, 21 tooltips set in code
  such as Stream Link's and the depth model's choices, 14 that upstream's
  dictionaries carried in English), plus one tooltip only the non-Frame menu
  has. 2,100 entries added, 142 of upstream's English placeholders filled, 98
  real upstream translations left alone. The four CJK font subsets rebuilt for
  the new characters. Source list, drafts and what was and wasn't checked:
  `steam-frame/i18n/`. **Drafts without a native speaker's review.** Still
  English: notices and popups, the Buttons tab, the Voice Commands list, and
  option values new on the Frame (tooltips name those in English to match the
  button).
- **Three English tooltips no longer run past the tooltip bar.** Laid out as
  the bar's label does (1160 px bar, two lines), the second line of
  Multi-Link's tooltip, and the first lines of the depth model's "Needs
  Meteor" and depth rate tooltips, each wrapped onto a third line that the
  bar cuts off. A few characters shorter now. (The "98 characters a line"
  rule of thumb is not exact: the font is proportional, and 98 characters
  came to 1,157 px against the bar's 1,112.)
- **The localization test checks what the bar shows.** Upstream's check is a
  width of 952 px for its one-line bar; this port's bar is 1160 px and two
  lines, so that check failed on 28 of the port's own English tooltips and
  told nothing. It now lays each tooltip out as the bar does and fails on a
  third line. The one failure it found in English, Head Lock's four-line
  tooltip, is fixed in this build (above).
- **Meteor sf11 confirmed on the headset** (2026-11-17, once the exe was in
  the installed folder): the Host depth notices came through both ways, and
  everything works.

### 7z (2026-11-17) and Meteor 0.9.0-sf11
From the 7y + sf10 session (the headset's logs and Meteor's) and a list
of faults from that day.
- **Meteor's depth over both links, working this time (Meteor).** sf10 let
  the headset's second connection in and then sent it nothing: both logs
  read "first-over: own link N, second link 0", and Meteor's log ends each
  such connection "closed after 0 maps". `depth_server.rs` only sends a map
  to a connection whose address is the address the map's video came from;
  the second connection comes from the adapter's address. It now also goes
  to the address a client's second-link pings came from
  (`for_this_client`). The 7y entry's "Meteor already sends every map down
  each connection it has" was wrong.
- **Meteor's depth follows "Host depth" during a stream.** The offer was read
  at a stream's start only. Meteor's answer at `/meteor/link`, which the
  headset reads every 2 seconds for the Stream Link choice, now also says
  whether depth is offered at that moment ("depth-live"); when that changes,
  the headset asks for the offer again and starts or stops Meteor's depth,
  with a notice ("Meteor's depth is back on. Using it."). Needs both sides.
  (`_follow_meteor_depth`, `refresh_meteor_depth`,
  `FrameSecondLink.depth_offer_is_news`.)
- **A note on the AI 3D page** while Meteor is the chosen depth
  and the headset's model is doing the work: "Not receiving depth from
  Meteor on your PC. The headset's model is filling in until it returns.",
  or "Meteor on your PC has its depth switched off (its menu: Host depth).
  The headset's model is in use." (`UIController.frame_ai3d_note`.)
- **Stream Link says when it can't do anything.** In a stream
  that isn't going through Meteor the button's tooltip says so, and
  changing the choice shows "Stream Link needs Nightfall Meteor on your PC.
  This stream isn't going through Meteor." Also said on a change: a Meteor
  too old for it, and the PC's adapter not answering.
  (`FrameSecondLink.tip`, `unavailable_note`.)
- **Wrong words when Meteor isn't running**, found in that log: a stream
  started while Meteor didn't answer was still described as passing
  through it ("Meteor is not offering depth" and its notice; "the PC's
  Meteor doesn't offer it (it needs 0.9.0-sf3 or later)"). The address of
  the last Meteor found was never cleared; `meteor_address()` now only
  answers while the stream has Meteor's reply in hand.
- **The second screen that kept coming back** (a second screen at every
  reconnect, even after turning it off; a way round it: go to three screens
  and back to one). Not the host's doing: the Screens page's counts began at 0
  in every app run while one virtual screen was saved for the host, so Virtual
  0 + Apply looked like no change, the screen left the headset only, and the
  next stream asked the host for it again. The page now takes its counts from
  what is live when it opens (`sync_staged_from_current_layout`, which
  upstream has and never calls; from the saved count when no stream runs), and
  Apply counts a difference from the saved count as a change
  (`virtual_count_changed`). In `UPSTREAM-FIXES.md`.
- **Voice:** "A Dlock.", "At lock." run head lock; "Disabled ..." /
  "Enabled ..." are taken as "disable" / "enable".
- **Adapter link's signal in the log:** the Frame's driver prints 0 under
  "signal" and the real figure under "avg ack signal" / "last ack signal"; that is now what is read. It never
  counts retried packets, so that clause is left out when both are 0.
- **Checked here:** GDScript suite (only the known translations failure),
  `test_frame_7k` (`_build_7z`), `for_this_client` compiled and tested
  alone. **Not compiled here:** Meteor as a whole. **Not seen on a
  headset:** any of it; in particular whether the AI 3D page still fits
  with its note showing.
- **Known, left for later:** Meteor's tray shows the Stream Link lines for
  any headset (a Quest never asks for a second link, so nothing is sent;
  the wording assumes a Frame). With Meteor quit in mid-stream, the last
  seconds' Stream Link changes are still logged as "told to Meteor". Three
  short "picture stopped" lines just after stream starts in the 7y logs
  are unexplained.

### 7y (2026-11-16) and Meteor 0.9.0-sf10
- **The microphone and Meteor's depth go over both links too**, in every
  Stream Link choice but "Wi-Fi only". With the picture, sound and controls
  already there, nothing of a stream now depends on Wi-Fi alone while the
  adapter is in reach.
  - Microphone: every frame is sent to Meteor's address on the adapter's
    link as well, the same datagram. Meteor knows the session by the key
    each datagram carries, takes it from either address as one stream and
    plays each frame once, by its number (`meteor_mic.cpp` `set_second`;
    `mic.rs` `session_key`).
  - Depth: a second connection to Meteor over the adapter's link beside the
    first. Meteor already sends every map down each connection it has; the
    headset keeps a map the first time it arrives
    (`MeteorDepthReceiver.set_second`, `is_late_copy`). The `[METEOR-DEPTH]`
    line adds over which link the maps came first.
  - Meteor: a connection from a streaming headset's adapter address counts
    as that headset's (`Stats::is_streaming`, from the second-link pings).
  - Needs both 7y and sf10 ("side-both"); with an older Meteor both stay on
    Wi-Fi as before. **Not tried on a headset; no stand-in test here beyond
    the pieces** (which map is a late copy, whose session a datagram is).
- **"Host depth is OFF" can't be missed any more.** Some confusion
  came from that tray item being unticked (Meteor gone from the
  Quality choices, nothing saying why). Meteor's menu now has "Host depth is
  OFF - click here to turn it on" as its second line while it is off;
  Nightfall shows a notice at the stream's start ("Meteor's depth is off on
  the PC (its menu: Host depth). Using the headset's."), writes it to the
  log, and Quality's tooltip says so. (A tray notification was considered
  and dropped: clicking any notification approves a waiting pairing
  request; see `UPSTREAM-FIXES.md`.)
- **Voice commands:** "Edlock", "Ad lock" and "headset lock" are heard as
  "head lock" (how the speech model sometimes writes it);
  "disable ..." and "enable ..." work as "... off" and "... on".
- **A second link no longer outlives its stream** (stream library): it is
  cleared when a stream is set up, so the next stream's first pings can't go
  to a link nobody has looked for yet. Meteor's sf9 guard stays as well.
- Log: what the system prints for the adapter's link is written once, with
  every address removed, to find out why signal and retried packets read 0;
  the voice line gives the length of each stretch when the model listened
  more than once ("listened 2 times (15.4 s, then 6.0 s)").

### Meteor 0.9.0-sf9 (2026-11-16; no headset build, 7x stays)
- **What the first 7x + sf8 session showed: none of the new part was in use,
  and Meteor's depth was off, for one reason.** Nightfall starts a stream
  twice at launch (it always has: "Starting stream" is in every log twice, a
  second apart). This time the first of the two got as far as setting up its
  second link before the second replaced it, so the second stream's very first
  pings went out over both links at once, and the adapter's, being the faster
  path, reached Meteor first. Meteor gave the stream to whichever address
  pinged first: it took the adapter's address for the headset's own and Wi-Fi
  for its "second link". Everything that followed comes from that: the depth
  connection, which comes from the Wi-Fi address, was refused 80 times ("not a
  streaming client"; the headset fell back to its own model, the 11 to 16 maps
  a second seen where Meteor gives 40 to 54); the microphone was ignored after
  the restart; the control copies were dropped ("controls: wlan0 1,315, wlanap
  0" in every line); and the Stream Link choice never reached Meteor
  (Nightfall said Adapter first, Meteor's menu Multi-Link). Reconnect Audio
  cured it by starting a stream that happened to win the race the right way.
  The fault has been possible since 7s; this is the first session it showed
  in.
- **Fix: a second link's ping never starts a stream's flow.** It is known
  by its make (it is longer than a stream's own ping, by the choice it
  carries); if the stream has no flow in Meteor yet, it waits for the
  stream's own ping. `proxy.rs`, `run_udp`; tried in the stand-alone copy
  of the relay logic (second-link ping first: nothing opened; then the
  stream's own: one flow, the first link's).
- **Result (7x + sf9):** the links the right way round on all three streams of
  the run; Meteor's depth delivering throughout (63 to 65 maps a second;
  Meteor's depth decoder had also been switched from Software to Auto, which
  chose NVDEC); **the controls going over both links** (equal counts over
  Wi-Fi and the adapter in every 10-second line); menus in step from either
  side; microphone reaching Windows. Still untested: Wi-Fi going silent while
  the adapter holds.
- Also learned: switching the headset's Wi-Fi off takes the adapter's link
  down with it (tried; the stream was lost on "Adapter first"). So "Wi-Fi goes
  silent with the adapter in reach" can only be tested from the router's side.

### 7x (2026-11-16) and Meteor 0.9.0-sf8
- **The controls go over both links too**, in every Stream Link choice but
  "Wi-Fi only". Until now only the picture and the sound did; the control
  channel (input, and the "are you there" between headset and PC that ends
  a stream when it stops) was on Wi-Fi alone, so Wi-Fi going silent ended
  the stream after about ten seconds whatever the adapter was doing. Now a
  stream should outlive either link going silent for as long as the other
  holds. **Still on Wi-Fi alone: the microphone and Meteor's depth**, which
  will pause while Wi-Fi is silent and pick up when it returns.
- How: the control channel is one ENet connection to one address. Below
  ENet, the headset sends every control datagram to the PC's address on the
  adapter's link as well, ending that copy with the stream's own 16 bytes
  and "NFL2"; Meteor knows the copy by that, takes the mark off, and passes
  it to the host out of the same socket as the Wi-Fi one, so the host sees
  one headset. The host's replies go to both of the headset's addresses,
  and the headset hands the adapter's to ENet as if they came over Wi-Fi.
  ENet numbers its datagrams and drops what it has seen, at both ends.
  (`0004-second-link.patch`: `enet/unix.c`, `LiSetSecondLinkControl`;
  `meteor/src/proxy.rs`: `control_trailer`. Needs both 7x and sf8; with an
  older Meteor the controls stay on Wi-Fi as before.)
- **Tried before it left the workshop**, as far as that can be done without
  a headset: an ENet client and server from the same library with a relay
  between them standing in for Meteor, each path cut in turn for 13 seconds
  against the 10 seconds after which a silent connection is given up. On
  one path the connection is lost; on two it is never lost and all 685
  messages arrive once and in order, with the server seeing one peer.
  Meteor's part was compiled and run in a stand-alone copy of its relay
  logic; the whole of Meteor only compiles on the PC.
- The `[LINK]` line every 10 seconds adds "controls: wlan0 N, wlanap M".
- Meteor: the queue for the adapter's copies holds 1024 packets (was 256,
  one packet short once in 14 minutes of ordinary running).
- The control socket is no longer tied to the address the stream started
  on (it has to hear the PC from the adapter's link). This applies to every
  stream, with or without a second link.

### 7w (2026-11-16; headset only, Meteor stays 0.9.0-sf7)
- **A network line every second while the picture is stopped**, and one when
  it moves again saying for how long ("picture stopped for 3 s; wlan0:
  connected, signal ...; 12 packets a second arriving, 140 leaving; the PC:
  answered | access point: ... NOT the one the stream began on | adapter
  link: ..."). Why: every roam of the Wi-Fi to another access point so far has
  ended with about nine seconds of nothing, the stream given up and a new
  one that works at once, and a line a minute could not say whether the
  Wi-Fi was dead until then or back sooner with the old stream not picking
  up. At most 40 lines for one stop.
- **The wireless adapter's own link in the log.** The headset is the access
  point the PC's adapter joins, so it has the figures: signal, the speed it is
  sending and receiving at, packets sent again and given up on since the last
  look, and how long since the adapter was last heard. Written at a stream's
  start, with the line each minute, with each second of a stopped picture, and
  whenever the headset asks Meteor for Wi-Fi's copies. Read with `iw dev
  wlanap station dump`; **not known whether SteamOS lets an app run that**: if
  not, the log says so once. The adapter's address is in what the system
  prints and is not kept. Its temperature is not something the headset can
  read.
- **Voice typing: listening again costs what is left of the clip, not the
  whole clip.** Measured in 7v: 30 s of speech took 9.6 s to work out when
  the model listened once, 21 to 23 s when it stopped at a pause and
  listened again, because whisper.cpp listens to a window as long as the
  whole clip each time. The clip is now handed over a stretch at a time:
  whisper.cpp is stopped as it is about to listen again, and the next
  stretch starts where its last part ended and is only as long as what
  remains. **Not tried on speech** (no speech model or recordings where the
  build is made): the log's "listened N times" and the work time will show
  what it saves, and whether any words go missing at the joins.

### Meteor 0.9.0-sf7 (2026-11-16; no headset build, 7v stays)
- **What 7v showed.** On "Adapter first" the headset asked for Wi-Fi's copies
  three times as the adapter went out of range, and Wi-Fi's first packet came
  52, 10 and 71 ms later: the asking works. The picture still froze for 8 to
  10 seconds. In all three, from about the moment the adapter died, **nothing
  arrived over either link** for 4 to 5 seconds, and it ended when Meteor gave
  the adapter up as quiet (its 5-second rule). Meteor's own tap of the stream,
  which sits after the sends in the same loop, missed packets in exactly those
  stretches (303, 435 and 225 frames incomplete, with nothing dropped from its
  queue in two of the three): the relay was not reading Sunshine, on the same
  PC. Returning to the adapter was smooth every time, and the adapter was
  picked up again after a reconnect out of its reach (7v's fix).
- **Cause, as far as the logs can show it: copies for a dead adapter held up
  the copies for Wi-Fi.** Both went out of one socket, one `send_to` after
  the other. When the adapter stops taking packets the socket's send buffer
  fills with packets for it and the next send waits, whichever address it
  is for. This also explains 7t and 7u, where the freeze was always about
  as long as the time Meteor kept sending to the adapter. It would hit
  **Multi-Link** just the same when the adapter drops out (not tested
  in that setting).
- **Fix: the second link's copies leave from a socket and a task of their
  own**, through a short queue (256 packets) that drops what doesn't fit, so
  an adapter that takes nothing can only hold up its own copies. Meteor's
  log says "isn't taking packets; copies for it dropped" at most once a
  second while that happens. `proxy.rs`, `SecondLinkOut`. The copies now
  come from another port of the PC than the stream's own; the headset's
  sockets take them from any port and tell the links apart by address. Not
  known: whether anything on the headset filters them (if so the log will
  say "nothing is arriving over wlanap" and every choice works as Wi-Fi).
- **Result (the same day):** with the adapter dropping out where the Wi-Fi
  does not roam, essentially no drop: a brief stutter of a couple of frames.
  Multi-Link near the PC unchanged, so the copies from another port do reach
  the headset. Where the Wi-Fi roams to another access point as well, the
  picture still drops for some seconds: that is the Wi-Fi's own hand-over,
  with the adapter out of range too, and is not what this fixed.
- **Voice typing, measured (7v log):** the slow clips are the ones the
  model listened to twice. 30 s of speech: 9.6 s to work out when it
  listened once, 20.8 and 23.4 s when twice; 17.6 s: 12.4 s, twice. Clips it
  listened to once took 0.32 to 0.44 s per second of speech with color
  passthrough on or off, so heat is the smaller part. Not changed yet.

### 7v (2026-11-16) and Meteor 0.9.0-sf6
- **What 7u showed.** The tray menu, the sync both ways, the notices and
  "Wi-Fi only at once" all worked (Meteor's tray code compiled on the PC at
  the first attempt). On "Adapter first", with the adapter going out of range three
  times: no picture for about 25 s ending in a reconnect (the Wi-Fi also
  roamed to another access point), about 10 s and about 4 s. Meteor did start Wi-Fi's copies 1.5 s after the adapter's last
  ping each time; the rest of the gap is not broken down in that log. The
  reading (not measured): a ping is 22 bytes and crosses a link that can no
  longer carry 120 Mbit/s of picture, so Meteor is the last to know.
- **The headset now judges the adapter's link itself on "Adapter first"**
  and tells Meteor ("both links for now") the moment it falters: nothing
  over the adapter for a fifth of a second (picture or sound; sound keeps
  coming when the screen is still), or more than 5% of the picture's packets
  missing in a tenth of a second. It goes back to the adapter alone after 3
  seconds of the adapter bringing the picture whole. The request is sent at
  once, not at the next half-second ping. Needs both 7v and sf6; with an
  older Meteor it works as in 7u. (In the stream library:
  `0004-second-link.patch`, `secondLinkWatch`; checked stand-alone with a
  timed run.)
- **Meteor finds a dead adapter link sooner too**: while the adapter is
  alone the headset pings ten times a second, and Meteor calls a ping late
  after three missed whatever the pace (0.4 s there, 1.5 s for the older
  twice-a-second pings).
- **Nightfall keeps looking for the adapter during a stream** (every 5 seconds
  while it has none). In 7u it looked once, at a stream's start: the stream
  that reconnected out of the adapter's range stayed on Wi-Fi alone once back
  in range and froze for about 20 s when the Wi-Fi roamed back (felt as a
  freeze of about eight seconds).
- **The log now times a fallback**: when the headset asked for Wi-Fi's
  copies and why, how many milliseconds until Wi-Fi's first packet came, and
  when the adapter was trusted alone again. Meteor's log says when it was
  asked and when it found the pings late.
- **Voice typing: the log counts how many times the model listened to each
  clip** ("listened 3 times"). It felt slower in 7u (several seconds before
  any text appeared); the log agrees: 0.52 s of work for each second of speech
  against 0.36 to 0.38 in 7s and 7t, and four clips at 0.84 to 0.91. That
  session was hotter (94 to 96 C against 86; color passthrough was on
  throughout, off before), and listening again after a pause, the 7t fix for
  cut-off sentences, costs about as much each time. Nothing changed in how it
  transcribes yet: this build measures.
- Meteor's log: one more fault of the original noted in `UPSTREAM-FIXES.md`
  (the "video tap" line repeating and wrapping).
- Known, left as it is: the tick in Meteor's tray menu doesn't move while
  the menu is open (close and reopen it).

### 7u (2026-11-16) and Meteor 0.9.0-sf5
- **What 7t showed** (headset log and Meteor's): on **Wi-Fi only** about 24
  lost video frames a minute; on **Multi-Link** none; on **Adapter only**
  none, except when the headset went out of the adapter's range: about 7
  seconds of almost no picture before Meteor's 5-second rule put the stream
  back on Wi-Fi, then Wi-Fi until the adapter returned and Meteor went back to
  it by itself. Voice typing: results of normal length again. Meteor 0.9.0-sf4
  failed to build at first because the zip had been unpacked one folder deeper
  and Windows' 260-character path limit was passed; the build script now
  checks the folder's path length and says so.
- **Stream Link can be chosen in Meteor's tray menu too, and the two stay in
  step.** The tray menu has a status line that is always there ("Stream Link:
  no stream / Wi-Fi only / on the adapter / Wi-Fi and adapter / Wi-Fi (waiting
  for the adapter)...") and under it the three choices with a tick on the
  current one. How: Meteor numbers each pick made in its menu; a streaming
  headset looks at Meteor's small `/meteor/link` page every 2 seconds (not
  written to Meteor's log), follows a pick it hasn't seen (button, saved
  setting, a notice "Stream Link: X (chosen on the PC)"), and its second-link
  pings carry its choice and the pick number it has seen, which is how Meteor
  learns a change made on the headset. A change made on the headset with no
  stream running is remembered as "not yet told" and wins at the next stream's
  first look. Needs both 7u and sf5; with an older Meteor the headset works as
  in 7t.
- **"Adapter only" is now "Adapter first"**, which is what it does. Each of
  the three choices has its own tooltip.
- **The headset now says when that happens**: "Adapter signal lost:
  streaming over Wi-Fi." and "Back on the adapter.", with a `[LINK]` line
  in the log for each (worked out on the headset from which link the
  packets arrive over, second by second).
- **A shorter gap when the adapter's signal goes** (Meteor): the stream is
  on the adapter alone only while its pings (two a second) arrive on time.
  One more than 1.5 seconds late and the Wi-Fi copies start again; they stop
  only after the adapter's pings have been steady for 3 seconds. Before:
  nothing was sent to Wi-Fi until 5 seconds of silence. Not yet measured on
  the headset.
- **"Wi-Fi only" takes effect at once**: the headset's pings now say so, so
  Meteor stops the adapter's copies on the next ping (half a second) where
  it used to wait for 5 seconds of silence. The headset keeps pinging over
  the adapter in this choice, which is what lets Meteor's menu show and
  change it.
- Not yet: the same choice on the connection screen; the controls, the
  microphone and Meteor's depth over both links (all three are still on
  Wi-Fi alone).

### 7t (2026-11-16) and Meteor 0.9.0-sf4
- **What 7s showed** (10 minutes at 144 Hz, strong Wi-Fi plus the
  adapter): with Multi-Link on, **no lost video frame at all**; the 24 lost
  frames of the session fall in the two short stretches when it was switched
  off. Earlier sessions on Wi-Fi alone lost 110 to 130 a minute. The
  adapter's copy arrived first for about 95% of packets, the adapter lost
  nothing on its own in steady running, and Wi-Fi lost between 8 and 548
  packets in each 10 seconds, all delivered by the adapter instead. Meteor
  0.9.0-sf3 compiled on the PC at the first attempt.
- **Advanced Settings > Stream Link: Multi-Link, Wi-Fi only, Adapter only**
  (was Multi-Link On/Off). "Adapter only" sends the picture and sound over the
  adapter's link alone: the headset's pings on that link carry one more byte
  saying so, and Meteor stops the packets to the Wi-Fi address while those
  pings keep coming. If they stop for 5 seconds Meteor is back on Wi-Fi by
  itself, so a dead adapter link cannot leave the headset with nothing. Needs
  Meteor 0.9.0-sf4; with sf3 the headset says so in the log and uses both
  links. Switching needs no restart. **Still on Wi-Fi in every choice: the
  controls, the microphone and Meteor's depth.** Not yet: the same choice on
  the connection screen and in Meteor's menu.
- **Meteor's tray menu says "Multi-Link: both links" or "Multi-Link: second
  link only"** while a stream is using the second link (a status line, not
  a setting yet).
- **Voice typing no longer drops what is said after a pause.** Whole parts of
  sentences were being cut off. In the 7s log: 34 characters came back from 10
  seconds of speech and 50 from 14, where the usual rate is 9 to 12 characters
  a second. Cause, in whisper.cpp's source: transcribing without timestamps,
  the model's first "end of text" ends the whole clip (`seek_delta` becomes
  the whole window). Now transcribed with timestamps, so whisper.cpp continues
  from where the model stopped. Cost: when that happens it listens again from
  that point, so those clips take longer than before, and they are the ones
  that used to lose text.
- The `[LINK]` line's "came first" share is now exact (each packet is
  counted once in the library); one 7s line read 103%.
- Tooltip wording from notes on 7r: Headset: GPU now ends "Drawing frames
  takes priority over refreshing depth"; Cursor Steady is "The amount of
  stabilization applied to the pointer. Adaptive steadies more the slower you
  move."

### 7s (2026-11-16) and Meteor 0.9.0-sf3
The first Multi-Link build: the stream's picture and sound over
Wi-Fi and the wireless adapter's link at once. Needs both this headset build
and Meteor 0.9.0-sf3 on the PC; with an older Meteor the headset says so in
the log and streams as before.

- **What Valve says its own does** (read first): the Steam Frame
  guide says streaming "will utilize a combination of the Wireless Adapter
  and your local Wi-Fi", and the adapter "works together with your local
  network"; Valve's reply on its SteamVR-for-Linux tracker (quoted by MIXED,
  3 Oct 2026) says Multi-Link "sends packets over multiple interfaces" and
  that "if one were to drop, the other interface would still be streaming
  packets just fine". The switch is Steam Link > Advanced Settings > "Allow
  Multiple Links". No more detail is published; one owner measured a full
  second copy of the stream on the other link. So: copies on both links,
  first to arrive is used.
- **How this build does the same through Meteor:**
  1. The headset looks in its own system tables for a PC that has answered
     on the adapter's link (`wlanap`; the headset is that link's access
     point), asks it "are you Meteor?" and goes on only if it has the same
     key as the Meteor the stream is passing through.
  2. The stream library then sends its video and audio pings (it already
     sends them to the PC every half second) to that address as well. A
     ping carries 16 bytes the host made for that one stream.
  3. Meteor has seen the same 16 bytes from the stream's own address, so it
     knows the new sender is the same stream on another path, and sends
     each video and audio packet to both addresses. Nobody else knows those
     bytes without already being able to read the stream. Copies stop
     5 seconds after the last ping on the second link.
  4. The headset uses whichever copy of a packet arrives first; the stream
     library already threw away packets it had seen.
- **What it does not do yet:** the controls connection (your input, and the
  "are you there" that ends a stream) stays on the one link the stream
  started on. A link that dies outright still ends the stream; this build
  only guards the picture and sound against packets lost on one link. Also
  not yet: a stream that started on the adapter's link adding Wi-Fi.
- **In the log:** `[LINK] second link on: ...` or `[LINK] no second link:`
  with the reason, then every 10 seconds how many packets came over each
  link, how often the adapter's copy came first, and of the packets old
  enough to judge, how many arrived over both, over Wi-Fi only, and over
  the adapter only (those are the ones the second link saved). Links are
  named by interface; no address is written.
- **Advanced Settings > Multi-Link** (On by default). Switching it takes
  effect without a restart.
- **The video and audio sockets now listen on every address of the headset**
  for an IPv4 stream, where they listened only on the one the stream started
  on. That is needed for copies to arrive and is the one change that applies
  even with Multi-Link off.
- **Cursor Steady's "One Euro" is now called "Adaptive"** (the name isn't a
  commonly used term). It is the published "1 euro" filter; the name was a
  joke in the paper about its cost.
- **Meteor 0.9.0-sf3** (`meteor/src/proxy.rs`, `discovery.rs`): the second
  link above; its "are you Meteor" answer lists "second-link" so that a
  headset never tries this with a Meteor that would mishandle it. Built on
  the PC with `meteor/tools/build_meteor_fix.ps1` as before; not compiled
  on the build machine (no access to Rust's package store there), where
  only the new logic was compiled and run on its own.
- New in the source: `src/frame_second_link.gd`,
  `steam-frame/toolchain/overlay-ports/moonlight-common-c/0004-second-link.patch`.

### 7r (2026-11-16)
- **Quality's tooltip changes as you press the button** (7q changed it only
  once the pointer left and came back).
- **Cursor Steady has a fifth level, Max,** after High (for when the body's
  movement shakes the hands). It closes the gap between the pointer and where
  the hand points gradually, about two thirds of it every 0.35 s, the same at
  every display rate: a bounce 2.5 times a second comes through at under a
  fifth of its size (High, at a 90 Hz display, lets about half through), and
  the pointer trails a deliberate move by about a third of a second. These are
  first figures, to be tuned by feel. The button now goes Off, Low, High, Max,
  One Euro; the tooltip says what each is for.
- **A new install starts on Headset: GPU** where it used to start on
  Headset: Detail (existing installs keep what they have). From the 7q
  battery test (unplugged, 1080p, passthrough off, about 3 minutes each,
  power averaged per minute; 144 Hz Detail and Light run twice):

  | | 90 Hz | 144 Hz |
  |---|---|---|
  | Meteor | 14.7 W | 18.6 W |
  | Headset: Light | 15.8 W | 20.6 to 21.2 W |
  | Headset: GPU | 17.0 W | 20.7 W |
  | Headset: Detail | 19.1 W | 22.7 to 23.4 W |

  The battery held about 18.7 Wh by this log (60% in 34.5 minutes at an
  average 19.5 W), so that is roughly 76 minutes on Meteor at 90 Hz down to
  48 on Detail at 144. GPU draws about 2 W less than Detail at either rate
  for the same look, and frees the processor. Hottest sensor: 72 to 80 C at
  90 Hz, 82 to 87 C at 144, for every model.
- One thing Detail still does better: at 144 Hz it makes about 15 maps a
  second where GPU makes 12, because GPU gives way to drawing.

### 7q (2026-11-16)
- **AI 3D > Quality has a tooltip for each choice** (four models are too many
  for one tooltip, and the one shown still only talked about Steam Frame and
  Meteor). Meteor, Headset: GPU, Headset: Detail and Headset: Light each say
  where the depth is made and what that costs, from what was measured in 7j to
  7o.
- **Why the old tooltip was wrong:** the menu is built before Nightfall
  knows whether this build can make depth on the headset, so the tooltip
  chosen then was the one for a build that can't ("made by Nightfall Meteor
  on your PC") and nothing replaced it. The tooltip is now set whenever the
  button's label is.
- Noted for before 1.0: go through every tooltip and check it against what the
  option does now.

### 7p (2026-11-16)
- **The `[POWER]` line gives the minute's average, lowest and highest
  power,** from a reading every second, where 7n and 7o gave the one reading
  at the minute. That one reading swung by several watts on a single
  setting (7o log, one model at one display rate: 17.2, 22.4, 19.0 and
  19.3 W), too much to tell settings apart by. The first line of a stream
  now comes after a minute, not at once.
- What 7o's readings did show (unplugged, 1080p, passthrough off): the
  headset draws about 15 to 18 W at a 90 Hz display and 17 to 23 W at 144,
  and the battery fell 24% in 14 minutes, most of them at 144. The display
  rate moves the figure more than the choice of depth model does.

### 7o (2026-11-15)
- **The installer's finishing window has a "Restart now" button** beside
  "Later". The window already advised restarting the headset once after an
  install (SteamOS can otherwise get stuck repeating the volume buttons); the
  button does it. It asks the system's login service to restart, as the
  desktop's own Restart does, falls back to asking the desktop, and says so in
  a window if neither works. Not tried on a headset before delivery (the build
  machine has neither window tool nor a system to restart): the first install
  will show.
- Nothing in Nightfall itself changed from 7n.

### 7n (2026-11-15)
- **New `[POWER]` line in the log, once a minute while a stream runs:** the
  battery's charge, whether it is charging, and the power being drawn at
  that moment in watts. The first battery figure for the graphics-chip
  model (100% to 54% in one sitting, 7l) covered moving about,
  two kinds of passthrough and 144 Hz at once, with nothing to compare it
  to. With this, a couple of minutes unplugged on each setting gives a
  figure for each. A controller's battery is passed over; its name is never
  written.
- **Fixed: cycling Camera FPS Limit past a choice restarted the stream for
  nothing.** Going from Auto through On to Off (two presses in a second)
  restarted a 144 fps stream at 144 fps: the restart the first press asked
  for still ran after the second press had put the rate back (7l log). That waiting restart is now called off.

### 7m (2026-11-15)
- **Headset: GPU is remembered between runs,** like Detail and Light. In
  7j to 7l every start went back to Headset: Detail, a safety net for the
  model's first runs on a real headset. It has run through five sessions
  without trouble, and the reset caused a mix-up in testing (a report about
  "GPU" that was Detail). If a build ever lacks the graphics-chip engine or
  the model's files, the saved choice falls back to Detail by itself.
- **Faster Voice Typing leaves Headset: GPU alone.** It slows the depth
  model while speech is worked out, because both use the processor. The
  graphics-chip model doesn't (7j log: a sentence took 2.0 s with the
  option off, as quick as Detail with it on), so slowing it only cost depth.
  The option's tooltip now says "Only with Headset: Detail or Light".
- Quality's tooltip no longer calls Headset: GPU a test.

### 7l (2026-11-15)
- **Fixed: 7k's `[NET]` lines all said "no route to the PC".** They read the
  system's network tables the way Nightfall reads other small files, by
  asking for the whole file; the tables under /proc report a length of
  zero, so that returned nothing. They are now read to the end piece by
  piece. Found in the first 7k log, which had a connection drop in it and
  could say nothing about it. Nothing else changed from 7k.
- **7k's result, for the record (same log):** the driver took the
  low-priority request ("low priority: taken by the driver"). Headset: GPU
  at a 90 Hz display: a steady 90 frames a second for five minutes (7j:
  about 80, dips to 61); at 144 Hz: 144 (7j: held at 72). The model's maps
  take longer in return, since drawing now goes first: 32 ms at 90 Hz
  (18 maps a second), 55 to 58 ms at 144 Hz (11 a second).

### 7k (2026-11-15)
A test build with one change to the picture and one addition to the log.
- **Headset: GPU asks the graphics driver to rank the depth model's work
  low.** Measured in 7j: the graphics chip runs the 512x288 model in 20 ms
  (Detail on the processor: 40 to 45 ms) and frees more than a processor
  core, and at a 72 Hz display Nightfall keeps full rate; but at 90 Hz
  Nightfall drew about 80 frames a second (dips to 61) and at 144 Hz it was
  held at 72, because the model's work and Nightfall's drawing were served
  in turn. Vulkan has a setting for exactly this, a queue's "global
  priority" (part of Vulkan 1.4, which the headset's driver reports); LOW
  needs no special rights. ncnn has no option for it, so the build applies
  a small patch to ncnn (`steam-frame/ncnn-low-priority.patch`, which says
  why). If the driver does not offer the setting, or refuses, the model
  runs exactly as in 7j.
- **Not known until it runs on the headset:** whether the driver takes the
  request, and whether it makes the chip put Nightfall's drawing ahead of a
  map already being worked out (the Linux driver gained that for this family
  of chips in 2024; whether the headset's system carries it is not
  published). The start-up line for the model now ends "low priority: taken
  by the driver", "not offered by the driver" or "refused by the driver",
  and the frame rate at 90 Hz says the rest.
- **New `[NET]` lines in the log: the headset's own network link.** On
  2026-11-15 two streams ended because nothing passed between headset and
  PC for minutes while both were running; the logs could show that, not
  where. Now: one line when a stream starts, one a minute while it runs,
  one every 5 seconds from the moment a stream is lost until the next one
  starts (at most 15 minutes). Each says whether the Wi-Fi link is up, its
  signal strength, packets arriving and leaving each second, and whether the
  PC (or the router, if the PC is reached through it) answered when the
  headset last looked for it. At a stream's start and in trouble, also the
  band, the sending speed, and whether the headset is still on the access
  point the stream began on.
  **Never in these lines: an address, a network's name, an access point's
  identity.** They are read to pick the right rows out of the system's
  tables and are not written anywhere (a test checks the sentences).
  Nothing is sent anywhere to find these things out; they are read from
  files the headset's system keeps, plus one run of the system's `iw` tool
  at a stream's start and every 30 seconds in trouble.
- New in the source: `src/frame_network_watch.gd`, `test/test_frame_7k.gd`,
  `steam-frame/ncnn-low-priority.patch` (applied by `build-ncnn.sh`).

### 7j (2026-11-15)
A test build: the depth model on the headset's graphics chip.
- **AI 3D > Quality has a third headset choice, "Headset: GPU".** It runs
  EdgePad 512x288, the model Meteor runs on the PC (the file Meteor's
  installer puts there, in ncnn's format), on the headset's graphics chip
  through ncnn's Vulkan backend, the engine upstream Nightfall uses on desktop
  Linux. Detail and Light still run on the processor, so the three can be
  flipped between on the same scene.
- **Why try it:** the processor model was chosen at 144 Hz, when drawing
  left the graphics chip no time. At 90 Hz it has time to spare, the
  processor model (Detail) is slow here (45 to 72 ms a map) and slows voice
  typing. Against it: the graphics chip is the hottest part of the headset,
  and passthrough and drawing share it.
- **Not known until it runs on the headset:** whether ncnn's Vulkan backend
  starts on the Frame's driver beside Godot's and SteamVR's use of it (if it
  doesn't, Quality shows a notice and the log says why), how long a map
  takes, and what it costs the frame rate. On the build machine, which has
  no graphics chip, the same model through the same engine gives a sensible
  map on the test scene (sky 1, far floor 153, near floor 241).
- **The choice is not remembered between runs while it is a test:** every
  start is back on Headset: Detail, so if the graphics-chip engine should
  bring Nightfall down, starting it again is enough.
- The log's `[DEPTH-PERF]` line names the model (`edgepad-512-gpu`) and the
  start-up line names the graphics chip it found.
- New in the source: `steam-frame/build-ncnn.sh`; licences for ncnn and
  glslang in the package.

### 7i (2026-11-15)
- **Hz Cap Auto now judges by Nightfall's own frame rate alone.** In 7h it
  also wanted the video to keep its rate, as upstream's pacer does, and sat at
  its lowest (12) for the whole session: a PC desktop only sends a new picture
  when something on it changes, so the video arrived at a median 73 a second
  on a 90 fps stream and 60 on a 144 one, with the headset doing nothing
  wrong. (Nothing looked amiss at 12 a second with either model.)
- **Faster Voice Typing** (Advanced Settings, Voice row; on by default).
  While a clip is being worked out, the headset's depth model runs 4 times a
  second and goes back to its rate when the text arrives. With Headset:
  Detail running, the Small speech model took 15.8 seconds to type out 30
  seconds of speech; resting the depth model a little (Hz Cap Auto) made no
  difference. The `[VOICE]` log line says "(depth model eased)" when it
  applied. The 3D depth trails for those seconds.
- **SteamOS's own passthrough** (double tap of the Steam button, or stepping
  out of the play space) is not Nightfall's and Nightfall is not told of it.
  At 144 Hz SteamOS then holds Nightfall at 72, and with a colour camera it
  hitches (7h log; nothing happens at 90 Hz). Nothing
  is done about it in this build: the add-on's sensors run whenever the room
  is light, whether passthrough is showing or not, so they don't say.

### 7h (2026-11-15)
- **Hz Cap has an Auto choice for the headset's depth models, and it is the
  default.** Auto starts the model at 20 maps a second and adjusts by
  itself, on two things:
  - *Is the headset keeping its frame rate?* A second in which the app or
    the video falls short cuts the model's rate by a quarter (not below 12);
    three good seconds in a row give 2 a second back. This is Nightfall's
    own pacer for the Quest's models, which was behind an option hidden on
    the Frame.
  - *How fast is the model?* Auto asks for at most four fifths of what the
    model can make, so it rests between maps. Headset: Detail takes 54 to 72
    ms a map here, so Auto holds it at 12 or 13 where a fixed 20 only ran it
    back to back; Headset: Light (about 20 ms) gets the full 20.
- The numbers 12 to 60 are still there to choose. A rate saved by an earlier
  build stays as it was: pick Auto on the AI 3D tab to try it.
- Each change is logged: `[DEPTH] Auto rate 15 a second, from 20 (app 78 fps
  and video 78 of 90; model 21 ms a map, so at most 20)`.
- The numbers are a first setting, to be judged from the logs.

### 7g (2026-11-15)
- **When the cameras change back before an announced restart, the notice says
  so:** "Camera switch canceled: staying at 90 fps." In 7f the restart was
  rightly called off, but the second notice still announced a change to the
  rate the stream was already at.

### 7f (2026-11-15)
Polish for the Camera FPS Limit, from its first run on the headset.
- **A warning before the rate changes by itself.** When the cameras change
  over (Auto), a notice says so and the stream restarts five seconds later:
  "Native passthrough detected: back to 144 fps in 5 seconds." or "Color
  camera detected: 90 fps in 5 seconds." Time to pause a game. If the
  cameras change back within those seconds, nothing restarts. A change made
  by pressing something (Passthrough, the option) still happens at once.
- **Wording:** "Native passthrough detected" in place of "Colour camera
  resting"; American spelling ("color") in what Nightfall shows; the
  option's tooltip says "the color camera" where "that camera" could be
  read two ways.
- Stepping through the option's three choices restarts the stream once, not
  for each step.
- **From 7e's log:** Auto followed the lights both ways, twice: back to 144
  twenty seconds after the colour camera went idle, down to 90 within a few
  seconds of it returning (two or three seconds of hitching).

### 7e (2026-11-15)
- **Camera FPS Limit is now Auto, On or Off, and Auto is the default.** Auto
  holds the rate at 90 only while the add-on's colour camera is the one
  showing the room, so in the dark, when the headset's own cameras take over,
  the chosen FPS comes back. On holds it whenever an add-on is fitted. Both
  only with Passthrough on.
- **How Auto tells:** the add-on's sensors read "active" while its camera
  runs and "suspended" when it has handed over (found by 7c's probe).
  Nightfall looks every 3 seconds. It drops to 90 as soon as the colour
  camera is running, and goes back up only after that camera has been idle
  for 20 seconds, so a shadow over the room doesn't restart the stream
  twice. The notice then reads "Colour camera resting: back to 144 fps."
- A saved Off from 7c or 7d stays Off; a saved On becomes Auto.

### 7d (2026-11-15)
- **The FPS button keeps saying both rates** while the Camera FPS Limit holds
  it lower ("144 (90 now)"). In 7c that showed for a moment and then became
  "90": a later refresh of the button wrote the rate in force over it. The
  same refresh also put the original tooltip back over the Frame's own.
- **The notice on the way back says why:** "Passthrough off: back to 144
  fps.", or "Camera FPS Limit off: back to 144 fps."
- **7c's probe answered, and is taken out.** Which camera is running can be
  told: the add-on's sensors read "active" while it shows the room and
  "suspended" once its app has handed over to the headset's own cameras in the
  dark (seen within 20 seconds of each change of light, both ways, three
  times). Nothing uses that yet: following it would restart the stream at
  every change of light, which is a design decision.

### 7c (2026-11-15)
- **Camera FPS Limit: 90 fps while a colour camera add-on shows the room.**
  With a camera add-on fitted (Arcturus Vision is the first) and Passthrough
  on, Nightfall streams and displays at 90 whatever FPS is set to, and goes
  back to the chosen rate when Passthrough goes off. The FPS button shows
  both ("144 (90 now)"), a notice says why when it happens, and Advanced
  Settings > Camera FPS Limit turns it off (the option is only there while
  an add-on is fitted). A headset without an add-on is not affected: its own
  black-and-white passthrough showed no hitching at any rate.
- **How the add-on is told apart:** by the camera sensors the system lists.
  7b's probe showed the add-on's sensors ("arcimx616") beside the headset's
  own two kinds; any sensor that is not one of those two counts as an
  add-on, so a camera from another maker is covered as well.
- **Why it follows the add-on being fitted and not the light in the room:**
  the add-on's app changes over to the headset's own cameras in the dark, but
  nothing read so far says reliably which camera is running, and every
  change of rate restarts the stream (grey screen, then a moment of black as
  the display changes). So with an add-on fitted the limit also holds in the
  dark. The probe now records each sensor's power state and everything the
  infrared light shows, to see whether that can be told.
- **From 7b's log:** FPS switched the display in 1.6 to 2.6 seconds each time
  (144, 72, 90, 120). At 72 and 90 Hz Nightfall's drawing took 2.6 to 2.9 ms
  against 5.5 at 120 and 144, and the hottest sensor read 79 to 87 C at 72 Hz
  against 94 to 95 at 144.

### 7b (2026-11-15)
- **FPS now sets the headset's display rate as well.** SteamVR runs each app
  at the one rate its per-app setting names and offers the app nothing else,
  so until now the display stayed at whatever was set in SteamVR's own menu
  (144 Hz here) whatever FPS said. Choosing FPS in Nightfall now has SteamVR
  switch Nightfall's display to match: 72, 90, 120 or 144 (a 60 fps stream is
  shown at 120, a 30 fps one at 90). It takes effect while Nightfall runs.
  The way to do it is Moonlight XR for Frame's (GPLv3), which sets the same
  setting through SteamVR's tool.
- **Why:** what 7a's test and the session after it showed. With passthrough
  on, asking for the cameras' picture costs Nightfall about 3.3 ms a frame
  (its see-through drawing costs nothing). At 144 Hz a frame has 6.9 ms, so
  Nightfall falls behind, SteamVR drops it to half rate and back about twenty
  times a minute, and with the colour camera add-on (Arcturus Vision) that
  shows as hitching when the head turns. At 90 Hz a frame has 11.1 ms: a
  steady 90 with the colour camera, a headset depth model and a 1440p stream,
  and no hitching. Motion smoothing blurs text badly and stays off; SteamVR's
  throttle setting made no difference.
- **Temporary: `[CAMERA-PROBE]` in the log.** To switch to 90 by itself only
  when a colour camera is feeding passthrough, Nightfall must tell that camera
  from the headset's own. This lists camera devices, lights, USB device names
  and running programs with a camera-like name, whenever they change. Names
  and on/off values only.
- **Taken out:** 7a's PT Test button.

### 7a (2026-11-15)
A test build: where passthrough's cost comes from.
- **What 6z's log showed.** The hitching when turning the head goes with
  Passthrough: flat screen at 1080p with a headset depth model, 143 to 144
  frames a second with it off, 83 to 93 with the colour camera add-on
  (Arcturus Vision), 97 with the headset's own black-and-white cameras; at
  1440p 100 to 107, 66 to 72 and 80. Nightfall's own drawing of the same
  scene takes twice as long while passthrough is on (5.5 ms against 2.6),
  and with the colour camera the graphics chip steps its clock down in about
  half the seconds.
- **Picture > PT Test (temporary): Off, 1, 2, 3.** With Passthrough on, each
  changes one thing: 1 draws see-through without asking for the cameras, 2
  asks for the cameras but draws solid, 3 is ordinary passthrough with the
  eye pictures at half size. The log's frame figures for each say whether
  the cost is in Nightfall's see-through drawing, in the cameras' picture,
  or follows the size of what Nightfall hands over. Not saved.
- **Taken out again:** 6z's `[VIDEO-COPY]` line (the copy is small: 0.4 ms a
  picture at 1080p, about 1 ms at 1440p), and its core test and core list
  (the depth model's threads already ran on the middle cores; keeping them
  there changed nothing in the frames).

### 6z (2026-11-15)
Two small fixes and two measurements, after the 6y sessions.
- **Voice typing drops text nobody could have said.** Once, the one word
  "connected" came back as 242 characters of unrelated words from a
  1.4 second clip. A result with more text than the clip has room for
  (20 characters plus 30 for each second; ordinary dictation is 8 to 15 a
  second) is not typed: "Didn't catch that."
- **The server list always shows the port.** Since 6s the standard port
  (47989) was left out, so Sunshine's row showed the bare address and looked
  as if the port had been lost. Two hosts on one PC differ only by port.
- **Measurement: what each video picture costs on its way to the graphics
  chip** (`[VIDEO-COPY]` once a second: the copy on the decoder's thread and
  the upload on the render thread). In the 6y logs the frame rate followed
  the stream's size whatever the host or depth source (about 100 fps at
  1080p, 67 to 88 at 1440p, 64 to 68 at 4K, flat screen), and the graphics
  chip was not the busy part. This is the step that grows with the stream's
  size; it has never been timed.
- **Measurement: which processor cores the depth model's threads run on**
  (end of the `[DEPTH-PERF]` line). Detail takes 60 to 66 ms a map here
  against 34 to 37 in Moonlight XR's bench, and the processor's clocks are
  not being held down.
- **Test: where the depth model's threads run.** Every other minute they
  are kept to the processor's middle cores (3 to 6, as Moonlight XR's option
  does); the minutes between, they run wherever the system puts them. The
  `[DEPTH-PERF]` line says which ("kept to 3-6" or "free") and where the
  main thread was. In the 6y logs a headset model added seconds with a frame
  over 20 ms (6 to 9% of seconds at 1440p against 0% with Meteor's depth),
  which is what shows as a hitch; this compares the two placements like for
  like, for model time and for long frames.
The measurements and the test are temporary.

### 6y (2026-11-15)
After the first headset run of on-headset depth (6x): it worked, and its log
showed three things to put right.
- **The depth stood still after changing Quality, sometimes for many
  seconds.** After a switch between Detail and Light the app could be told
  the old model's size, and then threw away every map of the new one ("Size
  mismatch" in the log, 13 seconds once). With Depth View on that is a grey
  screen. The engine now reports the chosen model's size at once and never
  hands out a map of the other size.
- **The model ran flat out.** Its rate came from Hz Cap, which was hidden on
  the Frame and still held 60 from long ago, so Detail ran back to back at
  11 to 15 maps a second and Light at 37 to 46, with 2 to 2.6 processor
  cores in use. The headset's model now has its own rate, 20 a second to
  start with, and **Hz Cap is back on the AI 3D tab** while a Headset model
  is chosen (12 to 60).
- **The model's threads now give way to everything else** (lower priority).
  In 6x, voice typing with the Small speech model took 0.91 of the speech's
  length to work out, against 0.35 without the depth model, and the longest
  frame each second went from 12 to 18 ms up to 22 to 28 on a curved screen.
  Whether this is enough is for the next log to say.
- Tooltips: Quality now says what Meteor and the two Headset choices are
  (the headset's model is ZipDepth: Detail its 512x288 version, Light the
  256 one); Hz Cap explains the trade; Foveation no longer says "Best with
  PT Fade at 0%" (not true since 6l) and says a flat screen is faster with
  it Off.
- The `[DEPTH-PERF]` line also gives the processor's clock speeds and any
  cap that heat has put on them.

### 6x (2026-11-15)
First build with **AI 3D made on the headset itself**, for when Meteor isn't
making the depth. A first, measuring build: it works end to end, and its log
says how fast it runs and what it costs.
- **A depth model runs on the headset's processor** (ZipDepth, with LiteRT
  and XNNPACK), not on its graphics chip, which Nightfall's drawing already
  keeps busy at 144 Hz. It takes its pictures straight from the video
  decoder, so nothing is read back from the graphics chip and the model
  never works on a stale frame.
- **AI 3D tab > Model** now cycles Meteor (while the PC offers it),
  **Headset: Detail** (ZipDepth at 512x288) and **Headset: Light** (256,
  8-bit: several times lighter on the processor). Meteor is still used first
  when it is there; if it stops delivering, the headset's model takes over
  after three seconds.
- The models (18 MB) come inside the package; nothing is downloaded.
- Log: `[DEPTH-PERF] on headset: ...` once a second with maps a second, the
  model's time per map, the age of the depth when it is ready, and how many
  processor cores the whole app is using.
- Learned from Moonlight XR for Frame, which measured this route on the
  Frame: the processor is fast enough once the arithmetic is half precision
  (27 maps a second for the larger model on two threads, in their test).
  Nightfall's own desktop Linux route (TensorFlow Lite without XNNPACK, a
  blocking read-back of the picture) was not used.
- `steam-frame/build-litert.sh` builds the runtime; `frame_depth_test`
  checks the engine on a PC.

### 6w (2026-11-15)
- Buttons tab: the Custom Gamepad entry reads "Button Mapping" underneath
  (what it opens) instead of "In use" / "Not in use". Whether the custom
  layout is in use is shown on the page it opens, as before.

### 6v (2026-11-15)
- **The log copy in Downloads is cleaned for sharing.** The copy in
  `~/Downloads/Nightfall-logs/` (the one that gets attached and posted) is
  now written through `share_log.py`, which masks network addresses
  (192.168.1.50 reads x.x.x.50), hardware addresses, the ids the headset
  and a PC give each other, session keys, PINs, certificates, PC and
  network names, the home folder's user name, e-mail addresses and Steam
  account numbers. The logs in the app's own folder are untouched: they
  never leave the headset by themselves. A real 9-minute log held the PC's
  address 36 times and the pairing ids 6 times; after cleaning, none, with
  98 of 39,189 lines changed and nothing else altered.
- The log no longer writes down a PC's name when Scan Network finds one.
- `collect-steamos-logs.sh` passes its copies through the same cleaner.
- Without python3 (the cleaner needs it) no copy is put in Downloads,
  rather than an uncleaned one.

### 6u (2026-11-15)
- **Edge Smoothing is gone.** No difference could be seen with it on, it cost
  2 to 5 ms a frame, and with Foveation it garbled the picture (6t). The
  Frame's 3D scene is now always drawn without multisampling. A saved "On" is
  ignored.
- **Buttons tab: "Gamepad Layout" is now "Custom Gamepad".** The Control
  tab has Gamepad Layout (Standard, Swapped, Custom: which layout is used);
  the Buttons tab had an entry with the same name showing the same value,
  which opens the editor for the custom layout. That one now reads Custom
  Gamepad, with "In use" or "Not in use" under it.
- **uninstall.sh.** Removes the app, its Steam library entry and its logs.
  It asks first, and asks separately whether to also remove the speech
  models and the settings and pairings. Tried in a pretend home folder
  here (what is removed and what is left alone); removing the Steam entry
  could not be tried without Steam, so the script asks Steam whether the
  entry is really gone and gives the manual steps if not.
- **WHERE-THINGS-ARE.txt** in the package: every place Nightfall keeps
  files on the headset, what each is and how big.

### 6t (2026-11-15)
- **Edge Smoothing no longer runs together with Foveation.** With both on,
  the scene filled with bright red and yellow blotches and each frame took
  61 to 71 ms to draw instead of about 6 (13 to 16 fps), every time, in the
  6r log. Edge Smoothing is multisampling, Foveation is a shading-rate map;
  that pair on the Frame is Godot issue 124165, still open. Each works on
  its own (Edge Smoothing alone: clean, 2 to 3 ms more per frame). While
  Foveation is on, Edge Smoothing shows "Waiting" and does nothing; it
  comes on by itself when Foveation goes Off.
- **The stream FPS list stops at 144 on the Frame.** 165 was offered: it and
  200/207 are Quest 3 display rates. A saved 165 becomes 144.

### 6s (2026-11-14)
The server list (Select Server).
- **Each saved PC is listed by name.** The name is the one the PC gives
  itself, with its address in small print underneath; until now the list
  only showed an address and port. A PC saved by an earlier build gets its
  name the next time it is connected to (the app already asks the PC for
  its details at that moment; the name was simply never read). The address
  shown is the one typed to pair, so the port only appears when it isn't the
  usual one.
- **Rename.** Each PC has a Rename button: a page with letter keys, up to
  24 characters. The PC's own name moves to the small print. Saving an
  empty name goes back to the PC's own. A name stays with its PC through a
  new pairing.
- **Remove.** Each PC has a Remove button; it asks "Sure?" and needs a
  second press within four seconds. It forgets that PC's pairing on the
  headset, its name and its saved settings, and nothing else. "Clear Saved
  Servers" (everything, on one press) is gone.
- **Two hosts at one address keep their own settings.** Stream settings and
  screen layouts were saved under the PC's address, so Sunshine and
  Meteor's built-in host on the same PC shared one set and overwrote each
  other's. They are now saved for each paired host. Both start from what
  was saved so far. A PC also keeps its settings when its address changes.
- **The first page names the PC that Connect will use**, with its address
  under it. The labels were there in the original but never filled in.
- **After a restart the app goes back to the host last used.** With two
  hosts at one address it went to the first one saved: pressing Connect
  wrote the address down again without saying which host.
- Checked here without a headset: the list, the naming page and the remove
  step in a run of the app on a PC (pictures taken, buttons pressed by
  script), with a pretend PC answering the pairing check for the name.
  Not checkable here: the name arriving at stream start, which needs a
  real paired host.

### 6r (2026-11-14)
- **Voice typing: long pauses are shortened before the speech model hears the
  clip.** Sentences were going missing: 18.5 seconds of speech came back as
  one character, 30 seconds as 40. The clip is worked out in one piece, and
  when the model decides the text has ended at a pause, everything said
  after it is dropped. Every pause longer than half a second is now cut to
  half a second first, which also makes long clips quicker to work out.
  Reasoned from the recogniser's source; it could not be tried with a real
  model here.
- The log line for each clip now carries its own numbers (how much of it was
  quiet or dead, how much pause was cut, how many pieces of text the model
  made), to tell a microphone that delivered nothing from a model that
  stopped early. Loudness and counts only; nothing of what was said.
- Screens tab: a layout with the second screen on the left. Save no longer
  adds a picture that is already there (it selects it and says so).
- Screens tab: the note for other hosts is reworded and in the blue the
  menu's other notices use.
- The Muted button sits flush against Exit: while shown it takes the rounded
  corner, instead of both having one with a wedge of the panel between.

### 6q (2026-11-14)
From the first trial of the Screens tab.
- **Picking a layout no longer removes the virtual screens.** Pressing Apply
  with the same number of virtual monitors (a different layout picture, or
  nothing changed) took every virtual screen away, and only changing their
  number brought them back. A fault in the original.
- **Curved screens show their own monitor.** With more than one screen, each
  curved screen showed the whole stream (every monitor side by side).
- **Voice typing: a runaway repeat is cut.** A one-second clip once came back
  as the same word 23 times. The recogniser now has a word budget for the
  clip's length, and a word or short phrase repeated four or more times in a
  row is typed once. Three in a row, and repeated digits, are left alone.
- Screens tab tooltips: Grid Mode says what On and Off do; Virtual says that
  Windows chooses where a new monitor sits on its desktop.
- The log records when the Screens tab's note about the built-in host is
  shown or hidden.

### 6p (2026-11-14)
- **The Screens tab is open on the Frame** (first trial): choose how many of
  the PC's monitors to show, add virtual monitors, pick a layout, Grid Mode.
  It is the original Nightfall's tab, which the port had hidden. It needs
  Nightfall Meteor's built-in host on the PC; with Sunshine or another host
  its controls are greyed out and a note says why. The in-headset browser
  the tab also offers on Quest doesn't exist on the Frame and is left out.

### 6o (2026-11-14)
- **A stream setting changed during a restart is no longer lost.** Stepping
  the Bitrate button on while the stream was already restarting left the
  stream at the value the restart began with: the button said 120, the
  stream ran at 60 until something else restarted it. Any Stream-tab setting
  could do this (Resolution, FPS, Codec). Nightfall now restarts once more
  when the stream is back, so it ends up at what the buttons show.
- **Flat Screen Detail: Stream Size is the default.** On the headset it held
  144 frames a second with AI 3D on a flat screen (Full: about 101), with
  no difference in the picture that could be seen. Full is still there for
  comparison. With the bezel off, the screen is about 0.4% larger each way
  than at Full: the 8-pixel margin round the picture is a larger share of a
  smaller picture, as it is on Quest.

### 6n (2026-11-14)
- **Picture > Flat Screen Detail (experimental): Full or Stream Size.** A
  flat Layer screen's picture has always been drawn at 4K on the Frame,
  whatever the stream's size. With AI 3D that is a left and a right 4K
  picture every frame, which is what kept Nightfall near 80 frames a second
  on a 144 Hz display (6.3 ms a frame for a 1080p stream, against 1.2 ms
  without AI 3D). Stream Size draws them at the stream's own size. Full is
  the default and is what every earlier build did. Voice: "flat screen
  detail stream size", "flat screen detail full".

### 6m (2026-11-14)
- **The drawn PT Fade is removed.** 6l's fade through the background's
  opacity was confirmed on the headset (smooth from 0 to 100%, no rings or
  pixel pattern, no bright patch under foveation, no flicker between flat
  and curved), so the dark shell, the far dark layer and the cross-fade
  between them are gone from the code. PT Fade on the Frame now needs
  Nightfall's engine build (steam-frame/engine/, patch 0003).
- The installer reports SteamVR's frame throttling for Nightfall. Left on
  Auto, SteamVR keeps Nightfall to 72 frames a second on a 144 Hz display;
  the installer does not change it.
- Temporary log lines for the 144 Hz work: the engine's once-a-second pacing
  line is followed by where the frame's time goes (each call into SteamVR
  that can wait, and the rest), and the frame cost line adds the drawing time
  of the pictures beside the 3D scene (the flat screen's layer, one per eye
  with 3D; menus; pointers).

### 6l (2026-11-14)
- **PT Fade costs nothing and has every step, with any screen.** The fade is
  now the opacity of the scene's background, which Nightfall's engine build
  keeps (engine patch 0003; stock Godot drops it). The dark shell that used
  to be drawn around you for curved and 3D Scene screens, with its fine pixel
  pattern, is no longer used, nor is the far dark layer behind a flat
  screen, which also dimmed the controllers and the pointer. Both remain in
  the code for an engine without the patch until this is confirmed on the
  headset.
- The engine build names itself (`nightfall3`), so the app knows which of
  the engine patches it can rely on.
- AI 3D tab: Hz Cap is hidden. It limits the depth model that runs on a
  headset; on the Frame the PC makes the depth and Meteor's own Rate setting
  is the control.
- Package read-me says what the installer downloads for voice typing, how
  large it is and where it is kept. The installer skips the larger speech
  model when less than 1 GB is free.
- Temporary engine log line, once a second: how SteamVR paces Nightfall's
  frames (for the question of why a 144 Hz display got 72 frames a second).

### 6k (2026-11-14)
- **Voice: the name alone switches an on/off setting.** "Depth view" shows
  the depth map, "depth view" again hides it. The same for head lock, menu,
  keyboard, passthrough, side by side, AI 3D, gamepad mode, pointer ray,
  microphone, custom buttons and vibration. "On" and "off" still work.
- "Depth of view" counts as "depth view" (how the Small model sometimes
  hears it).
- **Foveation changes without a restart** (first try): the option rebuilds
  the eye pictures for the new level, which is what happens at start; the
  picture blinks once. The graphics driver's draw mode follows the option
  while running.
- Temporary engine log lines say whose density map is in use and what
  SteamVR reports for the eye-tracked sharp area.

### 6j (2026-11-14)
- **The Speech Model you chose is the one that listens.** Since 6g the menu
  could say Small while Base was in use: voice typing started before the
  saved settings were read, and only pressing the option put the choice in
  force. Fixed.
- A short voice command the model writes out twice ("Depth view. Depth
  view.") runs as the command instead of being typed.
- Advanced Settings: the long "Screen, Menu & Keyboard Position" row is two
  rows, Screen Position and Menu & Keyboard Position.

### 6i (2026-11-14)
- **Voice typing works out short clips much sooner.** Whisper was listening
  to a full 30 second window for every clip, so two seconds of speech took as
  long as twenty-six (about 2 s with Base, 4 to 5 s with Small). It is now
  given the clip's own length plus a margin. Both models gain; the longer you
  speak, the smaller the gain.
- The log notes presses of the Speech Model option.

### 6h (2026-11-14)
- **Foveation, done so that Off costs nothing.** Advanced > Foveation: Off /
  Low / Medium / High, following the eyes, taking effect the next time
  Nightfall starts (changing it while running switched it off in 6f). Runs on
  our own engine build again (`steam-frame/engine/`). With Foveation Off the
  launcher asks the graphics driver for direct drawing, which is what made
  the official engine fast.
- Measured in 6f on a 7.6 m curved screen: Low 7.4, Medium 7.2, High 7.2 ms a
  frame; 6.3 ms with PT Fade at 0%, where the foveation could not be seen at
  all. The fade's pixel pattern is what showed as a brightness and hue step.
- From 6g: Speech Model Base / Small, bumpers.

### 6g (2026-11-14, sent but not installed)
- **Back on Godot's official engine.** 6f's own engine build made foveated
  rendering possible, and made everything else slower: 13 ms a frame where
  the official engine takes 6 (the fix moves the graphics driver into its
  tiled mode, which foveation needs and which costs double for Nightfall's
  scene). Foveation at Low came to 7.4 ms, still more than not having it. The
  Foveation option is out again; the findings are in
  `steam-frame/engine/README.md`.
- The bumpers stay (6f): LB and RB in Gamepad mode, assignable in the Buttons
  tab.
- **Advanced Settings > Speech Model: Base / Small.** Small is Whisper's
  larger English model (466 MB): it hears words more correctly and takes
  longer per sentence. The installer downloads and verifies it once. The log
  now says how long each clip took to work out and with which model.

### 6f (2026-11-14)
- **Our own build of the engine.** `Nightfall.arm64` is Godot 4.7-stable
  built with one added line, Godot pull request 124811 ("Fix foveated
  rendering on Steam Frame", not yet in any Godot release), so that foveated
  rendering can take effect without the FXAA detour of 6e. How it is built,
  and how it differs from the official engine: `steam-frame/engine/README.md`.
- Advanced > Foveation is back: Off / Low / Medium / High, eye-tracked, Off
  by default. Subsampled images are switched off by an `override.cfg` in the
  package (SteamVR can't show them yet; they warped the picture in 5v).
- **The bumpers work.** The click of each controller's bumper is bound (only
  its touch sensor was, since 5n). In Gamepad mode they press LB and RB, as
  the grips still do; they are in the Buttons tab (nothing assigned by
  default) and in Gamepad Layout.
- The launcher is the plain one again: no test runs, no settings file written.
- Temporary, for finding out why no eye tracking reaches Nightfall: the
  engine prints what SteamVR answers for the eye gaze pose
  (`OpenXR: eye gaze reading: …`), beside 6e's `[EYES]` lines.

### 6e (2026-11-14, diagnostic)
- 6d plus, for finding out why no eye tracking reaches Nightfall: the log gets
  the gaze direction once a second (`[EYES] gaze: …`, angles from straight
  ahead) and the headset's raw eye reading with its validity marks (`[EYES]
  detail …`, repeated every 15 s while nothing usable arrives). To come out
  again once eye tracking works.

### 6d (2026-11-14, diagnostic, not sent on its own)
- Foveation again, this time with the workaround from Godot's own issue
  tracker (issue 124141, fix proposed in PR 124811): on the Frame, Godot 4.7
  draws the scene in a way that puts the graphics driver in a mode where
  foveation does nothing; switching on FXAA avoids that. The first three
  launches after an install try FXAA alone, FXAA with fixed foveation, and
  FXAA with eye-tracked foveation; later launches are ordinary. Temporary.
- `[EYES] detail …` in the log: what the eye tracker gives Nightfall (counts
  and states only, never where the eyes point). Temporary.
- The launcher is otherwise the clean one again (6b's layer test is out);
  the installer removes what the test builds left behind.
- Kept from 6b: the launcher's log gives Nightfall's real exit code.

### 6c (2026-11-14, not sent)
- The clean build (5x app, no test code, exit-code fix). Superseded by 6d
  before it went out.

### 6b (2026-11-14, diagnostic)
- Foveated rendering, tried four ways over four launches, each log carrying
  the frame costs of the three runs before it: none; Godot's own foveation
  set at start-up (the route Valve's guide for custom engines names, with
  plain rather than subsampled images, unlike 5v); Valve's foveation layer
  switched on by its own setting and kept to the eye picture's size; and a
  fourth that follows from how the third went. Temporary.
- The launcher's log now gives Nightfall's real exit code. It always said 0:
  the date printed on the same line replaced it.
- `[PICTURE] foveation as started: …` in the log.

### 6a (2026-11-14)
- Same app as 5x. The test code of 5y to 5z2 is out of the launcher, and the
  installer removes the files those builds left behind.
- Result of those tests: Valve's foveation layer can be loaded into Nightfall,
  but as it comes it does nothing (frame cost identical with and without it),
  and switched on it stops Nightfall within seconds of starting. Not used.

### 5z2 (2026-11-14, diagnostic)
- Same app as 5x. 5z got Valve's foveation layer loaded into Nightfall; this
  build measures whether it saves anything. Launches take turns: without the
  layer, with it, and with it switched on by name and reporting what it does.
  Each log starts with the frame costs of the two runs before it.
- The launcher's report also lists the layer's own switches.

### 5z (2026-11-14, diagnostic)
- Same app as 5x. Follow-up to 5y, whose log showed Valve's two layer
  libraries are the right kind for the Frame and have nothing missing, yet
  the Vulkan loader can't find their entry point under the standard name.
- The launcher's report now lists what each library really offers, puts the
  loader's own questions to it, and, where the entry points exist under
  another name, writes a corrected description file into Nightfall's own
  folder (`vulkan-layers/`) and has the loader use it. Nothing of the
  system's is changed.
- A way back: if a run that tries the layers never finishes starting, the
  next launch goes without them. Temporary, like 5y's probe.

### 5y (2026-11-14, diagnostic)
- Same app as 5x. The launcher writes a report into the log about Valve's
  two Vulkan layers (foveation and render pass optimizer), which the Vulkan
  loader skips in Nightfall, and asks the loader to explain its layer
  loading. Temporary.
- Package read-me: how to keep a very large curved screen at 72 fps.

### 5x (2026-11-14)
- A screen can't be made wider than three times its distance any more, and a
  saved size past that is brought back when you connect. (A corner drag had
  made it 42.5 m wide; its corners, grab bar and icons were then out of
  reach, also after a restart.)
- Advanced > Screen Size: a slider for the main screen's width.

### 5w (2026-11-14)
- Foveation option removed again: on the headset it saved nothing
  measurable (11.2 ms off, 10.6 to 11.0 ms at Low, Medium and High), seemed
  to shift the picture slightly, and flashed passthrough when switched on.

### 5v (2026-11-14)
- Picture > Foveation: Off / Low / Medium / High, experimental and off by
  default. Draws the outer part of the view less finely to save drawing
  time on a curved or 3D Scene screen. Voice: "foveation low".
- Installer window says Meteor includes a streaming host of its own.
- `[FRAME-COST]` lines show the foveation level.

### 5u (2026-11-14)
- Flat to curved: the flat layer stays up nine frames (was three), and the
  room's dimming cross-fades from the layer to the scene over the same time
  without the two adding up.
- Installer sets SteamVR's motion smoothing to Off for Nightfall (the number
  is 2) where nothing or the old 0 is set, and says "Motion smoothing: Off".
- `[FRAME-COST]` lines carry the time of day, drawing time on the processor,
  the longest frame, and the graphics chip's clock and temperature where the
  system shows them (diagnostic for the frame-time swings).

### 5t (2026-11-14)
- Flat to curved no longer shows bare passthrough for a moment: the flat
  layer and the layer fade stay up three frames longer, until the screen and
  the fade drawn in the scene have appeared.
- The shareable log (`Downloads/Nightfall-logs/nightfall-latest.log`) is
  refreshed every 20 seconds while Nightfall runs. It was written only at
  exit, so a log fetched with Nightfall still open was the previous run's.
- Installer window shows SteamVR's number for a motion smoothing setting you
  chose yourself (needed to learn which number means Off).

### 5s (2026-11-14)
- Curved screen back to about 8 ms of drawing time looking straight at it
  (5r: 11 ms, and 47 to 70 fps): the Fast filter reads the colour planes once
  again, now with the exact brightness curve. 5r's form read them at every
  tap; the note under 5n that this made no measurable difference was wrong
  (it compared a 2D session with a 3D one).
- Installer window lists SteamVR's settings one per line. It no longer says
  motion smoothing is off: the value it wrote (0) means "use the global
  setting". The line now says so and where to choose Off.
- `vrpreferences.json` in the package (Valve's documented way for an app to
  ask for its resolution, refresh rate and motion smoothing off). Not yet
  confirmed that SteamVR reads it for a non-Steam shortcut.

### 5r (2026-11-14)
- Capacitive touch is used only with Cursor Follow: Capacitive Touch. Off and
  Standard never use the sensors, also with Cursor Type: PC Cursor.
- A controller is no longer held in place or hidden just because no finger is
  on it (5n, 5o). Lying still, untouched, and reported somewhere else for
  12 seconds: then its model is hidden.
- Curved screen picture: the Fast filter uses the exact brightness curve
  again (the shortcut from 5n drew shadows up to four steps too dark), and
  the engine's debanding is on for the 3D scene (its 10-bit buffer gave dark
  tones only a dozen levels).
- Bending the wrist while holding a grab no longer pushes the screen, and the
  menu and keyboard with it, nearer or farther.
- A hidden menu or keyboard rides along with a grabbed screen like a visible
  one (it used to come back swung by the screen's tilt).
- High Refresh Rates is not offered on the Frame.
- Cursor Follow tooltip: Capacitive Touch on its own line, shorter wording.
- `[GRAB] released:` log line with the distances of screen, menu and keyboard.

### 5q (2026-11-14)
- Installer sets SteamVR's settings for Nightfall where none is set yet
  (resolution 3408 per eye, 72 Hz, motion smoothing off), keeps any you have
  chosen yourself, and lists them in its finished window.
- The finished window says where to find Nightfall in Steam (Non-Steam
  games) and what the PC needs (Sunshine, Apollo or Vibepollo; Meteor is
  optional).

### 5p (2026-11-14)
- Cursor Follow has three choices: Off, Standard, Capacitive Touch. It
  replaces the separate Sleep When Put Down switch.
- A set-down controller's model no longer flashes (5o compared its position
  with a value Nightfall had just overwritten).
- The address keypad types and deletes at the caret.

### 5o (2026-11-14)
- Edge Smoothing is off by default (about 5 ms of drawing time per frame).
- A set-down controller whose reported position drifts has its model hidden
  until it is picked up.
- The installer's finished window shows whether SteamVR's motion smoothing
  was switched off.

### 5n (2026-11-14)
- Every touch sensor counts as a hand again (A B X Y, Menu, bumper, D-pad,
  View, as well as trigger, grip and thumbstick).
- A controller nobody is touching has its position held until it is touched.
- Picture > Edge Smoothing: On / Off.
- The installer switches SteamVR's motion smoothing off for Nightfall. The
  app logs SteamVR's settings for it at start.
- Lighter Fast filter, second pass (no measurable gain).

### 5m (2026-11-14)
- A resting controller really stops pointing (upstream fault since 0.9).
- Sleep When Put Down only applies with PC Cursor or Cursor Follow.

### 5l (2026-11-14, not tested on its own)
- Picture > Curved Filter: Fast / Full. Fast reads the video far fewer times
  per pixel for a screen drawn in the scene.
- Face buttons work on a sleeping controller without waking its pointer.

### 5k (2026-11-14)
- Start Distance survives a restart (the screen was placed before the saved
  settings were loaded).
- Sleep When Put Down ignores the A and B sensors (reversed in 5n).
- `[FRAME-COST]` log line: drawing time per frame and what was on screen.

### 5j (2026-11-14)
- Advanced > Start Distance: how far away the screen starts, 1 to 6 m.
- Sleep When Put Down: a controller no finger is touching stops pointing.
- Custom Buttons Off means the Default layout, not stock Nightfall's.
- Voice typing opens the microphone in the background (it froze the picture
  for about half a second on every press).
- PT Fade no longer flashes when it leaves Off.
- No script error at quit.
- Meteor 0.9.0-sf2 source: Vulkan VDA download in the Windows tray; a script
  to measure NVIDIA's TensorRT builder files.

### 5i (2026-11-13)
- PT Fade for a flat Layer screen is a dark quad layer far behind it: free
  and smooth. A curved screen keeps the in-scene shell.
- Meteor is asked again at stream start if it doesn't answer the first time,
  with a notice if AI 3D is on.
- No on-headset depth capture on the Frame (it was running for nothing).

### 5h (2026-11-13)
- Muted is visible: red Stream tab and a Muted button beside Exit.
- Profiles > Default loads Nightfall's own buttons, game keys and gamepad
  layout.
- Naming a profile: the page fits; keys in columns.
- PT Fade tried per-frame noise in place of the fixed pattern (reverted in
  5i: shimmer).

### 5g (2026-11-13)
- Voice commands for every menu button ("bezel off", "fps 90", "next
  background"), profiles by name, flipped word order.
- Right click no longer drags (the PC cursor holds still while the grip is
  held and the pointer hasn't moved far).
- The Buttons tab always opens at its front page.
- Right stick click defaults to Ctrl (hold), so stick up/down zooms.

### 5f (2026-11-13)
- PT Fade back inside the 3D scene with a fine pixel pattern for the levels
  in between (the quad from 5d hid parts of the screen).
- Menu and keyboard no longer rise or shake while a grabbed screen is moved.
- Lowering the menu or keyboard no longer swoops it toward the face.
- Volume by voice in decibels; "volume normal", "mute", "unmute".

### 5e (2026-11-13)
- New grab: body movement (turning, walking) carries the grabbed thing 1:1,
  only the hand's own movement is multiplied. Spinning on the spot works.
- Distance limits apply to hand moves (nothing can pass through the head).
- Voice: "passthrough fade 50", "volume 80".

### 5d (2026-11-12)
- Turning with a grab held: second attempt (replaced in 5e).
- PT Fade as a quad layer to get every level (replaced in 5f).

### 5c (2026-11-12)
- Walking with a grab held no longer drifts.
- Sliders hold their value on release; defaults catch the pointer.
- PT Fade is a slider. Advanced > Icon Backdrop. Solid tooltip bar.

### 5b (2026-11-12)
- Walking while grabbing: first fix.
- Thumbstick moves a grabbed screen, menu or keyboard nearer or farther.
- PT Fade works on the Frame (in-scene shell).
- Volume slider in decibels; Separation 25 to 400%, Convergence 0 to 100%.

### 5a (2026-11-12)
- The port merged onto upstream 0.9.0 (18 files with conflicts). Depth map
  orientation follows upstream's shader fix. Buttons tab moved to tab 8.
  Build recipe in the tree (`steam-frame/README.md`, `build-frame.sh`).

## Meteor (PC helper)

### 0.9.0-sf2 (2026-11-14, source only, not built)
- Windows tray: Vulkan VDA downloads under GPU / model, a line for a failed
  download, a balloon when a model is installed.
- `tools/measure_tensorrt_builders.ps1`.

### 0.9.0-sf1 (2026-11-13)
- Upstream Meteor 0.9.0 plus the port's fixes: sound after PC silence
  (`quiet-flows`), stereo microphone (`mic-stereo`), an accepted microphone
  sender keeps its stream. Built on the PC with `tools/build_meteor_fix.ps1`,
  which swaps only the exe of an installed upstream 0.9.0.

### 0.1.2 to 0.1.4 (2026-11-08 to 2026-11-10, on upstream 0.1.1)
- 0.1.2: UDP flows stay open while the client is still sending (sound after
  long pauses).
- 0.1.3: microphone written as stereo.
- 0.1.4: video flows counted per client (microphone no longer cut after about
  29 s); an accepted microphone sender is kept.

## On upstream 0.8.1

### 4a to 4i (2026-11-10 to 2026-11-11)
- Recenter (button, at launch, on the system recenter); Head Lock Off / Level
  / Tilt; never starts locked.
- Launch places the screen where you look, also lying down; At Launch: In
  Front / Same Spot.
- Grab bar auto-hides; Gamepad lock shows only the gamepad icon, hold to
  unlock.
- Menu and keyboard follow the screen rigidly; default spots relative to the
  screen; tilt follows the wrist; grip and twist rolls the screen.
- Voice command library with optional "Nightfall" prefix, the list in
  Advanced Settings, F keys, near-miss matching, confirmation popups,
  everyday wording ("turn 3D on", "set glow to 50").
- Notices appear where you are looking.

### 3l to 3z (2026-11-08 to 2026-11-10)
- Sliders (Curve, Glow Strength, Glow Size); menu 1400 px wide, rows of five.
- Controller tracking guard: holds the last tracked position, pins a
  controller lying still, ignores jumps, hides SteamVR's model while lost.
- Either hand can grab; the hand that starts a grab keeps it; long press
  resets or recovers the menu and keyboard; Save As Default / Original
  Default for their spots.
- Voice typing: hold Y, whisper.cpp built from source, recorded in memory
  only; spoken helpers ("new line", "clear", "submit").
- Notices as a floating popup; installer notifications and summary.
- Microphone for voice chat through Meteor.
- Vibration toggle, hover vibration, Super latch, keyboard Mic key, Windows
  dictation action.

### 3d to 3k (2026-11-08)
- Curved screen drawn in the 3D scene, sampling the decoded video directly;
  Picture > Flat Screen: Layer / 3D Scene; ambient glow as a soft mesh.

### Builds 2 and early 3 (2026-11-08)
- Steam Frame controller profile (X, Y, D-pad, View). Buttons tab: custom
  buttons, profiles, Game Keys, Gamepad Layout, Reset Buttons.
- Game Controller mode (starts off, amber while on, works with ViGEmBus).
- Cursor Follow, Cursor Type PC Cursor, Pointer Ray, Cursor Off Screen; the
  3D click bias removed.
- Headset volume and mute on the Stream tab; Reconnect Audio.
- SteamVR controller models; wider screen hit area; options that can't work
  on the Frame hidden.

### Phase 1 (2026-11-07): the native SteamOS build
- Godot 4.7 Mobile renderer, Linux arm64, own installer and Steam shortcut.
- Video through the Frame's V4L2 decoder directly (FFmpeg's wrapper stalled).
- Audio: jitter buffer, loss concealment, plain stream name so SteamOS's 3D
  audio applies; the pause buzz traced to the host's audio mode.
- Depth View, Meteor depth, pairing feedback on the server screen.

### APK fix1 to fix14 (2026-11-07): the Quest APK on the Frame
- Projectionless mode off on the Frame, flat quad layers in place of
  cylinders, RGB passthrough for the Frame's decoder, composition path with
  Meteor 3D working (fix14). Superseded by the native build.
