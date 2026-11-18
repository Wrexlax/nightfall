class_name VirtualKeyboard
extends VRPanelBase

func _init(owner: Node3D):
	super(owner)
	mesh_size = Vector2(1.04, 0.35)
	viewport_size = Vector2i(2080, 700)
var _kb_width := 1640
var _tp_width := 440
var _key_area_width := 1600
const KEY_ROW_UNITS := 15.0
var _kb_root: Control
var _key_data: Array = []
var _held_keys: Dictionary = {}
var _held_keys_secondary: Dictionary = {}
var _primary_hover_key: int = -1
var _secondary_hover_key: int = -1
var _shift_on: bool = false
# Super (Windows key): down while you hold it; a long hold latches it so the
# next key you press becomes Win+that key.
var _super_down: bool = false
var _super_latched: bool = false
var _super_used: bool = false
var _super_down_ms: int = 0
var _mic_down_ms: int = 0
var _mic_toggle_active: bool = false
var _ctrl_on: bool = false
var _alt_on: bool = false
# Steam Frame: Shift, Ctrl and Alt work as on a phone's keyboard.
# One press: down for the next key
# only. A second press: locked, until pressed again. Held down while other
# keys are pressed (two hands): down for as long as it is held. Elsewhere a
# press toggles, as upstream has it.
var _mod_locked := {KEY_SHIFT: false, KEY_CTRL: false, KEY_ALT: false}
# Pressed and not yet let go by the hand that pressed it, and whether a key
# was typed in that time.
var _mod_held := {KEY_SHIFT: false, KEY_CTRL: false, KEY_ALT: false}
var _mod_used_held := {KEY_SHIFT: false, KEY_CTRL: false, KEY_ALT: false}
const MODIFIERS: Array[int] = [KEY_SHIFT, KEY_CTRL, KEY_ALT]
var _caps_on: bool = false

const SHORTCUT_COPY := -100
const SHORTCUT_PASTE := -101
const SHORTCUT_CUT := -102
const SHORTCUT_UNDO := -103
const SHORTCUT_INSERT := -104
const SHORTCUT_SELECT_ALL := -105
const SHORTCUT_ALT_TAB := -106
const SHORTCUT_SHOW_DESKTOP := -107
const SHORTCUT_TASK_MANAGER := -108
const SHORTCUT_CLOSE_WINDOW := -109
const SHORTCUT_SECURITY := -110
const SHORTCUT_TRACKPAD := -111  # not a chord: shows/hides the trackpad
const SHORTCUT_MIC := -112  # not a chord: voice typing or Windows dictation (setting)
const SUPER_LATCH_MS := 450  # holding Super longer than this latches it for the next key

# Steam Frame: the "Expand" key opens an area beside the keys, and tabs along
# its top choose what it holds. Tab keys are PANEL_TAB_BASE, -1, -2...; like
# the Expand key they are never sent to the PC.
const PANEL_TRACKPAD := 0
const PANEL_MEDIA := 3
const PANEL_NAMES := ["Pad", "Arrows", "123", "Media", "Win"]
const PANEL_TAB_BASE := -120
const PANEL_TAB_H := 56
const SHORTCUT_SNAP_LEFT := -130
const SHORTCUT_SNAP_RIGHT := -131
const SHORTCUT_MAXIMIZE := -132
const SHORTCUT_MINIMIZE := -133
const SHORTCUT_MONITOR_LEFT := -134
const SHORTCUT_MONITOR_RIGHT := -135
const SHORTCUT_TASK_VIEW := -136
const SHORTCUT_SCREENSHOT := -137
const SHORTCUT_CLIPBOARD := -138
const SHORTCUT_EMOJI := -139

const SHORTCUT_CHORDS := {
	SHORTCUT_COPY: [KEY_CTRL, KEY_C],
	SHORTCUT_PASTE: [KEY_CTRL, KEY_V],
	SHORTCUT_CUT: [KEY_CTRL, KEY_X],
	SHORTCUT_UNDO: [KEY_CTRL, KEY_Z],
	SHORTCUT_INSERT: [KEY_INSERT],
	SHORTCUT_SELECT_ALL: [KEY_CTRL, KEY_A],
	SHORTCUT_ALT_TAB: [KEY_ALT, KEY_TAB],
	SHORTCUT_SHOW_DESKTOP: [KEY_META, KEY_D],
	SHORTCUT_TASK_MANAGER: [KEY_CTRL, KEY_SHIFT, KEY_ESCAPE],
	SHORTCUT_CLOSE_WINDOW: [KEY_ALT, KEY_F4],
	SHORTCUT_SECURITY: [KEY_CTRL, KEY_ALT, KEY_DELETE],
	SHORTCUT_SNAP_LEFT: [KEY_META, KEY_LEFT],
	SHORTCUT_SNAP_RIGHT: [KEY_META, KEY_RIGHT],
	SHORTCUT_MAXIMIZE: [KEY_META, KEY_UP],
	SHORTCUT_MINIMIZE: [KEY_META, KEY_DOWN],
	SHORTCUT_MONITOR_LEFT: [KEY_META, KEY_SHIFT, KEY_LEFT],
	SHORTCUT_MONITOR_RIGHT: [KEY_META, KEY_SHIFT, KEY_RIGHT],
	SHORTCUT_TASK_VIEW: [KEY_META, KEY_TAB],
	SHORTCUT_SCREENSHOT: [KEY_META, KEY_SHIFT, KEY_S],
	SHORTCUT_CLIPBOARD: [KEY_META, KEY_V],
	SHORTCUT_EMOJI: [KEY_META, KEY_PERIOD],
}

