extends SceneTree

# Steam Frame 6o: a stream setting changed while the stream is restarting is
# not lost. (Bitrate pressed on to 120 during a restart stayed at 60: the
# restart under way had already read 60, and the later presses asked for a
# restart while there was no stream to restart.)

class FakeMain:
	extends Node3D
	var is_streaming := true
	var current_host_id := 3
	var session_lifecycle := SessionLifecycle.new()
	var log_lines: Array[String] = []
	func _log(line: String) -> void:
		log_lines.append(line)

func _run() -> void:
	await process_frame  # nodes are only in the tree once the loop runs
	var owner := FakeMain.new()
	root.add_child(owner)
	var controller := SettingsController.new(owner)

	# During a restart the request is noted, not started and not dropped.
	owner.session_lifecycle.request_restart()
	owner.is_streaming = false
	controller._schedule_stream_restart()
	assert(controller._restart_again and not controller._restart_pending)

	# The stream went away instead of coming back: nothing is owed.
	controller.on_session_phase(SessionLifecycle.Phase.SERVER_SELECTION)
	assert(not controller._restart_again)

	# The setting was put back (voice stepping does this): nothing is owed.
	controller._schedule_stream_restart(0.8, 0.0, true)
	assert(controller._restart_again and controller._restart_again_ends_host_session)
	controller.cancel_stream_restart()
	assert(not controller._restart_again and not controller._restart_again_ends_host_session)

	# Still restarting: the debt is kept.
	controller._schedule_stream_restart()
	controller.on_session_phase(SessionLifecycle.Phase.RESTARTING)
	assert(controller._restart_again)

	# The stream is back: one more restart is asked for, after a moment.
	owner.session_lifecycle.stream_started()
	owner.is_streaming = true
	controller.on_session_phase(SessionLifecycle.Phase.STREAMING)
	assert(not controller._restart_again and not controller._restart_pending)
	await create_timer(0.5).timeout
	assert(controller._restart_pending, "the owed restart is waiting out its pause")
	assert(owner.log_lines.any(func(line): return line.contains("restarting once more")))
	controller.cancel_stream_restart()  # this test has no stream to restart
	assert(not controller._restart_pending)

	# With nothing owed, coming back to streaming asks for nothing.
	controller.on_session_phase(SessionLifecycle.Phase.STREAMING)
	await create_timer(0.5).timeout
	assert(not controller._restart_pending)

	owner.queue_free()
	print("All frame_6o tests passed")
	quit(0)

func _init() -> void:
	_run()
