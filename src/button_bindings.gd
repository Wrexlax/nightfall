class_name ButtonBindings
extends RefCounted
## Steam Frame controller buttons -> keys / mouse / app actions (pointer mode).
## The Frame controllers have buttons a Quest controller lacks (right X and Y,
## the left d-pad and View); they are bound through the
## /interaction_profiles/valve/frame_controller_valve profile in
## openxr_action_map.tres and only exist on the Frame. Choices are saved in
## user://button_bindings.cfg and changed on the Control tab ("Buttons" rows).

const SAVE_PATH := "user://button_bindings.cfg"
## Named button setups the user saved (one section per profile).
const PROFILES_PATH := "user://button_profiles.cfg"
const PROFILE_NAME_MAX := 20

# id -> [label, keys (Godot keycodes, modifiers first), special, category]
# special: "" = send the keys; otherwise a mouse or app action (see _apply).
const ACTIONS := {
	"none": ["None", [], "", ""],
	# Keys
	"enter": ["Enter", [KEY_ENTER], "", "keys"],
	"escape": ["Escape", [KEY_ESCAPE], "", "keys"],
	"tab": ["Tab", [KEY_TAB], "", "keys"],
	"space": ["Space", [KEY_SPACE], "", "keys"],
	"backspace": ["Backspace", [KEY_BACKSPACE], "", "keys"],
	"delete": ["Delete", [KEY_DELETE], "", "keys"],
	"up": ["Arrow Up", [KEY_UP], "", "keys"],
	"down": ["Arrow Down", [KEY_DOWN], "", "keys"],
	"left": ["Arrow Left", [KEY_LEFT], "", "keys"],
	"right": ["Arrow Right", [KEY_RIGHT], "", "keys"],
	"home": ["Home", [KEY_HOME], "", "keys"],
	"end": ["End", [KEY_END], "", "keys"],
	"pageup": ["Page Up", [KEY_PAGEUP], "", "keys"],
	"pagedown": ["Page Down", [KEY_PAGEDOWN], "", "keys"],
	"shift": ["Shift (hold)", [KEY_SHIFT], "", "keys"],
	"ctrl": ["Ctrl (hold)", [KEY_CTRL], "", "keys"],
	"alt": ["Alt (hold)", [KEY_ALT], "", "keys"],
	# Function keys
	"f1": ["F1", [KEY_F1], "", "fkeys"], "f2": ["F2", [KEY_F2], "", "fkeys"],
	"f3": ["F3", [KEY_F3], "", "fkeys"], "f4": ["F4", [KEY_F4], "", "fkeys"],
	"f5": ["F5", [KEY_F5], "", "fkeys"], "f6": ["F6", [KEY_F6], "", "fkeys"],
	"f7": ["F7", [KEY_F7], "", "fkeys"], "f8": ["F8", [KEY_F8], "", "fkeys"],
	"f9": ["F9", [KEY_F9], "", "fkeys"], "f10": ["F10", [KEY_F10], "", "fkeys"],
	"f11": ["F11 (Fullscreen)", [KEY_F11], "", "fkeys"], "f12": ["F12", [KEY_F12], "", "fkeys"],
	# Windows
	"win": ["Windows Key", [KEY_META], "", "windows"],
	"win_d": ["Show Desktop", [KEY_META, KEY_D], "", "windows"],
	"win_tab": ["Task View", [KEY_META, KEY_TAB], "", "windows"],
	"alt_tab": ["Alt+Tab", [KEY_ALT, KEY_TAB], "", "windows"],
	"win_shift_left": ["Window to Left Monitor", [KEY_META, KEY_SHIFT, KEY_LEFT], "", "windows"],
	"win_shift_right": ["Window to Right Monitor", [KEY_META, KEY_SHIFT, KEY_RIGHT], "", "windows"],
	"win_up": ["Maximise Window", [KEY_META, KEY_UP], "", "windows"],
	"alt_f4": ["Close Window", [KEY_ALT, KEY_F4], "", "windows"],
	"win_shift_s": ["Screenshot (Snip)", [KEY_META, KEY_SHIFT, KEY_S], "", "windows"],
	"win_e": ["File Explorer", [KEY_META, KEY_E], "", "windows"],
	"ctrl_shift_esc": ["Task Manager", [KEY_CTRL, KEY_SHIFT, KEY_ESCAPE], "", "windows"],
	"win_l": ["Lock PC", [KEY_META, KEY_L], "", "windows"],
	# Editing
	"ctrl_c": ["Copy", [KEY_CTRL, KEY_C], "", "editing"],
	"ctrl_v": ["Paste", [KEY_CTRL, KEY_V], "", "editing"],
	"ctrl_x": ["Cut", [KEY_CTRL, KEY_X], "", "editing"],
	"ctrl_z": ["Undo", [KEY_CTRL, KEY_Z], "", "editing"],
	"ctrl_y": ["Redo", [KEY_CTRL, KEY_Y], "", "editing"],
	"ctrl_a": ["Select All", [KEY_CTRL, KEY_A], "", "editing"],
	"ctrl_s": ["Save", [KEY_CTRL, KEY_S], "", "editing"],
	"ctrl_f": ["Find", [KEY_CTRL, KEY_F], "", "editing"],
	"ctrl_t": ["New Tab", [KEY_CTRL, KEY_T], "", "editing"],
	"ctrl_w": ["Close Tab", [KEY_CTRL, KEY_W], "", "editing"],
	# Media
	"play_pause": ["Play/Pause", [KEY_MEDIAPLAY], "", "media"],
	"next_track": ["Next Track", [KEY_MEDIANEXT], "", "media"],
	"prev_track": ["Previous Track", [KEY_MEDIAPREVIOUS], "", "media"],
	"vol_up": ["Volume Up (Headset)", [], "vol_up", "media"],
	"vol_down": ["Volume Down (Headset)", [], "vol_down", "media"],
	"mute": ["Mute (Headset)", [], "mute", "media"],
	# Mouse
	"lclick": ["Left Click", [], "lclick", "mouse"],
	"rclick": ["Right Click", [], "rclick", "mouse"],
	"mclick": ["Middle Click", [], "mclick", "mouse"],
	"dclick": ["Double Click", [], "dclick", "mouse"],
	"scroll_up": ["Scroll Up", [], "scroll_up", "mouse"],
	"scroll_down": ["Scroll Down", [], "scroll_down", "mouse"],
	# Nightfall
	"keyboard": ["Show Keyboard", [], "keyboard", "nightfall"],
	"menu": ["Nightfall Menu", [], "menu", "nightfall"],
	"sbs": ["SBS 3D On/Off", [], "sbs", "nightfall"],
	"ai3d": ["AI 3D On/Off", [], "ai3d", "nightfall"],
	"depthview": ["Depth View On/Off", [], "depthview", "nightfall"],
	"follow": ["Cursor Follow On/Off", [], "follow", "nightfall"],
	"ray": ["Pointer Ray On/Off", [], "ray", "nightfall"],
	"voice": ["Voice Typing (hold)", [], "voice", "nightfall"],
	"recenter": ["Recenter View", [], "recenter", "nightfall"],
	"headlock": ["Head Lock On/Off", [], "headlock", "nightfall"],
	"dictation": ["Windows Dictation (Win+H)", [], "dictation", "desktop"],
	"hidecursor": ["Cursor Off Screen", [], "hidecursor", "mouse"],
}
# Keyboard+Mouse (game) mode: which key each control presses. Ids match
# ControllerMapper's; values are Godot keycodes. [label, default]
const GAME_CONTROLS := {
	"left_up": ["Left Stick Up", KEY_W],
	"left_down": ["Left Stick Down", KEY_S],
	"left_left": ["Left Stick Left", KEY_A],
	"left_right": ["Left Stick Right", KEY_D],
	"left_trigger": ["Left Trigger", KEY_SHIFT],
	"left_grip": ["Left Grip", KEY_CTRL],
	"dpad_up": ["D-pad Up", KEY_1],
	"dpad_right": ["D-pad Right", KEY_2],
	"dpad_down": ["D-pad Down", KEY_3],
	"dpad_left": ["D-pad Left", KEY_4],
	"left_menu": ["View", KEY_ESCAPE],
	"right_a": ["A", KEY_SPACE],
	"right_b": ["B", KEY_R],
	"left_x": ["X", KEY_E],
	"left_y": ["Y", KEY_F],
	"right_menu": ["Menu", KEY_TAB],
	"left_stick_click": ["Left Stick Click", KEY_C],
	"right_stick_click": ["Right Stick Click", KEY_V],
}
const GAME_CONTROL_ORDER := ["left_up", "left_down", "left_left", "left_right", "left_trigger", "left_grip",
	"dpad_up", "dpad_right", "dpad_down", "dpad_left", "left_menu",
	"right_a", "right_b", "left_x", "left_y", "right_menu", "left_stick_click", "right_stick_click"]
