extends SceneTree

# Steam Frame 6p: the Screens tab (PC monitors and virtual monitors) is open
# on the Frame; the in-headset browser's controls are not.

func _screens_button(frame: bool) -> Dictionary:
	var was := MenuSchema._IS_FRAME
	MenuSchema._IS_FRAME = frame
	var found := {}
	var labels: Array[String] = []
	for button in MenuSchema.get_tab_buttons():
		if button["visible"]:
			labels.append(button["label"])
		if button["field"] == &"_tab_btn_monitors":
			found = button
	found["labels"] = labels
	MenuSchema._IS_FRAME = was
	return found

func _init() -> void:
	var on_frame := _screens_button(true)
	assert(on_frame["visible"] and not on_frame["disabled"] and on_frame["alpha"] == 1.0, "open on the Frame")
	assert(not String(on_frame["tooltip"]).contains("browser"), "no browser on the Frame")
	assert(on_frame["labels"] == ["Display", "Stream", "Control", "Buttons", "AI 3D", "Picture", "Screens"])

	# Elsewhere as upstream has it: enabled on Android only.
	var elsewhere := _screens_button(false)
	assert(elsewhere["visible"])
	assert(elsewhere["disabled"] == (OS.get_name() != "Android"))
	assert(not ("Buttons" in elsewhere["labels"]), "the Buttons tab is the Frame's")

	# The note for a host that offers no monitors to choose from fits two lines' worth of words.
	assert(UIController.SCREENS_HOST_NOTICE.count("\n") == 1)
	var source := FileAccess.get_file_as_string("res://src/ui_controller.gd")
	assert(source.contains("row.visible = not MenuSchema._IS_FRAME"), "browser row left out on the Frame")
	assert(source.contains("_browser_screens_btn.visible = not MenuSchema._IS_FRAME"))
	print("All frame_6p tests passed")
	quit(0)
