extends SceneTree

# Steam Frame 5r: the tracking guard no longer pins or hides a controller
# just because no finger is on it, and bending the wrist while holding a grab
# no longer pushes the screen.

class FakeTouch:
	extends RefCounted
	var down := {}
	func put_down(side: String) -> bool:
		return down.get(side, false)

class FakeMain:
	extends Node3D
	var right_hand: XRController3D
	var left_hand: XRController3D
	var controller_touch := FakeTouch.new()
	var xr_camera: Node3D
	var grab_start_node_pos := Vector3(0, 1.6, -3)
	var grab_forward := Vector3(0, 0, -1)
	var log_lines: Array[String] = []
	func _log(line: String) -> void:
		log_lines.append(line)
	func on_controller_tracking_changed(_side: String, _lost: bool) -> void:
		pass

const DT := 1.0 / 72.0

var _tracker: XRPositionalTracker

# One frame: the runtime reports `xf` (the engine copies it onto the node),
# then the guard runs.
func _frame(main: FakeMain, guard: ControllerTrackingGuard, xf: Transform3D) -> void:
	_tracker.set_pose(&"aim", xf, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	main.right_hand.transform = xf
	guard._step(DT, true)

func _guard(main: FakeMain) -> void:
	_tracker = XRPositionalTracker.new()
	_tracker.type = XRServer.TRACKER_CONTROLLER
	_tracker.name = &"right_hand"
	XRServer.add_tracker(_tracker)
	var guard := ControllerTrackingGuard.new()
	guard.setup(main)
	var h: Dictionary = guard._hands["right"]

	# Carried about with no finger on a sensor (held by its ring, say): it
	# turns, so it is never pinned and its model is never hidden.
	main.controller_touch.down["right"] = true
	for i in 72 * 20:
		var t := i * DT
		_frame(main, guard, Transform3D(Basis(Vector3.UP, t * 0.5), Vector3(sin(t), 1.0, -0.3)))
		assert(not h["pinned"], "untouched alone must not pin")
		assert(not guard.hide_model("right"), "untouched alone must not hide the model")
	assert(main.right_hand.transform.origin.distance_to(Vector3(sin(20.0 - DT), 1.0, -0.3)) < 0.001)

	# Laid down: still, so pinned where it lies. Reported where it is: shown.
	var rest := Transform3D(Basis(), Vector3(0.2, 0.7, -0.4))
	for i in 72 * 20:
		_frame(main, guard, rest)
	assert(h["pinned"] and not guard.hide_model("right"))

	# The reported position wanders off (covered by a blanket). The pointer
	# stays where the controller lies; the model stays for 12 s, then hides.
	var gone := Transform3D(Basis(), rest.origin + Vector3(0.0, 0.25, 0.0))
	for i in int(72 * 11.5):
		_frame(main, guard, gone)
		assert(not guard.hide_model("right"), "hidden too soon")
		assert(main.right_hand.transform.origin.is_equal_approx(rest.origin))
	for i in 72:
		_frame(main, guard, gone)
	assert(guard.hide_model("right"), "12 s away from where it lies, untouched: hidden")

	# A finger on it: shown at once.
	main.controller_touch.down["right"] = false
	_frame(main, guard, gone)
	assert(not guard.hide_model("right"))

	# Hidden again, then the reported position comes back: shown after 0.5 s.
	main.controller_touch.down["right"] = true
	for i in 72 * 13:
		_frame(main, guard, gone)
	assert(guard.hide_model("right"))
	for i in 20:
		_frame(main, guard, rest)
	assert(guard.hide_model("right"))
	for i in 30:
		_frame(main, guard, rest)
	assert(not guard.hide_model("right"))

	# Wandering in and out of place never adds up to 12 s.
	for i in 72 * 30:
		_frame(main, guard, gone if (i / 72) % 8 < 7 else rest)
	assert(not guard.hide_model("right"))

	XRServer.remove_tracker(_tracker)
	guard.free()

# A grab of a screen 3 m away, one second long: the wrist joint moves
# push_m forward while the controller's front end swings bend_deg about it.
func _grab(xi, bend_deg: float, push_m: float) -> float:
	xi._carry_init = false
	xi.main.grab_forward = Vector3(0, 0, -1)
	var wrist := Vector3(0.25, 1.2, -0.30)
	var tip := Vector3(0, 0.05, -0.15)
	for i in 73:
		var f := i / 72.0
		var b := Basis(Vector3.RIGHT, deg_to_rad(bend_deg) * f)
		xi._grab_step(wrist + Vector3(0, 0, -push_m * f) + b * tip, 6.0, 12.0, b)
	return (xi._grab_pos - xi.main.xr_camera.global_position).length()

func _wrist(main: FakeMain) -> void:
	var xi = load("res://src/xr_interaction.gd").new(main)
	assert(absf(_grab(xi, 30.0, 0.0) - 3.0) < 0.05, "bending the wrist up must not pull the screen in")
	assert(absf(_grab(xi, -30.0, 0.0) - 3.0) < 0.05, "bending the wrist down must not push the screen away")
	assert(absf(_grab(xi, 0.0, 0.10) - 4.2) < 0.01, "a straight push counts in full")
	assert(absf(_grab(xi, 0.0, -0.10) - 1.8) < 0.01, "a straight pull counts in full")
	assert(_grab(xi, 10.0, 0.20) > 4.8, "a push with a little wrist in it still pushes")

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var main := FakeMain.new()
	main.right_hand = XRController3D.new()
	main.right_hand.tracker = &"right_hand"
	main.right_hand.pose = &"aim"
	main.xr_camera = Node3D.new()
	main.xr_camera.position = Vector3(0, 1.6, 0)
	root.add_child(main)
	main.add_child(main.right_hand)
	main.add_child(main.xr_camera)
	_guard(main)
	_wrist(main)
	main.queue_free()
	print("All frame_5r tests passed")
	quit()
	return true