var game_keys: Dictionary = {}  # id -> keycode

func game_key(id: String, fallback: int) -> int:
	return int(game_keys.get(id, GAME_CONTROLS[id][1] if GAME_CONTROLS.has(id) else fallback))

func game_key_label(id: String) -> String:
	var k := game_key(id, 0)
	return "None" if k == 0 else OS.get_keycode_string(k)

func set_game_key(id: String, keycode: int) -> void:
	if not GAME_CONTROLS.has(id):
		return
	game_keys[id] = keycode
	save()
	main._log("[GAMEKEYS] %s -> %s" % [GAME_CONTROLS[id][0], game_key_label(id)])

func reset_game_keys() -> void:
	game_keys.clear()
	for id in GAME_CONTROLS:
		game_keys[id] = GAME_CONTROLS[id][1]
	save()

# Gamepad mode, Custom layout: which Xbox button each Frame button presses.
# [label, default Xbox button flag]
# Not real button bits: the analog triggers (LT/RT) as choices in the Custom
# layout. A trigger mapped to LT/RT keeps its analog pull; a button mapped to
# LT/RT pulls it fully.
const PAD_LT := 0x10000
const PAD_RT := 0x20000
const PAD_CONTROLS := {
	"a": ["A", 0x1000], "b": ["B", 0x2000], "x": ["X", 0x4000], "y": ["Y", 0x8000],
	"dpad_up": ["D-pad Up", 0x0001], "dpad_down": ["D-pad Down", 0x0002],
	"dpad_left": ["D-pad Left", 0x0004], "dpad_right": ["D-pad Right", 0x0008],
	"view": ["View", 0x0020], "menu": ["Menu", 0x0010],
	"lgrip": ["Left Grip", 0x0100], "rgrip": ["Right Grip", 0x0200],
	"lbumper": ["Left Bumper", 0x0100], "rbumper": ["Right Bumper", 0x0200],
	"lstick": ["Left Stick Click", 0x0040], "rstick": ["Right Stick Click", 0x0080],
	"ltrigger": ["Left Trigger", PAD_LT], "rtrigger": ["Right Trigger", PAD_RT],
}
const PAD_CONTROL_ORDER := ["a", "b", "x", "y", "dpad_up", "dpad_down", "dpad_left", "dpad_right",
	"view", "menu", "ltrigger", "rtrigger", "lbumper", "rbumper", "lgrip", "rgrip", "lstick", "rstick"]
