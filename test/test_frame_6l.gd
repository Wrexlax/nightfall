extends SceneTree

# Steam Frame 6l: PT Fade through the opacity of the scene's background
# colour, where Nightfall's own engine build keeps it (FrameEngine).

func _engine_level() -> void:
	assert(FrameEngine.level_of("nightfall3") == 3)
	assert(FrameEngine.level_of("nightfall12") == 12)
	assert(FrameEngine.level_of("official") == 0, "Godot's own builds have none of the patches")
	assert(FrameEngine.level_of("custom_build") == 0)
	assert(FrameEngine.level_of("nightfall") == 0 and FrameEngine.level_of("nightfallx") == 0 and FrameEngine.level_of("") == 0)
	assert(FrameEngine.patch_level() == 0, "the tests run on stock Godot")
	assert(FrameEngine.BACKGROUND_OPACITY == 3)

func _background_fade() -> void:
	var fade := PassthroughFade.new()
	assert(not fade.setup_background(null))
	var environment := Environment.new()
	environment.background_color = Color(0.2, 0.3, 0.4, 1.0)
	assert(fade.setup_background(environment) and fade.method == "background colour")
	# Passthrough off: the background is the Background setting's, untouched.
	fade.apply(false, 50)
	assert(environment.background_color == Color(0.2, 0.3, 0.4, 1.0))
	for pct in [0, 5, 40, 100]:
		fade.apply(true, pct)
		assert(environment.background_color.is_equal_approx(Color(0, 0, 0, pct / 100.0)), "black at the fade's opacity")
	assert(fade.layer == null, "nothing extra is drawn")
	# 6m: the drawn fades are gone.
	for gone in ["dome", "quad", "setup_dome", "setup_far_quad", "shell_share"]:
		assert(not (gone in fade) and not fade.has_method(gone))

func _hz_cap_hidden_on_frame() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui_controller.gd")
	assert(source.contains("main._ui_3d_hz_cap_btn.visible = not main.device_is_steam_frame"))

func _init() -> void:
	_engine_level()
	_background_fade()
	_hz_cap_hidden_on_frame()
	print("All frame_6l tests passed")
	quit(0)
