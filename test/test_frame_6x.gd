extends SceneTree

# Steam Frame 6x: on-headset depth. The Model button's choices in turn: Meteor
# first while the PC offers it, then the headset's own models.

func _init() -> void:
	var meteor := SettingsController.MODEL_METEOR
	var next := func(offered: bool, selected: bool, model: int) -> int:
		return SettingsController.next_frame_depth_choice(offered, selected, model)
	# Without Meteor: the two headset models take turns.
	assert(next.call(false, false, 0) == 1)
	assert(next.call(false, false, 1) == 0)
	# With Meteor offered: Meteor, Detail, Light, and round again.
	assert(next.call(true, true, 0) == 0, "from Meteor to the first headset model")
	assert(next.call(true, true, 1) == 0, "from Meteor, whatever model was saved before")
	assert(next.call(true, false, 0) == 1)
	assert(next.call(true, false, 1) == meteor)
	# A saved number that no longer exists starts at the top.
	assert(next.call(false, false, 7) == 0)
	assert(next.call(true, false, 7) == meteor)
	# One label for each of the native engine's models: two on the processor,
	# and the graphics-chip test (7j), which joins the cycle only where it is there.
	assert(SettingsController.FRAME_DEPTH_LABELS.size() == 3)
	assert(SettingsController.FRAME_DEPTH_LABELS[SettingsController.FRAME_DEPTH_GPU_MODEL] == "Headset: GPU")
	assert(SettingsController.next_frame_depth_choice(false, false, 1, 3) == 2, "Light to GPU where the GPU model is offered")
	assert(SettingsController.next_frame_depth_choice(false, false, 2, 3) == 0)
	assert(SettingsController.next_frame_depth_choice(true, false, 2, 3) == meteor)
	assert(SettingsController.next_frame_depth_choice(false, false, 2, 2) == 0, "a saved GPU choice on a build without it starts at the top")
	# The headset model's rate starts on Auto (7h); the numbers are still there to pick.
	assert(AppSettings.new().frame_depth_rate == SettingsController.FRAME_DEPTH_RATE_AUTO)
	assert(not SettingsController.AI3D_HZ_CAP_VALUES.has(SettingsController.FRAME_DEPTH_RATE_AUTO))
	await _bridge()
	print("All frame_6x tests passed")
	quit(0)

# The native side through the same calls the app makes: the model's size is
# known at once, a picture handed over comes back as a map of that size. Only
# where the native library has the Frame's depth engine and its models sit in
# depth_models/ next to the program; elsewhere there is nothing to run.
func _bridge() -> void:
	var bridge = ClassDB.instantiate("DepthBridge") if ClassDB.class_exists("DepthBridge") else null
	if bridge == null or not bridge.has_method("has_decoder_depth") or not bridge.has_decoder_depth():
		print("(no on-headset depth in this native library: bridge checks skipped)")
		return
	bridge.configure_depth(0, 0)
	assert(bridge.get_depth_model_width() == 512 and bridge.get_depth_model_height() == 288)
	assert(bridge.get_depth_model_input_width() == 512 and bridge.get_depth_model_input_height() == 288)
	bridge.configure_depth(1, 0)
	assert(bridge.get_depth_model_width() == 256 and bridge.get_depth_model_height() == 256)
	bridge.set_depth_hz_cap(60)
	bridge.set_decoder_depth_region(0.0, 0.0, 1.0, 1.0)
	bridge.set_decoder_depth_enabled(true)
	# A picture at the model's size: dark at the top, light at the bottom.
	var picture := PackedByteArray()
	picture.resize(256 * 256 * 4)
	for y in 256:
		for x in 256:
			var at := (y * 256 + x) * 4
			picture[at] = y
			picture[at + 1] = y
			picture[at + 2] = y
			picture[at + 3] = 255
	var map := PackedByteArray()
	for attempt in 400:
		await process_frame
		OS.delay_msec(10)
		if not String(bridge.get_depth_backend_status()).is_empty():
			break
		bridge.submit_depth_frame(picture, 256, 256)
		map = bridge.get_depth_map()
		if not map.is_empty():
			break
	var status := String(bridge.get_depth_backend_status())
	if status.contains("missing"):
		print("(depth models not beside the program: bridge run skipped)")
		return
	assert(status.is_empty(), status)
	assert(map.size() == 256 * 256, "a map the model's size, got %d bytes" % map.size())
	assert(bridge.get_depth_last_inference_ms() > 0.0)
	assert(not String(bridge.take_decoder_depth_report()).is_empty())
	# Switching model with one loaded: the app is told the new size at once.
	# (6x answered with the loaded model's size; the app then waited for maps
	# of the old size and the depth stood still.)
	bridge.configure_depth(0, 0)
	assert(bridge.get_depth_model_width() == 512 and bridge.get_depth_model_height() == 288)
	for attempt in 100:
		await process_frame
		OS.delay_msec(10)
		var stale: PackedByteArray = bridge.get_depth_map()
		assert(stale.is_empty() or stale.size() == 512 * 288, "a map of the old model's size after the switch")
	bridge.set_decoder_depth_enabled(false)
