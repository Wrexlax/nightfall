class_name ControllerMapper
extends Node

enum CtrlType { GAMEPAD, PAD_ABXY, KBMOUSE }
enum BtnToggle { HEAD, TILT, NONE }
enum PrimaryHand { RIGHT, LEFT, AUTO }

var btn_toggle: int = BtnToggle.TILT
var btn_toggle_labels: Array = ["Head", "Tilt", "None"]

var primary_hand: int = PrimaryHand.AUTO
var hand_policy = preload("res://src/controller_hand_policy.gd").new()
var primary_labels: Array = ["Right", "Left", "Auto"]

var main: Node3D
var active: bool = false
var ctrl_type: int = CtrlType.GAMEPAD
# PAD-HAND (GAMEPAD): face buttons split by hand - left hand's two buttons
# are the d-pad (swapped by alt), right hand's two are A/B (swapped to X/Y
# by alt). PAD-ABXY: face buttons always map to their real Xbox letter
# (left=X/Y, right=A/B); alt turns that HAND's two buttons into d-pad
# directions instead (b=left, a=right, y=up, x=down - see
# _send_gamepad_mode()'s abxy_layout branch). Both share is_gamepad_mode()/
# _send_gamepad_mode() below - only the four-face-button mapping differs.
var type_labels: Array = ["Gamepad (Hand)", "Gamepad (ABXY)", "Keyboard+Mouse"]

var _active_key_dirs: Dictionary = {}
var _prev_button_flags: int = 0
var _prev_lt: int = 0
var _prev_rt: int = 0
var _prev_lx: int = 0
var _prev_ly: int = 0
var _prev_rx: int = 0
var _prev_ry: int = 0
var _was_both_sticks: bool = false
var _close_to_head: bool = false
var _close_dist: float = 0.25
var _poll_timer: float = 0.0

var _KBM_DEFAULT = {
	"left_up": KEY_W,
	"left_down": KEY_S,
	"left_left": KEY_A,
	"left_right": KEY_D,
	"right_a": KEY_SPACE,
	"right_b": KEY_R,
	"left_x": KEY_E,
	"left_y": KEY_F,
	"left_trigger": KEY_SHIFT,
	"left_grip": KEY_CTRL,
	"left_menu": KEY_ESCAPE,
	"right_menu": KEY_TAB,
}

var _kbm_profile: Dictionary = {}
var _kb_held: Dictionary = {}

func _init(owner: Node3D):
	main = owner
	_kbm_profile = _KBM_DEFAULT.duplicate()

func write_settings(config: ConfigFile) -> void:
	config.set_value("controller", "active", active)
	config.set_value("controller", "ctrl_type", ctrl_type)
	config.set_value("controller", "btn_toggle", btn_toggle)
	config.set_value("controller", "primary_hand", primary_hand)

func read_settings(config: ConfigFile) -> void:
	if config.has_section_key("controller", "active"):
		active = config.get_value("controller", "active", false)
		ctrl_type = clampi(config.get_value("controller", "ctrl_type", CtrlType.GAMEPAD), 0, 2)
	else:
		# Preserve the legacy mapping exactly: 0=off, 1=PAD-ABXY, 2=PAD-HAND.
		var old_mode := clampi(config.get_value("controller", "mode", 0), 0, 2)
		active = old_mode != 0
		if active:
			ctrl_type = CtrlType.PAD_ABXY if old_mode == 1 else CtrlType.GAMEPAD
	# Steam Frame: Game Controller mode is turned on for a game, not kept: if it
	# came back on at launch, the VR cursor, clicks and custom buttons all
	# seemed broken. Always start with it off.
	if OS.get_name() == "Linux" and Engine.get_architecture_name() == "arm64":
		active = false
	btn_toggle = clampi(config.get_value("controller", "btn_toggle", BtnToggle.TILT), 0, 2)
	primary_hand = clampi(config.get_value("controller", "primary_hand", PrimaryHand.AUTO), 0, 2)

