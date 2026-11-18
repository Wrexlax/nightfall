class_name FrameDisplayRate
extends RefCounted

## Steam Frame: the display's refresh rate for Nightfall.
##
## SteamVR runs each app at the one rate its per-app setting names
## (preferredRefreshRate) and offers the app only that rate, so asking through
## OpenXR can't change it: every log reads "Runtime rates=[144.0]". Moonlight
## XR for Frame found the same and sets the per-app setting through SteamVR's
## own tool (its launcher/src/mlxrhandoff.cpp, GPLv3); this does likewise.
## The display follows within a second while the app runs (7a log, 15:08: the
## rate was changed in SteamVR's settings and the frame period went from 6.94
## to 11.11 ms with Nightfall still up).

const VRCMD := "/opt/steamvr/bin/linuxarm64/vrcmd"
## The rates SteamVR's per-app setting takes on the Frame, as named in
## Moonlight XR's notes. (SteamVR's own menu shows more steps between them.)
const RATES: Array = [72, 90, 120, 144]
## How long the display may take to follow before the try counts as failed.
const WAIT_SEC := 4.0

## The display rate for a wanted one: the lowest offered that is not below
## it, else the highest.
static func rate_for(wanted_hz: float) -> int:
	for rate in RATES:
		if float(rate) >= wanted_hz - 0.6:
			return rate
	return RATES[RATES.size() - 1]

## The command that sets the rate, after "env". The launcher clears the
## library path already; the tool is SteamVR's own and must not inherit one.
static func arguments(app_id: String, hz: int) -> PackedStringArray:
	return PackedStringArray(["-u", "LD_LIBRARY_PATH", "-u", "LD_PRELOAD", "timeout", "10", VRCMD,
		"--set-settings-int", "steam.app.%s.preferredRefreshRate" % app_id, str(hz)])

## Asks SteamVR for the rate. "" when the request went out, else why not.
## Whether it took shows in the rate the runtime then reports.
static func ask(hz: int) -> String:
	var app_id := OS.get_environment("SteamAppId")
	if not app_id.is_valid_int():
		return "Nightfall wasn't started from its Steam shortcut"
	if not FileAccess.file_exists(VRCMD):
		return "SteamVR's settings tool isn't at %s" % VRCMD
	if OS.create_process("/usr/bin/env", arguments(app_id, hz)) <= 0:
		return "SteamVR's settings tool didn't start"
	return ""