# One entry per panel: [columns, rows, keys]. A key sits at cell "x","y" of
# that grid and covers "w" by "h" cells (one each unless given). The trackpad
# panel has no keys.
# The number pad's digits and point are the main keyboard's: a real number
# pad's turn into arrows when the PC's Num Lock is off (8h, on the headset:
# found confusing).
# The media keys reach Windows as letters when sent down the stream (8h:
# Mute typed "d", Play "g"): the host turns each into a scan code and leaves
# off the "extended" mark that tells a media key from a letter key
# (Vibepollo, src/platform/windows/input.cpp, keyboard_update). So they are
# not sent down the stream: Meteor is asked to press them on the PC
# (MEDIA_KEY_NAMES, StreamManager.press_media_key), and the panel is only
# offered while the stream's Meteor says it can (`media_keys_work`).
const PANEL_KEYS := [
	[],
	[3, 4, [
		{"k": KEY_INSERT, "l": "Ins", "x": 0, "y": 0}, {"k": KEY_HOME, "l": "Home", "x": 1, "y": 0}, {"k": KEY_PAGEUP, "l": "PgUp", "x": 2, "y": 0},
		{"k": KEY_DELETE, "l": "Del", "x": 0, "y": 1}, {"k": KEY_END, "l": "End", "x": 1, "y": 1}, {"k": KEY_PAGEDOWN, "l": "PgDn", "x": 2, "y": 1},
		{"k": KEY_UP, "l": "▲", "x": 1, "y": 2},
		{"k": KEY_LEFT, "l": "◀", "x": 0, "y": 3}, {"k": KEY_DOWN, "l": "▼", "x": 1, "y": 3}, {"k": KEY_RIGHT, "l": "▶", "x": 2, "y": 3},
	]],
	[4, 5, [
		{"k": KEY_EQUAL, "l": "=", "x": 0, "y": 0}, {"k": KEY_KP_DIVIDE, "l": "/", "x": 1, "y": 0}, {"k": KEY_KP_MULTIPLY, "l": "*", "x": 2, "y": 0}, {"k": KEY_KP_SUBTRACT, "l": "-", "x": 3, "y": 0},
		{"k": KEY_7, "l": "7", "x": 0, "y": 1}, {"k": KEY_8, "l": "8", "x": 1, "y": 1}, {"k": KEY_9, "l": "9", "x": 2, "y": 1}, {"k": KEY_KP_ADD, "l": "+", "x": 3, "y": 1, "h": 2},
		{"k": KEY_4, "l": "4", "x": 0, "y": 2}, {"k": KEY_5, "l": "5", "x": 1, "y": 2}, {"k": KEY_6, "l": "6", "x": 2, "y": 2},
		{"k": KEY_1, "l": "1", "x": 0, "y": 3}, {"k": KEY_2, "l": "2", "x": 1, "y": 3}, {"k": KEY_3, "l": "3", "x": 2, "y": 3}, {"k": KEY_KP_ENTER, "l": "Enter", "x": 3, "y": 3, "h": 2},
		{"k": KEY_0, "l": "0", "x": 0, "y": 4, "w": 2}, {"k": KEY_PERIOD, "l": ".", "x": 2, "y": 4},
	]],
	[3, 3, [
		{"k": KEY_MEDIAPREVIOUS, "l": "Prev", "x": 0, "y": 0}, {"k": KEY_MEDIAPLAY, "l": "Play\nPause", "x": 1, "y": 0}, {"k": KEY_MEDIANEXT, "l": "Next", "x": 2, "y": 0},
		{"k": KEY_VOLUMEDOWN, "l": "Vol -", "x": 0, "y": 1}, {"k": KEY_VOLUMEMUTE, "l": "Mute", "x": 1, "y": 1}, {"k": KEY_VOLUMEUP, "l": "Vol +", "x": 2, "y": 1},
		{"k": KEY_MEDIASTOP, "l": "Stop", "x": 0, "y": 2, "w": 3},
	]],
	[2, 5, [
		{"k": SHORTCUT_SNAP_LEFT, "l": "Snap Left", "x": 0, "y": 0}, {"k": SHORTCUT_SNAP_RIGHT, "l": "Snap Right", "x": 1, "y": 0},
		{"k": SHORTCUT_MAXIMIZE, "l": "Maximize", "x": 0, "y": 1}, {"k": SHORTCUT_MINIMIZE, "l": "Minimize", "x": 1, "y": 1},
		{"k": SHORTCUT_MONITOR_LEFT, "l": "◀ Monitor", "x": 0, "y": 2}, {"k": SHORTCUT_MONITOR_RIGHT, "l": "Monitor ▶", "x": 1, "y": 2},
		{"k": SHORTCUT_TASK_VIEW, "l": "Task View", "x": 0, "y": 3}, {"k": SHORTCUT_SCREENSHOT, "l": "Screenshot", "x": 1, "y": 3},
		{"k": SHORTCUT_CLIPBOARD, "l": "Clipboard", "x": 0, "y": 4}, {"k": SHORTCUT_EMOJI, "l": "Emoji", "x": 1, "y": 4},
	]],
]
const MEDIA_KEY_NAMES := {
	KEY_VOLUMEMUTE: "mute", KEY_VOLUMEDOWN: "volume-down", KEY_VOLUMEUP: "volume-up",
	KEY_MEDIANEXT: "next", KEY_MEDIAPREVIOUS: "previous", KEY_MEDIASTOP: "stop", KEY_MEDIAPLAY: "play-pause",
}
# A volume key held down repeats, like a real one: first after
# MEDIA_REPEAT_AFTER_MS, then every MEDIA_REPEAT_EVERY_MS.
const MEDIA_REPEATS := [KEY_VOLUMEDOWN, KEY_VOLUMEUP]
const MEDIA_REPEAT_AFTER_MS := 450
const MEDIA_REPEAT_EVERY_MS := 120
var _media_held := 0
var _media_next_ms := 0
var _mute_lit := false
var _has_panels := false
var _panel := PANEL_TRACKPAD
var media_keys_work := false

var trackpad_active: bool = false
var _trackpad_hand: XRController3D = null
var _last_hand_pos: Vector3 = Vector3.ZERO
var _sensitivity: float = 20000.0
var _dead_zone: float = 0.001
var _tp_border: PanelContainer
var _tp_hint_label: Label = null
var _tp_left_clicking: bool = false
var _tp_right_clicking: bool = false
var _tp_was_stick_click: bool = false
var thumbstick_exit_flag: bool = false

