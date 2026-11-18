class_name ControllerTouch
extends RefCounted

## Steam Frame: is a hand on this controller?
##
## The Frame controllers have capacitive touch sensors on the grip, trigger,
## thumbstick and face buttons (Steamworks, "Steam Frame input"; bound in
## openxr_action_map.tres). A controller lying in a lap or on a desk moves
## with whatever it rests on, so movement alone can't tell it from one being
## held: its pointer wanders over the screen and drags the PC's mouse along.
## With no finger on any sensor for PUT_DOWN_AFTER seconds, it counts as put
## down (Control > Cursor Follow: Capacitive Touch; main._hand_inactive_time()).
##
## Which sensors: all of them (trigger, grip, thumbstick, and "face_touch":
## A B X Y, Menu, the bumper; on the left the D-pad, View, the bumper). With
## only trigger, thumbstick and grip (5l, 5m) the pointer was slow to come
## back on pick-up and dropped out in the hand, because the grip sensor needs
## a firm squeeze and a relaxed thumb rests by the buttons. The A sensor
## flickers ten times a second with a thumb near it; PUT_DOWN_AFTER rides
## over that. In the 5k log no sensor fired with the controller lying on a
## desk or in a lap.
##
## Nothing is trusted until that controller has reported a touch at least
## once, so gloves, a runtime without these sensors or a refused binding
## leave things exactly as they were. A pulled trigger or grip, or a pushed
## thumbstick, counts as a hand whatever the sensors say.
##
## The other buttons do not: they go on working on a sleeping controller
## without waking its pointer. In the 5k test Y was held to dictate with
## the controller lying in the lap, and each press woke the pointer, which
## then moved the PC's cursor for as long as the button was held.

const TOUCH_ACTIONS: Array[StringName] = [&"grip_touch", &"trigger_touch", &"primary_touch", &"face_touch"]
const PUT_DOWN_AFTER := 0.6

var _seen := {}       # side -> true once that controller has reported a touch
var _untouched := {}  # side -> seconds since anything touched or pressed it

## Call once a frame for each controller.
func update(side: String, hand: Object, delta: float) -> void:
	if hand == null:
		return
	if _touching(hand):
		_seen[side] = true
		_untouched[side] = 0.0
	elif _pressing(hand):
		_untouched[side] = 0.0
	else:
		_untouched[side] = float(_untouched.get(side, 0.0)) + delta

## The sensors work on this controller and no hand has been on it for a moment.
func put_down(side: String) -> bool:
	return _seen.get(side, false) and float(_untouched.get(side, 0.0)) >= PUT_DOWN_AFTER

## Whether this controller's sensors have been seen working.
func known(side: String) -> bool:
	return _seen.get(side, false)

static func _touching(hand: Object) -> bool:
	for action in TOUCH_ACTIONS:
		if hand.is_button_pressed(action):
			return true
	return false

static func _pressing(hand: Object) -> bool:
	if hand.get_float(&"trigger") > 0.1 or hand.get_float(&"grip") > 0.1:
		return true
	var stick: Vector2 = hand.get_vector2(&"primary")
	return absf(stick.x) > 0.1 or absf(stick.y) > 0.1
