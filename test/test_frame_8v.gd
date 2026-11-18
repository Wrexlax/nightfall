extends SceneTree

# Steam Frame 8v: Shift, Ctrl and Alt on Nightfall's keyboard. One press is
# for the next key, a second press locks, a third lets go; held while other
# keys are typed, it lasts as long as it is held. Elsewhere a press toggles.

class Stream extends RefCounted:
	var keys: Array = []
	func send_keyboard_event(code: int, action: int, _modifiers: int) -> void: keys.append([code, action])
	func send_mouse_button_event(_action: int, _button: int) -> void: pass

class State extends RefCounted:
	func save_state() -> void: pass

class Streams extends RefCounted:
	func pc_muted() -> int: return -1
	func meteor_presses_media_keys() -> bool: return false
	func press_media_key(_key: String) -> bool: return false

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
	keyboard._has_panels = true
	keyboard._build_keys()
	keyboard._build_trackpad()
	keyboard._build_panels()
	keyboard._side_from_settings()
	return keyboard

func _tap(keyboard: VirtualKeyboard, key: int) -> void:
	keyboard._on_key_press(key)
	keyboard._on_key_release(key)

func _style_of(keyboard: VirtualKeyboard, key: int) -> StyleBoxFlat:
	for kd in keyboard._key_data:
		if kd["key"] == key and kd.get("mod", "") != "":
			return kd["norm_style"]
	return null

func _initialize() -> void:
	await process_frame
	var owner := Owner.new()
	root.add_child(owner)
	var keyboard := _keyboard(owner)
	var sent: Array = owner.stream_backend.keys

	# One press: for the next key only.
	_tap(keyboard, KEY_SHIFT)
	assert(sent == [[KEY_SHIFT, 3]] and keyboard._shift_on and not keyboard._mod_locked[KEY_SHIFT])
	var armed_look: Color = _style_of(keyboard, KEY_SHIFT).bg_color
	_tap(keyboard, KEY_A)
	assert(sent == [[KEY_SHIFT, 3], [KEY_A, 3], [KEY_A, 4], [KEY_SHIFT, 4]], str(sent))
	assert(not keyboard._shift_on)
	_tap(keyboard, KEY_B)
	assert(sent.slice(4) == [[KEY_B, 3], [KEY_B, 4]], "the next key is plain again")
	sent.clear()

	# Two presses: locked through any number of keys, and it looks different.
	_tap(keyboard, KEY_SHIFT)
	_tap(keyboard, KEY_SHIFT)
	assert(sent == [[KEY_SHIFT, 3]] and keyboard._mod_locked[KEY_SHIFT])
	assert(_style_of(keyboard, KEY_SHIFT).bg_color != armed_look and _style_of(keyboard, KEY_SHIFT).border_width_left == 3, "locked looks like pressed once")
	_tap(keyboard, KEY_A)
	_tap(keyboard, KEY_B)
	assert(keyboard._shift_on and not [KEY_SHIFT, 4] in sent)
	# A third press lets go.
	_tap(keyboard, KEY_SHIFT)
	assert(sent.back() == [KEY_SHIFT, 4] and not keyboard._shift_on and not keyboard._mod_locked[KEY_SHIFT])
	sent.clear()

	# Ctrl, then Shift, then a key: one chord, and both go up after it.
	_tap(keyboard, KEY_CTRL)
	_tap(keyboard, KEY_SHIFT)
	_tap(keyboard, KEY_S)
	assert(sent.slice(0, 4) == [[KEY_CTRL, 3], [KEY_SHIFT, 3], [KEY_S, 3], [KEY_S, 4]], str(sent))
	assert([KEY_CTRL, 4] in sent and [KEY_SHIFT, 4] in sent and not keyboard._ctrl_on and not keyboard._shift_on)
	sent.clear()

	# Alt for one of the panel's shortcuts: it goes up after the shortcut.
	_tap(keyboard, KEY_ALT)
	keyboard._send_shortcut(VirtualKeyboard.SHORTCUT_SNAP_LEFT)
	assert(not keyboard._alt_on and sent.back() == [KEY_ALT, 4], str(sent))
	sent.clear()

	# Held with one hand while the other types: down for as long as it is
	# held, like a real one.
	keyboard._on_key_press(KEY_SHIFT)
	_tap(keyboard, KEY_A)
	_tap(keyboard, KEY_B)
	assert(keyboard._shift_on and not [KEY_SHIFT, 4] in sent)
	keyboard._on_key_release(KEY_SHIFT)
	assert(sent.back() == [KEY_SHIFT, 4] and not keyboard._shift_on)
	_tap(keyboard, KEY_C)
	assert(sent.slice(-2) == [[KEY_C, 3], [KEY_C, 4]])
	sent.clear()

	# Hiding the keyboard lets everything go, a lock included.
	_tap(keyboard, KEY_CTRL)
	_tap(keyboard, KEY_CTRL)
	keyboard.release_for_focus_loss()
	assert(not keyboard._ctrl_on and not keyboard._mod_locked[KEY_CTRL])
	sent.clear()

	# Away from the Steam Frame a press toggles, as before.
	keyboard._has_panels = false
	_tap(keyboard, KEY_SHIFT)
	_tap(keyboard, KEY_A)
	assert(keyboard._shift_on and not [KEY_SHIFT, 4] in sent)
	_tap(keyboard, KEY_SHIFT)
	assert(not keyboard._shift_on and sent.back() == [KEY_SHIFT, 4])

	# The expanded side: only the pad is the trackpad, and what lies around
	# it, or around another panel's keys, grabs the keyboard.
	keyboard._has_panels = true
	keyboard.set_trackpad_shown(true)
	keyboard.set_panel(VirtualKeyboard.PANEL_TRACKPAD)
	var pad: Rect2 = keyboard._side_area()
	var inside := pad.get_center()
	var beneath := Vector2(inside.x, pad.end.y + 12.0)
	assert(beneath.y < keyboard.viewport_size.y, "there is a strip under the pad")
	assert(keyboard._in_trackpad(inside) and not keyboard.is_empty_spot(inside))
	assert(not keyboard._in_trackpad(beneath), "a click under the pad starts the trackpad")
	assert(keyboard.is_empty_spot(beneath), "the strip under the pad doesn't grab the keyboard")
	keyboard.set_panel(1) # Arrows
	assert(not keyboard._in_trackpad(inside))
	assert(keyboard.is_empty_spot(beneath), "the strip under the arrows doesn't grab the keyboard")
	var on_a_key := false
	for kd in keyboard._key_data:
		if kd.get("panel", -1) == 1 and kd["btn"].visible:
			var middle: Vector2 = kd["btn"].position + kd["btn"].size / 2.0
			assert(not keyboard.is_empty_spot(middle))
			on_a_key = true
	assert(on_a_key)
	# A tab is a key too.
	for kd in keyboard._key_data:
		if kd.get("tab", -1) >= 0 and kd["btn"].visible:
			assert(not keyboard.is_empty_spot(kd["btn"].position + kd["btn"].size / 2.0))

	print("test_frame_8v passed")
	quit()