var _KEY_ROWS = [
	[{"k": SHORTCUT_COPY, "l": "Copy", "w": 1.15}, {"k": SHORTCUT_PASTE, "l": "Paste", "w": 1.15}, {"k": SHORTCUT_CUT, "l": "Cut"}, {"k": SHORTCUT_UNDO, "l": "Undo", "w": 1.05}, {"k": SHORTCUT_INSERT, "l": "Ins", "w": 1.05}, {"k": SHORTCUT_SELECT_ALL, "l": "Select All", "w": 1.35}, {"k": SHORTCUT_ALT_TAB, "l": "Alt+Tab", "w": 1.35}, {"k": SHORTCUT_SHOW_DESKTOP, "l": "Win+D", "w": 1.15}, {"k": SHORTCUT_TASK_MANAGER, "l": "Task Mgr", "w": 1.55}, {"k": SHORTCUT_CLOSE_WINDOW, "l": "Alt+F4", "w": 1.25}, {"k": SHORTCUT_SECURITY, "l": "Ctrl+Alt+Del", "w": 1.8}, {"k": SHORTCUT_TRACKPAD, "l": "Trackpad", "w": 1.45}],
	[{"k": KEY_ESCAPE, "l": "Esc", "w": 1.5}, {"k": KEY_F1, "l": "F1"}, {"k": KEY_F2, "l": "F2"}, {"k": KEY_F3, "l": "F3"}, {"k": KEY_F4, "l": "F4"}, {"k": KEY_F5, "l": "F5"}, {"k": KEY_F6, "l": "F6"}, {"k": KEY_F7, "l": "F7"}, {"k": KEY_F8, "l": "F8"}, {"k": KEY_F9, "l": "F9"}, {"k": KEY_F10, "l": "F10"}, {"k": KEY_F11, "l": "F11"}, {"k": KEY_F12, "l": "F12"}, {"k": KEY_DELETE, "l": "Del", "w": 1.5}],
	[{"k": KEY_QUOTELEFT, "l": "`", "s": "~"}, {"k": KEY_1, "l": "1", "s": "!"}, {"k": KEY_2, "l": "2", "s": "@"}, {"k": KEY_3, "l": "3", "s": "#"}, {"k": KEY_4, "l": "4", "s": "$"}, {"k": KEY_5, "l": "5", "s": "%"}, {"k": KEY_6, "l": "6", "s": "^"}, {"k": KEY_7, "l": "7", "s": "&"}, {"k": KEY_8, "l": "8", "s": "*"}, {"k": KEY_9, "l": "9", "s": "("}, {"k": KEY_0, "l": "0", "s": ")"}, {"k": KEY_MINUS, "l": "-", "s": "_"}, {"k": KEY_EQUAL, "l": "=", "s": "+"}, {"k": KEY_BACKSPACE, "l": "Bksp", "w": 2.0}],
	[{"k": KEY_TAB, "l": "Tab", "w": 1.5}, {"k": KEY_Q, "l": "Q"}, {"k": KEY_W, "l": "W"}, {"k": KEY_E, "l": "E"}, {"k": KEY_R, "l": "R"}, {"k": KEY_T, "l": "T"}, {"k": KEY_Y, "l": "Y"}, {"k": KEY_U, "l": "U"}, {"k": KEY_I, "l": "I"}, {"k": KEY_O, "l": "O"}, {"k": KEY_P, "l": "P"}, {"k": KEY_BRACKETLEFT, "l": "[", "s": "{"}, {"k": KEY_BRACKETRIGHT, "l": "]", "s": "}"}, {"k": KEY_BACKSLASH, "l": "\\", "s": "|", "w": 1.5}],
	[{"k": KEY_CAPSLOCK, "l": "Caps", "w": 1.75}, {"k": KEY_A, "l": "A"}, {"k": KEY_S, "l": "S"}, {"k": KEY_D, "l": "D"}, {"k": KEY_F, "l": "F"}, {"k": KEY_G, "l": "G"}, {"k": KEY_H, "l": "H"}, {"k": KEY_J, "l": "J"}, {"k": KEY_K, "l": "K"}, {"k": KEY_L, "l": "L"}, {"k": KEY_SEMICOLON, "l": ";", "s": ":"}, {"k": KEY_APOSTROPHE, "l": "'", "s": "\""}, {"k": KEY_ENTER, "l": "Enter", "w": 2.25}],
	[{"k": KEY_SHIFT, "l": "Shift", "w": 2.25, "mod": "shift"}, {"k": KEY_Z, "l": "Z"}, {"k": KEY_X, "l": "X"}, {"k": KEY_C, "l": "C"}, {"k": KEY_V, "l": "V"}, {"k": KEY_B, "l": "B"}, {"k": KEY_N, "l": "N"}, {"k": KEY_M, "l": "M"}, {"k": KEY_COMMA, "l": ",", "s": "<"}, {"k": KEY_PERIOD, "l": ".", "s": ">"}, {"k": KEY_SLASH, "l": "/", "s": "?"}, {"k": KEY_SHIFT, "l": "Shift", "w": 2.75, "mod": "shift"}],
	[{"k": KEY_CTRL, "l": "Ctrl", "w": 1.5, "mod": "ctrl"}, {"k": KEY_ALT, "l": "Alt", "w": 1.5, "mod": "alt"}, {"k": KEY_META, "l": "Super", "w": 1.5, "mod": "super"}, {"k": KEY_SPACE, "l": "Space", "w": 6.0}, {"k": SHORTCUT_MIC, "l": "Mic", "w": 1.5}, {"k": KEY_ALT, "l": "Alt", "w": 1.5, "mod": "alt"}, {"k": KEY_CTRL, "l": "Ctrl", "w": 1.5, "mod": "ctrl"}],
]

func build():
	_setup_viewport("KBViewport")

	_kb_root = Control.new()
	_kb_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kb_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_kb_root)

	var kb_bg = PanelContainer.new()
	kb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var kb_style = StyleBoxFlat.new()
	kb_style.bg_color = Color(0.04, 0.04, 0.1, 0.85)
	kb_style.set_corner_radius_all(48)
	kb_bg.add_theme_stylebox_override("panel", kb_style)
	kb_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(kb_bg)

	_has_panels = main.device_is_steam_frame
	_build_keys()
	_build_trackpad()
	if _has_panels:
		_build_panels()

	_setup_grab_bar(viewport, 38, -79, -37, 19)
	_setup_mesh("KBPanel")
	_setup_collision()
	_hide_initially()
	_side_from_settings()

func _build_keys():
	var key_h = 72
	var gap = 6
	var start_y = 16
	var base_w = (_key_area_width - 12 - gap * 14) / 15.0
	for row_idx in range(_KEY_ROWS.size()):
		var row = _KEY_ROWS[row_idx]
		var row_units := 0.0
		for key_data in row:
			row_units += float(key_data.get("w", 1.0))
		var row_width_scale := KEY_ROW_UNITS / maxf(row_units, 0.001)
		var x = 26
		var y = start_y + row_idx * (key_h + gap)
		for key_idx in range(row.size()):
			var key_data = row[key_idx]
			var w_unit = float(key_data.get("w", 1.0)) * row_width_scale
			var btn_w = w_unit * base_w + (w_unit - 1.0) * gap
			var btn = Button.new()
			btn.name = "Key_%d_%d" % [row_idx, key_idx]
			btn.position = Vector2(x, y)
			btn.size = Vector2(btn_w, key_h)
			btn.text = key_data["l"]
			if key_data["k"] == SHORTCUT_MIC:
				# Microphone icon instead of the word.
				btn.text = ""
				btn.icon = preload("res://src/assets/screen_shortcuts/mic.svg")
				btn.expand_icon = true
				btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
				btn.add_theme_constant_override("icon_max_width", int(key_h * 0.6))
				btn.add_theme_color_override("icon_normal_color", Color(0.85, 0.85, 0.85, 1.0))
				key_data = key_data.duplicate()
				key_data["l"] = ""
			btn.add_theme_font_size_override("font_size", 24)
			btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
			btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
			var norm = _make_key_style(Color(0.2, 0.2, 0.22, 0.9), Color(0.35, 0.35, 0.38, 1.0))
			btn.add_theme_stylebox_override("normal", norm)
			var hover = _make_key_style(Color(0.3, 0.3, 0.35, 0.95), Color(0.5, 0.5, 0.55, 1.0))
			btn.add_theme_stylebox_override("hover", hover)
			var pressed = _make_key_style(Color(0.45, 0.5, 0.65, 1.0), Color(0.6, 0.65, 0.8, 1.0))
			btn.add_theme_stylebox_override("pressed", pressed)
			_kb_root.add_child(btn)
			_key_data.append({"btn": btn, "key": key_data["k"], "mod": key_data.get("mod", ""), "l": key_data["l"], "s": key_data.get("s", ""), "norm_style": norm, "hover_style": hover, "last_style": norm})
			x += btn_w + gap
	_apply_modifier_visuals()