const PAD_BUTTONS := [["A", 0x1000], ["B", 0x2000], ["X", 0x4000], ["Y", 0x8000],
	["LT", PAD_LT], ["RT", PAD_RT], ["LB", 0x0100], ["RB", 0x0200], ["Back", 0x0020], ["Start", 0x0010],
	["L3", 0x0040], ["R3", 0x0080], ["D-pad Up", 0x0001], ["D-pad Down", 0x0002],
	["D-pad Left", 0x0004], ["D-pad Right", 0x0008], ["None", 0]]
var pad_map: Dictionary = {}  # id -> Xbox flag

func pad_flag(id: String) -> int:
	return int(pad_map.get(id, PAD_CONTROLS[id][1]))

func pad_label(id: String) -> String:
	var f := pad_flag(id)
	for pb in PAD_BUTTONS:
		if pb[1] == f:
			return pb[0]
	return "None"

func set_pad_button(id: String, flag: int) -> void:
	if not PAD_CONTROLS.has(id):
		return
	pad_map[id] = flag
	save()
	main._log("[PADMAP] %s -> %s" % [PAD_CONTROLS[id][0], pad_label(id)])

func reset_pad_map() -> void:
	pad_map.clear()
	for id in PAD_CONTROLS:
		pad_map[id] = PAD_CONTROLS[id][1]
	save()

