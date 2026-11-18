extends SceneTree

# Steam Frame 8h: the keyboard's Expand key and the five panels beside the keys.

class Stream extends RefCounted:
	var keys: Array = []
	var buttons: Array = []
	func send_keyboard_event(code: int, action: int, _modifiers: int) -> void: keys.append([code, action])
	func send_mouse_button_event(action: int, button: int) -> void: buttons.append([action, button])

class State extends RefCounted:
	var saves := 0
	func save_state() -> void: saves += 1

class Interaction extends RefCounted:
	var _active_hand := "right"

class Owner extends Node3D:
	var device_is_steam_frame := true
	var is_streaming := true
	var browser_prototype = null
	var screen_sources = null
	var composition_panels = null
	var pcvr_handover = null
	var settings := AppSettings.new()
	var state_manager := State.new()
	var stream_backend := Stream.new()
	var xr_interaction := Interaction.new()
	var right_hand := XRController3D.new()
	var input_handler: InputHandler
	func _init() -> void:
		input_handler = InputHandler.new(self)
		add_child(right_hand)
	func hover_buzz(_hand: String) -> void: pass

func _keyboard(owner: Owner) -> VirtualKeyboard:
	var keyboard := VirtualKeyboard.new(owner)
	keyboard.viewport = SubViewport.new()
	keyboard.viewport.size = keyboard.viewport_size
	root.add_child(keyboard.viewport)
	keyboard._kb_root = Control.new()
	keyboard.viewport.add_child(keyboard._kb_root)
	keyboard._has_panels = owner.device_is_steam_frame
	keyboard._build_keys()
	keyboard._build_trackpad()
	if keyboard._has_panels:
		keyboard._build_panels()
	keyboard._apply_panel()
	return keyboard

func _entry(keyboard: VirtualKeyboard, key_code: int, panel: int = -1) -> Dictionary:
	for kd in keyboard._key_data:
		if kd["key"] == key_code and kd.get("panel", -1) == panel:
			return kd
	return {}

func _center(kd: Dictionary) -> Vector2:
	var btn: Button = kd["btn"]
	return btn.position + btn.size / 2.0

