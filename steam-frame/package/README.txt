Nightfall for Steam Frame (preview)

An unofficial port of Nightfall (github.com/tB0nE/nightfall) to the Steam
Frame: your PC's screen as a big virtual screen, in 2D or 3D. Its author is
not involved in this port. Free software, GNU GPL version 3.

In this folder:
- install.sh     double-click this to install or update (step 2 below)
- uninstall.sh   removes Nightfall again; it asks first
- README.txt     this file
- files          everything else; nothing in it needs opening

Install:
1. Unpack this archive (e.g. in Downloads).
2. Double-click install.sh in this folder, with Steam running, and choose
   Launch when asked. Answer its question about speech models, let it
   download, and on its last page choose Restart now (restarting once after
   an install avoids SteamOS repeating the volume buttons). It copies the
   app to ~/Games/NightfallFrame and adds "Nightfall (Steam Frame)" to your
   Steam library. If double-clicking does nothing, type this in Konsole:
       bash ~/Downloads/NightfallFrame/install.sh
3. Launch "Nightfall (Steam Frame)" from the library in the headset.

On the PC you need a streaming host (Sunshine, Apollo or Vibepollo), or
Nightfall Meteor, which brings its own. Meteor also makes the 3D depth on
the PC, presses media keys, and carries the stream over the Frame's wireless
adapter and Wi-Fi together (Stream Link).

Pairing with your PC:
1. In Nightfall: Select Server, then Scan Network, or enter the PC's
   address. Add the host's port when it isn't 47989 (192.168.1.20:49989).
   Meteor's host uses 47989 unless another host has it; then 49989. To see
   which: Meteor's menu > Game streaming host > Open host web page; the port
   to enter is one lower than the page's.
2. Nightfall shows a four-digit PIN and says what to do next.
3. With Meteor: a window on the PC asks to pair, with the same PIN. Choose
   Yes. No window? Right-click Meteor's icon by the clock > Approve pairing
   (within a minute), or Game streaming host > Pair headset... and type the
   PIN.
4. Without Meteor: open the host's web page, find PIN (Sunshine, Apollo) or
   Clients (Vibepollo), and type the PIN.
If no PIN appears or the PC never asks, the host may still know this headset:
remove it on the host's Clients page and remove the PC in Nightfall's server
list, then pair again.

What the installer downloads (voice typing):
Voice typing works on the headset itself and needs a speech model. The
installer asks which you want: both, Base only, or none (no voice typing).
It first looks at what is already on the headset and says so, downloads only
what is missing, from whisper.cpp's model page on huggingface.co, shows how
far the download is, and checks each file before using it:
- ggml-base.en.bin, 142 MB (Speech Model: Base, quick)
- ggml-small.en.bin, 466 MB (Speech Model: Small, hears more correctly)
Voice typing and voice commands follow the language of Nightfall's menu
(Advanced Settings > Language). For another language than English the
installer fetches the multilingual models instead, the same sizes
(ggml-base.bin, ggml-small.bin): it asks which you want. The commands in
other languages are first drafts; Advanced Settings > Voice Commands lists
them in your language. To add the models for another language later (or
the English ones), run install.sh again and press "Speech models" in its
last window: it asks again, and removes nothing that is installed.
They are kept in ~/.local/share/nightfall/whisper/ (about 610 MB together),
outside the app's folder, so reinstalling or updating doesn't download them
again. The larger one is skipped when less than 1 GB of space is free; voice
typing then uses Base. To remove them, delete that folder; voice typing is
then off until the installer is run again. Nothing you say is sent anywhere
or saved: it is turned into text on the headset.

AI 3D (a normal picture turned into 3D):
With Nightfall Meteor running on the PC, the PC makes the depth, which is the
sharper and lighter way. Without Meteor the headset makes it itself: AI 3D
tab > Quality chooses between Headset: GPU (the default), Headset: Detail and
Headset: Light. Light uses the least of the headset; try it if the picture
stutters or the headset runs warm. At 1440p and 144 Hz the headset can't keep
up with making the depth as well: use 1080p, or 90 Hz, or Meteor.

Good to know:
- Stream Link is for your home network. Don't use it on a network you share
  with people you don't trust: two of its safety checks are still to come.
- Where mesh Wi-Fi hands over between units the picture can stop for a
  second or three.
- If Steam's own menu comes up over Nightfall and its Resume does nothing
  (Steam itself crashed and restarted; seen once), exit from Nightfall's
  menu and start it again.
- Other languages than English are first drafts.
- This port keeps its settings in a folder of its own, so the original
  Nightfall's Steam Frame build can be installed beside it. (Builds before
  8u shared a folder with it. If Nightfall ever starts with settings that
  aren't yours: Advanced Settings > General > Reset Settings, twice.)

Uninstall:
Double-click uninstall.sh in ~/Games/NightfallFrame (or run it in Konsole:
bash ~/Games/NightfallFrame/uninstall.sh). It asks first, and asks
separately whether to keep the speech models and your settings in case you
install again. Removing the settings also removes your button mappings and
PC pairings. WHERE-THINGS-ARE.txt lists every place Nightfall keeps files.

A very large curved screen (it fills most of your view) with PT Fade and
Ambient glow both on may run a little under 72 fps at the top resolution.
Any one of these brings it back to a steady 72:
- lower Nightfall's Resolution Per Eye in SteamVR's per-application video
  settings from 3408 to about 3000 (a flat screen, the menu and the keyboard
  are drawn separately and should not be affected), or
- set PT Fade to 0%, or
- set Ambient to Off.
A flat screen is not affected.

Logging is off on a new install. To get a log of a problem: in Nightfall,
Advanced Settings > About > Logging > On, close Nightfall, start it again and repeat
the problem. If Nightfall doesn't get as far as its menu, make an empty file
named  logging-on  in ~/Games/NightfallFrame/ and start it again (delete the
file to go back to the menu's choice).

Source code, newer builds and where to report a problem:
https://github.com/Wrexlax/nightfall (problems: its Issues page). Please
don't take problems with this port to the original Nightfall's author.

Logs to send with a report:
- ~/Downloads/Nightfall-logs/nightfall-latest.log (the current or last run)
  This copy is cleaned for sharing: network addresses, device and pairing
  ids, keys and names are masked (192.168.1.50 reads x.x.x.50). It is the
  one to attach or post.
The logs below are the untouched originals. They are for your own use;
send one only to someone you'd tell your home network's addresses to:
- ~/Games/NightfallFrame/logs/ (one log per launch, newest last)
- ~/.local/share/NightfallFrame/logs/ (newest file), if present
- ~/Games/nightfall-install.log (if the installer had trouble)
