# Unofficial Steam Frame port of tB0nE's Nightfall (early release)

Your PC's screen as a big virtual screen in the Steam Frame, in 2D or 3D,
running as a native SteamOS app.

> Already know Nightfall? Skip to [what this port adds](#what-this-port-adds),
> [the numbers](#the-numbers) or [install](#install-on-the-headset).

This is an **unofficial port** of tB0nE's
[Nightfall](https://github.com/tB0nE/nightfall), made by a Steam Frame
owner who wanted to use it on their headset. Nightfall is tB0nE's work,
and this port only adapts it to the Frame and adds a few things on top.
The original project is where Nightfall is developed, and it has an
experimental Steam Frame build of its own. This port is a separate effort
alongside it, not a replacement for it. It is free software under the same
license, the GNU General Public License, version 3. The original project's
own README is kept here as [README-original.md](README-original.md).

It is an **early release**: it is built on Nightfall 0.9, and it has been
tested on a single Steam Frame with a single Windows PC (an RTX 5090) so
far. It is used daily there and works well. On another setup something may
behave differently; if it does, please report it.

## What is Nightfall?

Nightfall, by tB0nE, puts your PC's desktop and games on big screens that
float in your headset. You place them anywhere, curve them, resize them,
and see your real room around them with passthrough. It can also turn an
ordinary flat game or film into stereoscopic 3D as you watch.

If you know Moonlight XR, it is the same family of app: your PC does the
work, the headset shows it, and both can make that 3D on the headset
itself. What sets Nightfall apart is Meteor.

<details>
<summary><b>How AI 3D works, briefly</b></summary>

A neural network that has learned from a great many images looks at each
frame and estimates, for every part of the picture, how near or far it is.
That gives a depth map. Nightfall then shifts the picture slightly
differently for each eye according to that depth, and your brain reads the
result as 3D. The depth is a best guess, not a measurement, which is why
it is impressive most of the time and now and then odd around fine edges.
More on the general idea:
[2D to 3D conversion](https://en.wikipedia.org/wiki/2D_to_3D_conversion)
on Wikipedia.

</details>

### Meteor

Nightfall Meteor is tB0nE's optional helper for the PC. It isn't required
to use Nightfall, but in my opinion it is the beating heart of Nightfall
and what makes the project so good.

It sits between the headset and the streaming host, which lets the host,
Windows and the headset talk to each other in ways they otherwise can't.
Its most useful feature is making the 3D depth on the PC's graphics card
and sending it to the headset alongside the picture:

- **Depth that keeps up.** In this port's tests Meteor delivered 40 to 65
  depth maps a second, where the headset's own models run at about 20.
- **Bigger models on cards that can run them.** On supported graphics
  cards Meteor can run Video Depth Anything, a larger model that follows
  motion over time, accelerated with NVIDIA's TensorRT.
- **A cooler, longer-lasting headset**, because it isn't doing that work
  itself: a few degrees cooler and less power drawn in this port's tests.

Meteor also makes the headset's microphone a PC input, for voice chat,
recording or Windows' voice typing (on Windows this needs VB-CABLE, see
[Two extras on the PC](#two-extras-on-the-pc)), and it brings a streaming
host of its own, so there is nothing else to install.

### Already in Nightfall

All of this is tB0nE's work, and it works in this port:

- **AI 3D**, using Nightfall's own EdgePad models, which tB0nE fine-tuned
  from ZipDepth.
- **Meteor** making the 3D on your PC, and the headset's microphone as a
  PC input.
- **Screens you grab, curve, resize and place anywhere**, with a bezel and
  an ambient glow.
- **Several screens**: your PC's monitors plus virtual ones (with Meteor's
  built-in host).
- **Passthrough with an adjustable fade**, so your room is as present as
  you want it.
- **A full-size keyboard** with a trackpad: Esc, all twelve F keys, and a
  row of one-press shortcuts such as Alt+Tab and Ctrl+Alt+Del.
- **Side-by-side 3D content**, gamepad layouts, and streams from 720p to
  4K, from Sunshine, Apollo, Vibepollo and other compatible hosts.
- **Menus in 21 languages.**

I can't recommend tB0nE's Nightfall and Meteor enough. It was the one app
that kept me going back to my Quest, before I started on this port and
before tB0nE's own Frame preview was announced. The interface, the
full keyboard and, to my eyes, the most convincing 3D I had seen from a
desktop streaming app are why I began.

The original does more on Quest. Not in this port: its built-in browser
and the PyroWave codec. Not tried in this port: hand tracking, HDR, USB
Link and PC VR games through Meteor.

## What this port adds

- **A native SteamOS app for the Frame**, with hardware video decoding,
  SteamVR's own controller models, and a display rate that follows the
  stream: 72, 90, 120 or 144 Hz.
- **3D made on the Frame itself.** The original makes 3D on the Quest; its
  Frame preview relies on Meteor for now. This port can make it on the
  Frame when there is no Meteor, with three models. Two are Moonlight XR's
  and run on the headset's CPU. The third is tB0nE's own EdgePad, which
  runs on the headset's GPU and takes the depth work off the CPU.
- **Stream Link.** The original's newest preview also sends the picture
  and sound over Wi-Fi and the Frame's wireless adapter together; the two
  were built separately. This port's version carries the controls,
  microphone and depth on both links as well, and has a choice of
  Multi-Link, Adapter first or Wi-Fi only, in the headset or in Meteor's
  menu.
- **Voice typing and voice commands.** Hold a button and speak, and what
  you say is typed on your PC. Say a menu button's name ("depth view",
  "head lock", "curve 40") and Nightfall does it. Say a PC shortcut
  ("show desktop", "switch window", "copy", "screenshot") and Nightfall
  presses those keys on the PC for you. It runs on the headset; nothing
  you say is sent anywhere or saved.
- **More on the keyboard.** Tabs that swap the original's trackpad for
  arrows, a number pad, media keys or Windows shortcuts; Shift, Ctrl and
  Alt that work like a phone's (one press for the next key, two to lock);
  and a Mic key that starts voice typing, either Windows' own or this
  port's on the headset.
- **Grab the menu or the keyboard anywhere.** Any spot on them that isn't
  a button moves them.
- **Head Lock, with Level and Tilt.** The screen can follow your head,
  staying level or tilting with it. On Quest, recentering and lying down
  are taken care of by the headset's own system. On the Frame this port
  does that part itself: Recenter puts the screen where you are looking,
  including above you when you lie back.
- **Controls that get out of the way.** The grab bar and its icons only
  show while you point near them.
- **A gamepad lock.** In Game Controller mode the grab bar shrinks to a
  single icon so nothing gets pressed by mistake, and leaving the mode
  takes a deliberate hold on it.
- **A cursor that knows when you're holding the controller.** With Cursor
  Follow on Capacitive Touch, the PC's cursor follows your pointer only
  while your fingers are on the controller. Set a controller down and the
  cursor stays where it was, and that controller's pointer ray switches
  off by itself.
- **Your own button layouts.** Choose what each controller button does on
  the desktop, make your own gamepad or keyboard-and-mouse layouts for
  games, and save them as profiles to switch between in the menu or by
  saying the profile's name. Place the menu and keyboard where you like
  them and make that the default.
- **Color camera handling.** Nightfall can tell when a color camera add-on
  is showing the room (Arcturus Vision is the one on the headset this port
  was built with). When color passthrough comes on, Nightfall drops to
  90 fps by itself, which is what the headset can hold with 5K
  passthrough. When it goes off, or the headset switches over to its own
  cameras, Nightfall returns to a higher FPS if you have set one. It warns
  you five seconds ahead, because the stream reloads briefly.
- **Eye-tracked foveation** for large curved screens. It uses the Steam
  Frame's own eye tracking and SteamVR's foveated rendering, so what you
  look at stays sharp while the edges of your view cost less to draw.
  Where you look is never logged.
- **A pairing request that's hard to miss.** The original's Meteor tells
  you about a pairing request with a Windows notification. This port's
  Meteor also opens a window in front of everything with the PIN.
- **Saved PCs by name** on the connection screen, each with Rename and
  Remove.
- **TensorRT for more of the NVIDIA family.** This port adds checksums so
  that Meteor can download the faster TensorRT engine for more NVIDIA
  generations, RTX 20 to RTX 50. Tried so far on RTX 30 and RTX 50.
- **Logs.** In this port logging is off until you turn it on, and the copy
  of the log you share has addresses and names masked, on the headset and
  in this port's Meteor.
- **Starting settings chosen with the battery in mind.**
- **Voice commands and this port's own menu text in 20 languages**, as
  first drafts that native speakers have not checked yet.

See [the numbers](#the-numbers) for what was measured.

There are two parts to install:

- **Nightfall** on the headset (`NightfallFrame-….tar.gz`).
- **Nightfall Meteor** on the PC (`Nightfall-Meteor-…-SteamFrame-Setup-x64.exe`).
  Optional, but many of the features above need it.

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
   from the [releases page](https://github.com/Wrexlax/nightfall/releases)
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

1. Download `Nightfall-Meteor-…-SteamFrame-Setup-x64.exe` from the
   [releases page](https://github.com/Wrexlax/nightfall/releases) and run
   it. It is not signed, so
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
  Advanced Settings. The menu and keyboard can also be moved by grabbing
  any spot on them that isn't a button.
- **AI 3D** is on by default. Its tab chooses who makes the depth.
- Lost the menu or the keyboard? **Hold its controller button** (Menu, and
  X for the keyboard, unless you changed them) for about three seconds and
  it appears right in front of your eyes. Holding its icon on the grab bar
  does the same, and a shorter hold there (about a second) puts it back in
  its usual spot.
- **Zoom:** hold the right stick's click and push the stick up or down. It
  sends Ctrl+scroll, which zooms in most PC programs (that is the default
  button mapping; you can change it).
- **Stream Link** is on the Stream tab: Multi-Link, Adapter first or Wi-Fi
  only.
- **Head Lock** and **Passthrough** are on the Display tab.
- Hold **Y** and speak (the button can be changed in the Buttons tab).
  What you say is **typed** on the PC, like dictation. If it is one of
  Nightfall's commands ("recenter", "bezel off"), the command runs instead.
  Advanced Settings > Voice & Microphone has the rest:
  - **Voice Commands** lists every command.
  - **Require 'Nightfall'**: turn it on and a voice command only runs when you
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

## The numbers

What was measured, and how. Everything here comes from this port's own
test sessions on one headset and one PC.

### Frame rate

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
  was tried, and it is easier on the battery than 144 (with Meteor's
  depth, about 76 minutes at 90 against about 60 at 144, worked out from
  the power it drew). **FPS** is on
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
- **Pairing** still works after another copy of Meteor has been run on
  the same PC.
- **TensorRT on more NVIDIA cards.** Meteor's faster TensorRT depth engine
  is tB0nE's. This port only added checksums so that its download also
  works for more NVIDIA generations, RTX 20 to RTX 50. So far it has run
  on RTX 30 and RTX 50.
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
- **Stream Link is made for a home network you trust.** This port's
  Meteor only sends its second copy of the stream to addresses on your own
  network, and only in answer to a request that carries that stream's own
  secret. Two further protections are planned for this port's Stream Link
  (see Planned). They would only matter if someone already on your network
  were deliberately trying to interfere. On a network you share with
  strangers, set Stream Link to Wi-Fi only.
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
  models; nobody has tried that on this port. NVIDIA's faster TensorRT
  engine has run on RTX 30 and RTX 50 cards.
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
- **Not in this build:** the in-headset browser and the PyroWave codec.
  **Not tried in it:** PC VR games through Meteor, hand tracking, HDR and
  USB Link.

## Planned

- **Profiles that follow the game:** the button profile switching by
  itself with the game you start on the PC.
- Two more protections for this port's Stream Link: making a second-link
  request impossible to reuse, and having Meteor prove its identity to
  the headset.
- A menu and keyboard that keep their place the way SteamOS's own do when
  the screen is pushed far away. This port has an option for the menu and
  keyboard to follow the screen, but it could use some work.
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
afterwards and attach the archive it makes. The script cleans its copies
the same way (addresses, names, Steam account and device ids). SteamOS's
own logs are large and varied, so it is still worth a look through the
archive before you share it.

## Uninstall

On the headset: double-click `uninstall.sh` in `~/Games/NightfallFrame`.
It asks first, and asks separately about the speech models and about
your settings.
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