func _process(_delta):
	var handover = main.get("pcvr_handover")
	if handover != null and handover.blocks_workspace():
		release_for_focus_loss()
		return
	var focused_browser = main.screen_sources.focused_browser() if main.get("screen_sources") != null else main.browser_prototype
	var browser_pad: bool = focused_browser != null and focused_browser.active and is_gamepad_mode()
	if main.browser_prototype and (not active or not browser_pad or main.ui_visible or main.virtual_keyboard.visible):
		var browser = main.browser_prototype
		if main.get("screen_sources") != null: browser = main.screen_sources.focused_browser()
		browser.clear_gamepad()
	if (not main.is_streaming and not browser_pad) or not main.is_xr_active or not active \
			or (browser_pad and (main.ui_visible or main.virtual_keyboard.visible)):
		if _kb_held.size() > 0:
			for kc in _kb_held.keys():
				main.stream_backend.send_keyboard_event(kc, 4, 0)
			_kb_held.clear()
		return

	_poll_timer += _delta

	if is_gamepad_mode():
		_send_gamepad_mode(ctrl_type == CtrlType.PAD_ABXY)
	elif ctrl_type == CtrlType.KBMOUSE:
		_send_kbm_mode()

# True for either PAD-HAND or PAD-ABXY - both drive InputHandler.send_pad_state
# via the shared _send_gamepad_mode() below and need the same UI/interaction
# gating (laser pointer disabled, "PAD" status indicator, etc.) elsewhere in
# the codebase - see xr_interaction.gd/main.gd/stream_manager.gd's callers.
func is_gamepad_mode() -> bool:
	return ctrl_type == CtrlType.GAMEPAD or ctrl_type == CtrlType.PAD_ABXY

func check_toggle():
	if not main.is_xr_active:
		return
	var l_click = false
	var r_click = false
	if main.left_hand:
		l_click = main.left_hand.is_button_pressed("primary_click")
	if main.right_hand:
		r_click = main.right_hand.is_button_pressed("primary_click")
	var both = l_click and r_click
	if both and not _was_both_sticks:
		main.screen_shortcuts.invoke(ScreenShortcutBar.ACTION_PAD)
	_was_both_sticks = both

func check_toggle_ui():
	if active:
		_deactivate()
	else:
		_activate()
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()

# The trigger pull (or button press) that turned a mode on must not reach
# the game: everything stays neutral until the controls are let go once.
var _hold_until_release := false
var _custom_pad_done := false

func _controls_released() -> bool:
	for h in [main.left_hand, main.right_hand]:
		if not h:
			continue
		if h.get_float("trigger") > 0.1 or h.get_float("grip") > 0.2:
			return false
		for b in ["ax_button", "by_button", "frame_x", "frame_y", "menu_button", "primary_click", "bumper"]:
			if h.is_button_pressed(b):
				return false
	return true

func _activate():
	active = true
	_hold_until_release = true
	if main.device_is_steam_frame and main.comp and main.comp.has_method("show_notice"):
		var what := "Keyboard+Mouse" if ctrl_type == 2 else "Gamepad"
		main.comp.show_notice(Localization.t("%s mode on - the VR cursor and custom buttons are off.\nGame not reacting? Alt+Tab to it. To get the cursor back, turn Game Controller off (menu or grab-bar gamepad button).") % what, 7.0)
	if is_gamepad_mode():
		_prev_button_flags = -1
		_prev_lt = -1
		_prev_rt = -1
		_prev_lx = -1
		_prev_ly = -1
		_prev_rx = -1
		_prev_ry = -1
		_poll_timer = 1.0
	_log("[CTRL] Activated: " + type_labels[ctrl_type])
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()
		main.ui_controller.update_ctrl_type_btn()

func release_for_focus_loss() -> void:
	for code in _kb_held: main.stream_backend.send_keyboard_event(code, 4, 0)
	_kb_held.clear()
	_active_key_dirs.clear()
	_prev_button_flags = -1 # Force current pad state to be sent after focus returns.

