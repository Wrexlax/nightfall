# Unofficial Steam Frame port of tB0nE's Nightfall (early release)

Your PC's screen as a big virtual screen in the Steam Frame, in 2D or 3D,
running as a native SteamOS app.

This is an **unofficial port** of tB0nE's
[Nightfall](https://github.com/tB0nE/nightfall), made by a Steam Frame
owner who wanted to use it on their headset. Nightfall is tB0nE's work:
the streaming, the virtual screen, AI 3D, Meteor and the menus all come
from the original, and this port only adapts them to the Frame and adds a
few things on top. The original
project is where Nightfall is developed, and it has an experimental Steam
Frame build of its own. This port is a separate effort alongside it, not a
replacement for it. It is free software under the same license, the GNU
General Public License, version 3. The original project's own README is
kept here as [README-original.md](README-original.md).

It is an **early release**: it is built on Nightfall 0.9, and it has been tested
on a single Steam Frame with a single Windows PC (an RTX 5090) so far. It
is used daily there and works well. On another setup something may behave
differently; if it does, please report it.

There are two parts:

- **Nightfall** on the headset (`NightfallFrame-….tar.gz`).
- **Nightfall Meteor** on the PC (`Nightfall-Meteor-…-SteamFrame-Setup-x64.exe`).
  Optional, but many of the features below need it.

## What you get

Much of this is Nightfall itself, which had already done the hard part:
the streaming, the virtual screens, AI 3D and Meteor. The rest was added
or adapted for the Frame.

- **Native on SteamOS.** A SteamOS app of its own, so it doesn't go through
  the Frame's Android support. Hardware video decoding, SteamVR's own
  controller models, and a display rate that follows the stream: 72, 90,
  120 or 144 Hz. (The original project now has an experimental native
  Frame build of its own; this port is separate from it.)
- **Any screen in 3D.** AI 3D turns a normal picture into stereo 3D. The
  depth is made on your PC by Meteor (sharper, and lighter on the headset),
  or on the headset itself with three models to choose from when there is
  no Meteor.
- **Stream Link.** With the Frame's wireless adapter in your PC, the picture,
  sound, controls, microphone and depth travel over your Wi-Fi and the
  adapter at the same time, and whichever copy arrives first is used. Choose
  Multi-Link, Adapter first or Wi-Fi only, in the headset or in Meteor's
  tray menu, without restarting anything.
- **Talk to it.** Hold a button and speak, and what you say is typed on
  your PC. It runs on the headset itself; nothing you say is sent anywhere
  or saved. Say a menu button's name instead ("bezel off", "head lock",
  "curve 40") and Nightfall does it: every button is a voice command, in 20
  languages.
- **A full-size keyboard.** Esc and all twelve F keys,
  Tab, Caps, Ctrl, Alt and the Windows key, plus a row of one-press
  shortcuts (Copy, Paste, Undo, Alt+Tab, Task Manager, Ctrl+Alt+Del and
  more). Shift, Ctrl and Alt work like a phone's: one press for the next
  key, two to lock. **Expand** it for a trackpad, arrow keys, a number pad,
  media keys (volume, mute, play) and Windows shortcuts (snap, task view,
  screenshot). Its **Mic key** starts voice typing: Nightfall's own on the
  headset, or Windows' dictation on the PC, whichever you set.
- **Looks after your eyes and your battery.** Eye-tracked foveation for
  large curved screens, curved or flat screens, passthrough with an
  adjustable fade, and starting settings chosen with the battery in mind
  (about 76 minutes at 90 Hz with Meteor's depth, worked out from the power
  it drew, not run down to empty).
- **Passthrough that keeps up with a color camera.** With a color camera
  add-on fitted (Arcturus Vision is the one it was built with), Nightfall
  notices when that camera is showing the room and drops to 90 fps by
  itself, which is what the headset can hold with it, then returns to your
  own FPS when it isn't (in the dark, or with Passthrough off). It warns
  you five seconds ahead so you can pause.
- **Feels right in the hand.** Grab the screen and walk with it, Head Lock
  (level or tilting with your head), and Recenter.