func _build_trackpad():
	# On the Steam Frame the tabs sit above it (see "Side panels" below).
	var side := _side_area()
	var tp_x = int(side.position.x)
	var tp_visual_w = int(side.size.x)
	var tp_y = int(side.position.y)
	var tp_h = int(side.size.y)

	var tp_bg = PanelContainer.new()
	tp_bg.position = Vector2(tp_x, tp_y)
	tp_bg.size = Vector2(tp_visual_w, tp_h)
	var tp_bg_style = StyleBoxFlat.new()
	tp_bg_style.bg_color = Color(0.05, 0.05, 0.1, 0.7)
	tp_bg_style.set_corner_radius_all(20)
	tp_bg_style.set_border_width_all(2)
	tp_bg_style.border_color = Color(0.25, 0.25, 0.35, 0.4)
	tp_bg.add_theme_stylebox_override("panel", tp_bg_style)
	tp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(tp_bg)

	_tp_border = PanelContainer.new()
	_tp_border.name = "TPBorder"
	_tp_border.position = Vector2(tp_x, tp_y)
	_tp_border.size = Vector2(tp_visual_w, tp_h)
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.set_corner_radius_all(20)
	border_style.set_border_width_all(3)
	border_style.border_color = Color(0.25, 0.25, 0.35, 0.4)
	_tp_border.add_theme_stylebox_override("panel", border_style)
	_tp_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(_tp_border)

	var cx = tp_x + tp_visual_w / 2.0
	var cy = tp_y + tp_h / 2.0

	var title = Label.new()
	title.text = "TRACKPAD"
	title.position = Vector2(tp_x, tp_y + 8)
	title.size = Vector2(tp_visual_w, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(title)

	var arrow_color = Color(0.4, 0.4, 0.5, 0.35)
	var arrow_len = 50

	var up_label = Label.new()
	up_label.text = "▲"
	up_label.position = Vector2(cx - 10, cy - arrow_len - 20)
	up_label.size = Vector2(20, 20)
	up_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	up_label.add_theme_font_size_override("font_size", 22)
	up_label.add_theme_color_override("font_color", arrow_color)
	up_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(up_label)

	var down_label = Label.new()
	down_label.text = "▼"
	down_label.position = Vector2(cx - 10, cy + arrow_len)
	down_label.size = Vector2(20, 20)
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_label.add_theme_font_size_override("font_size", 22)
	down_label.add_theme_color_override("font_color", arrow_color)
	down_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(down_label)

	var left_label = Label.new()
	left_label.text = "◀"
	left_label.position = Vector2(cx - arrow_len - 20, cy - 10)
	left_label.size = Vector2(20, 20)
	left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_label.add_theme_font_size_override("font_size", 22)
	left_label.add_theme_color_override("font_color", arrow_color)
	left_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(left_label)

	var right_label = Label.new()
	right_label.text = "▶"
	right_label.position = Vector2(cx + arrow_len, cy - 10)
	right_label.size = Vector2(20, 20)
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_label.add_theme_font_size_override("font_size", 22)
	right_label.add_theme_color_override("font_color", arrow_color)
	right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(right_label)

	var hint = Label.new()
	hint.text = "Click trigger\nto activate"
	hint.name = "TPHint"
	hint.position = Vector2(tp_x, cy - 16)
	hint.size = Vector2(tp_visual_w, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 0.4))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_tp_node(hint)
	_tp_hint_label = hint

# --- Trackpad show/hide (Steam Frame) ---------------------------------------
# The area beside the keys is rarely needed, so it starts hidden and the
# keyboard is only as wide as its keys; the "Expand" key on the top row shows
# or hides it. (Away from the Steam Frame it is always shown, trackpad only.)
var _tp_nodes: Array = []
var _tp_shown := true
const FULL_VIEWPORT_W := 2080
const FULL_MESH_W := 1.04

func _add_tp_node(n: Node) -> void:
	_kb_root.add_child(n)
	_tp_nodes.append(n)

func set_trackpad_shown(show: bool) -> void:
	if not main.device_is_steam_frame:
		show = true
	if show == _tp_shown and viewport and viewport.size.x == (FULL_VIEWPORT_W if show else _kb_width):
		return
	_tp_shown = show
	if not show:
		_deactivate_trackpad()
	_apply_panel()
	var vp_w: int = FULL_VIEWPORT_W if show else _kb_width
	viewport_size = Vector2i(vp_w, viewport_size.y)
	mesh_size = Vector2(FULL_MESH_W * float(vp_w) / float(FULL_VIEWPORT_W), mesh_size.y)
	if viewport:
		viewport.size = viewport_size
	if mesh_instance and mesh_instance.mesh is QuadMesh:
		(mesh_instance.mesh as QuadMesh).size = mesh_size
	if collision_shape and collision_shape.shape is BoxShape3D:
		(collision_shape.shape as BoxShape3D).size = Vector3(mesh_size.x, mesh_size.y, 0.02)
	if main.composition_panels and main.composition_panels.keyboard_layer:
		main.composition_panels.keyboard_layer.set_quad_size(mesh_size)
	_update_trackpad_key_label()
	if main.device_is_steam_frame and main.settings.keyboard_trackpad != show:
		main.settings.keyboard_trackpad = show
		main.state_manager.save_state()

func _update_trackpad_key_label() -> void:
	for kd in _key_data:
		if kd["key"] == SHORTCUT_TRACKPAD:
			if _has_panels:
				kd["l"] = "Hide" if _tp_shown else "Expand"
			else:
				kd["l"] = "Hide Pad" if _tp_shown else "Trackpad"
			kd["btn"].text = kd["l"]