func _deactivate():
	for kc in _kb_held.keys():
		main.stream_backend.send_keyboard_event(kc, 4, 0)
	_kb_held.clear()
	_active_key_dirs.clear()
	_prev_button_flags = 0
	_prev_lt = 0
	_prev_rt = 0
	_prev_lx = 0
	_prev_ly = 0
	_prev_rx = 0
	_prev_ry = 0
	if main.is_streaming:
		main.input_handler.neutral_pad_state(GamepadSlots.QUEST_PAD)
	active = false
	_log("[CTRL] Deactivated")
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()

func cycle_type():
	ctrl_type = (ctrl_type + 1) % 3
	# On the Steam Frame both gamepad layouts are the same 1:1 mapping, so skip
	# the duplicate entry: Gamepad <-> Keyboard+Mouse.
	if main.device_is_steam_frame and ctrl_type == CtrlType.GAMEPAD + 1:
		ctrl_type = 2
	if active:
		_hold_until_release = true
		_deactivate_silent()
		if is_gamepad_mode():
			_prev_button_flags = -1
			_prev_lt = -1
			_prev_rt = -1
			_prev_lx = -1
			_prev_ly = -1
			_prev_rx = -1
			_prev_ry = -1
			_poll_timer = 1.0
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()
		main.ui_controller.update_ctrl_type_btn()
	_log("[CTRL] Type: " + type_labels[ctrl_type])

func _deactivate_silent():
	for kc in _kb_held.keys():
		main.stream_backend.send_keyboard_event(kc, 4, 0)
	_kb_held.clear()
	_active_key_dirs.clear()
	_prev_button_flags = 0
	_prev_lt = 0
	_prev_rt = 0
	_prev_lx = 0
	_prev_ly = 0
	_prev_rx = 0
	_prev_ry = 0
	if main.is_streaming:
		main.input_handler.neutral_pad_state(GamepadSlots.QUEST_PAD)

func _log(msg: String):
	if main and main.has_method("_log"):
		main._log(msg)

