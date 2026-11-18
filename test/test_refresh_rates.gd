extends SceneTree

func _init():
	var next := func(current: int, high: bool) -> int: return SettingsController.next_fps_rate(current, high)
	assert(next.call(90, false) == 120)
	assert(next.call(165, false) == 30, "200 and 207 Hz are skipped by default")
	assert(next.call(165, true) == 200)
	assert(next.call(207, true) == 30)
	assert(next.call(207, false) == 30, "a hidden saved rate moves on to the first offered one")
	assert(next.call(100, false) == 120, "an unlisted rate continues from the next lower one")
	# Steam Frame: nothing above its display's 144 Hz.
	var frame := func(current: int) -> int: return SettingsController.next_fps_rate(current, false, SettingsController.FRAME_MAX_STREAM_FPS)
	assert(frame.call(120) == 144)
	assert(frame.call(144) == 30)
	assert(frame.call(165) == 30, "a saved 165 moves on to the first offered rate")
	print("All refresh_rates tests passed")
	quit()