# --- Side panels (Steam Frame) ----------------------------------------------
static func is_panel_tab(key_code: int) -> bool:
	return key_code <= PANEL_TAB_BASE and key_code > PANEL_TAB_BASE - PANEL_NAMES.size()

# The whole area beside the keys, in keyboard pixels.
func _side_rect() -> Rect2:
	var margin := 26
	var keys_h := _KEY_ROWS.size() * 72 + (_KEY_ROWS.size() - 1) * 6
	return Rect2(_kb_width + margin / 2, 16, _tp_width - margin / 2 - margin, keys_h)

# The part of it a panel may use: everything under the tabs.
func _side_area() -> Rect2:
	var r := _side_rect()
	if not _has_panels:
		return r
	var strip := PANEL_TAB_H + 6
	return Rect2(r.position.x, r.position.y + strip, r.size.x, r.size.y - strip)

static func panel_key_rect(within: Rect2, columns: int, rows: int, key: Dictionary, gap: float = 6.0) -> Rect2:
	var cell := Vector2((within.size.x - gap * (columns - 1)) / columns, (within.size.y - gap * (rows - 1)) / rows)
	var w := int(key.get("w", 1))
	var h := int(key.get("h", 1))
	return Rect2(
		within.position + Vector2(int(key["x"]) * (cell.x + gap), int(key["y"]) * (cell.y + gap)),
		Vector2(cell.x * w + gap * (w - 1), cell.y * h + gap * (h - 1)))

func _add_side_key(rect: Rect2, key_code: int, label: String, font_size: int, extra: Dictionary) -> void:
	var btn := Button.new()
	btn.position = rect.position
	btn.size = rect.size
	btn.text = label
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	var norm := _make_key_style(Color(0.2, 0.2, 0.22, 0.9), Color(0.35, 0.35, 0.38, 1.0))
	var hover := _make_key_style(Color(0.3, 0.3, 0.35, 0.95), Color(0.5, 0.5, 0.55, 1.0))
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", _make_key_style(Color(0.45, 0.5, 0.65, 1.0), Color(0.6, 0.65, 0.8, 1.0)))
	_kb_root.add_child(btn)
	var entry := {"btn": btn, "key": key_code, "mod": "", "l": label, "s": "", "norm_style": norm, "hover_style": hover, "last_style": norm}
	entry.merge(extra)
	_key_data.append(entry)

# The saved choices: whether the area is open and which panel it shows. Read
# each time the keyboard is brought up, because the keyboard is built before
# the saved settings are loaded (8h came back on the trackpad every start).
func _side_from_settings() -> void:
	if _has_panels:
		media_keys_work = _media_keys_offered()
		_panel = clampi(main.settings.keyboard_panel, 0, PANEL_NAMES.size() - 1)
	set_trackpad_shown(main.settings.keyboard_trackpad)
	_apply_panel()

func panel_offered(idx: int) -> bool:
	return idx != PANEL_MEDIA or media_keys_work

func _media_keys_offered() -> bool:
	var streams = main.get("stream_manager")
	return streams != null and streams.meteor_presses_media_keys()

# The Media tab comes and goes with the stream's Meteor while the keyboard
# is up (its answer arrives a moment after a stream starts), the Mute key
# is lit while the PC is muted, and a held volume key repeats.
func _follow_media_keys() -> void:
	if not _has_panels:
		return
	if _media_keys_offered() != media_keys_work:
		media_keys_work = not media_keys_work
		if media_keys_work and main.settings.keyboard_panel == PANEL_MEDIA:
			_panel = PANEL_MEDIA
		else:
			_media_held = 0
		_apply_panel()
	var streams = main.get("stream_manager")
	var muted: bool = media_keys_work and streams != null and streams.pc_muted() == 1
	if muted != _mute_lit:
		_mute_lit = muted
		_apply_mute_lit()
	if _media_held != 0 and Time.get_ticks_msec() >= _media_next_ms:
		_media_next_ms = Time.get_ticks_msec() + MEDIA_REPEAT_EVERY_MS
		_ask_media_key(_media_held)

func _apply_mute_lit() -> void:
	for kd in _key_data:
		if kd.get("panel", -1) == PANEL_MEDIA and kd["key"] == KEY_VOLUMEMUTE:
			var style := _make_key_style(Color(0.35, 0.45, 0.6, 1.0) if _mute_lit else Color(0.2, 0.2, 0.22, 0.9), Color(0.5, 0.6, 0.75, 1.0))
			kd["norm_style"] = style
			kd["last_style"] = style
			kd["btn"].add_theme_stylebox_override("normal", style)

# A media key: Meteor presses it on the PC; nothing goes down the stream.
func _press_media_key(key_code: int) -> void:
	_ask_media_key(key_code)
	if key_code in MEDIA_REPEATS:
		_media_held = key_code
		_media_next_ms = Time.get_ticks_msec() + MEDIA_REPEAT_AFTER_MS

func _ask_media_key(key_code: int) -> void:
	var streams = main.get("stream_manager")
	if streams != null:
		streams.press_media_key(MEDIA_KEY_NAMES[key_code])

func _build_panels() -> void:
	for i in range(PANEL_NAMES.size()):
		_add_side_key(Rect2(), PANEL_TAB_BASE - i, PANEL_NAMES[i], 20, {"tab": i})
	var below := _side_area()
	for i in range(PANEL_KEYS.size()):
		var panel: Array = PANEL_KEYS[i]
		if panel.is_empty():
			continue
		for key in panel[2]:
			_add_side_key(panel_key_rect(below, panel[0], panel[1], key), key["k"], key["l"], 24, {"panel": i})

func set_panel(idx: int) -> void:
	if not _has_panels:
		return
	idx = clampi(idx, 0, PANEL_NAMES.size() - 1)
	if not panel_offered(idx):
		return
	if idx != PANEL_TRACKPAD and trackpad_active:
		_deactivate_trackpad()
	_panel = idx
	_apply_panel()
	if main.settings.keyboard_panel != idx:
		main.settings.keyboard_panel = idx
		main.state_manager.save_state()

