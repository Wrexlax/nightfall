class_name FramePowerWatch
extends RefCounted

## Steam Frame: the battery in the log, once a minute while a stream runs.
##
## Why: whether a depth model, a display rate or passthrough is worth its
## cost is partly a question of battery, and 100% to 54% in one sitting (the
## first figure there was, 7l) mixes several settings and can't be compared
## with anything. The system reports how much power is being drawn at this
## moment, so two minutes on each setting gives a figure for each.
##
## Read from /sys/class/power_supply, where Linux lists the batteries and
## chargers it knows. A controller's battery is listed there too, marked as
## belonging to a device; those are passed over and their names (which can
## carry a serial number) are never written.

const ROOT := "/sys/class/power_supply"

## Power in watts from what a battery's folder says: its own figure
## (microwatts) where it gives one, else current times voltage (microamps,
## microvolts). -1 when neither is there. The sign differs between systems
## and is dropped; "charging" or "discharging" says which way.
static func watts(power_now: String, current_now: String, voltage_now: String) -> float:
	var power := power_now.strip_edges()
	if power.is_valid_int():
		return absf(float(power)) / 1.0e6
	var current := current_now.strip_edges()
	var voltage := voltage_now.strip_edges()
	if current.is_valid_int() and voltage.is_valid_int():
		return absf(float(current)) * float(voltage) / 1.0e12
	return -1.0

## Whether a power supply's folder is the headset's own battery.
static func is_own_battery(type: String, scope: String) -> bool:
	return type.strip_edges() == "Battery" and scope.strip_edges() != "Device"

## `reading` as a sentence. With `average` (and the lowest and highest) of the
## readings since the last line, those are given: one reading a minute swung
## by several watts on the same setting (7o: 17.2, 22.4, 19.0 and 19.3 W, all
## on one model at one display rate), too much to compare settings by.
static func describe(reading: Dictionary, average: float = -1.0, lowest: float = -1.0, highest: float = -1.0) -> String:
	if reading.is_empty():
		return "no battery of the headset's own is listed by the system"
	var text := "battery %d%%, %s" % [reading["percent"], reading["status"]]
	if average >= 0.0:
		text += ", %.1f W on average since the last line (%.1f to %.1f)" % [average, lowest, highest]
	elif reading["watts"] >= 0.0:
		text += ", %.1f W" % reading["watts"]
	else:
		text += " (the system gives no power figure)"
	return text

## The folder of the headset's own battery, "" when the system lists none.
static func find() -> String:
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return ""
	for supply in dir.get_directories():
		var folder := ROOT.path_join(supply)
		if is_own_battery(FrameNetworkWatch.file_text(folder.path_join("type")), FrameNetworkWatch.file_text(folder.path_join("scope"))):
			return folder
	return ""

## { "percent", "status" ("charging", "discharging", "full", ...), "watts" }
## from a battery's folder; empty for "".
static func read(folder: String) -> Dictionary:
	if folder.is_empty():
		return {}
	return {
		"percent": int(FrameNetworkWatch.file_text(folder.path_join("capacity"))),
		"status": FrameNetworkWatch.file_text(folder.path_join("status")).strip_edges().to_lower(),
		"watts": watts(FrameNetworkWatch.file_text(folder.path_join("power_now")),
			FrameNetworkWatch.file_text(folder.path_join("current_now")),
			FrameNetworkWatch.file_text(folder.path_join("voltage_now"))),
	}

# --- a reading a second, a line a minute ----------------------------------

var _folder := ""
var _looked := false
var _sum := 0.0
var _count := 0
var _lowest := 0.0
var _highest := 0.0

## Once a second while a stream runs: takes a reading of the power.
func sample() -> void:
	if not _looked:
		_looked = true
		_folder = find()
	if _folder.is_empty():
		return
	var now := watts(FrameNetworkWatch.file_text(_folder.path_join("power_now")),
		FrameNetworkWatch.file_text(_folder.path_join("current_now")),
		FrameNetworkWatch.file_text(_folder.path_join("voltage_now")))
	if now < 0.0:
		return
	_lowest = now if _count == 0 else minf(_lowest, now)
	_highest = now if _count == 0 else maxf(_highest, now)
	_sum += now
	_count += 1

## The line for the log, from the readings since the last one.
func line() -> String:
	if not _looked:
		_looked = true
		_folder = find()
	var text := describe(read(_folder), _sum / _count if _count > 0 else -1.0, _lowest, _highest)
	_sum = 0.0
	_count = 0
	return text
