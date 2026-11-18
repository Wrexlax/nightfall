class_name ControllerTrackingGuard
extends Node

# Steam Frame: never show a guessed controller position.
#
# When SteamVR loses sight of a controller (under a blanket, set on the floor
# out of view) it keeps reporting a position worked out from the motion
# sensors, which drifts - the model and pointer ray wander off. Three checks:
#
# 1. Lost: SteamVR marks the pose as not properly tracked. The controller is
#    held at its last tracked position; after HIDE_AFTER seconds it counts as
#    put down (model and ray hidden). Its SteamVR model is hidden at once,
#    since that model places itself and would show the guess.
# 2. Still: SteamVR doesn't always admit it is guessing (3l test: a
#    controller on the floor drifted up to knee height while still marked as
#    tracked). A hand-held controller always turns a little; one lying still
#    doesn't. So while it has hardly turned for STILL_TIME, its position is
#    pinned where it came to rest. Turning it again releases the pin at once.
# 3. Jumps: a sudden leap of more than JUMP_METERS in one frame (seen when a
#    controller is switched off) is ignored until the new position holds for
#    JUMP_CONFIRM frames.
#
# 4. Drift under a pin: SteamVR's own model places itself, so the pin can't
#    hold it. A controller that is pinned (lying still), has no finger on it
#    (ControllerTouch.put_down()) and whose reported position has been away
#    from the pin for PIN_DRIFT_HIDE_AFTER seconds can only be a guess: its
#    model is hidden until the position is back or it is picked up.
#    (5n pinned any untouched controller at once and 5o hid its model as
#    soon as it drifted. That froze the pointer and hid the model of a
#    controller being moved without a finger on a sensor, whatever the
#    Cursor Follow setting. Touch alone never pins or hides now.)
#
# Rotation always stays live, and buttons keep working throughout.

const HIDE_AFTER := 1.0
const STILL_TIME := 0.6
const STILL_ENTER_DEG_S := 1.5
const STILL_EXIT_DEG_S := 4.0
# A pinned controller no hand is on, whose reported position has wandered this
# far from the pin (until it is back within the second figure), has its
# SteamVR model hidden.
const PIN_DRIFT_HIDE := 0.08
const PIN_DRIFT_SHOW := 0.04
const PIN_DRIFT_HIDE_AFTER := 12.0  # seconds away from the pin before the model is hidden
const PIN_DRIFT_SHOW_AFTER := 0.5   # seconds back in place before it shows again
const JUMP_METERS := 0.5
const JUMP_CONFIRM := 10

var main: Node3D
var _hands: Dictionary = {}

func setup(p_main: Node3D) -> void:
	main = p_main
	name = "ControllerTrackingGuard"
	process_priority = -1000
	process_physics_priority = -1000
	for side in ["right", "left"]:
		_hands[side] = {
			"node": main.right_hand if side == "right" else main.left_hand,
			"ever": false, "frozen": false, "lost": 0.0, "xf": Transform3D(),
			"prev_basis": Basis(), "still_t": 0.0, "pinned": false, "pin_origin": Vector3.ZERO,
			"jump_frames": 0, "untouched": false, "drifted": false, "away_t": 0.0, "back_t": 0.0,
		}

func is_lost(side: String) -> bool:
	var h = _hands.get(side)
	if h == null:
		return false
	return not h["ever"] or h["lost"] >= HIDE_AFTER

# SteamVR's own model of this controller should be hidden right now.
func hide_model(side: String) -> bool:
	var h = _hands.get(side)
	return h != null and (not h["ever"] or h["frozen"] or h["drifted"])

static func _tracked(node: XRController3D) -> bool:
	if node == null:
		return false
	var tracker = XRServer.get_tracker(node.tracker)
	if tracker == null or not (tracker is XRPositionalTracker):
		return false
	var pose: XRPose = tracker.get_pose(node.pose)
	return pose != null and pose.has_tracking_data \
		and pose.tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_HIGH

# Where the runtime says this controller is right now, in the same space as
# the node's transform, or null.
static func _reported_origin(node: XRController3D):
	var tracker = XRServer.get_tracker(node.tracker)
	if tracker == null or not (tracker is XRPositionalTracker):
		return null
	var pose: XRPose = tracker.get_pose(node.pose)
	return pose.get_adjusted_transform().origin if pose != null else null