func _initialize() -> void:
	await process_frame

	# Tab keys: five, never mistaken for a key that is sent to the PC.
	assert(VirtualKeyboard.PANEL_NAMES.size() == 5 and VirtualKeyboard.PANEL_KEYS.size() == 5)
	assert(VirtualKeyboard.is_panel_tab(VirtualKeyboard.PANEL_TAB_BASE))
	assert(VirtualKeyboard.is_panel_tab(VirtualKeyboard.PANEL_TAB_BASE - 4))
	assert(not VirtualKeyboard.is_panel_tab(VirtualKeyboard.PANEL_TAB_BASE - 5))
	assert(not VirtualKeyboard.is_panel_tab(VirtualKeyboard.SHORTCUT_MIC))
	assert(not VirtualKeyboard.is_panel_tab(VirtualKeyboard.SHORTCUT_SNAP_LEFT))
	assert(not VirtualKeyboard.is_panel_tab(KEY_A))
	for code in VirtualKeyboard.SHORTCUT_CHORDS:
		assert(not VirtualKeyboard.is_panel_tab(code), "a chord shares a tab's code")

	# The grid: cells fill the area exactly, wide and tall keys span the gaps.
	var area := Rect2(100, 50, 406, 206)
	assert(VirtualKeyboard.panel_key_rect(area, 4, 2, {"x": 0, "y": 0}) == Rect2(100, 50, 97, 100))
	assert(VirtualKeyboard.panel_key_rect(area, 4, 2, {"x": 3, "y": 1}).end == area.end)
	assert(VirtualKeyboard.panel_key_rect(area, 4, 2, {"x": 0, "y": 0, "w": 2, "h": 2}) == Rect2(100, 50, 200, 206))

	var owner := Owner.new()
	root.add_child(owner)
	var keyboard := _keyboard(owner)
	keyboard.media_keys_work = true # all five panels; test_frame_8i has the four
	keyboard._apply_panel()
	await process_frame
	var side := keyboard._side_rect()
	var below := keyboard._side_area()
	assert(below.position.y > side.position.y and is_equal_approx(below.end.y, side.end.y))

	# Every panel's keys: inside the area under the tabs, none overlapping
	# another of the same panel, no key twice, label inside its key.
	for i in range(VirtualKeyboard.PANEL_KEYS.size()):
		var seen := {}
		var rects: Array[Rect2] = []
		for kd in keyboard._key_data:
			if kd.get("panel", -1) != i:
				continue
			var btn: Button = kd["btn"]
			var rect := Rect2(btn.position, btn.size)
			assert(below.grow(0.5).encloses(rect), "%s: outside the panel" % kd["l"])
			for other in rects:
				assert(not rect.grow(-1.0).intersects(other), "%s: over another key" % kd["l"])
			rects.append(rect)
			assert(not seen.has(kd["key"]), "%s: twice in one panel" % kd["l"])
			seen[kd["key"]] = true
			var font := btn.get_theme_font("font")
			var text_size := font.get_multiline_string_size(kd["l"], HORIZONTAL_ALIGNMENT_LEFT, -1, btn.get_theme_font_size("font_size"))
			assert(text_size.x <= btn.size.x - 8.0 and text_size.y <= btn.size.y - 8.0, "%s: label does not fit" % kd["l"])
		assert(seen.is_empty() == (i == VirtualKeyboard.PANEL_TRACKPAD))
	for kd in keyboard._key_data:
		if not kd.has("tab"):
			continue
		var tab: Button = kd["btn"]
		assert(side.grow(0.5).encloses(Rect2(tab.position, tab.size)) and tab.position.y + tab.size.y < below.position.y)
		var width := tab.get_theme_font("font").get_string_size(kd["l"], HORIZONTAL_ALIGNMENT_LEFT, -1, tab.get_theme_font_size("font_size")).x
		assert(width <= tab.size.x - 8.0, "%s: tab label does not fit" % kd["l"])

	# Number pad: digits that are digits whatever the PC's Num Lock says
	# (8i), the number pad's own operators, no Num Lock key.
	assert(not _entry(keyboard, KEY_7, 2).is_empty() and not _entry(keyboard, KEY_KP_ENTER, 2).is_empty())
	assert(not _entry(keyboard, KEY_PERIOD, 2).is_empty() and not _entry(keyboard, KEY_KP_ADD, 2).is_empty())
	assert(not _entry(keyboard, KEY_EQUAL, 2).is_empty(), "= sits where Num Lock was (8j)")
	for kd in keyboard._key_data:
		if kd.get("panel", -1) == 2:
			assert(kd["key"] != KEY_NUMLOCK and (kd["key"] < KEY_KP_0 or kd["key"] > KEY_KP_9), "%s depends on Num Lock" % kd["l"])
	assert(not _entry(keyboard, KEY_MEDIAPLAY, 3).is_empty() and not _entry(keyboard, KEY_VOLUMEMUTE, 3).is_empty())
	assert(VirtualKeyboard.SHORTCUT_CHORDS[VirtualKeyboard.SHORTCUT_MONITOR_RIGHT] == [KEY_META, KEY_SHIFT, KEY_RIGHT])

	# Starts on the trackpad: its parts shown, other panels' keys hidden and
	# deaf, the tabs shown.
	var up := _entry(keyboard, KEY_UP, 1)
	var seven := _entry(keyboard, KEY_7, 2)
	assert(keyboard._panel == VirtualKeyboard.PANEL_TRACKPAD)
	assert(keyboard._tp_border.visible and not up["btn"].visible and not seven["btn"].visible)
	assert(keyboard._key_from_pos(_center(up)) == -1, "a hidden key answered")
	assert(keyboard._in_trackpad(_center(up)))
	var arrows_tab := _entry(keyboard, VirtualKeyboard.PANEL_TAB_BASE - 1)
	assert(arrows_tab["btn"].visible and not keyboard._in_trackpad(_center(arrows_tab)), "the tabs are not trackpad")
	assert(not keyboard._in_trackpad(Vector2(100, 300)))

	# Pointing at a tab and pulling the trigger changes the panel, saves the
	# choice, and sends nothing to the PC.
	keyboard.visible = true
	keyboard.handle_pointer(_center(arrows_tab), true, false, owner.right_hand)
	keyboard.handle_pointer(_center(arrows_tab), false, true, owner.right_hand)
	assert(keyboard._panel == 1 and owner.settings.keyboard_panel == 1 and owner.state_manager.saves == 1)
	assert(owner.stream_backend.keys.is_empty() and not keyboard.trackpad_active)
	assert(up["btn"].visible and not keyboard._tp_border.visible and not seven["btn"].visible)
	assert(not keyboard._in_trackpad(_center(up)), "the trackpad is not under the arrow keys")

	# An arrow key: down on the press, up on the release.
	keyboard.handle_pointer(_center(up), true, false, owner.right_hand)
	assert(owner.stream_backend.keys == [[KEY_UP, 3]])
	keyboard.handle_pointer(_center(up), false, true, owner.right_hand)
	assert(owner.stream_backend.keys == [[KEY_UP, 3], [KEY_UP, 4]])

	# The other hand: a tab changes the panel and is not sent; a key is.
	owner.stream_backend.keys.clear()
	var pad_tab := _entry(keyboard, VirtualKeyboard.PANEL_TAB_BASE - 2)
	keyboard.handle_secondary_key(_center(pad_tab), true)
	keyboard.handle_secondary_key(_center(pad_tab), false)
	assert(keyboard._panel == 2 and owner.stream_backend.keys.is_empty())
	keyboard.handle_secondary_key(_center(seven), true)
	keyboard.handle_secondary_key(_center(seven), false)
	assert(owner.stream_backend.keys == [[KEY_7, 3], [KEY_7, 4]])

	# A window key sends its chord, let go in reverse.
	owner.stream_backend.keys.clear()
	keyboard.set_panel(4)
	var snap := _entry(keyboard, VirtualKeyboard.SHORTCUT_SNAP_LEFT, 4)
	keyboard.handle_pointer(_center(snap), true, false, owner.right_hand)
	keyboard.handle_pointer(_center(snap), false, true, owner.right_hand)
	assert(owner.stream_backend.keys == [[KEY_META, 3], [KEY_LEFT, 3], [KEY_LEFT, 4], [KEY_META, 4]])

	# Back on the trackpad panel a trigger pull under the tabs starts it;
	# leaving for another panel stops it.
	keyboard.set_panel(VirtualKeyboard.PANEL_TRACKPAD)
	keyboard.handle_pointer(below.get_center(), true, false, owner.right_hand)
	assert(keyboard.trackpad_active)
	keyboard.set_panel(3)
	assert(not keyboard.trackpad_active and owner.settings.keyboard_panel == 3)

	# Hiding the area hides tabs and keys alike; the Expand key says which
	# way it goes; the panel is remembered for next time.
	keyboard.set_trackpad_shown(false)
	var expand := _entry(keyboard, VirtualKeyboard.SHORTCUT_TRACKPAD)
	assert(expand["btn"].text == "Expand" and not pad_tab["btn"].visible and not _entry(keyboard, KEY_MEDIAPLAY, 3)["btn"].visible)
	keyboard.set_trackpad_shown(true)
	assert(expand["btn"].text == "Hide" and keyboard._panel == 3 and _entry(keyboard, KEY_MEDIAPLAY, 3)["btn"].visible)
	var saved := ConfigFile.new()
	SettingsPersistence.write_app(saved, owner.settings)
	var read_back := AppSettings.new()
	SettingsPersistence.read_app(saved, read_back, true, [])
	assert(read_back.keyboard_panel == 3 and AppSettings.new().keyboard_panel == 0)

	# Away from the Steam Frame: no tabs, no panels, the whole side area is
	# the trackpad as before.
	var quest_owner := Owner.new()
	quest_owner.device_is_steam_frame = false
	root.add_child(quest_owner)
	var quest := _keyboard(quest_owner)
	for kd in quest._key_data:
		assert(not kd.has("tab") and not kd.has("panel"))
	assert(quest._side_area() == quest._side_rect())
	assert(quest._in_trackpad(Vector2(quest._kb_width + 5, 20)))
	quest.set_panel(2)
	assert(quest._panel == VirtualKeyboard.PANEL_TRACKPAD and quest_owner.state_manager.saves == 0)

	for node in [keyboard.viewport, quest.viewport, keyboard, quest, owner, quest_owner]:
		node.free()
	print("All frame 8h tests passed")
	quit()
