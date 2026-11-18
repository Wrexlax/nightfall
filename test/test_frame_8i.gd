extends SceneTree

# Steam Frame 8i and 8j: the keyboard's panel is remembered, the Media panel
# is offered while Meteor can press its keys, and Advanced Settings > Logging.

class Stream extends RefCounted:
	var keys: Array = []
	func send_keyboard_event(code: int, action: int, _modifiers: int) -> void: keys.append([code, action])
	func send_mouse_button_event(_action: int, _button: int) -> void: pass

class State extends RefCounted:
	var saves := 0
	func save_state() -> void: saves += 1

class Streams extends RefCounted:
	var offers := false
	var pressed: Array = []
	var muted := -1
	func pc_muted() -> int: return muted if offers else -1
	func meteor_presses_media_keys() -> bool: return offers
	func press_media_key(key: String) -> bool:
		pressed.append(key)
		return true

class Owner extends Node3D:
	var stream_manager := Streams.new()
	var device_is_steam_frame := true
	var is_streaming := true
	var browser_prototype = null
	var screen_sources = null
	var composition_panels = null
	var pcvr_handover = null
	var settings := AppSettings.new()
	var state_manager := State.new()
	var stream_backend := Stream.new()
	var input_handler: InputHandler
	func _init() -> void: input_handler = InputHandler.new(self)

func _keyboard(owner: Owner) -> VirtualKeyboard:
	var keyboard := VirtualKeyboard.new(owner)
	keyboard.viewport = SubViewport.new()
	keyboard.viewport.size = keyboard.viewport_size
	root.add_child(keyboard.viewport)
	keyboard._kb_root = Control.new()
	keyboard.viewport.add_child(keyboard._kb_root)
	# As build() does it, with the settings still at their defaults: the
	# keyboard is built before the saved settings are loaded.
	keyboard._has_panels = true
	keyboard._build_keys()
	keyboard._build_trackpad()
	keyboard._build_panels()
	keyboard._side_from_settings()
	return keyboard

func _tab(keyboard: VirtualKeyboard, idx: int) -> Button:
	for kd in keyboard._key_data:
		if kd.get("tab", -1) == idx:
			return kd["btn"]
	return null

