class_name EyeGaze
extends RefCounted

# Steam Frame eye tracking (OpenXR XR_EXT_eye_gaze_interaction), used for
# eye-tracked foveation. The log says only whether it is available: nothing
# about where you look is written down or sent anywhere. (Builds 6e to 8m
# also logged the gaze direction and the tracker's raw reading, while it was
# being got to work; taken out for the first release.)

const TRACKER := &"/user/eyes_ext"
const POSE_NAMES: Array[StringName] = [&"default", &"default_pose"]

var main: Node3D
var _last_seen_ms := -100000
var _logged_state := -1 # -1 unknown, 0 none, 1 available
var _started_ms := 0

func _init(p_main: Node3D) -> void:
	main = p_main
	_started_ms = Time.get_ticks_msec()

# Returns [origin, direction] in world space, or [] when there is no fresh gaze.
func gaze_ray() -> Array:
	var tracker := XRServer.get_tracker(TRACKER) as XRPositionalTracker
	if tracker == null:
		return []
	for pn in POSE_NAMES:
		var pose := tracker.get_pose(pn)
		if pose and pose.has_tracking_data and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE:
			var t: Transform3D = main.xr_origin.global_transform * pose.transform
			_last_seen_ms = Time.get_ticks_msec()
			return [t.origin, (-t.basis.z).normalized()]
	return []

func available() -> bool:
	gaze_ray()
	return Time.get_ticks_msec() - _last_seen_ms < 1500

# Call every frame or so: logs once whether eye tracking works on this headset.
func log_status() -> void:
	var ok := available()
	if ok and _logged_state != 1:
		_logged_state = 1
		main._log("[EYES] Eye tracking available")
	elif not ok and _logged_state == -1 and Time.get_ticks_msec() - _started_ms > 8000:
		_logged_state = 0
		var xi = XRServer.find_interface("OpenXR")
		var sup := "unknown"
		if xi and xi.has_method("is_eye_gaze_interaction_supported"):
			sup = "yes" if xi.is_eye_gaze_interaction_supported() else "no"
		main._log("[EYES] No eye tracking data yet (checked for 8 s; runtime supports eye gaze: %s; tracker %s)" % [
			sup, "found" if XRServer.get_tracker(TRACKER) != null else "missing"])

# True when your gaze passes within a rectangle on node's plane: centred at
# center_local (node-local), half sizes in metres along node's X and Y.
func is_looking_at(node: Node3D, center_local: Vector3, half_w: float, half_h: float) -> bool:
	var ray := gaze_ray()
	if ray.is_empty() or node == null:
		return false
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var xf: Transform3D = node.global_transform.orthonormalized()
	var n: Vector3 = xf.basis.z
	var c: Vector3 = node.global_transform * center_local
	var denom := d.dot(n)
	if absf(denom) < 0.05:
		return false
	var t := (c - o).dot(n) / denom
	if t <= 0.0:
		return false
	var off: Vector3 = (o + d * t) - c
	return absf(off.dot(xf.basis.x)) <= half_w and absf(off.dot(xf.basis.y)) <= half_h