# Shows the chosen panel's parts and hides the others'; the tabs share the
# strip between the panels on offer.
func _apply_panel() -> void:
	if not panel_offered(_panel):
		_panel = PANEL_TRACKPAD
	var offered: Array[int] = []
	for i in range(PANEL_NAMES.size()):
		if panel_offered(i):
			offered.append(i)
	var strip := _side_rect()
	strip.size.y = PANEL_TAB_H
	for n in _tp_nodes:
		if is_instance_valid(n):
			n.visible = _tp_shown and _panel == PANEL_TRACKPAD
	for kd in _key_data:
		var btn: Button = kd["btn"]
		if kd.has("panel"):
			btn.visible = _tp_shown and kd["panel"] == _panel
		elif kd.has("tab"):
			var place := offered.find(kd["tab"])
			btn.visible = _tp_shown and place >= 0
			if place >= 0:
				var tab_rect := panel_key_rect(strip, offered.size(), 1, {"x": place, "y": 0})
				btn.position = tab_rect.position
				btn.size = tab_rect.size
			var chosen: bool = kd["tab"] == _panel
			var style := _make_key_style(Color(0.35, 0.45, 0.6, 1.0) if chosen else Color(0.2, 0.2, 0.22, 0.9), Color(0.5, 0.6, 0.75, 1.0))
			kd["norm_style"] = style
			kd["last_style"] = style
			btn.add_theme_stylebox_override("normal", style)

# True where the pointer drives the trackpad and not a key.
func _in_trackpad(pixel_pos: Vector2) -> bool:
	if pixel_pos.x < _kb_width:
		return false
	if not _has_panels:
		return true
	# Only the pad itself: the strip under it used to count too, so a click
	# there started the trackpad (2026-11-18).
	return _panel == PANEL_TRACKPAD and _side_area().has_point(pixel_pos)

# A spot on the keyboard with no key under it (and not the trackpad):
# pulling the trigger there grabs the keyboard, like the menu.
func is_empty_spot(pixel_pos: Vector2) -> bool:
	if pixel_pos.x < 0 or pixel_pos.y < 0 or pixel_pos.x > viewport_size.x or pixel_pos.y > viewport_size.y:
		return false
	if _tp_shown and pixel_pos.x >= _kb_width:
		# Beside the keys. Without panels all of it is the trackpad. With
		# them, only the pad is; around it, and around another panel's keys,
		# the keyboard can be grabbed like anywhere else (the strip under
		# the pad used not to).
		if not _has_panels or _in_trackpad(pixel_pos):
			return false
	for kd in _key_data:
		var btn: Button = kd["btn"]
		if not btn.visible:
			continue
		if Rect2(btn.position - Vector2(3, 3), btn.size + Vector2(6, 6)).has_point(pixel_pos):
			return false
	return true

func reset_to_default() -> void:
	_place_default()
	_save_offset()

func toggle():
	if not visible:
		_side_from_settings()
	super()

func _make_key_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_bg_color(bg)
	s.set_border_width_all(0)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(4)
	return s

func handle_pointer(pixel_pos: Vector2, clicking: bool, was_clicking: bool, hand: XRController3D = null):
	if not visible:
		if _primary_hover_key != -1:
			_primary_hover_key = -1
			_apply_hover_states()
		return

	var new_key = _key_from_pos(pixel_pos)
	if new_key != _primary_hover_key:
		_primary_hover_key = new_key
		_apply_hover_states()
		if new_key != -1:
			main.hover_buzz(main.xr_interaction._active_hand)

	if _in_trackpad(pixel_pos):
		if clicking and not was_clicking and not trackpad_active:
			trackpad_active = true
			_trackpad_hand = hand if hand else main.right_hand
			_last_hand_pos = _trackpad_hand.global_position
			_set_tp_active_visual(true)
			_update_tp_hint()
		return

	var ev_motion = InputEventMouseMotion.new()
	ev_motion.position = pixel_pos
	ev_motion.global_position = pixel_pos
	ev_motion.button_mask = MOUSE_BUTTON_MASK_LEFT if clicking else 0
	viewport.push_input(ev_motion)
	if clicking and not was_clicking:
		var ev = InputEventMouseButton.new()
		ev.position = pixel_pos
		ev.global_position = pixel_pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		viewport.push_input(ev)
		var key_code = _key_from_pos(pixel_pos)
		if key_code != -1:
			_on_key_press(key_code)
	elif not clicking and was_clicking:
		var ev = InputEventMouseButton.new()
		ev.position = pixel_pos
		ev.global_position = pixel_pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = false
		viewport.push_input(ev)
		for kc in _held_keys.keys():
			_on_key_release(kc)
		_held_keys.clear()

func handle_secondary_key(pixel_pos: Vector2, pressed: bool):
	if not visible:
		return
	var ev = InputEventMouseButton.new()
	ev.position = pixel_pos
	ev.global_position = pixel_pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	viewport.push_input(ev)
	if not pressed:
		for kc in _held_keys_secondary.keys():
			if kc in [KEY_META, SHORTCUT_MIC, SHORTCUT_TRACKPAD] or MEDIA_KEY_NAMES.has(kc):
				_on_key_release(kc)
			elif kc in MODIFIERS:
				_release_modifier(kc)
			elif kc != KEY_CAPSLOCK:
				_send_key(kc, 4)
				_modifiers_after_key()
				if _super_latched and _super_used:
					_super_latched = false
					_super_down = false
					_send_key(KEY_META, 4)
					_apply_modifier_visuals()
		_held_keys_secondary.clear()
		return
	if _in_trackpad(pixel_pos):
		return
	var key_code = _key_from_pos(pixel_pos)
	if key_code == -1:
		return
	if is_panel_tab(key_code):
		_on_key_press(key_code)
		return
	if MEDIA_KEY_NAMES.has(key_code):
		_on_key_press(key_code)
		_held_keys.erase(key_code)
		_held_keys_secondary[key_code] = true
		return
	if SHORTCUT_CHORDS.has(key_code):
		_send_shortcut(key_code)
		return
	if key_code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_CAPSLOCK, KEY_META, SHORTCUT_MIC, SHORTCUT_TRACKPAD]:
		_on_key_press(key_code)
		_held_keys.erase(key_code)
		if key_code != KEY_CAPSLOCK:
			_held_keys_secondary[key_code] = true
	else:
		if _super_down or _super_latched:
			_super_used = true
		_send_key(key_code, 3)
		_held_keys_secondary[key_code] = true

func handle_secondary_pointer(pixel_pos: Vector2):
	if not visible:
		if _secondary_hover_key != -1:
			_secondary_hover_key = -1
			_apply_hover_states()
		return
	var new_key = _key_from_pos(pixel_pos)
	if new_key != _secondary_hover_key:
		_secondary_hover_key = new_key
		_apply_hover_states()
		if new_key != -1:
			main.hover_buzz("left" if main.xr_interaction._active_hand == "right" else "right")

