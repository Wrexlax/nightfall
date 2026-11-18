class_name FramePassthroughCamera
extends RefCounted

## Steam Frame: is a camera add-on fitted?
##
## The headset's own passthrough is black-and-white. A colour camera add-on
## (Arcturus Vision is the first) plugs into the expansion port and takes
## passthrough over, and with it a frame Nightfall delivers late shows as a
## hitch when the head turns (7a and 7b logs), so Nightfall keeps to a display
## rate it can hold while such a camera is fitted and passthrough is on.
##
## The system lists every camera sensor by its chip's name ("og01a1b 4-0060":
## chip, then where it is wired). The headset's own are the two kinds named
## here; any other sensor is an add-on. Read on one headset (7b log, which
## showed "arcimx616" beside them): if Valve fits other sensors one day, this
## would take them for an add-on, and the Advanced option switches the limit
## off.

const BUILT_IN: Array = ["og01a1b", "og0ve10"]
const VIDEO_ROOT := "/sys/class/video4linux"

## "arcimx616 0-0010" -> "arcimx616"; "" for anything that isn't a sensor
## (the system's own pipeline stages, the video decoder).
static func sensor_chip(device_name: String) -> String:
	var parts := device_name.strip_edges().split(" ", false)
	if parts.size() != 2:
		return ""
	var wired := parts[1].split("-")
	if wired.size() != 2 or not wired[0].is_valid_int() or not wired[1].is_valid_hex_number():
		return ""
	return parts[0]

## The add-on sensors among these device names, each chip once.
static func addons_among(device_names: PackedStringArray) -> PackedStringArray:
	var found := PackedStringArray()
	for device_name in device_names:
		var chip := sensor_chip(device_name)
		if not chip.is_empty() and not BUILT_IN.has(chip) and not found.has(chip):
			found.append(chip)
	return found

## Which camera is running shows in each sensor's power state: "active"
## while it runs. The add-on's sensors go to "suspended" when its app hands
## over to the headset's own cameras in the dark, and back again in the light
## (7c log: within 20 seconds of each change, both ways, three times). The
## headset's own sensors read "active" either way, so they say nothing.
const RUNNING := "active"

## [device name, power state] for every camera sensor the system lists.
static func sensor_states() -> Array:
	var states: Array = []
	if not DirAccess.dir_exists_absolute(VIDEO_ROOT):
		return states
	for device in DirAccess.get_directories_at(VIDEO_ROOT):
		var name := _line("%s/%s/name" % [VIDEO_ROOT, device])
		if not sensor_chip(name).is_empty():
			states.append([name, _line("%s/%s/device/power/runtime_status" % [VIDEO_ROOT, device])])
	return states

static func _line(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	# These files claim a length they don't have; a line is all there is.
	return "" if f == null else f.get_line().strip_edges()

## Whether an add-on's camera is the one running, among these sensor states.
static func addon_running_among(states: Array) -> bool:
	for state in states:
		var chip := sensor_chip(str(state[0]))
		if not chip.is_empty() and not BUILT_IN.has(chip) and str(state[1]) == RUNNING:
			return true
	return false

## The add-on sensors the system shows now (empty: none, or nothing readable).
static func addons() -> PackedStringArray:
	var names := PackedStringArray()
	for state in sensor_states():
		names.append(state[0])
	return addons_among(names)

## Whether an add-on's camera is showing the room at the moment.
static func addon_running() -> bool:
	return addon_running_among(sensor_states())

## The add-on counts as in use while it runs, and for `release_ms` after it
## stops: a shadow over the room must not restart the stream twice.
static func still_in_use(in_use: bool, running: bool, idle_ms: int, release_ms: int) -> bool:
	if running:
		return true
	return in_use and idle_ms < release_ms