- **On the ceiling when you lie down.** The screen opens wherever you are
  looking, and Recenter brings it back there, straight up included: lie
  back, look up, recenter, and it is above you the right way up.
- **Controls that get out of the way.** The grab bar and its icons under
  the screen only show while you point near them, and are gone half a
  second after you point away, so nothing distracts from your game or film.
- **Your controllers as a gamepad, without accidents.** In Game Controller
  mode the two controllers act as one gamepad for the PC. The grab bar
  shrinks to a single gamepad icon so nothing gets pressed by mistake while
  you play, and leaving the mode takes a deliberate hold on that icon.
- **A cursor that knows when you're holding the controller.** With Cursor
  Follow on Capacitive Touch (Control tab), the PC's cursor follows your
  pointer only while your fingers are on the controller. Take them off, or
  set the controller down, and the cursor stays where it is and the pointer
  ray switches itself off. Touch it again and both are back.
- **Set up your way.** Map every controller button to what you want and
  save the sets as profiles. Put the menu and keyboard where you like them
  and make that the default.
- **Several screens.** Show more than one of your PC's monitors, or add
  virtual ones. This needs Meteor's built-in host.
- **Pairing you can't miss.** Meteor opens a window on the PC that shows
  the PIN and asks you to confirm it. One click.
- **Logs that are safe to share.** Logging is off until you turn it on, the log you
  share is cleaned of addresses and names, and so is Meteor's.
- **In your language.** Nightfall's menus come in 20 languages. What this
  port added to them, and its voice commands, are first drafts that native
  speakers have not checked yet.

## What you need

- A Steam Frame.
- A PC on the same home network running a streaming host: Sunshine, Apollo
  or Vibepollo. **Or just install Nightfall Meteor**, which brings its own
  host (Windows; this port's Meteor has only been built and run on
  Windows).
- For 3D made on the PC, media keys, Stream Link and the pairing window:
  Nightfall Meteor.
- For Stream Link: the Steam Frame's wireless adapter plugged into the PC.
- For the headset's microphone on the PC, and for Game Controller mode:
  two small free drivers on the PC, which Meteor's Setup does not install.
  See "Two extras on the PC" below.
- The stream uses H.264 or HEVC. This port's video decoder does not do AV1.

## Install on the headset

1. On the Frame, switch to the desktop, download `NightfallFrame-….tar.gz`
   and unpack it (right-click > Extract), for example in Downloads.
2. Open the unpacked `NightfallFrame` folder, **double-click `install.sh`**
   and choose **Launch** when asked. Steam has to be running.
3. Answer its question about the language you will speak and the speech
   models for voice typing (142 MB and 466 MB, or none), and let it
   download.
4. On its last page choose **Restart now**. Restarting once after an
   install avoids a SteamOS quirk where the volume buttons keep repeating.
5. In the headset, start **Nightfall (Steam Frame)** from your library
   (under Non-Steam).

To update, do the same with the newer archive. Your settings are kept.

The installer puts the app in `~/Games/NightfallFrame`, adds it to your
Steam library and sets SteamVR's video settings for it where you haven't
chosen your own. If double-clicking does nothing, open Konsole and type
`bash ~/Downloads/NightfallFrame/install.sh`.

## Install Meteor on the PC (optional, recommended)