func _apply_hover_states():
	for kd in _key_data:
		var key_code = kd["key"]
		var hovered = (key_code == _primary_hover_key or key_code == _secondary_hover_key)
		var use_style = kd["hover_style"] if hovered else kd["norm_style"]
		if kd["last_style"] != use_style:
			kd["last_style"] = use_style
			kd["btn"].add_theme_stylebox_override("normal", use_style)

func _set_tp_active_visual(active: bool):
	var base_color = Color(0.25, 0.25, 0.35, 0.4)
	var active_color = Color(0.3, 0.6, 1.0, 0.9)
	_apply_border_active(_tp_border, active, base_color, active_color)
	_update_tp_hint()

func _update_tp_hint():
	if not _tp_hint_label:
		return
	if trackpad_active:
		_tp_hint_label.text = "Click thumbstick\nto exit"
		_tp_hint_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.8))
	else:
		_tp_hint_label.text = "Click trigger\nto activate"
		_tp_hint_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 0.4))

func _process(_delta):
	if is_visible_in_tree():
		_follow_media_keys()
	if not is_visible_in_tree() or not main.is_streaming:
		if trackpad_active:
			_deactivate_trackpad()
		return

	if not trackpad_active:
		return

	var hand := _trackpad_hand
	if not is_instance_valid(hand):
		_deactivate_trackpad()
		return

	var stick_click = hand.is_button_pressed("primary_click")
	if stick_click and not _tp_was_stick_click:
		_deactivate_trackpad()
		thumbstick_exit_flag = true
		_tp_was_stick_click = stick_click
		return
	_tp_was_stick_click = stick_click

	var trigger = hand.get_float("trigger")
	if trigger > 0.5 and not _tp_left_clicking:
		main.stream_backend.send_mouse_button_event(7, 1)
		_tp_left_clicking = true
	elif trigger <= 0.5 and _tp_left_clicking:
		main.stream_backend.send_mouse_button_event(8, 1)
		_tp_left_clicking = false

	var gripping = hand.is_button_pressed("grip_click") or hand.get_float("grip") > 0.5
	if gripping and not _tp_right_clicking:
		main.stream_backend.send_mouse_button_event(7, 3)
		_tp_right_clicking = true
	elif not gripping and _tp_right_clicking:
		main.stream_backend.send_mouse_button_event(8, 3)
		_tp_right_clicking = false

	var stick_y = hand.get_vector2("primary").y
	if absf(stick_y) > 0.4:
		var clicks = int(stick_y * 0.8)
		if clicks != 0:
			main.stream_backend.send_scroll_event(clicks)

	var hand_pos = hand.global_position
	var delta_3d = hand_pos - _last_hand_pos

	if delta_3d.length() < _dead_zone:
		_last_hand_pos = hand_pos
		return

	var cam_right = main.xr_camera.global_transform.basis.x
	var cam_up = main.xr_camera.global_transform.basis.y

	var dx = delta_3d.dot(cam_right) * _sensitivity
	var dy = -delta_3d.dot(cam_up) * _sensitivity

	var idx = int(dx)
	var idy = int(dy)

	if idx != 0 or idy != 0:
		main.stream_backend.send_mouse_move_event(idx, idy)

	_last_hand_pos = hand_pos

func _deactivate_trackpad():
	trackpad_active = false
	_trackpad_hand = null
	_set_tp_active_visual(false)
	if _tp_left_clicking:
		main.stream_backend.send_mouse_button_event(8, 1)
		_tp_left_clicking = false
	if _tp_right_clicking:
		main.stream_backend.send_mouse_button_event(8, 3)
		_tp_right_clicking = false

func _key_from_pos(pixel_pos: Vector2) -> int:
	for kd in _key_data:
		var btn = kd["btn"]
		if not btn.visible:
			continue
		if pixel_pos.x >= btn.position.x and pixel_pos.x <= btn.position.x + btn.size.x \
			and pixel_pos.y >= btn.position.y and pixel_pos.y <= btn.position.y + btn.size.y:
			return kd["key"]
	return -1

func _send_key(code: int, action: int) -> void:
	var browser: RefCounted = main.get("browser_prototype")
	if main.get("screen_sources") != null:
		browser = main.screen_sources.focused_browser()
	if browser and browser.active:
		browser.key(code, action)
	else:
		main.input_handler.send_stream_key(code, action)

func release_for_focus_loss() -> void:
	_media_held = 0
	for code in _held_keys:
		if int(code) >= 0 and not MEDIA_KEY_NAMES.has(code): _send_key(code, 4)
	for code in _held_keys_secondary:
		if int(code) >= 0 and not MEDIA_KEY_NAMES.has(code): _send_key(code, 4)
	_held_keys.clear()
	_held_keys_secondary.clear()
	_shift_on = false
	_ctrl_on = false
	_alt_on = false
	for key_code in MODIFIERS:
		_mod_locked[key_code] = false
		_mod_held[key_code] = false
	_apply_modifier_visuals()

func _on_key_press(key_code: int):
	if key_code == SHORTCUT_TRACKPAD:
		set_trackpad_shown(not _tp_shown)
		return
	if is_panel_tab(key_code):
		set_panel(PANEL_TAB_BASE - key_code)
		return
	if MEDIA_KEY_NAMES.has(key_code):
		_press_media_key(key_code)
		_held_keys[key_code] = true # for the release, which ends a repeat
		return
	if key_code == SHORTCUT_MIC:
		_mic_press()
		_held_keys[key_code] = true
		return
	if key_code == KEY_META:
		if _super_latched:
			# Pressing Super again cancels the latch.
			_super_latched = false
			_super_down = false
			_send_key(KEY_META, 4)
			_apply_modifier_visuals()
			return
		_super_down = true
		_super_used = false
		_super_down_ms = Time.get_ticks_msec()
		_send_key(KEY_META, 3)
		_held_keys[key_code] = true
		return
	if SHORTCUT_CHORDS.has(key_code):
		_send_shortcut(key_code)
		return
	if key_code in MODIFIERS:
		_press_modifier(key_code)
		return
	if key_code == KEY_CAPSLOCK:
		_caps_on = not _caps_on
		_apply_modifier_visuals()
		_send_key(KEY_CAPSLOCK, 3)
		_send_key(KEY_CAPSLOCK, 4)
		return
	if _super_down or _super_latched:
		_super_used = true
	_send_key(key_code, 3)
	_held_keys[key_code] = true

func _mic_press() -> void:
	if main.settings.mic_key_mode == 1:
		main.send_win_chord(KEY_H)
		return
	var vt = main.voice_typing
	if vt == null:
		return
	if _mic_toggle_active and vt.is_recording():
		# Second tap: stop and type.
		_mic_toggle_active = false
		vt.release()
		return
	_mic_toggle_active = false
	_mic_down_ms = Time.get_ticks_msec()
	vt.press(true)