# abxy_layout=false: PAD-HAND (left hand = d-pad/swaps to X/Y under alt,
# right hand = A/B/swaps to d-pad under alt - the original single "PAD" mode).
# abxy_layout=true: PAD-ABXY (each hand's two buttons always map to their
# real Xbox letter; that hand's own alt state turns THAT hand's pair into
# d-pad directions instead - b=left, a=right, y=up, x=down, per-hand
# independent exactly like PAD-HAND's alt, just a different base mapping).
# Bit values below are moonlight-common-c's standard XInput-style button
# flags (0x0001/2/4/8 = d-pad up/down/left/right, 0x1000/2000/4000/8000 =
# A/B/X/Y).
func _send_gamepad_mode(abxy_layout: bool):
	var head_pos = main.xr_camera.global_position
	var left_pos = main.left_hand.global_position if main.left_hand else Vector3.ZERO
	var right_pos = main.right_hand.global_position if main.right_hand else Vector3.ZERO

	var left_alt = false
	var right_alt = false
	if btn_toggle == BtnToggle.HEAD:
		_close_to_head = left_pos.distance_to(head_pos) < _close_dist or right_pos.distance_to(head_pos) < _close_dist
		left_alt = left_pos.distance_to(head_pos) < _close_dist
		right_alt = right_pos.distance_to(head_pos) < _close_dist
	elif btn_toggle == BtnToggle.TILT:
		if main.left_hand:
			var left_roll = atan2(-main.left_hand.global_basis.x.y, main.left_hand.global_basis.x.x)
			left_alt = left_roll > 0.5
		if main.right_hand:
			var right_roll = atan2(-main.right_hand.global_basis.x.y, main.right_hand.global_basis.x.x)
			right_alt = right_roll < -0.5
		_close_to_head = left_alt or right_alt

	var button_flags: int = 0

	var lv = main.left_hand.get_vector2("primary") if main.left_hand else Vector2.ZERO
	var rv = main.right_hand.get_vector2("primary") if main.right_hand else Vector2.ZERO
	# Steam Frame: while a grab is held, that hand's stick sets the distance.
	if main.xr_interaction and main.xr_interaction.grab_owns_stick("left"):
		lv = Vector2.ZERO
	if main.xr_interaction and main.xr_interaction.grab_owns_stick("right"):
		rv = Vector2.ZERO

	var lt_val = main.left_hand.get_float("trigger") if main.left_hand else 0.0
	var rt_val = main.right_hand.get_float("trigger") if main.right_hand else 0.0
	var lg_val = main.left_hand.get_float("grip") if main.left_hand else 0.0
	var rg_val = main.right_hand.get_float("grip") if main.right_hand else 0.0

	var left_a = main.left_hand.is_button_pressed("ax_button") if main.left_hand else false
	var left_b = main.left_hand.is_button_pressed("by_button") if main.left_hand else false
	var right_a = main.right_hand.is_button_pressed("ax_button") if main.right_hand else false
	var right_b = main.right_hand.is_button_pressed("by_button") if main.right_hand else false
	var left_menu = main.left_hand.is_button_pressed("menu_button") if main.left_hand else false
	var right_menu = main.right_hand.is_button_pressed("menu_button") if main.right_hand else false
	var l_click = main.left_hand.is_button_pressed("primary_click") if main.left_hand else false
	var r_click = main.right_hand.is_button_pressed("primary_click") if main.right_hand else false

	if main.device_is_steam_frame:
		# Steam Frame: its controllers already have a full gamepad's buttons, so
		# map them 1:1 instead of the Quest's split-by-hand layouts (no alt layer):
		# right A/B/X/Y, left d-pad, View = Back, right Menu = Start, the
		# bumpers and the grips = LB/RB (the grips did that job alone until
		# the bumpers were bound in 6f, and keep doing it), stick clicks = L3/R3.
		var rh = main.right_hand
		var lh = main.left_hand
		if rh and rh.is_button_pressed("ax_button"): button_flags |= 0x1000
		if rh and rh.is_button_pressed("by_button"): button_flags |= 0x2000
		if rh and rh.is_button_pressed("frame_x"): button_flags |= 0x4000
		if rh and rh.is_button_pressed("frame_y"): button_flags |= 0x8000
		if lh and lh.is_button_pressed("dpad_up"): button_flags |= 0x0001
		if lh and lh.is_button_pressed("dpad_down"): button_flags |= 0x0002
		if lh and lh.is_button_pressed("dpad_left"): button_flags |= 0x0004
		if lh and lh.is_button_pressed("dpad_right"): button_flags |= 0x0008
		if lh and lh.is_button_pressed("view_button"): button_flags |= 0x0020
		if main.settings.gamepad_layout == 2 and main.button_bindings:
			# Custom layout: every button is looked up in the Buttons tab's
			# Gamepad Layout (grips, Menu and stick clicks included).
			var bb = main.button_bindings
			var pressed := {
				"a": rh and rh.is_button_pressed("ax_button"), "b": rh and rh.is_button_pressed("by_button"),
				"x": rh and rh.is_button_pressed("frame_x"), "y": rh and rh.is_button_pressed("frame_y"),
				"dpad_up": lh and lh.is_button_pressed("dpad_up"), "dpad_down": lh and lh.is_button_pressed("dpad_down"),
				"dpad_left": lh and lh.is_button_pressed("dpad_left"), "dpad_right": lh and lh.is_button_pressed("dpad_right"),
				"view": lh and lh.is_button_pressed("view_button"), "menu": right_menu,
				"lgrip": lg_val > 0.5, "rgrip": rg_val > 0.5, "lstick": l_click, "rstick": r_click,
				"lbumper": lh and lh.is_button_pressed("bumper"), "rbumper": rh and rh.is_button_pressed("bumper"),
			}
			button_flags = 0
			for id in pressed:
				if pressed[id]:
					button_flags |= bb.pad_flag(id)
			# Triggers: mapped to LT/RT they keep their analog pull; mapped to
			# a button they press it past half way. Any button mapped to LT/RT
			# pulls that trigger fully.
			var lt_out := 0.0
			var rt_out := 0.0
			for pair in [["ltrigger", lt_val], ["rtrigger", rt_val]]:
				var f: int = bb.pad_flag(pair[0])
				var v: float = pair[1]
				if f == bb.PAD_LT:
					lt_out = maxf(lt_out, v)
				elif f == bb.PAD_RT:
					rt_out = maxf(rt_out, v)
				elif v > 0.5:
					button_flags |= f
			if button_flags & bb.PAD_LT:
				lt_out = 1.0
			if button_flags & bb.PAD_RT:
				rt_out = 1.0
			button_flags &= 0xFFFF
			lt_val = lt_out
			rt_val = rt_out
			_custom_pad_done = true
		elif main.settings.gamepad_layout == 1 or main.settings.gamepad_face_swap:
			var a := button_flags & 0x1000
			var b := button_flags & 0x2000
			var x := button_flags & 0x4000
			var y := button_flags & 0x8000
			button_flags &= ~0xF000
			if a: button_flags |= 0x2000
			if b: button_flags |= 0x1000
			if x: button_flags |= 0x8000
			if y: button_flags |= 0x4000
		left_menu = false
		_close_to_head = false
	elif abxy_layout:
		# left_a/left_b are physically X/Y; right_a/right_b are physically A/B
		# (see the ax_button/by_button reads above - same "_a"/"_b" naming as
		# PAD-HAND, just interpreted differently here).
		if left_alt:
			if left_a: button_flags |= 0x0002 # X -> DOWN
			if left_b: button_flags |= 0x0001 # Y -> UP
		else:
			if left_a: button_flags |= 0x4000 # X -> X
			if left_b: button_flags |= 0x8000 # Y -> Y

		if right_alt:
			if right_a: button_flags |= 0x0008 # A -> RIGHT
			if right_b: button_flags |= 0x0004 # B -> LEFT
		else:
			if right_a: button_flags |= 0x1000 # A -> A
			if right_b: button_flags |= 0x2000 # B -> B
	else:
		if left_alt:
			if left_a: button_flags |= 0x0002
			if left_b: button_flags |= 0x0001
		else:
			if left_a: button_flags |= 0x0004
			if left_b: button_flags |= 0x0008

		if right_alt:
			if right_a: button_flags |= 0x4000
			if right_b: button_flags |= 0x8000
		else:
			if right_a: button_flags |= 0x1000
			if right_b: button_flags |= 0x2000

	if not _custom_pad_done:
		if lg_val > 0.5: button_flags |= 0x0100
		if rg_val > 0.5: button_flags |= 0x0200
		if main.device_is_steam_frame:
			# The Frame's own bumpers (bound since 6f) press LB/RB as well.
			if main.left_hand and main.left_hand.is_button_pressed("bumper"): button_flags |= 0x0100
			if main.right_hand and main.right_hand.is_button_pressed("bumper"): button_flags |= 0x0200
		if left_menu: button_flags |= 0x0020
		if right_menu: button_flags |= 0x0010
		if l_click: button_flags |= 0x0040
		if r_click: button_flags |= 0x0080
	_custom_pad_done = false

	var lt = int(clampf(lt_val, 0.0, 1.0) * 255.0)
	var rt = int(clampf(rt_val, 0.0, 1.0) * 255.0)
	if main.xr_interaction and main.xr_interaction.pointer_on_ui:
		rt = 0
	if _hold_until_release:
		if _controls_released():
			_hold_until_release = false
		else:
			button_flags = 0
			lt = 0
			rt = 0
	var lx = int(clampf(lv.x, -1.0, 1.0) * 32767.0)
	var ly = int(clampf(lv.y, -1.0, 1.0) * 32767.0)
	var rx = int(clampf(rv.x, -1.0, 1.0) * 32767.0)
	var ry = int(clampf(rv.y, -1.0, 1.0) * 32767.0)

	var changed = button_flags != _prev_button_flags or lt != _prev_lt or rt != _prev_rt \
		or lx != _prev_lx or ly != _prev_ly or rx != _prev_rx or ry != _prev_ry
	if button_flags != _prev_button_flags and _prev_button_flags >= 0:
		_log("[PAD-OUT] buttons=0x%04x lt=%d rt=%d" % [button_flags, lt, rt])
	if changed or _poll_timer >= 0.1:
		main.input_handler.send_pad_state(GamepadSlots.QUEST_PAD, ControllerLayout.CTYPE_XBOX, button_flags, lt, rt, lx, ly, rx, ry)
		_prev_button_flags = button_flags
		_prev_lt = lt
		_prev_rt = rt
		_prev_lx = lx
		_prev_ly = ly
		_prev_rx = rx
		_prev_ry = ry
		_poll_timer = 0.0

