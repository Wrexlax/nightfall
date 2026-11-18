extends SceneTree

# Steam Frame 8a: asking the PC for a keyframe when Meteor's depth is
# connected and silent, and what the app does while it isn't being shown.

class FakeMain:
	extends Node
	var lines: Array[String] = []
	func _log(line: String) -> void:
		lines.append(line)

func _initialize() -> void:
	# Meteor's depth decoder can only start at a keyframe, and the PC sends
	# one only when asked (log of 2026-11-17: 12.5 minutes without a map after
	# "Host depth" was turned back on). Silence is counted from the later of
	# the last map and the connection.
	assert(MeteorDepthReceiver.silence(10.0, 0.0, INF) == 0.0, "no connection: no silence to act on")
	assert(is_equal_approx(MeteorDepthReceiver.silence(10.0, 0.0, 7.5), 2.5), "no map yet: since the connection")
	assert(is_equal_approx(MeteorDepthReceiver.silence(10.0, 9.0, 7.5), 1.0), "maps came: since the last one")
	assert(is_equal_approx(MeteorDepthReceiver.silence(10.0, 3.0, 7.5), 2.5), "a map from before a reconnect doesn't count")
	assert(MeteorDepthReceiver.silence(1.0, 5.0, 0.5) == 0.0, "never negative")

	# Three asks, each later than the last, then no more until maps flow.
	var asks_at: Array[float] = DepthEstimatorModule.METEOR_KEYFRAME_ASK_SEC
	assert(asks_at.size() == 3 and asks_at[0] < asks_at[1] and asks_at[1] < asks_at[2])
	assert(asks_at[0] > MeteorDepthReceiver.STALL_SEC, "never while maps are merely a little late")
	assert(not DepthEstimatorModule.keyframe_ask_due(1.9, 0))
	assert(DepthEstimatorModule.keyframe_ask_due(2.0, 0))
	assert(not DepthEstimatorModule.keyframe_ask_due(7.9, 1), "the second ask waits its turn")
	assert(DepthEstimatorModule.keyframe_ask_due(8.0, 1))
	assert(DepthEstimatorModule.keyframe_ask_due(30.0, 2))
	assert(not DepthEstimatorModule.keyframe_ask_due(3600.0, 3), "after three, no more")

	# While Nightfall isn't shown: which lines are the once-a-second ones.
	assert(FrameSessionWatch.is_periodic("[FRAME-COST] cpu 3.1 ms"))
	assert(FrameSessionWatch.is_periodic("[STATS] 144 fps"))
	assert(FrameSessionWatch.is_periodic("[METEOR-DEPTH] 60 maps"))
	assert(not FrameSessionWatch.is_periodic("[METEOR] depth connected"))
	assert(not FrameSessionWatch.is_periodic("[STREAM] connection lost"))
	assert(not FrameSessionWatch.is_periodic("note: [STATS] inside a line"))
	assert(FrameSessionWatch.duration_text(12) == "12 s")
	assert(FrameSessionWatch.duration_text(89) == "89 s")
	assert(FrameSessionWatch.duration_text(180) == "3 min")
	assert(FrameSessionWatch.duration_text(23 * 60 + 10) == "23 min")
	assert(FrameSessionWatch.duration_text(2 * 3600 + 5 * 60) == "2 h 5 min")

	# In the tree from here on, as the app's main node is.
	await process_frame
	var main := FakeMain.new()
	root.add_child(main)
	var watch := FrameSessionWatch.new()
	watch.main = main
	# Start-up: the session passes through "not shown" on its way to being
	# shown for the first time, and that isn't worth a line.
	watch._set_shown(false)
	watch._hidden_at -= 5000
	watch._before_draw()
	assert(not watch.shown and main.lines.is_empty(), "nothing is written at start-up")
	watch._set_shown(true)
	assert(watch.shown and main.lines.is_empty())
	assert(not watch.holds_back("[STATS] 144 fps"), "shown: every line is written")
	watch._set_shown(true)
	assert(main.lines.is_empty(), "shown twice in a row (visible, then focused) is one event")

	# A blip (the displays going dark for an instant): one short line, and
	# nothing is held back.
	watch._set_shown(false)
	watch._before_draw()
	assert(main.lines.is_empty(), "nothing is said in the first second")
	assert(not watch.holds_back("[STATS] 144 fps"), "nor held back")
	watch._set_shown(true)
	assert(main.lines.size() == 1 and main.lines[0].contains("was not shown for a moment ("), str(main.lines))
	main.lines.clear()

	# The headset comes off: said once it has lasted a second.
	watch._set_shown(false)
	watch._hidden_at -= FrameSessionWatch.ANNOUNCE_MSEC + 100
	watch._before_draw()
	assert(main.lines.size() == 1 and main.lines[0].begins_with("[SESSION] ") and main.lines[0].contains("is not being shown"), str(main.lines))
	watch._before_draw()
	assert(main.lines.size() == 1, "said once")
	assert(watch.holds_back("[STATS] 144 fps") and watch.holds_back("[FRAME-COST] x"))
	assert(not watch.holds_back("[STREAM] connection lost"), "anything that isn't a periodic reading is still written")
	watch._set_shown(false)
	assert(main.lines.size() == 1, "not shown twice in a row is one event")
	# And goes back on.
	watch._set_shown(true)
	assert(main.lines.size() == 2 and main.lines[1].contains("is being shown again after 1 s (2 once-a-second lines were held back)"), str(main.lines))
	assert(not watch.holds_back("[STATS] 144 fps"))

	# While not shown, a composition layer's viewport is held at "don't
	# update" in the renderer, from the first frame, and its node keeps the
	# mode the app gave it.
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var layer := OpenXRCompositionLayerQuad.new()
	layer.layer_viewport = viewport
	root.add_child(layer)
	watch._set_shown(false)
	watch._before_draw()
	assert(watch._viewports.has(viewport), "the layer's viewport is found")
	assert(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the node keeps its own mode")
	watch._set_shown(true)
	assert(watch._viewports.is_empty(), "handed back when shown again")

	print("test_frame_8a: all passed")
	quit(0)
