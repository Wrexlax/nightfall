extends SceneTree

# Steam Frame 5t/5u: going from the flat quad layer to the screen in the scene,
# the layer stays up for a few frames (the screen vanished for a moment when
# it was hidden at once). Also the system readings beside [FRAME-COST]. (The
# fade's own hand-over between a quad and a shell went with them in 6m.)

class FakeSettings:
	extends RefCounted
	var frame_flat_3d := false
	var frame_fast_filter := true
	var ambient_mode := 0

class FakeMain:
	extends Node3D
	var device_is_steam_frame := true
	var is_streaming := false
	var screens: Array = []
	var primary_screen = null
	var settings := FakeSettings.new()
	var settings_controller = null
	var log_lines: Array[String] = []
	func _log(line: String) -> void:
		log_lines.append(line)

# The readings beside [FRAME-COST] come from plain files; a made-up set here.
func _system() -> void:
	var base := OS.get_user_data_dir().path_join("frame_5t_sys")
	var files := {
		"devfreq/3d00000.gpu/cur_freq": "585000000",
		"devfreq/3d00000.gpu/available_frequencies": "220000000 585000000 903000000",
		"devfreq/soc:qcom,cpu-llcc/cur_freq": "1000",
		"thermal/thermal_zone0/type": "aoss-0", "thermal/thermal_zone0/temp": "41000",
		"thermal/thermal_zone1/type": "gpuss-0", "thermal/thermal_zone1/temp": "63200",
		"thermal/thermal_zone2/type": "cpu-0-0", "thermal/thermal_zone2/temp": "58000",
		"thermal/cooling_device0/type": "fan",
	}
	for rel in files:
		DirAccess.make_dir_recursive_absolute(base.path_join(rel).get_base_dir())
		var f := FileAccess.open(base.path_join(rel), FileAccess.WRITE)
		f.store_string(files[rel] + "\n")
		f.close()
	var stats := FrameSystemStats.new()
	stats.devfreq_root = base.path_join("devfreq")
	stats.thermal_root = base.path_join("thermal")
	var found := stats.setup()
	assert(found.contains("3d00000.gpu") and found.contains("gpuss-0"), found)
	assert(stats.sample() == "gpu clock 585 MHz, hottest 63 C (gpuss-0)", stats.sample())
	# Nothing there (another machine): no text, no error.
	var none := FrameSystemStats.new()
	none.devfreq_root = base.path_join("missing")
	none.thermal_root = base.path_join("missing")
	assert(none.setup() == "nothing readable" and none.sample() == "")
	OS.move_to_trash(base)

# Screen Size slider and the width limit (5x).
func _screen_size() -> void:
	assert(is_equal_approx(VRScreen.max_width_at(6.0), 18.0))
	assert(is_equal_approx(VRScreen.max_width_at(0.5), 3.0), "close up a screen may still be 3 m")
	for distance in [1.0, 2.25, 6.0]:
		for v in range(0, 101, 5):
			var width := SettingsController.screen_width_from_slider(v, distance)
			assert(width <= VRScreen.MAX_WIDTH_PER_METRE * distance + 0.001)
			assert(SettingsController.screen_width_to_slider(width, distance) == v)
	# The size that got stuck: far off the scale, reads as the top of the slider.
	assert(SettingsController.screen_width_to_slider(42.5, 6.0) == 100)
	# The default size at the default distance sits at the slider's mark.
	assert(SettingsController.screen_width_to_slider(2.24, 2.25) == 25)

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var main := FakeMain.new()
	root.add_child(main)
	var comp := CompositionLayerManager.new(main)
	comp.in_use = true
	var scr := VRScreen.new()  # not in the tree: its _ready() wants the screen scene's children
	main.screens = [scr]
	scr._original_mat = ShaderMaterial.new()
	scr.comp_cylinder = Node3D.new()
	scr.comp_viewport = SubViewport.new()
	scr.comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(scr.comp_cylinder)
	main.add_child(scr.comp_viewport)

	# Flat: the layer shows, nothing is touched.
	scr.curvature = 0
	scr.comp_cylinder.visible = true
	comp._apply_frame_curve()
	assert(scr.comp_cylinder.visible and not comp._frame_curve_active)

	# Flat to curved: the mesh gets its material at once, the layer stays for
	# a few frames with its viewport still drawing, then goes.
	scr.curvature = 1
	comp._apply_frame_curve()
	assert(comp._frame_curve_active)
	assert(scr.material_override == scr._original_mat, "the mesh shows at once")
	assert(scr.comp_cylinder.visible, "the layer must not vanish in the same frame")
	var frames := 0
	while scr.comp_cylinder.visible and frames < 20:
		assert(scr.comp_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "a showing layer keeps drawing")
		comp.process_frame_curve()
		frames += 1
	var want := CompositionLayerManager.CURVE_LAYER_OVERLAP_FRAMES
	assert(frames >= want - 1 and frames <= want + 1, "layer hidden after the overlap, took %d frames" % frames)
	comp.process_frame_curve()
	assert(scr.comp_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "then its viewport is paused")

	# Already curved and something shows the layer again (a 3D mode change):
	# hidden at once, as before.
	scr.comp_cylinder.visible = true
	comp._apply_frame_curve()
	assert(not scr.comp_cylinder.visible)

	# Curved to flat inside the overlap: the layer stays.
	scr.curvature = 0
	scr.comp_cylinder.visible = true
	comp._apply_frame_curve()
	scr.curvature = 1
	comp._apply_frame_curve()
	scr.curvature = 0
	comp._apply_frame_curve()
	for i in 20:
		comp.process_frame_curve()
	assert(scr.comp_cylinder.visible and not comp._frame_curve_active)

	scr.free()
	main.queue_free()
	_system()
	_screen_size()
	print("All frame_5t tests passed")
	quit()
	return true