func _mic_release() -> void:
	if main.settings.mic_key_mode == 1 or main.voice_typing == null or _mic_down_ms == 0:
		return
	var held := Time.get_ticks_msec() - _mic_down_ms
	_mic_down_ms = 0
	if not main.voice_typing.is_recording():
		return
	if held >= SUPER_LATCH_MS:
		main.voice_typing.release() # held while talking: type now
	else:
		_mic_toggle_active = true # quick tap: keep listening until the next tap

func _super_release() -> void:
	if not _super_down or _super_latched:
		return
	var held := Time.get_ticks_msec() - _super_down_ms
	if _super_used or held < SUPER_LATCH_MS:
		_super_down = false
		_send_key(KEY_META, 4)
		return
	_super_latched = true
	_apply_modifier_visuals()

func _send_shortcut(shortcut_code: int) -> void:
	var chord: Array = SHORTCUT_CHORDS.get(shortcut_code, [])
	if chord.is_empty():
		return
	var pressed_here: Array[int] = []
	for key_code in chord:
		if _modifier_is_latched(key_code):
			continue
		_send_key(key_code, 3)
		pressed_here.append(key_code)
	for i in range(pressed_here.size() - 1, -1, -1):
		_send_key(pressed_here[i], 4)
	_modifiers_after_key()

func _set_modifier(key_code: int, on: bool) -> void:
	match key_code:
		KEY_SHIFT: _shift_on = on
		KEY_CTRL: _ctrl_on = on
		KEY_ALT: _alt_on = on

## Shift, Ctrl or Alt was pressed.
func _press_modifier(key_code: int) -> void:
	var on := _modifier_is_latched(key_code)
	if not _has_panels:
		# Not the Steam Frame's keyboard (see build()): every press toggles,
		# as upstream has it.
		_set_modifier(key_code, not on)
		_send_key(key_code, 4 if on else 3)
		if not on:
			_held_keys[key_code] = true
	elif not on:
		# For the next key.
		_set_modifier(key_code, true)
		_mod_locked[key_code] = false
		_mod_held[key_code] = true
		_mod_used_held[key_code] = false
		_send_key(key_code, 3)
		_held_keys[key_code] = true
	elif not _mod_locked[key_code]:
		_mod_locked[key_code] = true
	else:
		_mod_locked[key_code] = false
		_mod_held[key_code] = false
		_set_modifier(key_code, false)
		_send_key(key_code, 4)
	_apply_modifier_visuals()

## The hand that pressed Shift, Ctrl or Alt let go of it. If keys were typed
## while it was held, it was used the way a real one is, and goes up.
func _release_modifier(key_code: int) -> void:
	if not _mod_held.get(key_code, false):
		return
	_mod_held[key_code] = false
	if _mod_used_held[key_code] and not _mod_locked[key_code] and _modifier_is_latched(key_code):
		_set_modifier(key_code, false)
		_send_key(key_code, 4)
		_apply_modifier_visuals()

## A key has been typed: modifiers that were down for one key go up. Locked
## ones stay, and so does one that is still being held.
func _modifiers_after_key() -> void:
	if not _has_panels:
		return
	var changed := false
	for key_code in MODIFIERS:
		if not _modifier_is_latched(key_code) or _mod_locked[key_code]:
			continue
		if _mod_held[key_code]:
			_mod_used_held[key_code] = true
			continue
		_set_modifier(key_code, false)
		_send_key(key_code, 4)
		changed = true
	if changed:
		_apply_modifier_visuals()

func _modifier_is_latched(key_code: int) -> bool:
	match key_code:
		KEY_SHIFT:
			return _shift_on
		KEY_CTRL:
			return _ctrl_on
		KEY_ALT:
			return _alt_on
	return false

func _on_key_release(key_code: int):
	if key_code == KEY_SHIFT or key_code == KEY_CTRL or key_code == KEY_ALT:
		_release_modifier(key_code)
		return
	if MEDIA_KEY_NAMES.has(key_code):
		_media_held = 0
		return
	if key_code == SHORTCUT_MIC:
		_mic_release()
		return
	if key_code == SHORTCUT_TRACKPAD:
		return
	if key_code == KEY_META:
		_super_release()
		return
	_send_key(key_code, 4)
	_modifiers_after_key()
	if _super_latched and _super_used:
		# The latched chord is done: let go of Super.
		_super_latched = false
		_super_down = false
		_send_key(KEY_META, 4)
		_apply_modifier_visuals()

func _apply_modifier_visuals():
	for kd in _key_data:
		var btn = kd["btn"]
		var mod = kd["mod"]
		var is_on = false
		if mod == "shift":
			is_on = _shift_on
		elif mod == "ctrl":
			is_on = _ctrl_on
		elif mod == "alt":
			is_on = _alt_on
		elif mod == "super":
			is_on = _super_latched
		elif kd["key"] == KEY_CAPSLOCK:
			is_on = _caps_on
		else:
			continue
		var bg = Color(0.35, 0.45, 0.6, 1.0) if is_on else Color(0.2, 0.2, 0.22, 0.9)
		var border = Color(0.5, 0.6, 0.75, 1.0) if is_on else Color(0.35, 0.35, 0.38, 1.0)
		var locked: bool = is_on and _mod_locked.get(kd["key"], false)
		if locked:
			bg = Color(0.3, 0.55, 0.9, 1.0)
		var style = _make_key_style(bg, border)
		if locked:
			# Locked: brighter, with a white edge (key styles have none).
			style.set_border_width_all(3)
			style.border_color = Color(1.0, 1.0, 1.0, 1.0)
		kd["norm_style"] = style
		btn.add_theme_stylebox_override("normal", style)
	var shifted = _shift_on or _caps_on
	for kd in _key_data:
		var shift_label = kd.get("s", "")
		if shift_label == "":
			continue
		var btn = kd["btn"]
		btn.text = shift_label if shifted else kd["l"]

func _place_default():
	var cam_pos = main.xr_camera.global_position
	if main.device_is_steam_frame and main.apply_spot(self, main.settings.keyboard_spot):
		return
	if main.device_is_steam_frame:
		main.apply_spot(self, main.FRAME_KEYBOARD_SPOT)
		return
	var offset = Vector3(0, -0.7, 0.6)
	global_position = main.primary_screen.global_position + main.primary_screen.global_transform.basis * offset
	var to_cam = (cam_pos - global_position).normalized()
	rotation.y = atan2(to_cam.x, to_cam.z)
	rotation.x = -PI / 4.0

func _on_hide():
	_save_offset()
	_deactivate_trackpad()
	_media_held = 0
