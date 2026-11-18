extends SceneTree

# Steam Frame 5j: Sleep When Put Down (ControllerTouch), Custom Buttons Off
# using the Default layout, and the Start Distance slider's steps.

class FakeHand:
	extends RefCounted
	var down := {}
	var trigger := 0.0
	func is_button_pressed(action: StringName) -> bool:
		return down.get(action, false)
	func get_float(action: StringName) -> float:
		return trigger if action == &"trigger" else 0.0
	func get_vector2(_action: StringName) -> Vector2:
		return Vector2.ZERO

func _touch() -> void:
	var touch := ControllerTouch.new()
	var hand := FakeHand.new()
	# Sensors never seen working (gloves, no sensors): never "put down".
	for i in 200:
		touch.update("right", hand, 0.014)
	assert(not touch.put_down("right"), "an unseen sensor must not put a controller to sleep")
	# A pressed trigger is a hand, but doesn't prove the sensors work.
	hand.trigger = 1.0
	touch.update("right", hand, 0.014)
	hand.trigger = 0.0
	for i in 200:
		touch.update("right", hand, 0.014)
	assert(not touch.known("right") and not touch.put_down("right"))
	# Held: grip sensor on. Thumb lifting off the stick changes nothing.
	hand.down[&"grip_touch"] = true
	hand.down[&"primary_touch"] = true
	touch.update("right", hand, 0.014)
	hand.down[&"primary_touch"] = false
	for i in 200:
		touch.update("right", hand, 0.014)
	assert(touch.known("right") and not touch.put_down("right"), "a held controller stays awake")
	# Let go: put down after a moment, not at once.
	hand.down[&"grip_touch"] = false
	for i in 20:  # 0.28 s
		touch.update("right", hand, 0.014)
	assert(not touch.put_down("right"), "a finger lifting briefly isn't putting it down")
	for i in 40:
		touch.update("right", hand, 0.014)
	assert(touch.put_down("right"), "no hand for a second: put down")
	# A thumb by the buttons is a hand.
	hand.down[&"face_touch"] = true
	touch.update("right", hand, 0.014)
	assert(not touch.put_down("right"), "any sensor wakes it")
	hand.down[&"face_touch"] = false
	for i in 60:
		touch.update("right", hand, 0.014)
	assert(touch.put_down("right"))
	# A face button's click alone doesn't wake it...
	hand.down[&"frame_y"] = true
	touch.update("right", hand, 0.014)
	assert(touch.put_down("right"), "Y must not wake a sleeping controller")
	hand.down[&"frame_y"] = false
	# ...a pulled trigger does, even without the sensors (through cloth).
	hand.trigger = 1.0
	touch.update("right", hand, 0.014)
	assert(not touch.put_down("right"))
	hand.trigger = 0.0
	# The other controller is its own case.
	assert(not touch.put_down("left"))

class FakeMain:
	extends Node
	var controller_mapper = null
	var ui_controller = null
	var is_streaming := false
	var log_lines: Array[String] = []
	func _log(line: String) -> void:
		log_lines.append(line)

func _buttons() -> void:
	var main := FakeMain.new()
	var bb := ButtonBindings.new(main)
	bb.enabled = true
	bb.bindings["a"] = "none"
	assert(bb.active_action("a") == "none")
	assert(bb.owns_buttons())
	bb.enabled = false
	assert(bb.active_action("a") == ButtonBindings.CONTROLS["a"][3], "off: A does its Default job")
	assert(bb.bindings["a"] == "none", "off keeps your own layout for later")
	assert(bb.owns_buttons(), "off no longer hands the buttons back to stock Nightfall")
	for c in ButtonBindings.CONTROLS:
		assert(ButtonBindings.ACTIONS.has(bb.active_action(c)))
	main.free()

func _start_distance() -> void:
	assert(is_equal_approx(SettingsController.start_distance_from_slider(0), 1.0))
	assert(is_equal_approx(SettingsController.start_distance_from_slider(100), 6.0))
	assert(is_equal_approx(SettingsController.start_distance_from_slider(25), 2.25))
	assert(is_equal_approx(SettingsController.start_distance_from_slider(100), AppSettings.SCREEN_START_DISTANCE_DEFAULT), "the default is the far end")
	for v in range(0, 101, 5):
		assert(SettingsController.start_distance_to_slider(SettingsController.start_distance_from_slider(v)) == v)
	assert(SettingsController.start_distance_to_slider(2.16) == 25)  # a 5i-era value lands on the default step

func _initialize() -> void:
	_touch()
	_buttons()
	_start_distance()
	print("All frame_5j tests passed")
	quit()