func _send_kbm_mode():
	if _hold_until_release:
		if _controls_released():
			_hold_until_release = false
		else:
			return
	var lv = main.left_hand.get_vector2("primary") if main.left_hand else Vector2.ZERO
	if main.xr_interaction and main.xr_interaction.grab_owns_stick("left"):
		lv = Vector2.ZERO
	var stick_threshold = 0.5
	var profile = _kbm_profile

	_handle_thumbstick_key(lv.y < -stick_threshold, "left_up", _gk("left_up", KEY_W))
	_handle_thumbstick_key(lv.y > stick_threshold, "left_down", _gk("left_down", KEY_S))
	_handle_thumbstick_key(lv.x < -stick_threshold, "left_left", _gk("left_left", KEY_A))
	_handle_thumbstick_key(lv.x > stick_threshold, "left_right", _gk("left_right", KEY_D))

	var trigger_threshold = 0.5
	var lt = main.left_hand.get_float("trigger") if main.left_hand else 0.0
	_handle_analog_key(lt > trigger_threshold, "left_trigger", _gk("left_trigger", KEY_SHIFT))

	var grip_threshold = 0.5
	var lg = main.left_hand.get_float("grip") if main.left_hand else 0.0
	_handle_analog_key(lg > grip_threshold, "left_grip", _gk("left_grip", KEY_CTRL))

	_handle_button_key(main.right_hand.is_button_pressed("ax_button") if main.right_hand else false, "right_a", _gk("right_a", KEY_SPACE))
	_handle_button_key(main.right_hand.is_button_pressed("by_button") if main.right_hand else false, "right_b", _gk("right_b", KEY_R))
	if main.device_is_steam_frame:
		# Frame: X/Y live on the right controller next to A/B, the left has a
		# d-pad and View instead of Quest X/Y/Menu. D-pad = number keys 1-4.
		var rh = main.right_hand
		var lh = main.left_hand
		_handle_button_key(rh.is_button_pressed("frame_x") if rh else false, "left_x", _gk("left_x", KEY_E))
		_handle_button_key(rh.is_button_pressed("frame_y") if rh else false, "left_y", _gk("left_y", KEY_F))
		_handle_button_key(lh.is_button_pressed("view_button") if lh else false, "left_menu", _gk("left_menu", KEY_ESCAPE))
		_handle_button_key(lh.is_button_pressed("dpad_up") if lh else false, "dpad_up", _gk("dpad_up", KEY_1))
		_handle_button_key(lh.is_button_pressed("dpad_right") if lh else false, "dpad_right", _gk("dpad_right", KEY_2))
		_handle_button_key(lh.is_button_pressed("dpad_down") if lh else false, "dpad_down", _gk("dpad_down", KEY_3))
		_handle_button_key(lh.is_button_pressed("dpad_left") if lh else false, "dpad_left", _gk("dpad_left", KEY_4))
	else:
		_handle_button_key(main.left_hand.is_button_pressed("ax_button") if main.left_hand else false, "left_x", _gk("left_x", KEY_E))
		_handle_button_key(main.left_hand.is_button_pressed("by_button") if main.left_hand else false, "left_y", _gk("left_y", KEY_F))
		_handle_button_key(main.left_hand.is_button_pressed("menu_button") if main.left_hand else false, "left_menu", _gk("left_menu", KEY_ESCAPE))
	_handle_button_key(main.right_hand.is_button_pressed("menu_button") if main.right_hand else false, "right_menu", _gk("right_menu", KEY_TAB))
	if main.device_is_steam_frame:
		# Stick clicks (the right controller's trigger and grip stay the mouse's
		# left and right buttons, and its stick the scroll wheel).
		_handle_button_key(main.left_hand.is_button_pressed("primary_click") if main.left_hand else false, "left_stick_click", _gk("left_stick_click", KEY_C))
		_handle_button_key(main.right_hand.is_button_pressed("primary_click") if main.right_hand else false, "right_stick_click", _gk("right_stick_click", KEY_V))

