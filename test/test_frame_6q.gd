extends SceneTree

# Steam Frame 6q, from the first trial of the Screens tab (6p): a layout
# picture applied with virtual monitors in the stream keeps them; a curved
# screen shows its own part of the stream; voice typing cuts a runaway repeat.

func _monitor(id: String, x: int, virtual: bool, enabled: bool = true) -> ScreenLayout.MonitorSpec:
	var m := ScreenLayout.MonitorSpec.new()
	m.id = StringName(id)
	m.enabled = enabled
	m.frame_rect = Rect2i(x, 0, 1920, 1080)
	m.desktop_rect = Rect2i(x, 0, 1920, 1080)
	m.hint = {"virtual": true} if virtual else {}
	return m

func _ids(layout: ScreenLayout) -> Array:
	var ids: Array = []
	for m in layout.monitors:
		ids.append(String(m.id))
	return ids

func _layout_keeps_live_virtual() -> void:
	# What is in the stream: the real monitor and the host's virtual display.
	var live := ScreenLayout.new()
	live.frame_size = Vector2i(3840, 1080)
	live.monitors.append(_monitor("m0", 0, false))
	live.monitors.append(_monitor("v1", 1920, true))
	live.monitors.append(_monitor("v2", 3840, true, false))
	# What Apply stages: the real monitor and a stand-in for the virtual one.
	var target := ScreenLayout.new()
	target.frame_size = live.frame_size
	target.monitors.append(_monitor("m0", 0, false))
	target.monitors.append(_monitor("virtual_0", 3840, true))
	# Same number of virtual monitors (a layout picture was picked): v1 stays.
	var kept := SettingsController.layout_without_placeholders(target, live, true)
	assert(_ids(kept) == ["m0", "v1"], "the live virtual display stays, the stand-in and the switched-off one do not")
	assert(kept.frame_size == Vector2i(3840, 1080))
	# Their number changed: as before, only the real monitors until the new manifest.
	assert(_ids(SettingsController.layout_without_placeholders(target, live, false)) == ["m0"])
	assert(_ids(SettingsController.layout_without_placeholders(target, null, true)) == ["m0"])

func _curved_screen_region() -> void:
	var source := FileAccess.get_file_as_string("res://src/composition_layer_manager.gd")
	assert(source.contains('if n != "" and n != "stereo_mode" and n != "tile_inset":'), "uv_region is mirrored onto the curved material")
	assert(FileAccess.get_file_as_string("res://src/shaders/stereo_screen_core.gdshaderinc").contains("uniform vec4 uv_region"))

func _runaway() -> void:
	var loop := "Meteor"
	for i in 22:
		loop += " Meteor"
	assert(VoiceTyping.collapse_runaway("the vibepollo from " + loop) == "the vibepollo from Meteor")
	assert(VoiceTyping.collapse_runaway("Thank you. Thank you. Thank you. Thank you. Thank you.") == "Thank you.")
	assert(VoiceTyping.collapse_runaway("so I said go go go go go and left") == "so I said go and left")
	# Left exactly as they came:
	for kept in ["no, no, no", "very very very good", "Depth view. Depth view.", "call 5 5 5 5 1 2 3 4",
			"the cat and the dog and the bird and the fish", "", "one"]:
		assert(VoiceTyping.collapse_runaway(kept) == kept, kept)
	# A phrase of up to four words, four times.
	assert(VoiceTyping.collapse_runaway("a b c d a b c d a b c d a b c d e") == "a b c d e")
	var native := FileAccess.get_file_as_string("res://addons/nightfall-stream/src/voice/voice_typer.cpp")
	assert(native.contains("p.max_tokens = "), "the recogniser is given a budget for the clip's length")

func _init() -> void:
	_layout_keeps_live_virtual()
	_curved_screen_region()
	_runaway()
	print("All frame_6q tests passed")
	quit(0)