const CATEGORIES := [["keys", "Keys"], ["fkeys", "F Keys"], ["windows", "Windows"],
	["editing", "Editing"], ["media", "Media"], ["mouse", "Mouse"], ["nightfall", "Nightfall"]]
# Kept for the old cycling buttons.
var ORDER: Array = ACTIONS.keys()

# control id -> [menu label, hand ("left"/"right"), OpenXR action, default]
# Triggers stay left click and grips right click (never rebindable), so the
# pointer can't be locked out. The defaults reproduce Nightfall's own
# behaviour (A keyboard, B menu, right stick click SBS).
const CONTROLS := {
	"a": ["A", "right", "ax_button", "dclick"],
	"b": ["B", "right", "by_button", "escape"],
	"x": ["X", "right", "frame_x", "keyboard"],
	"y": ["Y", "right", "frame_y", "voice"],
	"menu_btn": ["Menu", "right", "menu_button", "menu"],
	"rstick": ["Stick Click", "right", "primary_click", "ctrl"], # hold it and push the stick: Ctrl+scroll zooms
	"rbumper": ["Bumper", "right", "bumper", "rclick"],
	"dpad_up": ["D-pad Up", "left", "dpad_up", "up"],
	"dpad_down": ["D-pad Down", "left", "dpad_down", "down"],
	"dpad_left": ["D-pad Left", "left", "dpad_left", "left"],
	"dpad_right": ["D-pad Right", "left", "dpad_right", "right"],
	"view": ["View", "left", "view_button", "menu"],
	"lstick": ["Stick Click", "left", "primary_click", "ctrl"], # as the right one
	"lbumper": ["Bumper", "left", "bumper", "rclick"],
}
## No button starts with nothing on it (8z): an empty button on a first look
## reads as a broken one. Saved layouts are not touched; Profiles > Default
## and Reset Buttons give these.
const CONTROL_ORDER := ["a", "b", "x", "y", "menu_btn", "rstick", "rbumper",
	"dpad_up", "dpad_down", "dpad_left", "dpad_right", "view", "lstick", "lbumper"]

const MOD_BITS := {KEY_SHIFT: 0x01, KEY_CTRL: 0x02, KEY_ALT: 0x04, KEY_META: 0x08}

var main: Node
# Custom Buttons (Buttons tab). Off: every button does its Default job (the
# layout in CONTROLS) and your own layout is kept for when it's back on.
var enabled := true
var enabled_button: Button
var bindings := {}        # control id -> action id
var buttons := {}         # control id -> menu Button
var _down := {}           # control id -> true while held
var _logged_profile := ""

func _init(main_node: Node) -> void:
	main = main_node
	for c in CONTROLS:
		bindings[c] = CONTROLS[c][3]
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		enabled = cfg.get_value("buttons", "enabled", true)
		current_profile = cfg.get_value("buttons", "_profile", "")
		for c in CONTROLS:
			var a: String = cfg.get_value("buttons", c, bindings[c])
			if ACTIONS.has(a):
				bindings[c] = a
		# One-time move of Y from Nightfall Menu (a copy of the Menu button)
		# to Voice Typing, the new default.
		if not cfg.get_value("buttons", "_voice_default_v1", false):
			if bindings.get("y", "") == "menu":
				bindings["y"] = "voice"
		for id in GAME_CONTROLS:
			game_keys[id] = int(cfg.get_value("game_keys", id, GAME_CONTROLS[id][1]))
		for id in PAD_CONTROLS:
			pad_map[id] = int(cfg.get_value("pad_map", id, PAD_CONTROLS[id][1]))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("buttons", "enabled", enabled)
	cfg.set_value("buttons", "_profile", current_profile)
	cfg.set_value("buttons", "_voice_default_v1", true)
	for c in bindings:
		cfg.set_value("buttons", c, bindings[c])
	for id in game_keys:
		cfg.set_value("game_keys", id, game_keys[id])
	for id in pad_map:
		cfg.set_value("pad_map", id, pad_map[id])
	cfg.save(SAVE_PATH)

