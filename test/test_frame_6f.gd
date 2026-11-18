extends SceneTree

# Steam Frame 6f: the Frame controllers' bumpers are bound (click as well as
# touch) and appear in the Buttons tab and the Gamepad Layout. 6g: a choice of
# speech model for voice typing.

func _bumpers_in_action_map() -> void:
	var map := load("res://openxr_action_map.tres") as OpenXRActionMap
	assert(map != null)
	var bumper: OpenXRAction = null
	for set_index in map.get_action_set_count():
		var action_set: OpenXRActionSet = map.get_action_set(set_index)
		for action in action_set.actions:
			if action.resource_name == "bumper":
				bumper = action
	assert(bumper != null and bumper.action_type == OpenXRAction.OPENXR_ACTION_BOOL)
	assert("/user/hand/left" in bumper.toplevel_paths and "/user/hand/right" in bumper.toplevel_paths)
	var frame := map.find_interaction_profile("/interaction_profiles/valve/frame_controller_valve")
	assert(frame != null)
	var paths := {}
	for binding in frame.bindings:
		if binding.action == bumper:
			paths[binding.binding_path] = true
	# The paths Valve's Steam Frame input page and the engine's own profile name.
	assert(paths.has("/user/hand/left/input/bumper/click"))
	assert(paths.has("/user/hand/right/input/bumper/click"))
	assert(paths.size() == 2)
	# The touch sensor still counts as a hand on the controller (5n).
	var touch_paths := {}
	for binding in frame.bindings:
		if binding.action.resource_name == "face_touch":
			touch_paths[binding.binding_path] = true
	assert(touch_paths.has("/user/hand/left/input/bumper/touch") and touch_paths.has("/user/hand/right/input/bumper/touch"))

func _bumpers_in_tables() -> void:
	for id in ["lbumper", "rbumper"]:
		assert(ButtonBindings.CONTROLS.has(id) and id in ButtonBindings.CONTROL_ORDER)
		assert(ButtonBindings.CONTROLS[id][2] == "bumper")
		assert(ButtonBindings.CONTROLS[id][3] == "rclick")  # 8z: no button starts empty
		assert(ButtonBindings.ACTIONS.has(ButtonBindings.CONTROLS[id][3]))
		assert(ButtonBindings.PAD_CONTROLS.has(id) and id in ButtonBindings.PAD_CONTROL_ORDER)
	assert(ButtonBindings.CONTROLS["lbumper"][1] == "left" and ButtonBindings.CONTROLS["rbumper"][1] == "right")
	# Gamepad mode: LB and RB, the same as the grips.
	assert(ButtonBindings.PAD_CONTROLS["lbumper"][1] == 0x0100 and ButtonBindings.PAD_CONTROLS["rbumper"][1] == 0x0200)
	assert(ButtonBindings.PAD_CONTROLS["lgrip"][1] == 0x0100 and ButtonBindings.PAD_CONTROLS["rgrip"][1] == 0x0200)
	# Every control in an order list exists, and nothing is listed twice.
	for id in ButtonBindings.CONTROL_ORDER:
		assert(ButtonBindings.CONTROLS.has(id))
	for id in ButtonBindings.PAD_CONTROL_ORDER:
		assert(ButtonBindings.PAD_CONTROLS.has(id))
	assert(ButtonBindings.CONTROL_ORDER.size() == ButtonBindings.CONTROLS.size())
	assert(ButtonBindings.PAD_CONTROL_ORDER.size() == ButtonBindings.PAD_CONTROLS.size())
	assert("bumper" in ButtonBindings._RAW_ACTIONS)

# 6h: Foveation is back as a choice that takes effect at the next start.
func _foveation() -> void:
	assert(SettingsController.FOVEATION_LABELS == ["Off", "Low", "Medium", "High"])
	assert(AppSettings.new().frame_foveation == 0)  # off until chosen
	assert("Foveation" in VoiceMenu.OFF_AND_MORE)
	# The saved value keeps the name and place nightfall.sh reads it by.
	var config := ConfigFile.new()
	var settings := AppSettings.new()
	settings.frame_foveation = 2
	SettingsPersistence.write_app(config, settings)
	assert(config.get_value("display", "frame_foveation") == 2)
	var launcher := FileAccess.get_file_as_string("res://steam-frame/package/nightfall.sh")
	assert(launcher.contains("^frame_foveation="))
	# 8u: the settings are in this port's own folder. The launcher reads the
	# file where override.cfg has Godot keep it, and carries the earlier
	# folder's settings over only when they are this port's.
	var override := ConfigFile.new()
	assert(override.load("res://steam-frame/package/override.cfg") == OK)
	assert(override.get_value("application", "config/use_custom_user_dir") == true)
	var folder: String = override.get_value("application", "config/custom_user_dir_name")
	assert(folder == "NightfallFrame")
	assert(launcher.contains("DATA=\"${XDG_DATA_HOME:-$HOME/.local/share}/%s\"" % folder))
	assert(launcher.contains("CFG=\"$DATA/app_state.cfg\""))
	assert(launcher.contains("grep -q '^frame_' \"$OLD_DATA/app_state.cfg\""))
	assert(FileAccess.get_file_as_string("res://steam-frame/package/uninstall.sh").contains("/%s\"" % folder))