# Steam Frame: the Buttons tab's Game Keys choose these; elsewhere the built-in
# Keyboard+Mouse profile stays. A key of 0 (None) presses nothing.
func _gk(id: String, fallback: int) -> int:
	if main.device_is_steam_frame and main.button_bindings:
		return main.button_bindings.game_key(id, fallback)
	return _kbm_profile.get(id, fallback)

func _handle_thumbstick_key(active: bool, dir_id: String, keycode: int):
	if keycode == 0:
		return
	if active and not _active_key_dirs.get(dir_id, false):
		main.stream_backend.send_keyboard_event(keycode, 3, 0)
		_active_key_dirs[dir_id] = true
		_kb_held[keycode] = true
	elif not active and _active_key_dirs.get(dir_id, false):
		main.stream_backend.send_keyboard_event(keycode, 4, 0)
		_active_key_dirs[dir_id] = false
		_kb_held.erase(keycode)

func _handle_analog_key(active: bool, id: String, keycode: int):
	if keycode == 0:
		return
	if active and not _kb_held.has(keycode):
		main.stream_backend.send_keyboard_event(keycode, 3, 0)
		_kb_held[keycode] = true
	elif not active and _kb_held.has(keycode):
		main.stream_backend.send_keyboard_event(keycode, 4, 0)
		_kb_held.erase(keycode)