func toggle_enabled() -> void:
	_release_all()  # before the buttons change jobs
	enabled = not enabled
	save()
	if enabled_button and main.ui_controller:
		main.ui_controller.update_option_btn(enabled_button, "On" if enabled else "Off")
	main._log("[BUTTONS] custom buttons %s" % ("on" if enabled else "off (Default layout)"))

## What a control does right now: your binding, or the Default layout's while
## Custom Buttons is off.
func active_action(control: String) -> String:
	return bindings[control] if enabled else CONTROLS[control][3]

# --- Profiles -------------------------------------------------------------

var current_profile := ""  # name of the profile last loaded or saved

func profile_names() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILES_PATH) != OK:
		return []
	var names: Array = cfg.get_sections()
	names.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	return names

func has_profile(profile: String) -> bool:
	return profile_names().has(profile)

func save_profile(profile: String) -> void:
	profile = profile.strip_edges().left(PROFILE_NAME_MAX)
	if profile.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(PROFILES_PATH)
	if cfg.has_section(profile):
		cfg.erase_section(profile)
	for c in bindings:
		cfg.set_value(profile, c, bindings[c])
	for id in GAME_CONTROLS:
		cfg.set_value(profile, "game:" + id, game_key(id, 0))
	for id in PAD_CONTROLS:
		cfg.set_value(profile, "pad:" + id, pad_flag(id))
	cfg.set_value(profile, "pad_layout", main.settings.gamepad_layout)
	cfg.save(PROFILES_PATH)
	current_profile = profile
	main._log("[BUTTONS] saved profile '%s'" % profile)

func load_profile(profile: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILES_PATH) != OK or not cfg.has_section(profile):
		return
	_release_all()
	for c in CONTROLS:
		var a: String = cfg.get_value(profile, c, CONTROLS[c][3])
		bindings[c] = a if ACTIONS.has(a) else CONTROLS[c][3]
	for id in GAME_CONTROLS:
		game_keys[id] = int(cfg.get_value(profile, "game:" + id, GAME_CONTROLS[id][1]))
	for id in PAD_CONTROLS:
		pad_map[id] = int(cfg.get_value(profile, "pad:" + id, PAD_CONTROLS[id][1]))
	if cfg.has_section_key(profile, "pad_layout"):
		main.settings.gamepad_layout = clampi(int(cfg.get_value(profile, "pad_layout", 0)), 0, 2)
		main.settings.gamepad_face_swap = main.settings.gamepad_layout == 1
		main.state_manager.save_state()
	save()
	current_profile = profile
	main._log("[BUTTONS] loaded profile '%s'" % profile)

## The built-in profile: Nightfall's own buttons, game keys and gamepad
## layout for the Steam Frame. Always in the list, never saved or deleted.
const DEFAULT_PROFILE := "Default"

func load_default_profile() -> void:
	reset_defaults()
	reset_game_keys()
	reset_pad_map()
	current_profile = DEFAULT_PROFILE
	main._log("[BUTTONS] loaded the default profile")

func delete_profile(profile: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILES_PATH) != OK or not cfg.has_section(profile):
		return
	cfg.erase_section(profile)
	cfg.save(PROFILES_PATH)
	if current_profile == profile:
		current_profile = ""
	main._log("[BUTTONS] deleted profile '%s'" % profile)

func next_profile_name() -> String:
	var names := profile_names()
	var n := names.size() + 1
	while names.has("Profile %d" % n):
		n += 1
	return "Profile %d" % n

func reset_defaults() -> void:
	_release_all()
	for c in CONTROLS:
		bindings[c] = CONTROLS[c][3]
		if buttons.has(c) and main.ui_controller:
			main.ui_controller.update_option_btn(buttons[c], label_for(c))
	save()