func _initialize() -> void:
	await process_frame
	var owner := Owner.new()
	root.add_child(owner)
	var keyboard := _keyboard(owner)
	assert(keyboard._panel == VirtualKeyboard.PANEL_TRACKPAD and not keyboard._tp_shown)

	# The saved settings arrive after the keyboard was built (8h came
	# back on the trackpad whatever panel was showing at exit). Bringing the keyboard up reads them.
	owner.settings.keyboard_trackpad = true
	owner.settings.keyboard_panel = 2
	keyboard._side_from_settings()
	assert(keyboard._tp_shown and keyboard._panel == 2, "the saved panel was not taken up")
	var number_keys := 0
	for kd in keyboard._key_data:
		if kd.get("panel", -1) == 2:
			assert(kd["btn"].visible)
			number_keys += 1
	assert(number_keys == 17 and not keyboard._tp_border.visible)
	assert(owner.state_manager.saves == 0, "reading the saved choice saved it again")
	var source := FileAccess.get_file_as_string("res://src/virtual_keyboard.gd")
	var toggle := source.substr(source.find("func toggle():"), 120)
	assert(toggle.find("_side_from_settings()") > 0 and toggle.find("_side_from_settings()") < toggle.find("super()"), "toggle() must read the saved choices before showing")

	# Media: only offered while the stream's Meteor says it presses those
	# keys on the PC (8j). Otherwise four tabs share the strip; the panel can't be chosen, and a
	# saved choice of it falls back to the trackpad.
	var strip := keyboard._side_rect()
	var shown := 0
	for i in range(VirtualKeyboard.PANEL_NAMES.size()):
		if _tab(keyboard, i).visible:
			shown += 1
	assert(shown == 4 and not _tab(keyboard, VirtualKeyboard.PANEL_MEDIA).visible)
	assert(is_equal_approx(_tab(keyboard, 0).position.x, strip.position.x))
	assert(is_equal_approx(_tab(keyboard, 4).position.x + _tab(keyboard, 4).size.x, strip.end.x), "the four tabs fill the strip")
	for i in [0, 1, 2, 4]:
		var tab := _tab(keyboard, i)
		var width := tab.get_theme_font("font").get_string_size(tab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tab.get_theme_font_size("font_size")).x
		assert(width <= tab.size.x - 8.0)
	keyboard.set_panel(VirtualKeyboard.PANEL_MEDIA)
	assert(keyboard._panel == 2 and owner.settings.keyboard_panel == 2)
	owner.settings.keyboard_panel = VirtualKeyboard.PANEL_MEDIA
	keyboard._side_from_settings()
	assert(keyboard._panel == VirtualKeyboard.PANEL_TRACKPAD and keyboard._tp_border.visible)
	for kd in keyboard._key_data:
		if kd.get("panel", -1) == VirtualKeyboard.PANEL_MEDIA:
			assert(not kd["btn"].visible and keyboard._key_from_pos(kd["btn"].position + kd["btn"].size / 2.0) != kd["key"])
	# Meteor's answer arrives while the keyboard is up: the tab appears, and
	# the panel saved from last time comes back.
	owner.stream_manager.offers = true
	keyboard._follow_media_keys()
	assert(keyboard._panel == VirtualKeyboard.PANEL_MEDIA and _tab(keyboard, VirtualKeyboard.PANEL_MEDIA).visible)
	assert(is_equal_approx(_tab(keyboard, 4).position.x + _tab(keyboard, 4).size.x, strip.end.x), "the five tabs fill the strip")
	# A media key asks Meteor and sends nothing down the stream, from either hand.
	keyboard.visible = true
	var saves_before: int = owner.state_manager.saves
	keyboard._on_key_press(KEY_VOLUMEMUTE)
	keyboard._on_key_release(KEY_VOLUMEMUTE) # as letting go of the trigger does
	keyboard._held_keys.clear()
	for kd in keyboard._key_data:
		if kd.get("panel", -1) == VirtualKeyboard.PANEL_MEDIA and kd["key"] == KEY_MEDIAPLAY:
			keyboard.handle_secondary_key(kd["btn"].position + kd["btn"].size / 2.0, true)
			keyboard.handle_secondary_key(kd["btn"].position + kd["btn"].size / 2.0, false)
	assert(owner.stream_manager.pressed == ["mute", "play-pause"], str(owner.stream_manager.pressed))
	assert(owner.stream_backend.keys.is_empty(), "a media key went down the stream: %s" % str(owner.stream_backend.keys))
	assert(keyboard._held_keys.is_empty() and keyboard._held_keys_secondary.is_empty() and owner.state_manager.saves == saves_before)
	# A volume key held down repeats until it is let go; Mute doesn't.
	owner.stream_manager.pressed.clear()
	keyboard._on_key_press(KEY_VOLUMEUP)
	keyboard._follow_media_keys()
	assert(owner.stream_manager.pressed == ["volume-up"], "repeated at once")
	keyboard._media_next_ms = 0 # the wait is over
	keyboard._follow_media_keys()
	keyboard._media_next_ms = 0
	keyboard._follow_media_keys()
	assert(owner.stream_manager.pressed == ["volume-up", "volume-up", "volume-up"])
	keyboard._on_key_release(KEY_VOLUMEUP)
	keyboard._held_keys.clear()
	keyboard._media_next_ms = 0
	keyboard._follow_media_keys()
	assert(owner.stream_manager.pressed.size() == 3, "still repeating after the key was let go")
	keyboard._on_key_press(KEY_VOLUMEMUTE)
	keyboard._media_next_ms = 0
	keyboard._follow_media_keys()
	assert(owner.stream_manager.pressed.size() == 4 and keyboard._media_held == 0, "Mute repeated")
	keyboard._on_key_release(KEY_VOLUMEMUTE)
	keyboard._held_keys.clear()
	assert(VirtualKeyboard.MEDIA_REPEAT_AFTER_MS > VirtualKeyboard.MEDIA_REPEAT_EVERY_MS)
	# The Mute key is lit while the PC is muted, as Meteor reports it.
	var mute_key: Dictionary = {}
	for kd in keyboard._key_data:
		if kd.get("panel", -1) == VirtualKeyboard.PANEL_MEDIA and kd["key"] == KEY_VOLUMEMUTE:
			mute_key = kd
	var plain: Color = mute_key["norm_style"].bg_color
	owner.stream_manager.muted = 1
	keyboard._follow_media_keys()
	assert(keyboard._mute_lit and mute_key["norm_style"].bg_color != plain, "Mute is not lit")
	owner.stream_manager.muted = 0
	keyboard._follow_media_keys()
	assert(not keyboard._mute_lit and mute_key["norm_style"].bg_color == plain)
	owner.stream_manager.muted = -1 # an older Meteor never says: never lit
	keyboard._follow_media_keys()
	assert(not keyboard._mute_lit)
	assert(MeteorClient.parse_media_answer('{"pressed":"mute","muted":true}', "mute") == {"pressed": "mute", "muted": true})
	assert(MeteorClient.parse_media_answer('{"pressed":"mute"}', "mute") == {"pressed": "mute"}, "sf13 says nothing about muted")
	assert(MeteorClient.parse_media_answer('{"error":"not a streaming client"}', "mute").is_empty())
	assert(MeteorClient.parse_media_answer('{"pressed":"stop","muted":true}', "mute").is_empty())
	var page := '{"service":"nightfall-meteor","link":{"choice":0,"rev":3},"depth":true,"muted":%s}'
	assert(MeteorClient.parse_link_pick(page % "true").get("muted") == true and MeteorClient.parse_link_pick(page % "false").get("muted") == false)
	assert(not MeteorClient.parse_link_pick('{"service":"nightfall-meteor","link":{"choice":0,"rev":3}}').has("muted"))
	var stream_source := FileAccess.get_file_as_string("res://src/stream_manager.gd")
	assert(stream_source.contains("\t_meteor = {}\n\t_pc_muted = PC_MUTED_UNKNOWN"), "a new stream starts without the last one's mute state")

	# Every media key on the panel has a name, the names are the ones the
	# headset may send, and Meteor's list is the same.
	var meteor_source := FileAccess.get_file_as_string("res://meteor/src/media_keys.rs")
	var names: Array = []
	for kd in keyboard._key_data:
		if kd.get("panel", -1) == VirtualKeyboard.PANEL_MEDIA:
			assert(VirtualKeyboard.MEDIA_KEY_NAMES.has(kd["key"]), "%s would be sent down the stream" % kd["l"])
			names.append(VirtualKeyboard.MEDIA_KEY_NAMES[kd["key"]])
	names.sort()
	var allowed: Array = MeteorClient.MEDIA_KEYS.duplicate()
	allowed.sort()
	assert(names == allowed and names.size() == 7)
	for media_name in names:
		assert(meteor_source.contains("(\"%s\", 0x" % media_name), "Meteor doesn't know %s" % media_name)
	assert(MeteorClient.media_key_url("192.168.1.20", 47984, "mute") == "http://192.168.1.20:%d/meteor/media?key=mute" % MeteorClient.discovery_port(47984))
	assert(StreamManager.offers_media_keys({"fixes": ["second-link", "media-keys"]}, "192.168.1.20"))
	assert(not StreamManager.offers_media_keys({"fixes": ["second-link"]}, "192.168.1.20"), "an older Meteor")
	assert(not StreamManager.offers_media_keys({"fixes": ["media-keys"]}, ""), "a stream that isn't going through Meteor")
	assert(not StreamManager.offers_media_keys({}, "192.168.1.20"))
	# The stream ends, or Meteor goes: back to four tabs and the trackpad.
	owner.stream_manager.offers = false
	keyboard._follow_media_keys()
	assert(keyboard._panel == VirtualKeyboard.PANEL_TRACKPAD and not _tab(keyboard, VirtualKeyboard.PANEL_MEDIA).visible)
	assert(owner.settings.keyboard_panel == VirtualKeyboard.PANEL_MEDIA, "the saved choice is kept for the next stream")

	# Logging: on for an install that never had the option, off on a new
	# install and after Reset Settings, saved as a line the launcher can read.
	assert(AppSettings.new().frame_logging)
	var fresh := AppSettings.new()
	FrameDefaults.apply(fresh, true, true)
	assert(not fresh.frame_logging)
	var written := ConfigFile.new()
	SettingsPersistence.write_app(written, fresh)
	assert(("\n" + written.encode_to_text()).contains("\nframe_logging=false\n"), "not as the launcher looks for it")
	var read_back := AppSettings.new()
	SettingsPersistence.read_app(written, read_back, true, [])
	assert(not read_back.frame_logging)
	SettingsPersistence.read_app(ConfigFile.new(), read_back, true, [])
	assert(read_back.frame_logging, "no saved line: logging stays on")
	var launcher := FileAccess.get_file_as_string("res://steam-frame/package/nightfall.sh")
	assert(launcher.contains("s/^frame_logging=") and launcher.contains("export NIGHTFALL_LOGGING=$LOGGING") and launcher.contains("logging-on"))
	var main_source := FileAccess.get_file_as_string("res://main.gd")
	assert(main_source.contains("func _log(msg: String):\n\tif not _logging:\n\t\treturn"))
	assert(main_source.contains("OS.get_environment(\"NIGHTFALL_LOGGING\") != \"0\""))

	# Reset Settings (8j): Nightfall asks its launcher to start it again
	# (before, it closed without saying so); the launcher knows the same number.
	var settings_source := FileAccess.get_file_as_string("res://src/settings_controller.gd")
	var reset := settings_source.substr(settings_source.find("func reset_settings():"), 1400)
	assert(reset.contains("main.restart_app()") and not reset.contains("main.exit_app()"))
	assert(main_source.contains("const RESTART_EXIT_CODE := 75") and main_source.contains("get_tree().quit(RESTART_EXIT_CODE)"))
	assert(launcher.contains("\" = 75 ]") and launcher.contains("exec \"$HERE/nightfall.sh\" \"$@\""))
	assert(SettingsController.RESET_DONE.contains("restarting") and SettingsController.RESET_ASK.contains("will restart"))

	# In the menu: About, beside Licences, with a tooltip for each choice.
	var was_frame: bool = MenuSchema._IS_FRAME
	MenuSchema._IS_FRAME = true
	var found := false
	assert(MenuSchema.validate().is_empty(), "\n".join(MenuSchema.validate()))
	for row in MenuSchema.get_tab(&"settings")["rows"]:
		for option in row["options"]:
			if option["field"] == &"_ui_logging_btn":
				found = row["node_name"] == &"SettingsAboutRow"
	MenuSchema._IS_FRAME = was_frame
	assert(found, "Logging is not in the About row")
	assert(MenuSchema.LOGGING_TIPS.has("On") and MenuSchema.LOGGING_TIPS.has("Off"))

	for node in [keyboard.viewport, keyboard, owner]:
		node.free()
	print("All frame 8i tests passed")
	quit()
