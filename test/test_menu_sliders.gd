extends SceneTree

# Steam Frame menu sliders: the value you are on holds until the pointer
# clearly leaves it, the default value is easier to land on, and a change in
# the last moment before the trigger is released is taken back.

class FakeMain extends Node3D:
	var ui_visible := true

var _calls: Array = []
var _controller: UIController
var _btn: Button
var _step := 0.0

func _init():
	call_deferred("_run")

func _press(pressed: bool, at_step: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = Vector2(UIController.SLIDER_MARGIN + at_step * _step, 40)
	_controller._on_slider_input(e, _btn, _record)

func _move(at_step: float) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = Vector2(UIController.SLIDER_MARGIN + at_step * _step, 40)
	_controller._on_slider_input(e, _btn, _record)

func _record(value: int, commit: bool) -> void:
	_calls.append([value, commit])
	_controller.set_slider_value(_btn, value)

func _reset(value: int) -> void:
	_calls.clear()
	_btn.set_meta("slider_dragging", false)
	_controller.set_slider_value(_btn, value)

func _run():
	var main := FakeMain.new()
	root.add_child(main)
	_controller = UIController.new(main)
	_btn = Button.new()
	_btn.size = Vector2(250, 132)
	_btn.set_meta("slider", true)
	_btn.set_meta("slider_value", -1)
	main.add_child(_btn)
	_step = (_btn.size.x - UIController.SLIDER_MARGIN * 2.0) / 20.0

	# A click goes straight to the spot, and a small slip on release keeps it.
	_reset(0)
	_press(true, 12.0)
	_press(false, 12.3)
	assert(_calls == [[60, false], [60, true]], "click should set and commit 60: %s" % [_calls])

	# Dragging: a wobble of under 0.8 of a step stays on the value...
	_reset(0)
	_press(true, 6.0)
	_move(6.7)
	assert(_calls == [[30, false]], "a wobble must not change the value: %s" % [_calls])
	# ...and a clear move changes it.
	_move(7.0)
	_move(10.0)
	assert(_calls[-1] == [50, false])
	# Held on 50, then the release jolts the pointer onto the next step.
	OS.delay_msec(UIController.SLIDER_RELEASE_GUARD_MS + 60)
	_move(10.9)
	assert(_calls[-1] == [55, false])
	_press(false, 10.9)
	assert(_calls[-1] == [50, true], "the jolt on release must be taken back: %s" % [_calls])
	assert(int(_btn.get_meta("slider_value")) == 50)

	# A change made well before the release is kept.
	_reset(0)
	_press(true, 6.0)
	_move(10.0)
	OS.delay_msec(UIController.SLIDER_RELEASE_GUARD_MS + 60)
	_press(false, 10.2)
	assert(_calls[-1] == [50, true], "a settled value must be kept: %s" % [_calls])

	# The default value catches the pointer from further away, but the steps
	# next to it can still be reached.
	_btn.set_meta("slider_detent", 80)
	_reset(0)
	_press(true, 15.3)
	assert(_calls[-1] == [80, false], "15.3 steps should land on the default (16): %s" % [_calls])
	_move(16.8)
	assert(_calls[-1] == [80, false])
	_move(17.0)
	assert(_calls[-1] == [85, false], "the step after the default must be reachable: %s" % [_calls])
	_press(false, 17.0)

	# Fifteen-step sliders (Separation) still reach both ends.
	_btn.remove_meta("slider_detent")
	_btn.set_meta("slider_steps", 15)
	_step = (_btn.size.x - UIController.SLIDER_MARGIN * 2.0) / 15.0
	_reset(50)
	_press(true, 0.0)
	_press(false, 0.0)
	assert(_calls[-1] == [0, true])
	_reset(50)
	_press(true, 15.0)
	_press(false, 15.0)
	assert(_calls[-1] == [100, true])

	# A disabled slider ignores input.
	_reset(40)
	_btn.disabled = true
	_press(true, 3.0)
	_press(false, 3.0)
	assert(_calls.is_empty())

	print("All menu_sliders tests passed")
	quit()
