extends SceneTree

# Steam Frame 7z: the AI 3D page's note and Stream Link's tooltip, on the
# real UIController with stand-ins for everything it asks.

class FakeHost:
	var ai_3d_speed := 2
	var ai_3d_meteor_declined := false
	var virtual_display_count := 1
	var virtual_display_installed := true
	var virtual_only := false
	var sbs_mode := 0

class FakeSettings:
	var host := FakeHost.new()
	var frame_link_mode := 0
	# The Meteor suggestion (8e): hidden here until the end of this test.
	var frame_meteor_hint_hidden := true

class FakeState:
	var saves := 0
	func save_state() -> void:
		saves += 1

class FakeSC:
	var offered := false
	var selected := false
	func frame_depth_available() -> bool: return true
	func meteor_depth_offered() -> bool: return offered
	func meteor_depth_selected() -> bool: return selected

class FakeManager:
	var through := false
	func through_meteor() -> bool: return through

class FakeDepth:
	var filling := false
	func headset_filling_in() -> bool: return filling

class FakeMain:
	extends Node3D
	var device_is_steam_frame := true
	var is_streaming := false
	var settings := FakeSettings.new()
	var settings_controller := FakeSC.new()
	var stream_manager := FakeManager.new()
	var depth_estimator := FakeDepth.new()
	var state_manager := FakeState.new()
	var logged: Array[String] = []
	func _log(line: String) -> void:
		logged.append(line)
	var _ui_second_link_btn: Button
	var _ui_head_lock_btn: Button
	var _ui_3d_btn: Button

# Every tooltip the Frame's menu shows, in every language, fits the tooltip
# bar's two lines (what doesn't is cut off with an ellipsis). The menu's own
# tooltips are checked by test_localization; this also covers the ones set in
# code for each choice (Stream Link, the depth model, Head Lock).
func _tooltips_fit() -> void:
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://steam-frame/i18n/source.json"))
	var width := float(UIController.TOOLTIP_VIEWPORT_SIZE.x - 48)
	var over := PackedStringArray()
	var checked := 0
	for language in Localization.LANGUAGES:
		Localization.apply(language["code"])
		for entry in source:
			if not String(entry[1]).begins_with("tooltip"):
				continue
			var paragraph := TextParagraph.new()
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.width = width
			paragraph.add_string(Localization.t(entry[0]), ThemeDB.fallback_font, 24)
			checked += 1
			if paragraph.get_line_count() > 2:
				over.append("%s: %s" % [language["code"], String(entry[0]).left(50)])
	Localization.apply("en")
	assert(checked > 1500, "the list was read: %d" % checked)
	assert(over.is_empty(), "tooltips of more than two lines:\n" + "\n".join(over))
	# Head Lock's tooltip is the one for its choice.
	for choice in ["Off", "Level", "Tilt"]:
		assert(MenuSchema.HEAD_LOCK_TIPS.has(choice) and String(MenuSchema.HEAD_LOCK_TIPS[choice]).count("\n") == 1)

func _init() -> void:
	_tooltips_fit()
	var m := FakeMain.new()
	var ui := UIController.new(m)
	ui._tab_ai3d = VBoxContainer.new()
	var note := Label.new()
	note.name = "Ai3dNotice"
	note.visible = false
	ui._tab_ai3d.add_child(note)
	var btn := Button.new()
	ui._init_option_text(btn, "Stream Link", "Multi-Link")
	m._ui_second_link_btn = btn
	var lock := Button.new()
	ui._init_option_text(lock, "Head Lock", "Off")
	m._ui_head_lock_btn = lock
	for choice in ["Level", "Tilt", "Off"]:
		ui.update_option_btn(lock, choice)
		assert(lock.get_meta(UIController.TOOLTIP_META) == MenuSchema.HEAD_LOCK_TIPS[choice], choice)
	lock.free()
	ui.refresh_ai3d_note()
	assert(not note.visible)
	ui.refresh_link_tip()
	assert(btn.get_meta(UIController.TOOLTIP_META) == FrameSecondLink.MODE_TIPS[0], str(btn.get_meta(UIController.TOOLTIP_META)))
	m.is_streaming = true
	ui.refresh_link_tip()
	assert(btn.get_meta(UIController.TOOLTIP_META) == FrameSecondLink.NO_METEOR_TIP)
	ui.refresh_ai3d_note()
	assert(not note.visible)
	m.stream_manager.through = true
	ui.refresh_link_tip()
	assert(btn.get_meta(UIController.TOOLTIP_META) == FrameSecondLink.MODE_TIPS[0])
	ui.refresh_ai3d_note()
	assert(note.visible and "depth switched off" in note.text, note.text)
	m.settings_controller.offered = true
	m.settings_controller.selected = true
	ui.refresh_ai3d_note()
	assert(not note.visible)
	m.depth_estimator.filling = true
	ui.refresh_ai3d_note()
	assert(note.visible and "filling in" in note.text)
	# The suggestion to install Meteor (8e, fixed in 8g): shown while the
	# stream doesn't pass through Meteor, with a button over it, because a
	# click on anything in the menu that isn't a button moves the menu. One
	# press hides the note for good.
	var hide := Button.new()
	hide.name = "Ai3dNoticeHide"
	hide.visible = false
	hide.pressed.connect(ui._on_ai3d_hint_pressed)
	note.add_child(hide)
	m.settings.frame_meteor_hint_hidden = false
	m.settings.host.ai_3d_meteor_declined = false
	m.is_streaming = true
	m.stream_manager.through = false
	m.settings_controller.offered = false
	m.depth_estimator.filling = false
	ui.refresh_ai3d_note()
	assert(note.visible and note.text == UIController.METEOR_HINT, note.text)
	assert(hide.visible, "the button that takes the click is there with the suggestion")
	hide.pressed.emit()
	assert(m.settings.frame_meteor_hint_hidden and m.state_manager.saves == 1, "hidden for good, and saved")
	assert(not note.visible and not hide.visible)
	# With another note showing, nothing takes clicks.
	m.stream_manager.through = true
	ui.refresh_ai3d_note()
	assert(note.visible and note.text != UIController.METEOR_HINT and not hide.visible, note.text)
	# And the real page is built with that button over the note.
	var page := FileAccess.get_file_as_string("res://src/ui_controller.gd")
	assert(page.contains('hide_hint.name = "Ai3dNoticeHide"') and page.contains("ai3d_notice.add_child(hide_hint)"))

	ui._tab_ai3d.free()
	btn.free()
	m.free()
	print("All frame_7z tests passed")
	quit(0)