# 6g: voice typing can use a larger speech model when it is installed.
func _speech_models() -> void:
	assert(VoiceTyping.MODEL_FILES == ["ggml-base.en.bin", "ggml-small.en.bin"])
	assert(VoiceTyping.MODEL_LABELS.size() == VoiceTyping.MODEL_FILES.size())
	assert(AppSettings.new().voice_model == 0)  # Base unless chosen
	assert(VoiceTyping.model_path().ends_with("/.local/share/nightfall/whisper/ggml-base.en.bin"))
	assert(VoiceTyping.model_path(1).ends_with("/ggml-small.en.bin"))
	assert(VoiceTyping.model_path(9).ends_with("/ggml-small.en.bin"))  # out of range: the last one

# 6j: a short clip the model wrote out twice still counts as its command.
func _said_twice() -> void:
	# More text than a clip has room for (6z): the 242 characters from 1.4 s.
	assert(VoiceTyping.more_than_spoken(242, 1.4))
	assert(not VoiceTyping.more_than_spoken(6, 1.5))
	assert(not VoiceTyping.more_than_spoken(248, 16.3))   # the fastest ordinary clip in the 6y logs
	assert(not VoiceTyping.more_than_spoken(20, 0.3))     # a short word or two always passes
	assert(VoiceTyping.said_twice("Depth view. Depth view.") == "Depth view.")
	assert(VoiceTyping.said_twice("Depth view, depth view") == "Depth view,")
	assert(VoiceTyping.said_twice("Nightfall depth view. Nightfall depth view.") == "Nightfall depth view.")
	assert(VoiceTyping.said_twice("Depth view.") == "")
	assert(VoiceTyping.said_twice("no no") == "no")           # only ever tried as a command
	assert(VoiceTyping.said_twice("depth view depth map") == "")
	assert(VoiceTyping.said_twice("one two three") == "")
	assert(VoiceTyping.said_twice("") == "")
	assert(not VoiceCommands.match_command(VoiceTyping.said_twice("Depth view. Depth view."), false).is_empty())
	assert(VoiceCommands.match_command("Depth view. Depth view.", false).is_empty())

# 6k: the bare name of an on/off setting is a toggle; "depth of view" is how
# the Small model sometimes hears "depth view".
func _toggles() -> void:
	for phrase in ["Depth view.", "depth of view", "Nightfall, depth view", "Depth of view. Depth of view."]:
		var said: String = phrase if VoiceTyping.said_twice(phrase) == "" else VoiceTyping.said_twice(phrase)
		assert(VoiceCommands.match_command(said, false).get("id", "") == "depth_toggle", phrase)
	assert(VoiceCommands.match_command("depth view on", false)["id"] == "depth_on")
	assert(VoiceCommands.match_command("Depth of view off.", false)["id"] == "depth_off")
	assert(VoiceCommands.match_command("head lock", false)["id"] == "headlock_toggle")
	assert(VoiceCommands.match_command("on head lock", false)["id"] == "headlock_on")
	assert(VoiceCommands.match_command("passthrough", false)["id"] == "passthrough_toggle")
	assert(VoiceCommands.match_command("gamepad mode", false)["id"] == "gamepad_toggle")
	assert(VoiceCommands.match_command("show menu", false)["id"] == "menu_show")
	assert(VoiceCommands.match_command("menu", false)["id"] == "menu_toggle")
	# Every toggle names two real commands, and every toggle phrase a real toggle.
	var ids := {}
	for group in VoiceCommands.GROUPS:
		for entry in group[1]:
			ids[entry[0]] = true
	for id in VoiceCommands.TOGGLES:
		assert(ids.has(VoiceCommands.TOGGLES[id][0]) and ids.has(VoiceCommands.TOGGLES[id][1]), id)
	for phrase in VoiceCommands.TOGGLE_PHRASES:
		assert(VoiceCommands.TOGGLES.has(VoiceCommands.TOGGLE_PHRASES[phrase]), phrase)

var _done := false
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_bumpers_in_action_map()
	_bumpers_in_tables()
	_foveation()
	_speech_models()
	_said_twice()
	_toggles()
	print("All frame_6f tests passed")
	quit()
	return true