func set_binding(control: String, action_id: String) -> void:
	if not CONTROLS.has(control) or not ACTIONS.has(action_id):
		return
	if _down.get(control, false):
		_apply(active_action(control), false)
		_down[control] = false
	bindings[control] = action_id
	save()
	main._log("[BUTTONS] %s %s -> %s" % [CONTROLS[control][1], CONTROLS[control][0], label_for(control)])

func label_for(control: String) -> String:
	return ACTIONS[bindings[control]][0]

func cycle(control: String) -> void:
	var i := ORDER.find(bindings[control])
	bindings[control] = ORDER[(i + 1) % ORDER.size()]
	save()
	if buttons.has(control) and main.ui_controller:
		main.ui_controller.update_option_btn(buttons[control], label_for(control))
	main._log("[BUTTONS] %s -> %s" % [CONTROLS[control][0], label_for(control)])

## Called every frame from main._process_button_input() while XR is active.
# Diagnostics: log every change of every bound OpenXR button on both hands, so
# a log shows which physical Frame button reaches which action.
# The touch entries are temporary (5i, 5j): to see in a log what the Frame
# controllers' touch sensors report while held, and while lying in a lap
# (Sleep When Put Down, ControllerTouch). Remove once that is confirmed.
const _RAW_ACTIONS := ["ax_button", "by_button", "frame_x", "frame_y", "menu_button",
	"view_button", "primary_click", "trigger_click", "grip_click", "bumper",
	"dpad_up", "dpad_down", "dpad_left", "dpad_right",
	"primary_touch", "trigger_touch", "grip_touch"]
var _raw_state := {}
func _log_raw_buttons() -> void:
	for side in ["left", "right"]:
		var hand = main.left_hand if side == "left" else main.right_hand
		if hand == null:
			continue
		for a in _RAW_ACTIONS:
			var key: String = side + ":" + a
			var p: bool = hand.is_button_pressed(a)
			if p != _raw_state.get(key, false):
				_raw_state[key] = p
				main._log("[RAWBTN] %s %s %s" % [side, a, "down" if p else "up"])

func process() -> void:
	_log_raw_buttons()
	if main.controller_mapper and main.controller_mapper.is_active():
		_release_all()
		return
	for c in CONTROLS:
		var hand = main.left_hand if CONTROLS[c][1] == "left" else main.right_hand
		var pressed: bool = hand != null and hand.is_button_pressed(CONTROLS[c][2])
		var was: bool = _down.get(c, false)
		if pressed == was:
			continue
		_down[c] = pressed
		var action_id: String = active_action(c)
		# Keys and mouse only make sense while streaming; menu/keyboard always.
		var special: String = ACTIONS.get(action_id, ACTIONS["none"])[2]
		if not main.is_streaming and special not in ["menu", "keyboard"]:
			continue
		_apply(action_id, pressed)
		if pressed:
			main._log("[BUTTONS] %s %s pressed -> %s" % [CONTROLS[c][1], CONTROLS[c][0], ACTIONS[action_id][0]])
	_post_process()

func _post_process() -> void:
	if main.virtual_keyboard and main.right_hand and not main.right_hand.is_button_pressed("primary_click"):
		main.virtual_keyboard.thumbstick_exit_flag = false

## True while this script owns the face buttons (main skips its own A/B/stick
## handling): always, except in the controller mapping modes.
func owns_buttons() -> bool:
	return not (main.controller_mapper and main.controller_mapper.is_active())

# Spaced out like a real double-click: some Windows apps ignore four mouse
# events that arrive in the same instant (it sometimes didn't register), and
# the cursor should land on the pointer before the first click.
func _double_click() -> void:
	var be = main.stream_backend
	if main.xr_interaction:
		main.xr_interaction.move_host_cursor_to_pointer()
	await main.get_tree().create_timer(0.03).timeout
	be.send_mouse_button_event(7, 1)
	await main.get_tree().create_timer(0.03).timeout
	be.send_mouse_button_event(8, 1)
	await main.get_tree().create_timer(0.06).timeout
	be.send_mouse_button_event(7, 1)
	await main.get_tree().create_timer(0.03).timeout
	be.send_mouse_button_event(8, 1)