func _step(delta: float, is_render_frame: bool) -> void:
	for side in _hands:
		var h: Dictionary = _hands[side]
		var node: XRController3D = h["node"]
		if node == null:
			continue
		var was_lost := is_lost(side)
		var was_hidden := hide_model(side)
		var tracked := _tracked(node)
		# 3. Jump check (render frames only, once the hand has a history).
		if tracked and h["ever"] and is_render_frame:
			if node.transform.origin.distance_to(h["xf"].origin) > JUMP_METERS:
				h["jump_frames"] += 1
				if h["jump_frames"] < JUMP_CONFIRM:
					tracked = false
				else:
					main._log("[TRACK] %s controller jump accepted" % side)
			else:
				h["jump_frames"] = 0
		if tracked:
			if h["frozen"]:
				main._log("[TRACK] %s controller tracked again" % side)
			elif not h["ever"]:
				main._log("[TRACK] %s controller tracked" % side)
			h["ever"] = true
			h["frozen"] = false
			h["lost"] = 0.0
			# 2. Stillness pin.
			if is_render_frame and delta > 0.0:
				var prev: Basis = h["prev_basis"]
				var q: Quaternion = (prev.orthonormalized().inverse() * node.transform.basis.orthonormalized()).get_rotation_quaternion()
				var turn_deg: float = rad_to_deg(2.0 * acos(clampf(absf(q.w), 0.0, 1.0)))
				var rate: float = turn_deg / delta
				h["prev_basis"] = node.transform.basis
				var touch = main.get("controller_touch")
				var untouched: bool = touch != null and touch.put_down(side)
				h["untouched"] = untouched
				if h["pinned"]:
					if rate > STILL_EXIT_DEG_S:
						h["pinned"] = false
						h["still_t"] = 0.0
				elif rate < STILL_ENTER_DEG_S:
					h["still_t"] += delta
					if h["still_t"] >= STILL_TIME:
						h["pinned"] = true
						h["pin_origin"] = h["xf"].origin
						main._log("[TRACK] %s controller lying still - position pinned" % side)
				else:
					h["still_t"] = 0.0
			if h["pinned"] and h["untouched"]:
				# 4. Drift under a pin. Measured against the tracker's own
				# pose: this node's position is the pin from the last step
				# until the engine refreshes it, and comparing with that made
				# the model flash every frame (5o).
				var reported = _reported_origin(node)
				if reported != null and is_render_frame:
					var off: float = (reported as Vector3).distance_to(h["pin_origin"])
					if not h["drifted"]:
						if off > PIN_DRIFT_HIDE:
							h["away_t"] += delta
							if h["away_t"] >= PIN_DRIFT_HIDE_AFTER:
								h["drifted"] = true
								h["back_t"] = 0.0
								main._log("[TRACK] %s controller: lying still, untouched, reported %.0f cm from where it lies for %d s - model hidden" % [side, off * 100.0, int(PIN_DRIFT_HIDE_AFTER)])
						else:
							h["away_t"] = 0.0
					elif off < PIN_DRIFT_SHOW:
						h["back_t"] += delta
						if h["back_t"] >= PIN_DRIFT_SHOW_AFTER:
							h["drifted"] = false
							h["away_t"] = 0.0
							main._log("[TRACK] %s controller: reported position back in place - model shown" % side)
					else:
						h["back_t"] = 0.0
				node.transform = Transform3D(node.transform.basis, h["pin_origin"])
			else:
				h["drifted"] = false
				h["away_t"] = 0.0
				if h["pinned"]:
					node.transform = Transform3D(node.transform.basis, h["pin_origin"])
			h["xf"] = node.transform
		else:
			if h["ever"]:
				if not h["frozen"]:
					h["frozen"] = true
					main._log("[TRACK] %s controller lost - holding its last tracked position" % side)
				node.transform = h["xf"]
			if is_render_frame:
				h["lost"] += delta
		if was_lost != is_lost(side) or was_hidden != hide_model(side):
			main.on_controller_tracking_changed(side, is_lost(side))

func _physics_process(delta: float) -> void:
	_step(delta, false)

func _process(delta: float) -> void:
	_step(delta, true)
