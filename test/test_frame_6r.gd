extends SceneTree

# Steam Frame 6r: voice typing shortens long pauses before the model hears a
# clip (a sentence said after a pause could be lost), and the log carries each
# clip's own numbers. Also the Screens tab's layouts and its note.

const RATE := 16000

func _tone(seconds: float, amplitude: float = 0.2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	for i in out.size():
		out[i] = amplitude * sin(TAU * 220.0 * i / RATE)
	return out

func _silence(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out

func _cut(samples: PackedFloat32Array) -> PackedFloat32Array:
	return ClassDB.class_call_static("VoiceTyper", "compress_pauses_in", samples)

func _seconds(samples: PackedFloat32Array) -> float:
	return float(samples.size()) / RATE

func _pauses() -> void:
	# Speech, a three second pause, speech: the pause becomes half a second.
	var clip := _tone(1.0)
	clip.append_array(_silence(3.0))
	clip.append_array(_tone(1.0))
	var cut := _cut(clip)
	assert(is_equal_approx(_seconds(cut), 2.5), "1 + 0.5 + 1 seconds, got %.2f" % _seconds(cut))
	# The words on both sides are untouched.
	assert(cut.slice(0, RATE) == clip.slice(0, RATE))
	assert(cut.slice(cut.size() - RATE) == clip.slice(clip.size() - RATE))
	# A short pause is left alone, and so is a clip with none.
	var short := _tone(1.0)
	short.append_array(_silence(0.5))
	short.append_array(_tone(1.0))
	assert(_cut(short) == short)
	assert(_cut(_tone(2.0)) == _tone(2.0))
	# Silence before the first word and after the last is shortened too.
	var padded := _silence(2.0)
	padded.append_array(_tone(1.0))
	padded.append_array(_silence(4.0))
	assert(is_equal_approx(_seconds(_cut(padded)), 2.0))
	# A microphone with a noise floor above the silence level: nothing is a pause.
	var hiss := _tone(1.0)
	hiss.append_array(_tone(3.0, 0.004))
	hiss.append_array(_tone(1.0))
	assert(_cut(hiss) == hiss)
	# Odd ends: empty, shorter than one block, and a tail that isn't a whole block.
	assert(_cut(PackedFloat32Array()).is_empty())
	assert(_cut(_tone(0.05)) == _tone(0.05))
	var tail := _silence(2.0)
	tail.append_array(_tone(0.07))
	var tail_cut := _cut(tail)
	assert(is_equal_approx(_seconds(tail_cut), 0.57) and tail_cut.slice(tail_cut.size() - 1120) == _tone(0.07))

func _log_text() -> void:
	assert(VoiceTyping.clip_stats_text({}) == "")
	var text := VoiceTyping.clip_stats_text({"quiet_share": 0.62, "zero_share": 0.004, "trimmed_seconds": 9.3,
		"tokens": 3, "parts": 1, "passes": 2, "no_speech": 0.71})
	assert(text == " | sound: 62% quiet, 0% dead, 9.3s of pauses cut | model: 3 tokens in 1 parts, listened 2 times, no-speech 71%", text)

func _stats_method() -> void:
	var typer: Object = ClassDB.instantiate("VoiceTyper")
	var stats: Dictionary = typer.get_last_clip_stats()
	for key in ["quiet_share", "zero_share", "trimmed_seconds", "tokens", "parts", "no_speech"]:
		assert(stats.has(key), key)

# Two screens can also be laid out with the second one on the left, and Save
# doesn't add a picture that is already there.
func _layouts() -> void:
	var two: Array = []
	for preset in MonitorPresets.default_presets():
		if preset["screen_count"] == 2:
			two.append(preset["id"])
	assert(two == ["default_2_side_by_side", "default_2_second_on_left", "default_2_stacked"], str(two))
	var left: Dictionary = MonitorPresets.find_preset("default_2_second_on_left")
	assert(left["screens"][0]["is_primary"] and left["screens"][0]["grid_pos"] == [4, 1] and left["screens"][1]["grid_pos"] == [2, 1])
	var side_by_side := [
		{"is_primary": true, "grid_mode": true, "grid_pos": [2, 1], "free_pos": [0, 1, -2], "free_rot": [0, 0, 0]},
		{"is_primary": false, "grid_mode": true, "grid_pos": [4, 1], "free_pos": [1, 1, -2], "free_rot": [0, 0, 0]}]
	assert(MonitorPresets.find_same_grid_layout(side_by_side) == "default_2_side_by_side")
	var elsewhere := side_by_side.duplicate(true)
	elsewhere[1]["grid_pos"] = [6, 1]
	assert(MonitorPresets.find_same_grid_layout(elsewhere) == "", "a new grid arrangement is saved")
	var free := side_by_side.duplicate(true)
	free[1]["grid_mode"] = false
	assert(MonitorPresets.find_same_grid_layout(free) == "", "freely placed screens are always saved")

func _note() -> void:
	assert(UIController.SCREENS_HOST_NOTICE == "Using additional screens requires Meteor's built-in streaming host.\nPlease connect to the appropriate host.")

func _init() -> void:
	_pauses()
	_log_text()
	_stats_method()
	_layouts()
	_note()
	print("All frame_6r tests passed")
	quit(0)