func _apply(action_id: String, pressed: bool) -> void:
	var entry: Array = ACTIONS.get(action_id, ACTIONS["none"])
	var special: String = entry[2]
	var be = main.stream_backend
	match special:
		"lclick":
			if pressed and main.xr_interaction:
				main.xr_interaction.move_host_cursor_to_pointer()
			be.send_mouse_button_event(7 if pressed else 8, 1)
			return
		"dclick":
			if pressed:
				_double_click()
			return
		"scroll_up", "scroll_down":
			if pressed:
				be.send_scroll_event(1 if special == "scroll_up" else -1)
			return
		"sbs":
			if pressed:
				var vk = main.virtual_keyboard
				if vk and (vk.trackpad_active or vk.thumbstick_exit_flag):
					return
				main.screen_shortcuts.invoke(ScreenShortcutBar.ACTION_SBS)
			return
		"depthview":
			if pressed:
				main.ui_controller.on_ai_3d_depth_view_toggled()
			return
		"hidecursor":
			if pressed and main.xr_interaction:
				main.xr_interaction.park_host_cursor()
			return
		"ray":
			if pressed:
				main.settings_controller.toggle_pointer_ray()
			return
		"follow":
			if pressed:
				main.settings_controller.toggle_cursor_follow()
			return
		"ai3d":
			if pressed:
				main.auto_detect_enabled = false
				main.settings_controller.toggle_ai_3d_enabled()
			return
		"rclick":
			if pressed and main.xr_interaction:
				main.xr_interaction.move_host_cursor_to_pointer()
			be.send_mouse_button_event(7 if pressed else 8, 3)
			return
		"mclick":
			if pressed and main.xr_interaction:
				main.xr_interaction.move_host_cursor_to_pointer()
			be.send_mouse_button_event(7 if pressed else 8, 2)
			return
		"keyboard":
			if pressed:
				main.screen_shortcuts.invoke(ScreenShortcutBar.ACTION_KEYBOARD)
			_hold_to_view("keyboard", pressed)
			return
		"menu":
			if pressed:
				main.screen_shortcuts.invoke(ScreenShortcutBar.ACTION_MENU)
			_hold_to_view("menu", pressed)
			return
		"recenter":
			if pressed:
				main.recenter_view()
			return
		"headlock":
			if pressed:
				main.settings_controller.switch_head_lock()
			return
		"dictation":
			if pressed:
				main.send_win_chord(KEY_H)
			return
		"voice":
			if main.voice_typing:
				if pressed:
					main.voice_typing.press()
				else:
					main.voice_typing.release()
			return
		"vol_up", "vol_down", "mute":
			if pressed:
				_change_volume(special)
			return
	var keys: Array = entry[1]
	if keys.is_empty():
		return
	var mods := 0
	if pressed:
		for k in keys:
			be.send_keyboard_event(k, 3, mods)
			mods |= MOD_BITS.get(k, 0)
	else:
		for k in keys:
			mods |= MOD_BITS.get(k, 0)
		for idx in range(keys.size() - 1, -1, -1):
			var k = keys[idx]
			mods &= ~MOD_BITS.get(k, 0)
			be.send_keyboard_event(k, 4, mods)

# Holding the Menu or Keyboard button for about 3 s brings that panel right
# in front of your eyes (Steam Frame).
var _hold_gen := {"menu": 0, "keyboard": 0}

func _hold_to_view(which: String, pressed: bool) -> void:
	_hold_gen[which] += 1
	if not pressed or not main.device_is_steam_frame:
		return
	var gen: int = _hold_gen[which]
	await main.get_tree().create_timer(3.0).timeout
	if _hold_gen[which] != gen:
		return # let go before 3 s
	main.buzz(main.xr_interaction._active_hand, 0.6, 0.06)
	if which == "menu":
		main.show_menu_in_view()
	else:
		main.show_keyboard_in_view()

# Stream volume on the headset: the same setting as Stream > Volume.
func _change_volume(what: String) -> void:
	main.settings_controller.step_volume(what)

func _release_all() -> void:
	for c in _down.keys():
		if _down[c]:
			_apply(active_action(c), false)
	_down.clear()
