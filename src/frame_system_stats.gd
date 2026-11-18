class_name FrameSystemStats
extends RefCounted

# Steam Frame diagnostic, temporary (5u). With the same picture and settings,
# drawing a curved screen took 7.5 ms in some seconds and 11 to 12 in others
# (5t log), and no setting or view explains it. The headset's graphics chip
# changes its clock speed with load and heat, which would do exactly that.
# This reads the clock and a few temperatures from the system (plain files
# under /sys, nothing personal) so [FRAME-COST] can show them side by side.

const MAX_ZONES := 6

var devfreq_root := "/sys/class/devfreq"
var thermal_root := "/sys/class/thermal"
var _clock_path := ""
var _zones: Array = []  # [type, temp path]

static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	# /sys files claim a length they don't have; a line is all there is.
	return f.get_line().strip_edges()

static func _directories(path: String) -> PackedStringArray:
	return DirAccess.get_directories_at(path) if DirAccess.dir_exists_absolute(path) else PackedStringArray()

## Finds what can be read. Returns a line for the log.
func setup() -> String:
	_clock_path = ""
	_zones.clear()
	var found: Array[String] = []
	for name in _directories(devfreq_root):
		var lower := name.to_lower()
		if lower.contains("gpu") or lower.contains("kgsl"):
			var path := "%s/%s/cur_freq" % [devfreq_root, name]
			if _read(path).is_valid_int():
				_clock_path = path
				found.append("graphics clock from %s (steps: %s)" % [name, _read("%s/%s/available_frequencies" % [devfreq_root, name])])
				break
	var graphics: Array = []
	var processor: Array = []
	var other: Array = []
	for name in _directories(thermal_root):
		if not name.begins_with("thermal_zone"):
			continue
		var temp := "%s/%s/temp" % [thermal_root, name]
		if not _read(temp).is_valid_int():
			continue
		var type := _read("%s/%s/type" % [thermal_root, name]).to_lower()
		if type.contains("gpu"):
			graphics.append([type, temp])
		elif type.contains("cpu"):
			processor.append([type, temp])
		else:
			other.append([type, temp])
	_zones = (graphics + processor + other).slice(0, MAX_ZONES)
	if not _zones.is_empty():
		found.append("temperatures from %s" % ", ".join(_zones.map(func(z): return z[0])))
	return "nothing readable" if found.is_empty() else "; ".join(found)

## "gpu clock 585 MHz, hottest 61 C (gpuss-0)", or "" when nothing can be read.
func sample() -> String:
	var parts: Array[String] = []
	if _clock_path != "":
		var hz := _read(_clock_path)
		if hz.is_valid_int():
			parts.append("gpu clock %d MHz" % roundi(hz.to_float() / 1.0e6))
	var hottest := -1.0
	var where := ""
	for zone in _zones:
		var raw := _read(zone[1])
		if not raw.is_valid_int():
			continue
		var c := raw.to_float()
		if c > 1000.0:
			c /= 1000.0  # most report thousandths of a degree
		if c > hottest and c < 150.0:
			hottest = c
			where = zone[0]
	if hottest > 0.0:
		parts.append("hottest %d C (%s)" % [roundi(hottest), where])
	return ", ".join(parts)