func _handle_button_key(pressed: bool, id: String, keycode: int):
	if keycode == 0:
		return
	var held = _kb_held.has(keycode)
	if pressed and not held:
		main.stream_backend.send_keyboard_event(keycode, 3, 0)
		_kb_held[keycode] = true
	elif not pressed and held:
		main.stream_backend.send_keyboard_event(keycode, 4, 0)
		_kb_held.erase(keycode)

func is_active() -> bool:
	return active

func effective_primary_hand() -> int:
	return primary_hand if main._is_using_hands else hand_policy.effective(primary_hand)

func update_available_hands(delta: float) -> void:
	if not main.is_xr_active or main._is_using_hands: return
	var policy = preload("res://src/startup_hand_fallback.gd")
	var right := policy.physical_controller_available(XRServer.get_tracker(&"/user/hand/right"))
	var left := policy.physical_controller_available(XRServer.get_tracker(&"/user/hand/left"))
	var busy: bool = main.was_clicking or main.was_right_clicking or main.grabbed_node != null or main.grabbed_corner_idx >= 0
	if hand_policy.step(delta, right, left, busy):
		main._log("[CTRL] Tracked controller selection: " + (primary_labels[hand_policy.single_hand] if hand_policy.single_hand >= 0 else "saved preference"))
		if main.ui_controller: main.ui_controller.update_primary_btn()

func get_mode_label() -> String:
	if not active:
		return "Off"
	return get_type_label()

func get_type_label() -> String:
	if main.device_is_steam_frame and ctrl_type != 2:
		return "Gamepad"
	return type_labels[ctrl_type]

func get_close_to_head() -> bool:
	return _close_to_head

func cycle_btn_toggle():
	btn_toggle = (btn_toggle + 1) % 3
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_btn_toggle_btn()
	_log("[CTRL] Button toggle: " + btn_toggle_labels[btn_toggle])

func cycle_primary_hand():
	primary_hand = (primary_hand + 1) % 3
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_primary_btn()
	_log("[CTRL] Primary hand: " + primary_labels[primary_hand])