1. Run `Nightfall-Meteor-…-SteamFrame-Setup-x64.exe`. It is not signed, so
   Windows shows "Windows protected your PC": choose **More info**, then
   **Run anyway**. To be sure the file is the one that was published,
   compare its SHA-256 with `SHA256SUMS.txt` beside the downloads (in
   PowerShell: `Get-FileHash` and the file's name).
2. Meteor starts with an icon near the clock. Right-click it for its menu.
   It runs its own streaming host; you don't need to install one.
3. If its menu says the firewall is blocking the headset, choose
   **Allow the headset through the firewall...**.

This is this port's own build of Meteor (its version ends in `-sf`). Run
only one Meteor at a time: if you also have the original Nightfall Meteor,
quit one before starting the other.

### Two extras on the PC

Neither comes with Meteor's Setup, and Nightfall works without them. Each
is needed for one thing:

- **The headset's microphone on the PC** (voice chat, or Windows' own
  voice typing with the keyboard's Mic key set to Windows): install
  **VB-CABLE** from <https://vb-audio.com/Cable/>, then restart Meteor.
  Meteor plays the headset's microphone into it. In the program that
  should hear you, choose **CABLE Output** as the microphone (for Windows'
  own voice typing, make it Windows' default microphone). This needs
  Meteor. Voice typing on the headset itself (hold Y) needs none of this.
- **Game Controller mode** (the two controllers as a gamepad for PC
  games): the streaming host makes a gamepad on the PC through a driver.
  Install **ViGEmBus**, version 1.17 or newer, from
  <https://github.com/nefarius/ViGEmBus/releases/latest>, then restart the
  PC. If you already use Sunshine or Apollo and gamepads work with them,
  you have it. ViGEmBus is no longer developed, but it is what these hosts
  fall back to and it works.

## Pair the headset with your PC

1. In Nightfall, choose **Select Server**. Try **Scan Network**, or enter
   your PC's address by hand.
   - The address is your PC's IPv4 address (Windows: Settings > Network &
     internet > your connection's properties).
   - Add the host's port if it isn't the usual 47989, like
     `192.168.1.20:49989`. Meteor's host uses 47989 unless another host
     already has it; then it takes 49989 (or 51989, 53989). To see which:
     Meteor's menu > Game streaming host > **Open host web page**, and
     subtract one from the port in the page's address (49990 means 49989).
2. Nightfall shows a four-digit PIN.
3. **With Meteor:** a window appears on the PC with the same PIN. Choose
   **Yes**. That's it.
   - No window? Right-click Meteor's icon and choose **Approve pairing**
     within a minute.
   - Or use Meteor's menu > Game streaming host > **Pair headset...** and
     type the PIN while the headset is still showing it.
4. **Without Meteor** (or if the above fails): open your host's web page,
   go to PIN (Sunshine, Apollo) or Clients (Vibepollo) and type the PIN.
   For Meteor's host, the login is in Meteor's menu > Game streaming host >
   **Open host login (host.toml)**.

If no PIN appears, or the PC never asks: the host may still know this
headset from an earlier pairing. Remove the headset on the host's web page
(Clients), remove the PC in Nightfall's server list (press Remove twice),
then pair again.

## First steps

- The **grab bar** under the screen moves it; the corners resize it.
- The tabs along the menu hold the everyday options; the **gear** opens
  Advanced Settings.
- **AI 3D** is on by default. Its tab chooses who makes the depth.
- Lost the menu or the keyboard? **Hold its controller button** (Menu, and
  X for the keyboard, unless you changed them) for about three seconds and
  it appears right in front of your eyes. Holding its icon on the grab bar
  does the same, and a shorter hold there (about a second) puts it back in
  its usual spot.
- **Zoom:** hold the right stick's click and push the stick up or down. It
  sends Ctrl+scroll, which zooms in most PC programs (that is the default
  button mapping; you can change it).
- **Stream Link** is on the Stream tab.
- **Head Lock** and **Passthrough** are on the Display tab.
- Hold **Y** and speak (the button can be changed in the Buttons tab).
  What you say is **typed** on the PC, like dictation. If it is one of
  Nightfall's commands ("recenter", "bezel off"), the command runs instead.
  Advanced Settings > Voice & Microphone has the rest:
  - **Voice Commands** lists every command.
  - **Require 'Nightfall'**: turn it on and a command only runs when you
    say "Nightfall" first ("Nightfall bezel off"). Everything else is
    typed. Use it if commands go off by accident while you dictate.
  - **Commands** off: nothing is ever taken as a command; it is all typed.
  - **Keyboard Mic Key**: what the Mic key on Nightfall's keyboard does.
    *Nightfall*: voice typing on the headset (tap to start and stop, or
    hold while talking). *Windows*: opens Windows' own dictation (Win+H).

### The buttons as they come

| Right controller | What it does |
| --- | --- |
| Trigger | Left click |
| Grip | Right click |
| Bumper | Right click |
| A | Double click |
| B | Escape |
| X | Show Keyboard |
| Y | Voice Typing (hold it and speak) |
| Menu | Nightfall Menu |
| Stick, up and down | Scroll |
| Stick click | Ctrl while you hold it (with the stick: zoom) |

| Left controller | What it does |
| --- | --- |
| Trigger | Left click |
| Grip | Right click |
| Bumper | Right click |
| D-pad | Arrow keys |
| View | Nightfall Menu |
| Stick click | Ctrl while you hold it |

On the grab bar under the screen, the trigger and grip do more:

- **Trigger on the grab bar, and drag:** moves the screen. It tilts with
  your wrist as you go.
- **Add the grip while dragging,** and twist your wrist: rolls the screen
  (one corner up, the other down).
- **Push the stick while dragging:** up sends it farther away, down brings
  it closer.
- **Trigger on a corner, and drag:** resizes it.

The menu and the keyboard move the same way.

The triggers and grips always click, so you can't lock yourself out of
pointing. Everything else can be changed in the Buttons tab, and Profiles >
Default brings this layout back. In Game Controller mode the controllers
are a gamepad for the PC instead.

## Make it yours

- **Buttons.** The Buttons tab lets you choose what each controller button
  does (a key, a mouse button, Voice Typing, Depth View, Recenter and so
  on), save sets of them as **profiles** and switch between them, set the
  keys used in games, and choose the gamepad layout. Profiles > Default
  brings back Nightfall's own. A profile can also be loaded by voice, by
  its name.
- **Where things sit.** Drag the menu and the keyboard to where you like
  them, then Advanced Settings > Menu & Keyboard Position > **Save As
  Default**: they start there from then on. **Original Default** goes back
  to Nightfall's spots. **Menu & Keyboard Follow** makes them move along
  when you move the screen.
- **Where the screen starts.** Advanced Settings > Screen Position: how far
  away it starts (**Start Distance**), how big (**Screen Size**), and
  whether it appears in front of you or where you left it (**At Launch**).
- **With a color camera add-on.** Advanced Settings > General > **Camera
  FPS Limit**: Auto (90 fps only while the color camera is showing the
  room), On (whenever the add-on is fitted and Passthrough is on) or Off.
  The option only appears when an add-on is fitted. It also helps to
  lower the camera's own resolution: in the Arcturus Vision Camera app,
  Passthrough settings > **Passthrough resolution** > 2.5K (from 5K),
  which is what this was tested with. That app's FPS choices have not been
  tried with Nightfall.
- **Everything back to how it came:** Advanced Settings > General >
  **Reset Settings** (your paired PCs, buttons and language are kept).

## What frame rate to expect

Every Steam Frame is the same headset, so what the headset can hold should
be the same for you. What your PC and your Wi-Fi can send is the part that
differs: these were measured with one PC (an RTX 5090).

| Stream | 3D made by | What it held |
| --- | --- | --- |
| Up to 1440p at 90 fps (90 is what it starts with) | the headset or Meteor | 90 |
| 1080p at 144 fps | the headset | 144 most of the time; 125 in the slowest second |
| 1440p at 144 fps | the headset | 67 to 107: too much, and SteamVR halves the rate |
| Any, with a color camera add-on showing the room | either | 90 (Nightfall switches to it by itself) |

- Nightfall starts at **90 fps**. It is the setting that held everywhere it
  was tried, and it is easier on the battery than 144 (about 76 minutes
  with Meteor's depth, worked out from the power it drew). **FPS** is on
  the Stream tab.
- For **144**, use a 1080p stream. Whether 1440p holds 144 with Meteor
  making the 3D has not been measured with this build.
- **With a color camera add-on and Camera FPS Limit off:** at the camera's
  5K setting, 144 hitches (about 104 fps, with dips to 78, in our test).
  With the camera at 2.5K it held about 140, with dips to about 120. How to
  set that is under "Make it yours" above.
- **Stream Link** doesn't change what the headset can hold; it changes how
  many frames go missing on the way to it. Measured at 144 fps:

  | Stream Link | Video frames lost |
  | --- | --- |
  | Wi-Fi only | about 24 a minute on strong Wi-Fi; 110 to 130 in earlier sessions |
  | Multi-Link | none in 10 minutes |
  | Adapter first | none while the adapter was in reach |

  On Multi-Link the adapter's copy arrived first for about 95% of packets,
  and every packet Wi-Fi lost came over the adapter instead.
- 72 and 120 fps, and 4K streams, have not been measured with this build.
- If the picture turns choppy all at once, SteamVR has probably halved the
  rate because the headset fell behind: lower FPS or Resolution one step.

## Smoothed along the way

Using Nightfall every day on a new headset turned up a few rough spots,
as a new device always does. This is how those now behave in this port.
Many aren't specific to the Frame, so the details are written up in
`steam-frame/UPSTREAM-FIXES.md` in the source, in case any of it is useful
to the original project. The original has since taken care of at least
the sound one itself, in its 0.9.1.

**In Meteor (this port's build):**

- **Sound** carries on after the PC has been silent for a while.
- **The headset microphone** reaches Windows on both channels and keeps
  going through a long recording.
- **Pairing.** Meteor asks in a window on the PC, and approving still works
  after another copy of Meteor has been run on the same PC.
- **TensorRT for every recent NVIDIA card.** On Windows the faster depth
  engine can be downloaded for every generation NVIDIA makes it for; so
  far it has run on RTX 30 and RTX 50.
- **"Host depth is OFF" is easy to see.** When that item is unticked in
  Meteor's menu, the menu says so on its second line and Nightfall tells
  you when the stream starts.
- **Media keys** (mute, volume, play/pause) reach Windows as media keys.
- **Meteor's log** is written without your addresses or your Windows user
  name.

**On the headset:**

- **Pausing a video** on the PC leaves the headset quiet.
- **Meteor's depth** starts within seconds when Host depth is switched on
  in the middle of a stream.
- **The list of PCs.** A saved PC shows its name, can be renamed, and can
  be removed by itself. Two hosts on one PC keep their own settings.
- **The address field.** Point into the middle of an address and the
  keypad types there; highlight part of it and the next key replaces it.
- **Connect** can be pressed while Nightfall is already connecting without
  upsetting the connection.
- **A screen** can't be resized so far that its corners are out of reach.

## Known limits

- **One tester.** One headset, one PC, one home network.
- **Stream Link is for home networks.** Meteor only sends its extra copy of
  the stream to home-network addresses, but two checks are still to come:
  a request to open a second link could in theory be replayed by someone
  already on your network who recorded it, and the headset does not yet
  make Meteor prove its identity. Don't use Stream Link on a network you
  share with people you don't trust.
- **1440p at 144 Hz with 3D made on the headset** is more than the headset
  can hold; SteamVR halves the frame rate. Use 1080p or 90 Hz. With
  Meteor's depth it may hold; that has not been measured with this build.
- **Mesh Wi-Fi.** Where your Wi-Fi hands over between mesh units the
  picture can stop for one to three seconds, and now and then for much
  longer. Stream Link helps while the adapter is in reach.
- **Steam can crash** when the adapter's link drops (seen once). Steam
  restarts itself and shows a menu whose Resume and Exit do nothing;
  Nightfall is still running underneath. Exit from Nightfall's own menu and
  start it again.
- **AMD and Intel graphics cards** should work with Meteor's Vulkan depth
  models; nobody has tried. NVIDIA's faster TensorRT model has run on RTX 30
  and RTX 50 cards.
- **Languages** other than English are first drafts, and voice commands in
  them have barely been heard by a speech model. Corrections are welcome.
- **Two different Meteors.** This port comes with its own build of
  Nightfall Meteor (its version ends in `-sf`, like 0.9.0-sf19), and that
  is the one everything in this README describes. The *original* Nightfall
  Meteor from tB0nE (0.9.1 or later) also works with this headset build:
  its Multi-Link carries picture and sound over both links. A few things
  described here need this port's Meteor: controls, microphone and depth
  over both links, Adapter first, the media keys, the pairing window and
  the Stream Link choice in Meteor's menu. Run only one of the two at a
  time.
- **Beside the original's Steam Frame build.** This port keeps its settings
  in a folder of its own, so both can be installed on one headset without
  one starting with the other's settings.
- **Not in this build:** the in-headset browser, PCVR, the PyroWave codec.

## Planned

- **Profiles that follow the game:** the button profile switching by
  itself with the game you start on the PC.
- The two remaining Stream Link safety checks.
- A menu and keyboard that keep their place the way SteamOS's own do when
  the screen is pushed far away.
- Translations and voice commands checked by people who speak the
  languages.

## Logs and reporting a problem

Logging is off on a new install. To capture a problem: Advanced Settings >
About > **Logging** > On, exit Nightfall, start it again, repeat the
problem. Then open an issue at
<https://github.com/Wrexlax/nightfall/issues>, say what happened, and
attach `~/Downloads/Nightfall-logs/nightfall-latest.log`. That copy is
cleaned for sharing (addresses, names, ids and keys are masked).

Meteor's log (its menu > **Open log**) is cleaned as it is written. Logs
from an older Meteor, and the streaming host's own log, are not: look
before you share those.

For trouble that looks like SteamOS's (Steam's menu appearing, sound, the
display), run `bash ~/Games/NightfallFrame/collect-steamos-logs.sh` right
afterwards and attach the archive it makes.

## Uninstall

On the headset: double-click `uninstall.sh` in `~/Games/NightfallFrame`.
It asks first, and asks separately about the speech models and about your settings.
**Saying yes to settings also removes your button mappings and PC
pairings.** `WHERE-THINGS-ARE.txt` in the same folder lists every place
Nightfall keeps files.

On the PC: Windows Settings > Apps > Nightfall Meteor > Uninstall.

## Credits and source

This port is other people's work put together and adapted. With thanks to:

- **[Nightfall](https://github.com/tB0nE/nightfall) and Nightfall Meteor**
  by tB0nE. This port is Nightfall: nearly everything in it is tB0nE's
  design and code, published under a license that lets others build on it.
  The port began with tB0nE's
  [remark](https://reddit.com/r/virtualreality/s/5bL9sd3tce) that someone
  with a Steam Frame could take the source and add support for it. Thank
  you for Nightfall, and for the nudge.
- **[Moonlight XR for Frame](https://github.com/simplysanatori/moonlight-xr-steam-frame)**:
  the hardware video decoder and the small script the installer uses to
  add Nightfall to your Steam library are that project's code, and this
  port's launcher script and its recipe for building LiteRT started from
  that project's. Its source also showed how an app can change SteamVR's
  display rate for itself, with SteamVR's own tool, which is how the FPS
  button does it here.
- **[Moonlight XR](https://github.com/Gilleece/moonlight-android-xr)** by
  Sean Gilleece: the two LiteRT depth models on the headset are its
  conversions of ZipDepth, unchanged.
- **[ZipDepth](https://github.com/fabiotosi92/ZipDepth)**: the depth model
  that runs on the headset, and the one Nightfall's own EdgePad models are
  tuned from.
- **Godot Engine**, and **David Snopek's fix for foveated rendering on the
  Steam Frame** (Godot pull request 124811), which this port's engine
  build carries ahead of a Godot release.
- **whisper.cpp** and OpenAI's Whisper speech models: voice typing.
- **ncnn** and **LiteRT**: what the headset's depth models run on.
- moonlight-common-c, FFmpeg, Opus and the others listed with their
  licences in the app, under Advanced Settings > About > Licences.

The source code of both parts is at <https://github.com/Wrexlax/nightfall>,
published with each release as the GPL requires. `steam-frame/CHANGELOG.md`
in it lists every build,
`steam-frame/UPSTREAM-FIXES.md` lists the fixes that may be useful to the
original project, and `steam-frame/engine/README.md` says how the
engine build differs from Godot's own.

The Meteor Setup includes the original's own streaming host (tB0nE's build
of Vibepollo), unchanged from the original Meteor 0.9.0. Its source is at
<https://github.com/tB0nE/Vibepollo>.

The port's code, its tests and its translations were written with an AI
assistant (Claude, by Anthropic), directed and tested on the headset by a
person.

This port is not affiliated with or endorsed by Valve.
Steam, SteamVR and Steam Frame are trademarks of Valve Corporation.
