extends SceneTree

# Steam Frame 8b: Advanced Settings regrouped, the Commands switch, and the
# notices' translations.

func _initialize() -> void:
	var was := MenuSchema._IS_FRAME

	# Off the Frame the settings rows are upstream's, untouched.
	MenuSchema._IS_FRAME = false
	var upstream_rows: Array = MenuSchema.get_tab(&"settings")["rows"]
	assert(upstream_rows[0]["node_name"] == &"SettingsDiagnosticsRow", "upstream's order off the Frame")
	assert(MenuSchema.validate().is_empty(), "\n".join(MenuSchema.validate()))

	# On the Frame: the agreed groups, in the agreed order.
	MenuSchema._IS_FRAME = true
	var errors := MenuSchema.validate()
	assert(errors.is_empty(), "\n".join(errors))
	var rows: Array = MenuSchema.get_tab(&"settings")["rows"]
	var titles: Array = []
	var where := {}
	for row in rows:
		if row.has("title") and row["options"].any(func(o): return o.get("visible", true)):
			titles.append(row["title"])
		for option in row["options"]:
			assert(not where.has(option["field"]), "%s is in two rows" % option["field"])
			where[option["field"]] = row["node_name"]
	assert(titles == ["View & Feel", "Screen Position", "Menu & Keyboard Position", "Voice & Microphone",
		"Connection", "General", "About"], str(titles))
	assert(not where.has(&"_ui_second_link_btn"), "Stream Link has left Advanced Settings")
	var on_stream := false
	for row in MenuSchema.get_tab(&"stream")["rows"]:
		for option in row["options"]:
			on_stream = on_stream or option["field"] == &"_ui_second_link_btn"
	assert(on_stream, "Stream Link is on the Stream tab")
	assert(where[&"_ui_3d_cursor_position_btn"] == &"SettingsGeneralRow", "AI 3D's one option has no category to itself")
	assert(where[&"_ui_icon_backdrop_btn"] == &"SettingsViewRow")
	# 8t: Head Lock and Bezel changed places. Head Lock ends the Display
	# tab's first row, where Bezel was; Bezel has Head Lock's old place.
	assert(not where.has(&"_ui_head_lock_btn"), "Head Lock has left Advanced Settings")
	assert(where[&"_ui_bezel_btn"] == &"SettingsViewRow")
	var first_row: Array = MenuSchema.get_tab(&"display")["rows"][0]["options"].map(func(o): return o["field"])
	assert(first_row.back() == &"_ui_head_lock_btn" and not first_row.has(&"_ui_bezel_btn") and first_row.size() == 5, str(first_row))
	for row in rows:
		if row["node_name"] == &"SettingsViewRow":
			assert(row["options"].map(func(o): return o["field"]) == [&"_ui_recenter_btn", &"_ui_bezel_btn", &"_ui_haptics_btn", &"_ui_icon_backdrop_btn"])
		assert(not row["options"].is_empty() or row.get("title", "") != "", "an empty row of upstream's was left behind: %s" % row["node_name"])
	assert(where[&"_ui_voice_commands_btn"] == &"SettingsVoiceRow")
	assert(where[&"_ui_microphone_btn"] == &"SettingsVoiceMoreRow" and where[&"_ui_mic_key_btn"] == &"SettingsVoiceMoreRow")
	assert(where[&"_ui_stats_btn"] == &"SettingsGeneralRow")
	# The rows other code looks up by name are still there.
	for needed in [&"SettingsVoiceRow", &"SettingsAboutRow", &"SettingsGeneralRow"]:
		assert(rows.any(func(row): return row["node_name"] == needed), "%s is gone" % needed)
	# Nothing upstream defines went missing in the regrouping.
	MenuSchema._IS_FRAME = false
	var upstream_fields := {}
	for row in MenuSchema.get_tab(&"settings")["rows"]:
		for option in row["options"]:
			upstream_fields[option["field"]] = true
	for field in upstream_fields:
		assert(where.has(field) or field in [&"_ui_second_link_btn", &"_ui_head_lock_btn"], "%s was lost in the regrouping" % field)
	# Controls: Pointer Ray is last in its row, above Controller Models, and
	# the cursor options sit together.
	MenuSchema._IS_FRAME = true
	var control_rows: Array = MenuSchema.get_tab(&"control")["rows"]
	var shown_first: Array = []
	for option in control_rows[0]["options"]:
		if option.get("visible", true):
			shown_first.append(option["label"])
	assert(shown_first == ["Cursor Type", "Cursor Follow", "Cursor Steady", "Cursor Off Screen", "Pointer Ray"], str(shown_first))
	var shown_second: Array = []
	for option in control_rows[1]["options"]:
		if option.get("visible", true):
			shown_second.append(option["label"])
	assert(shown_second.size() == shown_first.size() and shown_second[-1] == "Controller Models", str(shown_second))
	# Picture: the picture's look on top, how the screen is drawn below.
	var picture_rows: Array = MenuSchema.get_tab(&"picture")["rows"]
	var picture: Array = []
	for row in picture_rows:
		picture.append(row["options"].filter(func(o): return o.get("visible", true)).map(func(o): return o["label"]))
	assert(picture[0] == ["Brightness", "Contrast", "Gamma", "Sharpen", "Foveation"], str(picture))
	assert(picture[1] == ["Flat Screen", "Flat Screen Detail", "Curved Filter", "PT Fade"], str(picture))
	MenuSchema._IS_FRAME = was

	# The Voice Commands list: every row keeps to the page (1400 wide, 24 px
	# margins), however long its text.
	await process_frame
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	var longest := 0
	for row in VoiceMenu.HELP + VoiceCommands.TYPING_HELP:
		longest = maxi(longest, String(row[1]).length())
		grid.add_child(UIController._voice_cell("\"%s\"" % row[0], 17, Color.WHITE, UIController.VOICE_LIST_COMMAND_WIDTH))
		grid.add_child(UIController._voice_cell(row[1], 16, Color.WHITE, UIController.VOICE_LIST_NOTE_WIDTH))
	root.add_child(grid)
	await process_frame
	assert(longest > 60, "the list has long rows to wrap: %d" % longest)
	assert(grid.get_combined_minimum_size().x <= 1352.0, "the list is %d wide" % grid.get_combined_minimum_size().x)
	for cell in grid.get_children():
		assert(cell.size.x <= UIController.VOICE_LIST_NOTE_WIDTH + 1.0, "a cell is %d wide: %s" % [cell.size.x, cell.text])
	# The built-in spots are whole spots: five numbers each, the keyboard
	# further away than the 0.55 m it used to start at, the menu to the left.
	var main_script: GDScript = load("res://main.gd")
	var built_in: Dictionary = main_script.get_script_constant_map()
	assert(built_in["FRAME_MENU_SPOT"].size() == 5 and built_in["FRAME_KEYBOARD_SPOT"].size() == 5)
	assert(float(built_in["FRAME_KEYBOARD_SPOT"][2]) < -0.8 and float(built_in["FRAME_MENU_SPOT"][0]) < -0.5)
	# Saved spots as the log gives them.
	assert(SettingsController.spot_text([]) == "Nightfall's own")
	assert(SettingsController.spot_text([0.1, -0.25, -1.5, 0.0, -0.3]) == "[0.100, -0.250, -1.500, 0.000, -0.300]")
	# Connect pressed while a launch is in flight starts no second one...
	var connecting := SessionLifecycle.Phase.CONNECTING
	assert(StreamManager.launch_in_flight(connecting, 5000, 6000), "Quick Start began a second ago")
	# ...but a Connect that is the first launch goes through: the welcome
	# screen asks before it puts the session into "connecting" itself, when
	# no launch has begun (8c to 8e blocked every Connect here).
	assert(not StreamManager.launch_in_flight(SessionLifecycle.Phase.SERVER_SELECTION, 0, 6000))
	assert(not StreamManager.launch_in_flight(SessionLifecycle.Phase.FAILED, 5000, 6000), "after a failure Connect works again")
	assert(not StreamManager.launch_in_flight(SessionLifecycle.Phase.SERVER_SELECTION, 5000, 6000), "after a disconnect too")
	assert(not StreamManager.launch_in_flight(connecting, 0, 6000), "connecting, but no launch has begun")
	assert(not StreamManager.launch_in_flight(connecting, 5000, 5000 + StreamManager.CONNECT_GUARD_MSEC), "a launch that never answers doesn't keep Connect shut")
	assert(not StreamManager.launch_in_flight(SessionLifecycle.Phase.RECONNECTING, 5000, 6000), "Connect to another PC while a lost stream is being retried")
	# The welcome screen's Connect handler asks before arming its timeout.
	var welcome_source := FileAccess.get_file_as_string("res://src/welcome_screen.gd")
	var asks := welcome_source.find("launch_is_in_flight()")
	var arms := welcome_source.find("main.start_connect_timeout()")
	assert(asks > 0 and arms > asks, "the question comes before the timeout is armed")
	assert(FileAccess.get_file_as_string("res://src/stream_manager.gd").find("func on_pair_pressed():\n\tvar raw_text") > 0, "on_pair_pressed() itself asks nothing")
	# Quick Start stands back when a connection was started by hand meanwhile.
	assert(StreamManager.connection_under_way(SessionLifecycle.Phase.CONNECTING))
	assert(not StreamManager.connection_under_way(SessionLifecycle.Phase.SERVER_SELECTION))
	MenuSchema._IS_FRAME = was

	# Commands: on by default, saved, and its tooltip says what the choice does.
	var settings := AppSettings.new()
	assert(settings.voice_commands, "voice commands are on unless turned off")
	for choice in ["On", "Off"]:
		assert(String(MenuSchema.VOICE_COMMANDS_TIPS[choice]).count("\n") == 1)
		assert(String(MenuSchema.VOICE_COMMANDS_TIPS[choice]).begins_with(choice + ":"), "the current choice comes first")

	# Notices: translated in every language, with the same blanks to fill in,
	# and short enough for the notice panel (1200 x 240, text 36, 30 px sides).
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://steam-frame/i18n/source.json"))
	var blanks := RegEx.create_from_string("%[sd]")
	var checked := 0
	var problems := PackedStringArray()
	for language in Localization.LANGUAGES:
		if language["code"] == "en":
			continue
		Localization.apply(language["code"])
		for entry in source:
			if entry[1] != "notice":
				continue
			var english: String = entry[0]
			var shown := Localization.t(english)
			checked += 1
			if shown == english:
				problems.append("%s: not translated: %s" % [language["code"], english.left(40)])
			var want := blanks.search_all(english).map(func(m): return m.get_string())
			var got := blanks.search_all(shown).map(func(m): return m.get_string())
			if want != got:
				problems.append("%s: blanks differ: %s" % [language["code"], english.left(40)])
			var paragraph := TextParagraph.new()
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.width = 1140.0
			paragraph.add_string(shown, ThemeDB.fallback_font, 36)
			if paragraph.get_line_count() > 4:
				problems.append("%s: more than four lines: %s" % [language["code"], english.left(40)])
	Localization.apply("en")
	assert(checked > 800, "the notices were read: %d" % checked)
	assert(problems.is_empty(), "\n".join(problems))

	# A first start on the Frame: the starting choices agreed 2026-11-17.
	var fresh := AppSettings.new()
	FrameDefaults.apply(fresh, true, true)
	assert(not fresh.bezel_enabled and fresh.ambient_color == 4 and fresh.frame_curve_amount == 0 and not fresh.icon_backdrop)
	assert(fresh.cursor_mode == AppSettings.CURSOR_MODE_HIDDEN and fresh.cursor_follow and not fresh.sleep_when_put_down, "PC Cursor, Cursor Follow: Standard")
	assert(fresh.pointer_steady == 2 and fresh.haptics == 2 and not fresh.keyboard_follows_screen)
	assert(is_equal_approx(fresh.screen_start_distance, 6.0) and is_equal_approx(FrameDefaults.SCREEN_WIDTH, 7.5))
	assert(fresh.host.stream_fps == 90 and fresh.host.ai_3d_speed == 1, "90 a second, AI 3D on")
	assert(fresh.voice_model == 1 and fresh.mic_key_mode == 0, "the larger speech model when it is installed")
	assert(FrameDefaults.voice_choices(true, false) == {"model": 0, "mic_key": 0})
	assert(FrameDefaults.voice_choices(false, false) == {"model": 0, "mic_key": 1}, "no speech model: the Mic key opens Windows dictation")
	# What stays as it was: these are the user's choices too.
	assert(not fresh.passthrough_enabled and fresh.ambient_mode == 0 and fresh.ambient_strength == 50 and fresh.ambient_size == 35)
	assert(fresh.codec_preference == 1 and fresh.frame_link_mode == 0 and fresh.show_pointer_ray and fresh.show_controller_models)
	assert(fresh.frame_foveation == 0 and not fresh.frame_flat_3d and fresh.frame_layer_match_stream and fresh.frame_fast_filter)
	assert(fresh.head_lock == 0 and not fresh.keep_room_position and fresh.voice_commands and fresh.voice_confirm and not fresh.voice_require_prefix)
	assert(not fresh.microphone_enabled and fresh.auto_reconnect_enabled and not fresh.quick_start_enabled and fresh.idle_timeout_min == 0)
	assert(fresh.host.ai_3d_separation_pct == 75 and fresh.host.ai_3d_convergence_pct == 50 and fresh.host.bitrate_idx == -1)
	assert(fresh.frame_depth_model == SettingsController.FRAME_DEPTH_GPU_MODEL and fresh.frame_depth_rate == 0 and fresh.frame_camera_limit == 0)

	# Reset Settings: what the file it writes holds. Everything as on a first
	# start, except the language and the gamepad layout choice.
	var mine := AppSettings.new()
	mine.language = "fr"
	mine.gamepad_layout = 2
	mine.bezel_enabled = true
	mine.haptics = 0
	var reset := AppSettings.new()
	FrameDefaults.apply(reset, true, false)
	FrameDefaults.keep_across_reset(reset, mine)
	assert(reset.language == "fr" and reset.gamepad_layout == 2, "the language and the gamepad layout choice are kept")
	assert(not reset.bezel_enabled and reset.haptics == 2, "the rest is as on a first start")
	var written := ConfigFile.new()
	SettingsPersistence.write_app(written, reset)
	var read_back := AppSettings.new()
	SettingsPersistence.read_app(written, read_back, true, [])
	assert(read_back.language == "fr" and not read_back.bezel_enabled and read_back.haptics == 2 and read_back.cursor_mode == AppSettings.CURSOR_MODE_HIDDEN, "it survives being written and read")
	assert(read_back.menu_spot.is_empty() and read_back.keyboard_spot.is_empty(), "the menu and keyboard go back to the built-in spots")
	# Not by voice, and it asks before doing anything.
	assert("Reset Settings" in VoiceMenu.SKIP)
	assert(SettingsController.RESET_ASK.contains("again") and SettingsController.RESET_CONFIRM_SEC >= 4.0)
	# Saving is off once the defaults are written (the app saves on its way out).
	var state_source := FileAccess.get_file_as_string("res://src/state_manager.gd")
	assert(state_source.contains("func save_state():\n\tif reset_done:\n\t\treturn") and state_source.contains("func save_host_state():\n\tif reset_done:\n\t\treturn"))

	# The AI 3D page suggests Meteor only when the stream doesn't pass
	# through it, and not once the note has been clicked away.
	assert(UIController.frame_ai3d_note(true, true, true, false, false, false, false, true) == UIController.METEOR_HINT)
	assert(UIController.frame_ai3d_note(true, true, true, false, false, false, false, false) == "", "hidden for good")
	assert(UIController.frame_ai3d_note(true, true, true, true, true, false, false, true) == "", "Meteor is there: nothing to suggest")
	assert(UIController.frame_ai3d_note(true, false, true, false, false, false, false, true) == "", "not while nothing is streaming")
	assert(UIController.frame_ai3d_note(true, true, false, false, false, false, false, true) == "", "nor with AI 3D off")

	# And it fits the page's note (1300 wide, text 24) in two lines everywhere.
	var long_notes := PackedStringArray()
	for language in Localization.LANGUAGES:
		Localization.apply(language["code"])
		var paragraph := TextParagraph.new()
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		paragraph.width = 1300.0
		paragraph.add_string(Localization.t(UIController.METEOR_HINT), ThemeDB.fallback_font, 24)
		if paragraph.get_line_count() > 2:
			long_notes.append(language["code"])
		if language["code"] != "en" and Localization.t(UIController.METEOR_HINT) == UIController.METEOR_HINT:
			long_notes.append(language["code"] + " (not translated)")
	Localization.apply("en")
	assert(long_notes.is_empty(), "the Meteor suggestion runs past two lines in: " + ", ".join(long_notes))

	print("test_frame_8b: all passed")
	quit(0)
