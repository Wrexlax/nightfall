extends SceneTree

# Steam Frame 6n: Picture > Flat Screen Detail. The flat screen's layer
# pictures are 4K (Full) or follow the stream's size (Stream Size).

class FakeMain:
	extends Node3D
	var device_is_steam_frame := true

func _pinned_or_following() -> void:
	var owner := FakeMain.new()
	var screen := VRScreen.new()
	screen.main = owner
	VRScreen.sf_match_stream = false
	screen.comp_base_size = Vector2i(1920, 1080)
	assert(screen.comp_base_size == VRScreen.SF_COMP_BASE_SIZE, "Full: 4K whatever is asked for")
	assert(screen.comp_base_requested == Vector2i(1920, 1080), "what was asked for is kept")
	# The option is switched while running: each screen is asked again.
	VRScreen.sf_match_stream = true
	screen.comp_base_size = screen.comp_base_requested
	assert(screen.comp_base_size == Vector2i(1920, 1080), "Stream Size: as asked")
	screen.comp_base_size = Vector2i(2560, 1440)
	assert(screen.comp_base_size == Vector2i(2560, 1440) and screen.comp_base_requested == Vector2i(2560, 1440))
	VRScreen.sf_match_stream = false
	screen.comp_base_size = screen.comp_base_requested
	assert(screen.comp_base_size == VRScreen.SF_COMP_BASE_SIZE and screen.comp_base_requested == Vector2i(2560, 1440))
	# Other headsets are never pinned.
	owner.device_is_steam_frame = false
	screen.comp_base_size = Vector2i(1280, 720)
	assert(screen.comp_base_size == Vector2i(1280, 720))
	screen.free()
	owner.free()

func _saved() -> void:
	assert(AppSettings.new().frame_layer_match_stream, "Stream Size unless Full is chosen (6o)")
	assert(VRScreen.sf_match_stream, "what holds before the settings are read matches that default")
	var settings := AppSettings.new()
	settings.frame_layer_match_stream = false
	var config := ConfigFile.new()
	SettingsPersistence.write_app(config, settings)
	assert(config.get_value("display", "frame_layer_match_stream") == false)
	var loaded := AppSettings.new()
	SettingsPersistence.read_app(config, loaded, true, [])
	assert(not loaded.frame_layer_match_stream)
	assert(SettingsPersistence.read_app(ConfigFile.new(), loaded, true, []) != null and loaded.frame_layer_match_stream, "nothing saved: Stream Size")

func _init() -> void:
	_saved()
	_pinned_or_following()
	VRScreen.sf_match_stream = true
	print("All frame_6n tests passed")
	quit(0)
