class_name XRInteraction
extends RefCounted

var main: Node3D
var pointer_on_ui: bool = false
var _tab_ray_exclusion: CollisionObject3D
var _tab_priority_ray: RayCast3D

var _active_hand: String = "right"
var _pinch_start_time: float = 0.0
var _pinch_start_pos: Vector2 = Vector2.ZERO
var _pinch_start_screen: VRScreen = null
var _click_pending_release: bool = false
var _trigger_was_pressed: bool = false
var _grip_was_pressed: bool = false
var _trigger_press_msec: int = -1
var _grip_press_msec: int = -1
var _double_click_chord_active: bool = false
var _last_follow_pt := Vector2i(-1, -1)
var _cursor_parked := false
var _parked_at_pointer := Vector2i(-1, -1)
const DOUBLE_CLICK_MS := 500
const DOUBLE_CLICK_PX := 24.0
var _last_click_pos := Vector2(-1000, -1000)
var _last_click_ms := -100000.0
var _last_click_screen = null
var _press_was_still := false
var _corner_resize_started: bool = false
var _auto_primary: String = ""
var _auto_reset_timer: float = 0.0
var _right_on_screen: bool = false
var _left_on_screen: bool = false
var _other_hand_clicking: bool = false
var _secondary_press_viewport: SubViewport = null
var _secondary_press_was_keyboard: bool = false
var _right_inactive_time: float = 0.0
var _left_inactive_time: float = 0.0
var _last_known_right_pos: Vector3 = Vector3.ZERO
var _last_known_left_pos: Vector3 = Vector3.ZERO
var _last_known_right_rot: Vector3 = Vector3.ZERO
var _last_known_left_rot: Vector3 = Vector3.ZERO

var _primary_ui_pixel: Vector2 = Vector2(-1, -1)
var _secondary_ui_pixel: Vector2 = Vector2(-1, -1)
var _ui_button_states: Array = []
var _last_ui_style: Dictionary = {}
var _screen_shortcut_press_active: bool = false
var _browser_press_owner: RefCounted
var _last_pointer_screen: VRScreen
var _last_hand_input_state: String = ""
var _pointer_suspended := false
var _pointer_rearm_required := false

func set_application_suspended(suspended: bool) -> void:
	_pointer_suspended = suspended
	cancel_transient_interactions("application paused" if suspended else "application resumed")
	if not suspended and not main._is_using_hands:
		# Hand aiming uses top-level rays. Never reuse its last world-space
		# transform when physical controllers regain ownership after standby.
		for ray in [main.hand_raycast, main.left_hand_raycast]:
			if ray:
				ray.top_level = false
				ray.transform = Transform3D.IDENTITY

static func controller_pose_valid(hand: XRController3D) -> bool:
	if not hand or not hand.get_is_active() or not hand.get_has_tracking_data(): return false
	var pose := hand.get_pose()
	return pose != null and pose.has_tracking_data and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE

func _pointer_input_ready(tracked: bool, pressed: bool) -> bool:
	if _pointer_suspended or not tracked:
		_pointer_rearm_required = true
		return false
	if _pointer_rearm_required:
		if pressed: return false
		_pointer_rearm_required = false
	return true

func _active_pointer_tracked() -> bool:
	if not main.is_xr_active: return true
	if main._is_using_hands:
		if hand_aim_available(): return hand_aim_valid(_active_hand)
		var tracker = XRServer.get_tracker("/user/hand_tracker/" + _active_hand)
		return tracker != null and tracker.get_has_tracking_data()
	return controller_pose_valid(main.left_hand if _active_hand == "left" else main.right_hand)

func _pointer_controls_held() -> bool:
	if _is_now_clicking() or _is_now_gripping(): return true
	if main.is_xr_active and not main._is_using_hands:
		for hand in [main.left_hand, main.right_hand]:
			if hand and (hand.get_float("trigger") > 0.1 or hand.get_float("grip") > 0.1): return true
	return false

# Chord mode waits this long before committing a grip to right-click, giving a
# near-simultaneous trigger press time to turn the pair into an explicit
# double-click. This stays below the existing 150 ms tap-vs-drag threshold.
const DOUBLE_CLICK_CHORD_MSEC := 150 # trigger and grip pressed within this many ms count as together

func populate_ui_buttons(buttons: Array):
	_ui_button_states = buttons

func cancel_transient_interactions(reason: String = "") -> void:
	_pointer_rearm_required = true
	if main.screen_sources:
		main.screen_sources.cancel_browser_pointers_except()
	# Tracking poses are discontinuous across headset removal or app pause.
	# A saved drag baseline would move a screen when the next pose arrives.
	if main.is_streaming and main.stream_backend:
		if main.was_clicking and _pinch_start_screen != null:
			main.stream_backend.send_mouse_button_event(8, 1)
		if main.was_right_clicking:
			main.stream_backend.send_mouse_button_event(8, 3)
	if _other_hand_clicking:
		_end_secondary_press(_secondary_ui_pixel)
	var moved_screen = main.grabbed_node is VRScreen or main.grabbed_corner_screen != null
	if is_instance_valid(main.grabbed_bar) and is_instance_valid(main.grabbed_node):
		_set_grab_bar_color(main.grabbed_bar, _bar_base_color(main.grabbed_node), 0.01)
	if is_instance_valid(main.grabbed_corner_screen):
		if main.grabbed_corner_idx >= 0 and main.grabbed_corner_idx < main.grabbed_corner_screen.corner_handles.size():
			_set_corner_color(main.grabbed_corner_screen.corner_handles[main.grabbed_corner_idx], Color.WHITE, 0.05)
		if _corner_resize_started:
			main.grabbed_corner_screen.end_corner_resize()
	main.grabbed_node = null
	_carry_init = false
	main.grabbed_bar = null
	main.grabbed_corner_idx = -1
	main.grabbed_corner_screen = null
	main.grab_start_hand_basis = Basis()
	main.grab_start_node_basis = Basis()
	main.grab_start_node_euler = Vector3.ZERO
	main.grab_group_start_transforms.clear()
	main.grab_snap_candidate = Vector2i(-1, -1)
	main.was_clicking = false
	main.was_right_clicking = false
	_pinch_start_screen = null
	_pinch_start_time = 0.0
	_pinch_start_pos = Vector2.ZERO
	_click_pending_release = false
	_trigger_was_pressed = false
	_grip_was_pressed = false
	_trigger_press_msec = -1
	_grip_press_msec = -1
	_double_click_chord_active = false
	_corner_resize_started = false
	_screen_shortcut_press_active = false
	_browser_press_owner = null
	_secondary_press_viewport = null
	_secondary_press_was_keyboard = false
	pointer_on_ui = false
	if moved_screen and main.state_manager:
		main.state_manager.save_state()
	if not reason.is_empty():
		main._log("[INPUT] Cancelled transient interactions: %s" % reason)

func _init(owner: Node3D):
	main = owner

func get_active_raycast() -> RayCast3D:
	if not main.is_xr_active:
		return main.mouse_raycast
	if _active_hand == "left" and main.left_hand_raycast:
		return main.left_hand_raycast
	return main.hand_raycast

func _get_hand_raycast(hand: String) -> RayCast3D:
	if hand == "left" and main.left_hand_raycast:
		return main.left_hand_raycast
	return main.hand_raycast

func hand_aim_available() -> bool:
	return XRServer.get_tracker("/user/fbhandaim/left") != null or XRServer.get_tracker("/user/fbhandaim/right") != null

func hand_aim_valid(hand: String) -> bool:
	var tracker = XRServer.get_tracker("/user/fbhandaim/" + hand)
	if not tracker:
		return false
	var pose = tracker.get_pose("default")
	# The vendor plugin publishes system_gesture only on right and
	# menu_gesture only on left. bool(null) is an invalid constructor call.
	var gesture_name := "menu_gesture" if hand == "left" else "system_gesture"
	return pose != null and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE and tracker.get_input(gesture_name) != true

func _get_hand_pinch_strength(tracker_name: String) -> float:
	var hand := "left" if tracker_name.ends_with("left") else "right"
	var aim = XRServer.get_tracker("/user/fbhandaim/" + hand)
	var runtime_strength := 0.0
	if aim:
		if not hand_aim_valid(hand):
			return 0.0
		runtime_strength = float(aim.get_input("index_pinch_strength"))
	var tracker = XRServer.get_tracker(tracker_name)
	if not tracker:
		return runtime_strength
	var thumb_flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_TIP)
	var index_flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	if (thumb_flags & 8) == 0 or (index_flags & 8) == 0:
		return runtime_strength
	var thumb_tip = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var index_tip = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var dist = (index_tip - thumb_tip).length()
	return maxf(runtime_strength, clampf(1.0 - (dist - 0.015) / (0.045 - 0.015), 0.0, 1.0))

func _get_hand_grasp_strength(tracker_name: String) -> float:
	var hand := "left" if tracker_name.ends_with("left") else "right"
	var aim = XRServer.get_tracker("/user/fbhandaim/" + hand)
	if aim:
		return float(aim.get_input("middle_pinch_strength")) if hand_aim_valid(hand) and not bool(aim.get_input("index_pinch")) else 0.0
	var tracker = XRServer.get_tracker(tracker_name)
	if not tracker:
		return 0.0
	# Prevent right-click if left-click is fully active
	if _get_hand_pinch_strength(tracker_name) > 0.85:
		return 0.0
	var thumb_flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_TIP)
	var middle_flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP)
	if (thumb_flags & 8) == 0 or (middle_flags & 8) == 0:
		return 0.0
	var thumb_tip = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var middle_tip = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP).origin
	var dist = (middle_tip - thumb_tip).length()
	return clampf(1.0 - (dist - 0.015) / (0.045 - 0.015), 0.0, 1.0)

func _update_active_hand():
	if not main.is_xr_active:
		return
	if main._is_using_hands:
		# A press owns its hand until release, even when the other hand pinches.
		if main.was_clicking or main.was_right_clicking or main.grabbed_node or main.grabbed_corner_idx >= 0 or _trigger_was_pressed or _grip_was_pressed:
			return
		var right_has_data = false
		var left_has_data = false
		var right_tracker = XRServer.get_tracker("/user/hand_tracker/right")
		var left_tracker = XRServer.get_tracker("/user/hand_tracker/left")
		if right_tracker and right_tracker is XRHandTracker and right_tracker.get_has_tracking_data():
			right_has_data = true
		if left_tracker and left_tracker is XRHandTracker and left_tracker.get_has_tracking_data():
			left_has_data = true
		if hand_aim_available():
			right_has_data = hand_aim_valid("right")
			left_has_data = hand_aim_valid("left")
		var primary: int = main.controller_mapper.effective_primary_hand() if main.controller_mapper else ControllerMapper.PrimaryHand.RIGHT
		_active_hand = _select_tracked_hand(primary, right_has_data, left_has_data,
			_get_hand_pinch_strength("/user/hand_tracker/right"),
			_get_hand_pinch_strength("/user/hand_tracker/left"),
			_is_hand_on_screen("right"), _is_hand_on_screen("left"))
		return
	var primary = main.controller_mapper.effective_primary_hand() if main.controller_mapper else 0
	# A press (click, drag, grab) owns its hand until it is released. Switching
	# hands mid-grab made the grab maths jump by the distance between the two
	# controllers (x12) - that is what threw the keyboard through the ceiling.
	var busy: bool = main.was_clicking or main.was_right_clicking or main.grabbed_node != null \
		or main.grabbed_corner_idx >= 0
	if busy:
		_update_prev_triggers()
		return
	if _borrowed_hand != "":
		# The other hand took over for a grab. This runs twice a frame, so
		# keep it until that hand's trigger is let go, then hand control back.
		var bnode: XRController3D = main.left_hand if _borrowed_hand == "left" else main.right_hand
		if bnode and bnode.get_float("trigger") > 0.1:
			_active_hand = _borrowed_hand
			_update_prev_triggers()
			return
		_borrowed_hand = ""
	var sel: String
	match primary:
		ControllerMapper.PrimaryHand.RIGHT:
			sel = "right"
		ControllerMapper.PrimaryHand.LEFT:
			sel = "left"
		_:
			sel = _get_auto_primary()
	# Steam Frame: the other controller can take over with a fresh trigger pull.
	# Auto: it becomes the pointing hand. Right/Left: only for grabbing (grab
	# bars, corners, or the empty parts of the menu and keyboard), then control
	# returns to the chosen hand.
	if main.device_is_steam_frame:
		var other := "left" if sel == "right" else "right"
		var other_node: XRController3D = main.left_hand if other == "left" else main.right_hand
		if other_node and other_node.get_float("trigger") > 0.5 and _prev_trigger.get(other, 0.0) <= 0.5:
			if primary == ControllerMapper.PrimaryHand.AUTO:
				_auto_primary = other
				_auto_reset_timer = 0.0
				sel = other
			elif _hand_wants_grab(other):
				_borrowed_hand = other
				sel = other
				main._log("[GRAB] %s hand takes over for a grab" % other)
			else:
				var orc := _get_hand_raycast(other)
				var orole = PointerTarget.resolve(orc.get_collider()).role if orc and orc.is_colliding() else &"none"
				main._log("[GRAB] %s hand press, not a grab target (%s)" % [other, String(orole)])
	_active_hand = sel
	_update_prev_triggers()

var _borrowed_hand := ""
var _prev_trigger := {"right": 0.0, "left": 0.0}

func _update_prev_triggers() -> void:
	_prev_trigger["right"] = main.right_hand.get_float("trigger") if main.right_hand else 0.0
	_prev_trigger["left"] = main.left_hand.get_float("trigger") if main.left_hand else 0.0

# Whether this hand's ray is on something it could grab: a grab bar or
# corner, or (Steam Frame) an empty part of the menu or keyboard.
func _hand_wants_grab(hand: String) -> bool:
	var rc := _get_hand_raycast(hand)
	if not rc:
		return false
	if not rc.enabled:
		# A resting hand's ray is off; the pull that picks it up still counts.
		rc.enabled = true
		rc.force_raycast_update()
	if not rc.is_colliding():
		return false
	var col = rc.get_collider()
	var t = PointerTarget.resolve(col)
	if t.role in [&"grab_bar", &"corner"]:
		return true
	if t.role != &"panel":
		return false
	var panel = col.get_parent()
	var hit: Vector3 = rc.get_collision_point()
	if panel == main.ui_panel_3d:
		var lp: Vector3 = panel.to_local(hit)
		var px := Vector2(clampf((lp.x / (main._ui_mesh_size.x / 2.0) + 1.0) / 2.0, 0.0, 1.0) * main._ui_viewport_size.x,
			clampf(1.0 - (lp.y / (main._ui_mesh_size.y / 2.0) + 1.0) / 2.0, 0.0, 1.0) * main._ui_viewport_size.y + main.UI_TOOLTIP_STRIP_PX)
		return _is_ui_grab_bar(px) or _ui_point_is_empty(px)
	if main.virtual_keyboard and panel == main.virtual_keyboard.mesh_instance:
		var kb = main.virtual_keyboard
		var lp: Vector3 = kb.mesh_instance.to_local(hit)
		var px := Vector2((lp.x / (kb.mesh_size.x / 2.0) + 1.0) / 2.0 * kb.viewport_size.x,
			(1.0 - (lp.y / (kb.mesh_size.y / 2.0) + 1.0) / 2.0) * kb.viewport_size.y)
		return _is_kb_grab_bar(px) or kb.is_empty_spot(px)
	return false

func _select_tracked_hand(primary: int, right_valid: bool, left_valid: bool,
		right_pinch: float, left_pinch: float, right_target: bool, left_target: bool) -> String:
	# Explicit preference must not silently become the other hand. Invalid
	# runtime poses suppress input separately until the preferred hand returns.
	if primary == ControllerMapper.PrimaryHand.RIGHT:
		return "right"
	if primary == ControllerMapper.PrimaryHand.LEFT:
		return "left"
	if right_valid and left_valid:
		if left_pinch > 0.5 and right_pinch <= 0.5:
			return "left"
		if right_pinch > 0.5 and left_pinch <= 0.5:
			return "right"
		if right_target != left_target:
			return "right" if right_target else "left"
	elif right_valid:
		return "right"
	elif left_valid:
		return "left"
	return _active_hand

func _get_auto_primary() -> String:
	# A cached primary must not hold ownership after it has been put down.
	if main.right_hand_resting != main.left_hand_resting:
		_auto_primary = "left" if main.right_hand_resting else "right"
		return _auto_primary
	if _auto_primary != "":
		return _auto_primary
	if _right_on_screen and not _left_on_screen:
		_auto_primary = "right"
		_auto_reset_timer = 0.2
	elif _left_on_screen and not _right_on_screen:
		_auto_primary = "left"
		_auto_reset_timer = 0.2
	return _active_hand if _active_hand != "" else "right"

func _process_auto_primary(delta: float):
	if not _right_on_screen and not _left_on_screen:
		_auto_reset_timer -= delta
		if _auto_reset_timer <= 0.0:
			_auto_primary = ""
			_auto_reset_timer = 0.0
	else:
		_auto_reset_timer = 0.2

func _is_now_clicking() -> bool:
	if not main.is_xr_active:
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if main._is_using_hands:
		var aim = XRServer.get_tracker("/user/fbhandaim/" + _active_hand)
		if aim:
			return hand_aim_valid(_active_hand) and (bool(aim.get_input("index_pinch")) or _get_hand_pinch_strength("/user/hand_tracker/" + _active_hand) > 0.85)
		var tracker_name = "/user/hand_tracker/left" if _active_hand == "left" else "/user/hand_tracker/right"
		return _get_hand_pinch_strength(tracker_name) > 0.85
	else:
		var hand = main.left_hand if _active_hand == "left" else main.right_hand
		if hand:
			return hand.get_float("trigger") > 0.5
		return false

func _is_now_gripping() -> bool:
	if not main.is_xr_active:
		return false
	if main._is_using_hands:
		var aim = XRServer.get_tracker("/user/fbhandaim/" + _active_hand)
		if aim:
			return hand_aim_valid(_active_hand) and bool(aim.get_input("middle_pinch")) and not bool(aim.get_input("index_pinch"))
		var tracker_name = "/user/hand_tracker/left" if _active_hand == "left" else "/user/hand_tracker/right"
		return _get_hand_grasp_strength(tracker_name) > 0.85
	var hand = main.left_hand if _active_hand == "left" else main.right_hand
	if not hand:
		return false
	if hand.is_button_pressed("grip_click"):
		return true
	if hand.is_button_pressed("grip"):
		return true
	if hand.get_float("grip") > 0.2:
		return true
	return false

func _position_stream_pointer(active_raycast: RayCast3D) -> bool:
	var host_pt = _stream_host_point(active_raycast)
	if host_pt == null:
		return false
	var ref = main.layout.host_ref()
	main.stream_backend.send_mouse_position_event(host_pt.x, host_pt.y, ref.x, ref.y)
	return true

# The host pixel under the pointer, or null when it isn't on a stream screen.
func _stream_host_point(active_raycast: RayCast3D) -> Variant:
	if not active_raycast or not active_raycast.is_colliding():
		return null
	var col = active_raycast.get_collider()
	var target = PointerTarget.resolve(col) if col else {"role": &""}
	if target.role != &"screen":
		return null
	if main.screen_sources.is_browser_screen(target.screen):
		return null
	var hit_pos = main._get_steady_hit(active_raycast.get_collision_point())
	var uv = target.screen.hit_point_to_uv(hit_pos)
	var uv_x = uv.x
	uv_x = _stereo_click_uv_x(target.screen, uv_x)
	return main.layout.uv_to_host_point(target.screen.monitor, Vector2(uv_x, uv.y))

var _mouse_following := false

# Mouse Follows Pointer (#61): RTS games preview placement under the cursor
# before a click, so move the host cursor with the pointer, not only on
# trigger or grip. Every frame's sample goes to the native side, which skips
# unchanged pixels and fills in between frames at 250 Hz.
func _follow_pointer_with_mouse(active_raycast: RayCast3D, blocked: bool) -> void:
	var host_pt = null
	if not blocked and main.settings.mouse_follows_pointer and main.is_streaming:
		host_pt = _stream_host_point(active_raycast)
	if host_pt == null:
		if _mouse_following:
			_mouse_following = false
			main.stream_backend.stop_mouse_follow()
		return
	_mouse_following = true
	var ref = main.layout.host_ref()
	main.stream_backend.follow_mouse_position_event(host_pt.x, host_pt.y, ref.x, ref.y)

func _send_double_click_chord(active_raycast: RayCast3D) -> bool:
	if not _position_stream_pointer(active_raycast):
		return false
	for _click in range(2):
		main.stream_backend.send_mouse_button_event(7, 1)
		main.stream_backend.send_mouse_button_event(8, 1)
	return true

func handle_pointer_interaction():
	_update_active_hand()
	_update_on_screen_tracking()
	_process_auto_primary(main.get_process_delta_time())
	var active_raycast = get_active_raycast()
	var hands_ui_only: bool = main.settings.tracking_mode == 3 or (main.input_handler and main.input_handler.hand_desktop_suspended())
	if main._is_using_hands and hands_ui_only and active_raycast and active_raycast.is_colliding():
		var target := PointerTarget.resolve(active_raycast.get_collider())
		if target.role == &"screen" and main.is_streaming:
			cancel_transient_interactions()
			main.composition_pointers.hide_primary()
			if main.pointer_cursor:
				main.pointer_cursor.visible = false
			return
	pointer_on_ui = false

	_primary_ui_pixel = Vector2(-1, -1)

	var raw_clicking = _is_now_clicking()
	var is_gripping = _is_now_gripping()
	var input_state := "%s %s click=%s grip=%s" % ["hands" if main._is_using_hands else "controllers", _active_hand, raw_clicking, is_gripping]
	if input_state != _last_hand_input_state:
		_last_hand_input_state = input_state
		main._log("[INPUT] Pointer %s right_trigger=%.2f left_trigger=%.2f" % [input_state,
			main.right_hand.get_float("trigger") if main.right_hand else 0.0,
			main.left_hand.get_float("trigger") if main.left_hand else 0.0])
		if main._is_using_hands:
			for hand in ["right", "left"]:
				var aim = XRServer.get_tracker("/user/fbhandaim/" + hand)
				if aim:
					main._log("[HAND] %s valid=%s pinch=%s strength=%s system=%s menu=%s" % [hand,
						hand_aim_valid(hand), aim.get_input("index_pinch"), aim.get_input("index_pinch_strength"),
						aim.get_input("system_gesture"), aim.get_input("menu_gesture")])
	var now_msec = Time.get_ticks_msec()
	var trigger_pressed_edge = raw_clicking and not _trigger_was_pressed
	var grip_pressed_edge = is_gripping and not _grip_was_pressed
	var grip_released_edge = not is_gripping and _grip_was_pressed
	if trigger_pressed_edge:
		_trigger_press_msec = now_msec
	if grip_pressed_edge:
		_grip_press_msec = now_msec

	var pad_blocking = main.controller_mapper and main.controller_mapper.is_active() and main.controller_mapper.is_gamepad_mode()
	var tp_blocking = main.virtual_keyboard and main.virtual_keyboard.trackpad_active
	_follow_pointer_with_mouse(active_raycast, pad_blocking or tp_blocking \
		or main.grabbed_node != null or main.grabbed_corner_idx >= 0)
	# Steam Frame: off (grip is right click there); the Buttons tab's Double
	# Click action is the way to double-click with one press instead.
	var chord_enabled = main.settings.double_click_mode == 1 and not main._is_using_hands and not main.device_is_steam_frame \
		and main.is_streaming and not pad_blocking and not tp_blocking
	if chord_enabled and not _double_click_chord_active and raw_clicking and is_gripping \
	and _trigger_press_msec >= 0 and _grip_press_msec >= 0 \
	and absi(_trigger_press_msec - _grip_press_msec) <= DOUBLE_CLICK_CHORD_MSEC \
	and not main.was_right_clicking:
		# The trigger usually lands a frame or two before the grip, so its
		# left-button press has often already gone out: finish that one as
		# the first click instead of refusing the chord (which made Trigger +
		# Grip never work).
		if main.was_clicking and _position_stream_pointer(active_raycast):
			main.stream_backend.send_mouse_button_event(8, 1)
			main.stream_backend.send_mouse_button_event(7, 1)
			main.stream_backend.send_mouse_button_event(8, 1)
			main.was_clicking = false
			_double_click_chord_active = true
			_click_pending_release = false
			_pinch_start_screen = null
			main._log("[INPUT] Trigger + Grip double-click (trigger was already down)")
		elif not main.was_clicking and _send_double_click_chord(active_raycast):
			main._log("[INPUT] Trigger + Grip double-click")
			_double_click_chord_active = true
			_click_pending_release = false
			_pinch_start_screen = null
	var chord_completed_this_frame = _double_click_chord_active and not raw_clicking and not is_gripping
	if chord_completed_this_frame:
		_double_click_chord_active = false

	# Store the physical edges before any of the target-specific branches below
	# can return. While a chord is active, suppress the ordinary trigger path
	# until both controls have been released.
	_trigger_was_pressed = raw_clicking
	_grip_was_pressed = is_gripping
	var is_now_clicking = raw_clicking and not _double_click_chord_active
	var shortcut_target = PointerTarget.resolve(active_raycast.get_collider()) if active_raycast.is_colliding() else {"role": &"", "screen": null, "action": &""}
	if main.screen_sources:
		main.screen_sources.cancel_browser_pointers_except(shortcut_target.screen if shortcut_target.role == &"screen" else null)
	var on_primary_shortcut = shortcut_target.role == &"screen_shortcut" and shortcut_target.screen == main.primary_screen
	var tab_menu = main.screen_sources.menu_for_screen(shortcut_target.screen) if shortcut_target.role == &"screen_tab" else null
	var on_primary_tab = tab_menu != null
	if is_now_clicking and not main.was_clicking:
		var col = active_raycast.get_collider() if active_raycast.is_colliding() else null
		main._log("[PTR] press: collider=%s role=%s action=%s primary=%s grabbed=%s" % [
			col.name if col else "none", String(shortcut_target.role), String(shortcut_target.action),
			str(shortcut_target.screen == main.primary_screen), str(main.grabbed_node != null)])
	# A drag started on the grab bar/corner owns this press until release.
	# The ray can pass over a shortcut as the screen moves underneath it, and
	# was_clicking may be cleared by another target branch during that motion.
	# Never interpret such a held press as a new shortcut click.
	if main.grabbed_node or main.grabbed_corner_idx >= 0:
		if main.screen_shortcuts:
			main.screen_shortcuts.set_hover(&"")
		if not is_now_clicking:
			main.was_clicking = false
			_click_pending_release = false
		return
	if _screen_shortcut_press_active:
		pointer_on_ui = true
		if on_primary_shortcut:
			main.screen_shortcuts.set_hover(shortcut_target.action)
		elif on_primary_tab:
			tab_menu.set_hover(shortcut_target.action)
		if not is_now_clicking:
			_screen_shortcut_press_active = false
			main.was_clicking = false
		else:
			_check_shortcut_long_press(shortcut_target if on_primary_shortcut else {})
			return
	if on_primary_tab:
		pointer_on_ui = true
		tab_menu.set_hover(shortcut_target.action)
		if is_now_clicking and not main.was_clicking:
			_screen_shortcut_press_active = true
			main.was_clicking = true
			tab_menu.invoke(shortcut_target.action)
		elif not is_now_clicking:
			main.was_clicking = false
		return
	if on_primary_shortcut:
		pointer_on_ui = true
		main.screen_shortcuts.set_hover(shortcut_target.action)
		if screen_controls_blocked(is_now_clicking, shortcut_target.action == ScreenShortcutBar.ACTION_PAD):
			return
		if is_now_clicking and not main.was_clicking:
			_screen_shortcut_press_active = true
			main.was_clicking = true
			main.screen_shortcuts.log_hit(shortcut_target.screen, shortcut_target.action, active_raycast.get_collision_point())
			main.screen_shortcuts.invoke(shortcut_target.action)
			_shortcut_press_ms = Time.get_ticks_msec()
			_shortcut_press_action = shortcut_target.action
			_shortcut_long_done = false
			_shortcut_view_done = false
		elif not is_now_clicking:
			main.was_clicking = false
		return
	if is_now_clicking and not main.was_clicking and not _click_pending_release:
		_pinch_start_time = now_msec
		var col = active_raycast.get_collider() if active_raycast.is_colliding() else null
		var t0 = PointerTarget.resolve(col) if col else {"role": &""}
		if t0.role == &"screen" and main.is_streaming and not main.screen_sources.is_browser_screen(t0.screen):
			var hit_pos = main._get_steady_hit(active_raycast.get_collision_point())
			var uv = t0.screen.hit_point_to_uv(hit_pos)
			var uv_x = uv.x
			uv_x = _stereo_click_uv_x(t0.screen, uv_x)
			_pinch_start_pos = Vector2(main.layout.uv_to_host_point(t0.screen.monitor, Vector2(uv_x, uv.y)))
			# Double-click assist (after Moonlight XR's xr_pressfix): Windows only
			# pairs two presses within ~2 px and 500 ms, but the hand drifts and
			# the second trigger pull jolts the aim. A press soon after a click and
			# close to it goes down exactly where that click did.
			if t0.screen == _last_click_screen and now_msec - _last_click_ms < DOUBLE_CLICK_MS \
					and _pinch_start_pos.distance_to(_last_click_pos) <= DOUBLE_CLICK_PX:
				_pinch_start_pos = _last_click_pos
			_pinch_start_screen = t0.screen
			_click_pending_release = true

	if main.is_xr_active and main.is_streaming and main.controller_mapper:
		main.controller_mapper.check_toggle()

	if main.is_xr_active and main.is_streaming:
		var right_click_ready = is_gripping and not _double_click_chord_active
		if chord_enabled:
			# Give a newly pressed grip 80 ms to become a chord. Also avoid
			# starting a right-click while trigger is held outside the window;
			# it can begin normally if grip remains held after trigger releases.
			right_click_ready = right_click_ready and not raw_clicking \
				and now_msec - _grip_press_msec > DOUBLE_CLICK_CHORD_MSEC
		if not pad_blocking and not tp_blocking and right_click_ready and not main.was_right_clicking and main.right_click_cooldown <= 0.0:
			var col = active_raycast.get_collider() if active_raycast.is_colliding() else null
			var t1 = PointerTarget.resolve(col) if col else {"role": &""}
			_rclick_start_pt = Vector2(-1, -1)
			if t1.role == &"screen" and not main.screen_sources.is_browser_screen(t1.screen):
				var hit_pos = main._get_steady_hit(active_raycast.get_collision_point())
				var uv = t1.screen.hit_point_to_uv(hit_pos)
				var uv_x = uv.x
				var uv_y = uv.y
				uv_x = _stereo_click_uv_x(t1.screen, uv_x)
				var host_pt = main.layout.uv_to_host_point(t1.screen.monitor, Vector2(uv_x, uv_y))
				var ref = main.layout.host_ref()
				main.stream_backend.send_mouse_position_event(host_pt.x, host_pt.y, ref.x, ref.y)
				_rclick_start_pt = Vector2(host_pt)
			main.stream_backend.send_mouse_button_event(7, 3)
			main.was_right_clicking = true
			_rclick_dragging = false
			main.right_click_cooldown = 0.5
		elif not is_gripping and main.was_right_clicking:
			main.stream_backend.send_mouse_button_event(8, 3)
			main.was_right_clicking = false
		elif chord_enabled and grip_released_edge and not chord_completed_this_frame \
		and not _double_click_chord_active \
		and not raw_clicking and now_msec - _grip_press_msec <= DOUBLE_CLICK_CHORD_MSEC \
		and main.right_click_cooldown <= 0.0:
			# Preserve very quick standalone grip taps that release during the
			# detection window: emit a complete right-click on release.
			_position_stream_pointer(active_raycast)
			main.stream_backend.send_mouse_button_event(7, 3)
			main.stream_backend.send_mouse_button_event(8, 3)
			main.right_click_cooldown = 0.5

	for s in main.screens:
		if not main.device_is_steam_frame:
			s.grab_bar.visible = true # (Steam Frame: ScreenShortcutBar shows/hides it)
		var controls_revealed: bool = main.screen_shortcuts != null \
			and main.screen_shortcuts.controls_are_revealed(s)
		for ch in s.corner_handles:
			ch.visible = controls_revealed
			var ch_area = ch.get_node_or_null("Area3D")
			if ch_area:
				ch_area.monitoring = false
				ch_area.monitorable = false

	if main.grabbed_corner_idx >= 0 and main.grabbed_corner_screen:
		var gh = main.grabbed_corner_screen.corner_handles[main.grabbed_corner_idx]
		gh.visible = true
		var gh_area = gh.get_node_or_null("Area3D")
		if gh_area:
			gh_area.monitoring = true
			gh_area.monitorable = true

	if not main.grabbed_node and main.grabbed_corner_idx < 0:
		for s in main.screens:
			_set_grab_bar_color(s.grab_bar, _bar_base_color(s), 0.05)
		main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.08))
		if main.virtual_keyboard and main.virtual_keyboard.visible:
			main.set_comp_grab_bar_color(main.virtual_keyboard.viewport, Color(1, 1, 1, 0.08))
		for s in main.screens:
			for ch in s.corner_handles:
				_set_corner_color(ch, Color.WHITE, 0.05)
	elif main.grabbed_node and main.grabbed_bar:
		_set_grab_bar_color(main.grabbed_bar, _bar_base_color(main.grabbed_node), 0.4)
	elif main.grabbed_node == main.ui_panel_3d:
		main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.8))
	elif main.grabbed_node == main.virtual_keyboard:
		main.set_comp_grab_bar_color(main.virtual_keyboard.viewport, Color(1, 1, 1, 0.8))
	elif main.grabbed_corner_idx >= 0 and main.grabbed_corner_screen:
		_set_corner_color(main.grabbed_corner_screen.corner_handles[main.grabbed_corner_idx], Color.WHITE, 0.4)

	var right_laser = main.get_node("%Laser")
	var left_laser = null
	if main.left_hand_raycast:
		left_laser = main.left_hand_raycast.get_node_or_null("Laser")
	if main.is_xr_active:
		var right_hit = main.hand_raycast and main.hand_raycast.is_colliding()
		var left_hit = main.left_hand_raycast and main.left_hand_raycast.is_colliding()
		var right_on_ui = _is_hand_on_ui("right")
		var left_on_ui = _is_hand_on_ui("left")
		if main._is_using_hands:
			var has_data = main.get_hand_tracking_has_data()
			if right_laser:
				right_laser.visible = has_data and _active_hand == "right" and right_hit
			if left_laser:
				left_laser.visible = has_data and _active_hand == "left" and left_hit
		else:
			if right_laser:
				right_laser.visible = (_active_hand == "right" and right_hit) or (_active_hand != "right" and right_on_ui)
			if left_laser:
				left_laser.visible = (_active_hand == "left" and left_hit) or (_active_hand != "left" and left_on_ui)
	else:
		if right_laser:
			right_laser.visible = false
		if left_laser:
			left_laser.visible = false
	# Pointer Ray off: hide the 3D-scene beam too (only the composition-layer
	# beam was hidden before, so the 3D one still showed when aiming at a screen).
	if not main.settings.show_pointer_ray:
		if right_laser:
			right_laser.visible = false
		if left_laser:
			left_laser.visible = false
	var on_screen = false
	var tp_capturing = main.virtual_keyboard and main.virtual_keyboard.trackpad_active
	var pad_mode_active = main.controller_mapper and main.controller_mapper.is_active() and main.controller_mapper.is_gamepad_mode()
	if tp_capturing:
		if main.contact_dot:
			main.contact_dot.visible = false
		if main.pointer_cursor:
			main.pointer_cursor.visible = false
		main.composition_pointers.hide_primary()
		right_laser.visible = false
		if left_laser:
			left_laser.visible = false
	if not tp_capturing and active_raycast.is_colliding():
		var raw_hit = active_raycast.get_collision_point()
		var _col = active_raycast.get_collider()
		var t_hover = PointerTarget.resolve(_col) if _col else {"role": &""}
		on_screen = (t_hover.role == &"screen")
		var hide_on_screen = on_screen and (pad_mode_active or main.hides_screen_cursor(t_hover.screen))
		var hit_point = main._get_steady_hit(raw_hit) if on_screen else raw_hit
		var col_normal = active_raycast.get_collision_normal()
		var dot_offset = col_normal * 0.025 if col_normal != Vector3() else (main.xr_camera.global_position - hit_point).normalized() * 0.025
		if main.screen_cursor_mode(t_hover.screen if on_screen else null) == 0 or not on_screen or hide_on_screen:
			if main.contact_dot:
				main.contact_dot.global_position = hit_point + dot_offset
				main.contact_dot.visible = not hide_on_screen
			if main.pointer_cursor:
				main.pointer_cursor.visible = false
			if hide_on_screen:
				main.composition_pointers.hide_primary()
		else:
			if main.pointer_cursor:
				main.pointer_cursor.global_position = hit_point
				var surface_normal: Vector3 = t_hover.screen.get_cylinder_normal_at(hit_point) \
					if t_hover.screen else (main.xr_camera.global_position - hit_point).normalized()
				main.pointer_cursor.look_at(main.pointer_cursor.global_position + surface_normal, Vector3.UP)
				main.pointer_cursor.rotate_object_local(Vector3.UP, PI)
				var face = -main.pointer_cursor.global_transform.basis.z
				var right = main.pointer_cursor.global_transform.basis.x
				var up = main.pointer_cursor.global_transform.basis.y
				main.pointer_cursor.global_position = hit_point + face * 0.002 + right * 0.03 - up * 0.04
				main.pointer_cursor.visible = true
			if main.contact_dot:
				main.contact_dot.visible = false
	else:
		if main.contact_dot:
			main.contact_dot.visible = false
		if main.pointer_cursor:
			main.pointer_cursor.visible = false

	if active_raycast.is_colliding():
		var collider = active_raycast.get_collider()
		var parent = collider.get_parent()
		var t = PointerTarget.resolve(collider)
		pointer_on_ui = false
		if t.role == &"panel" and parent == main.ui_panel_3d:
			pointer_on_ui = true
		if t.role == &"grab_bar" and main.ui_visible:
			pointer_on_ui = true
		if main.virtual_keyboard and main.virtual_keyboard.visible and t.role == &"panel" and parent == main.virtual_keyboard.mesh_instance:
			pointer_on_ui = true

		if t.role == &"grab_bar" and parent != main.grabbed_bar:
			_set_grab_bar_color(parent, _bar_base_color(parent.get_parent()), 0.15)

		is_now_clicking = _is_now_clicking()

		var hit_ui = false
		if main.ui_visible and main.ui_panel_3d and main.ui_panel_3d.visible:
			var area = main.ui_panel_3d.get_node_or_null("Area3D")
			if area and area.monitoring and t.role == &"panel" and parent == main.ui_panel_3d:
				hit_ui = true

		if (t.role == &"panel" and parent == main.ui_panel_3d) or hit_ui:
			var hit_pos = main._get_steady_hit(active_raycast.get_collision_point())
			var local_pos = main.ui_panel_3d.to_local(hit_pos)
			var half_w = main._ui_mesh_size.x / 2.0
			var half_h = main._ui_mesh_size.y / 2.0
			var nx = clampf((local_pos.x / half_w + 1.0) / 2.0, 0.0, 1.0)
			var ny = clampf(1.0 - (local_pos.y / half_h + 1.0) / 2.0, 0.0, 1.0)
			var pixel_pos = Vector2(nx * main._ui_viewport_size.x,
				ny * main._ui_viewport_size.y + main.UI_TOOLTIP_STRIP_PX)
			_primary_ui_pixel = pixel_pos

			var is_grab_bar = _is_ui_grab_bar(pixel_pos)
			if main.grabbed_node == main.ui_panel_3d:
				main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.8))
			elif (is_grab_bar or (main.device_is_steam_frame and is_now_clicking and not main.was_clicking \
					and _ui_point_is_empty(pixel_pos))) and main.grabbed_corner_idx < 0:
				main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.25))
				if is_now_clicking and not main.was_clicking:
					main.grabbed_node = main.ui_panel_3d
					main.grabbed_bar = null
					var grab_point = active_raycast.get_collision_point()
					main.grab_distance = (grab_point - active_raycast.global_position).length()
					main.grab_offset = main.grabbed_node.global_position - grab_point
					main.grab_start_hand_pos = active_raycast.global_position
					main.grab_start_node_pos = main.grabbed_node.global_position
					main.grab_forward = -active_raycast.global_transform.basis.z
					if main.is_xr_active:
						main.grab_start_hand_basis = active_raycast.global_transform.basis
						main.grab_start_node_basis = main.grabbed_node.global_transform.basis
						main.grab_start_node_euler = main.grabbed_node.rotation
					main.was_clicking = true
					return
			else:
				main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.08))

			if not is_grab_bar:
				var motion = InputEventMouseMotion.new()
				motion.position = pixel_pos
				motion.global_position = pixel_pos
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT if is_now_clicking else 0
				main.ui_viewport.push_input(motion)

				if is_now_clicking and not main.was_clicking:
					_push_ui_click(pixel_pos, true)
					main.was_clicking = true
				elif not is_now_clicking and main.was_clicking:
					_push_ui_click(pixel_pos, false)
					main.was_clicking = false
			return

		if main.virtual_keyboard and main.virtual_keyboard.visible and t.role == &"panel" and parent == main.virtual_keyboard.mesh_instance:
			var hit_pos = main._get_steady_hit(active_raycast.get_collision_point())
			var local_pos = main.virtual_keyboard.mesh_instance.to_local(hit_pos)
			var half_w = main.virtual_keyboard.mesh_size.x / 2.0
			var half_h = main.virtual_keyboard.mesh_size.y / 2.0
			var nx = (local_pos.x / half_w + 1.0) / 2.0
			var ny = 1.0 - (local_pos.y / half_h + 1.0) / 2.0
			var pixel_pos = Vector2(nx * main.virtual_keyboard.viewport_size.x, ny * main.virtual_keyboard.viewport_size.y)

			var is_kb_grab = _is_kb_grab_bar(pixel_pos)
			if main.grabbed_node == main.virtual_keyboard:
				main.set_comp_grab_bar_color(main.virtual_keyboard.viewport, Color(1, 1, 1, 0.8))
			elif (is_kb_grab or (main.device_is_steam_frame and is_now_clicking and not main.was_clicking \
					and main.virtual_keyboard.is_empty_spot(pixel_pos))) and main.grabbed_corner_idx < 0:
				main.set_comp_grab_bar_color(main.virtual_keyboard.viewport, Color(1, 1, 1, 0.25))
				if is_now_clicking and not main.was_clicking:
					main.grabbed_node = main.virtual_keyboard
					main.grabbed_bar = null
					main.grab_distance = (hit_pos - active_raycast.global_position).length()
					main.grab_offset = main.grabbed_node.global_position - hit_pos
					main.grab_start_hand_pos = active_raycast.global_position
					main.grab_start_node_pos = main.grabbed_node.global_position
					main.grab_forward = -active_raycast.global_transform.basis.z
					if main.is_xr_active:
						main.grab_start_hand_basis = active_raycast.global_transform.basis
						main.grab_start_node_basis = main.grabbed_node.global_transform.basis
						main.grab_start_node_euler = main.grabbed_node.rotation
					main.was_clicking = true
					return
			else:
				main.set_comp_grab_bar_color(main.virtual_keyboard.viewport, Color(1, 1, 1, 0.08))

			if not is_kb_grab:
				var active_hand_node = main.left_hand if _active_hand == "left" else main.right_hand
				main.virtual_keyboard.handle_pointer(pixel_pos, is_now_clicking, main.was_clicking, active_hand_node)
				if is_now_clicking:
					main.was_clicking = true
				else:
					main.was_clicking = false
			return

		elif t.role == &"screen" and (main.grabbed_node or main.grabbed_corner_idx >= 0):
			# A grab-bar or corner-handle drag is in progress and the ray just
			# happens to be sweeping over some screen's surface en route (easy
			# to hit now that grid mode can place screens close together) -
			# don't forward that as a click/cursor-move to whatever's playing
			# on that screen. The drag itself is driven by handle_grab()/
			# handle_corner_resize() elsewhere, not by this hit-test.
			return

		elif t.role == &"screen" and (not main.is_streaming or main.screen_sources.is_browser_screen(t.screen)):
			var hit_pos = main._get_steady_hit(active_raycast.get_collision_point())
			var uv = t.screen.hit_point_to_uv(hit_pos)
			var browser = main.screen_sources.browser_for_screen(t.screen)
			if browser and browser.active:
				if is_now_clicking and not main.was_clicking:
					_browser_press_owner = browser
					main.screen_sources.focus_browser(browser)
				if is_now_clicking and _browser_press_owner != browser:
					return # A held press must not become a new click on another screen.
				browser.pointer(uv, is_now_clicking)
				if not is_now_clicking: _browser_press_owner = null
				main.was_clicking = is_now_clicking
				return
			var wv = main.welcome_viewport
			var pixel_pos = Vector2(uv.x * wv.size.x, uv.y * wv.size.y)

			var motion = InputEventMouseMotion.new()
			motion.position = pixel_pos
			motion.global_position = pixel_pos
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT if is_now_clicking else 0
			wv.push_input(motion)

			if is_now_clicking and not main.was_clicking:
				var ev = InputEventMouseButton.new()
				ev.position = pixel_pos
				ev.global_position = pixel_pos
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				wv.push_input(ev)
				main.was_clicking = true
			elif not is_now_clicking and main.was_clicking:
				var ev = InputEventMouseButton.new()
				ev.position = pixel_pos
				ev.global_position = pixel_pos
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = false
				wv.push_input(ev)
				main.was_clicking = false
			return

		elif t.role == &"screen" and main.is_streaming:
			if is_now_clicking and not main.was_clicking:
				main.screen_sources.focus_browser(null)
			if main.virtual_keyboard and main.virtual_keyboard.trackpad_active:
				return
			if main.controller_mapper and main.controller_mapper.is_active() and main.controller_mapper.is_gamepad_mode():
				return
			var hit_pos = main._get_steady_hit(active_raycast.get_collision_point())
			var uv = t.screen.hit_point_to_uv(hit_pos)
			var uv_x = uv.x
			var uv_y = uv.y
			uv_x = _stereo_click_uv_x(t.screen, uv_x)
			var host_pt = main.layout.uv_to_host_point(t.screen.monitor, Vector2(uv_x, uv_y))
			var ref = main.layout.host_ref()

			# Cursor Follow: keep the PC cursor under the pointer while just
			# pointing (clicks and drags send their own positions below).
			if _cursor_parked and (is_now_clicking or Vector2(host_pt).distance_to(Vector2(_parked_at_pointer)) > 24.0):
				_cursor_parked = false
			if main.is_xr_active and is_cursor_following() and not _cursor_parked and not is_now_clicking \
					and not main.was_clicking and not _click_pending_release and host_pt != _last_follow_pt \
					and not _right_click_holding_still(host_pt):
				main.stream_backend.send_mouse_position_event(host_pt.x, host_pt.y, ref.x, ref.y)
				_last_follow_pt = host_pt

			if main.is_xr_active:
				if is_now_clicking:
					var hold_time = Time.get_ticks_msec() - _pinch_start_time
					var dist = Vector2(host_pt).distance_to(_pinch_start_pos)
					if hold_time > 150 or dist > 15:
						if not main.was_clicking and dist <= 15:
							# A slow pull that hasn't moved: press where it started
							# (keeps double clicks on one point), then follow the aim.
							main.stream_backend.send_mouse_position_event(int(_pinch_start_pos.x), int(_pinch_start_pos.y), ref.x, ref.y)
							_press_was_still = true
						elif dist > 15 or not _press_was_still:
							main.stream_backend.send_mouse_position_event(host_pt.x, host_pt.y, ref.x, ref.y)
							_press_was_still = false
						if not main.was_clicking:
							main.stream_backend.send_mouse_button_event(7, 1)
							main.was_clicking = true
				elif main.was_clicking:
					main.stream_backend.send_mouse_button_event(8, 1)
					main.was_clicking = false
					_click_pending_release = false
					if _press_was_still and Time.get_ticks_msec() - _pinch_start_time < DOUBLE_CLICK_MS:
						_last_click_pos = _pinch_start_pos
						_last_click_ms = _pinch_start_time
						_last_click_screen = t.screen
					_press_was_still = false
				elif _click_pending_release:
					if _pinch_start_screen == t.screen:
						main.stream_backend.send_mouse_position_event(int(_pinch_start_pos.x), int(_pinch_start_pos.y), ref.x, ref.y)
						main.stream_backend.send_mouse_button_event(7, 1)
						main.stream_backend.send_mouse_button_event(8, 1)
						_last_click_pos = _pinch_start_pos
						_last_click_ms = _pinch_start_time
						_last_click_screen = t.screen
					_click_pending_release = false
			else:
				if is_now_clicking and not main.was_clicking:
					main.stream_backend.send_mouse_position_event(host_pt.x, host_pt.y, ref.x, ref.y)
					main.suppress_input_frames = 3
					main.input_handler.capture_stream_mouse()
					main.was_clicking = true
			return

		# A stream-content drag already in flight (e.g. dragging a window/icon
		# toward another screen, kept alive across the gap by the fallback
		# below) must not be hijacked into a corner-resize or grab-bar-move just
		# because the ray happens to sweep over one of those hitboxes en route -
		# the user is still holding the SAME click that started on a screen.
		# Require a release (which clears _pinch_start_screen) before either
		# gesture can start.
		var mid_content_drag = main.was_clicking and _pinch_start_screen != null and not main.grabbed_node and main.grabbed_corner_idx < 0

		if (t.role == &"corner" or t.role == &"grab_bar") and t.get("screen") is VRScreen \
				and screen_controls_blocked(is_now_clicking, t.role == &"grab_bar"):
			return
		if t.role == &"corner":
			var corner_idx = t.corner_idx
			parent.visible = true
			var p_area = parent.get_node_or_null("Area3D")
			if p_area:
				p_area.monitoring = true
				p_area.monitorable = true
			if is_now_clicking and main.grabbed_corner_idx < 0 and not main.grabbed_node and not mid_content_drag:
				main.grabbed_corner_idx = corner_idx
				main.grabbed_corner_screen = t.screen
				var opposite_idx = 3 - corner_idx
				var opposite = t.screen.corner_handles[opposite_idx]
				main.corner_anchor_world = opposite.global_position
				_set_corner_color(parent, Color.WHITE, 0.4)
				main.was_clicking = true
			elif main.grabbed_corner_idx < 0 and corner_idx != main.grabbed_corner_idx:
				_set_corner_color(parent, Color.WHITE, 0.15)
			return

		elif t.role == &"grab_bar":
			if is_now_clicking and not main.grabbed_node and main.grabbed_corner_idx < 0 and not mid_content_drag:
				main.grabbed_node = parent.get_parent()
				main.grabbed_bar = parent
				var grab_point = active_raycast.get_collision_point()
				main.grab_distance = (grab_point - active_raycast.global_position).length()
				main.grab_offset = main.grabbed_node.global_position - grab_point
				main.grab_start_hand_pos = active_raycast.global_position
				main.grab_start_node_pos = main.grabbed_node.global_position
				main.grab_forward = -active_raycast.global_transform.basis.z
				if main.is_xr_active:
					main.grab_start_hand_basis = active_raycast.global_transform.basis
					main.grab_start_node_basis = main.grabbed_node.global_transform.basis
					main.grab_start_node_euler = main.grabbed_node.rotation
				main.grab_group_start_transforms.clear()
				if main.grabbed_node == main.primary_screen:
					main.grab_start_primary_transform = main.primary_screen.global_transform
					for other in main.screens:
						if other != main.primary_screen:
							main.grab_group_start_transforms[other] = other.global_transform
					# Steam Frame: the menu and keyboard come along (Menu & Keyboard Follow Screen).
					# A hidden one too, from the place it would open in: it
					# used to be left out and came back swung nearer or
					# farther by however the screen had been tilted since.
					if main.device_is_steam_frame and main.settings.keyboard_follows_screen:
						var kb = main.virtual_keyboard
						if kb and (kb.visible or kb._has_saved_offset):
							if not kb.visible:
								kb.anchor_to_saved_offset()
							main.grab_group_start_transforms[kb] = kb.global_transform
						if main.ui_panel_3d and (main.ui_visible or main._ui_has_saved_offset):
							if not main.ui_visible:
								main._anchor_to_primary(main.ui_panel_3d, main._ui_saved_offset, main._ui_saved_rot_y, main._ui_saved_rot_x)
							main.grab_group_start_transforms[main.ui_panel_3d] = main.ui_panel_3d.global_transform
				_set_grab_bar_color(parent, _bar_base_color(parent.get_parent()), 0.3)
				main.was_clicking = true
			return

	elif main.was_clicking:
		# The raycast hit nothing at all this frame - could be the physical trigger/
		# pinch actually releasing, or just the ray passing through the gap between
		# two adjacent screens (or off the edge into empty space) mid-drag. Only treat
		# it as a real release when the physical input itself let go; otherwise keep
		# the click held server-side and simply skip sending a position update this
		# frame. Once the ray lands on a screen again (this one or another), the
		# t.role == &"screen" branch above resumes sending positions from wherever it
		# is now - which is exactly "drag onto another screen" for free, since it maps
		# through whichever screen is currently hit, not just the one the drag started on.
		var mid_screen_drag = _pinch_start_screen != null and main.grabbed_node == null and main.grabbed_corner_idx < 0
		if is_now_clicking and mid_screen_drag and main.is_streaming:
			pass
		else:
			if main.is_streaming:
				main.stream_backend.send_mouse_button_event(8, 1)
			main.was_clicking = false
			_click_pending_release = false
			_pinch_start_screen = null

# Steam Frame: holding the trigger on the menu or keyboard icon under the
# screen for about a second brings that panel back to its default spot and
# shows it - the way to find a menu or keyboard that got lost.
var _shortcut_press_ms := 0
var _shortcut_press_action: StringName = &""
var _shortcut_long_done := false

var _shortcut_view_done := false

func _check_shortcut_long_press(target: Dictionary) -> void:
	if not main.device_is_steam_frame or _shortcut_press_ms == 0:
		return
	if target.is_empty() or target.get("action", &"") != _shortcut_press_action:
		_shortcut_press_ms = 0  # pointer left the icon: no long press
		_shortcut_view_done = false
		return
	var held := Time.get_ticks_msec() - _shortcut_press_ms
	if _shortcut_long_done:
		# Keep holding (about 3 s): bring it right in front of your eyes.
		if not _shortcut_view_done and held >= LONG_LONG_PRESS_MS:
			_shortcut_view_done = true
			main.buzz(_active_hand, 0.6, 0.06)
			if _shortcut_press_action == ScreenShortcutBar.ACTION_MENU:
				main.show_menu_in_view()
			elif _shortcut_press_action == ScreenShortcutBar.ACTION_KEYBOARD:
				main.show_keyboard_in_view()
		return
	if held < LONG_PRESS_MS:
		return
	_shortcut_long_done = true
	_shortcut_view_done = false
	main.buzz(_active_hand, 0.4, 0.04)
	if _shortcut_press_action == ScreenShortcutBar.ACTION_MENU:
		if not main.ui_visible:
			main._toggle_ui()
		main.reset_ui_position()
		main._log("[SHORTCUT] Long press: menu back to its default spot")
	elif _shortcut_press_action == ScreenShortcutBar.ACTION_KEYBOARD and main.virtual_keyboard:
		if not main.virtual_keyboard.visible:
			main.virtual_keyboard.toggle()
		main.virtual_keyboard.reset_to_default()
		main._log("[SHORTCUT] Long press: keyboard back to its default spot")

func _update_on_screen_tracking():
	_right_on_screen = _is_hand_on_screen("right")
	_left_on_screen = _is_hand_on_screen("left")

func process_pointer_frame(delta: float):
	if main.screen_sources:
		main.screen_sources.begin_pointer_frame()
	if main.screen_shortcuts:
		main.screen_shortcuts.begin_pointer_frame(delta)
	_update_active_hand()
	if not _pointer_input_ready(_active_pointer_tracked(), _pointer_controls_held()):
		if main.was_clicking or main.was_right_clicking or main.grabbed_node or _other_hand_clicking:
			cancel_transient_interactions("pointer tracking unavailable or awaiting release")
		pointer_on_ui = false
		_primary_ui_pixel = Vector2(-1, -1)
		_secondary_ui_pixel = Vector2(-1, -1)
		if main.screen_shortcuts: main.screen_shortcuts.set_hover(&"")
		if main.pointer_cursor: main.pointer_cursor.visible = false
		if main.composition_pointers: main.composition_pointers.hide_primary()
		_hide_other_hand_ui()
		_apply_ui_hover_states()
		return
	_update_on_screen_tracking()
	_process_auto_primary(delta)
	_prioritize_tab_overlay()
	var pointer_ray := get_active_raycast()
	var pointer_screen: VRScreen = null
	if pointer_ray and pointer_ray.is_colliding():
		pointer_screen = PointerTarget.resolve(pointer_ray.get_collider()).screen
	if pointer_screen != _last_pointer_screen:
		main._reset_steady_filter()
		_last_pointer_screen = pointer_screen
	_reveal_contextual_screen_controls()
	if not main.mouse_captured_by_stream:
		handle_pointer_interaction()
	_process_other_hand_ui()
	_apply_ui_hover_states()
	if main.screen_shortcuts:
		for screen in main.screens:
			main.screen_shortcuts.refresh_visuals(screen)

func _prioritize_tab_overlay() -> void:
	# Composition video can use a different curvature from its physics mesh.
	# Resolve overlays explicitly rather than relying on millimetre offsets.
	if is_instance_valid(_tab_priority_ray) and is_instance_valid(_tab_ray_exclusion):
		_tab_priority_ray.remove_exception(_tab_ray_exclusion)
	_tab_ray_exclusion = null
	_tab_priority_ray = get_active_raycast()
	var ray := _tab_priority_ray
	if not ray or not ray.is_inside_tree(): return
	# A resting controller's ray is switched off (main._apply_hand_rest()).
	# force_raycast_update() works on a switched-off ray too, and this runs
	# every frame, so since 0.9 a resting controller went on pointing: with
	# Cursor Follow its tracking jitter kept pulling the PC's cursor back
	# while the PC's own mouse was being used (5k test).
	if not ray.enabled: return
	ray.force_raycast_update()
	if not ray.is_colliding(): return
	var collider = ray.get_collider()
	var target := PointerTarget.resolve(collider)
	if target.role != &"screen": return
	var query := PhysicsRayQueryParameters3D.create(ray.global_position,
		ray.to_global(ray.target_position), ray.collision_mask, [collider.get_rid()])
	query.collide_with_areas = ray.collide_with_areas
	query.collide_with_bodies = ray.collide_with_bodies
	var hit := ray.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var overlay := PointerTarget.resolve(hit.collider)
	if overlay.role != &"screen_tab" or overlay.screen != target.screen: return
	_tab_ray_exclusion = collider
	ray.add_exception(collider)
	ray.force_raycast_update()

func _reveal_contextual_screen_controls() -> void:
	if not main.screen_shortcuts:
		return
	var browser = main.screen_sources.focused_browser()
	if browser and browser.active and browser.navigation.get("editing", false):
		main.screen_shortcuts.reveal_controls(browser.screen)
	if main.grabbed_corner_idx >= 0 and main.grabbed_corner_screen:
		main.screen_shortcuts.reveal_controls(main.grabbed_corner_screen)
		return
	if main.grabbed_node is VRScreen:
		main.screen_shortcuts.reveal_controls(main.grabbed_node)
		return
	# Either controller pointing near a screen's grab bar shows it (the other
	# hand can grab it too).
	for raycast in [get_active_raycast(), _get_hand_raycast("left" if _active_hand == "right" else "right")]:
		if not raycast or not raycast.is_colliding():
			continue
		var target := PointerTarget.resolve(raycast.get_collider())
		if target.role in [&"grab_bar", &"corner", &"screen_shortcut", &"screen_tab"]:
			main.screen_shortcuts.reveal_controls(target.screen)
			return
	# Shows the screen's grab bar while pointing at it, without its corner handles.
	# (Not on the Steam Frame, where the bar only shows when pointing near it.)
	var active_ray := get_active_raycast()
	if not main.device_is_steam_frame and active_ray and active_ray.is_colliding():
		var pointed := PointerTarget.resolve(active_ray.get_collider())
		if pointed.role == &"screen":
			main.screen_shortcuts.point_at(pointed.screen)

func _is_hand_on_screen(hand: String) -> bool:
	var rc = main.hand_raycast if hand == "right" else main.left_hand_raycast
	if not rc or not rc.is_colliding():
		return false
	var t = PointerTarget.resolve(rc.get_collider())
	if t.role == &"screen":
		return true
	return t.role == &"panel"

func _is_hand_on_ui(hnd: String) -> bool:
	var rc = main.hand_raycast if hnd == "right" else main.left_hand_raycast
	if not rc or not rc.is_colliding():
		return false
	return PointerTarget.resolve(rc.get_collider()).role == &"panel"

func _process_other_hand_ui():
	if not main.is_xr_active or main._is_using_hands:
		_hide_other_hand_ui()
		return
	var other = "left" if _active_hand == "right" else "right"
	if not controller_pose_valid(main.left_hand if other == "left" else main.right_hand):
		_hide_other_hand_ui()
		return
	var rc = _get_hand_raycast(other)
	if not rc or not rc.is_colliding():
		_hide_other_hand_ui()
		return
	var col = rc.get_collider()
	if not col:
		_hide_other_hand_ui()
		return
	var parent = col.get_parent()
	var t_other = PointerTarget.resolve(col)
	if t_other.role != &"panel":
		_hide_other_hand_ui()
		return
	var panel = parent
	var wv = main.ui_viewport if panel == main.ui_panel_3d else (main.virtual_keyboard.viewport if main.virtual_keyboard else null)
	if not wv:
		return
	var hit_pos = rc.get_collision_point()
	var local_pos = panel.to_local(hit_pos)
	var half_w = main._ui_mesh_size.x / 2.0 if panel == main.ui_panel_3d else (main.virtual_keyboard.mesh_size.x / 2.0 if main.virtual_keyboard else 1.0)
	var half_h = main._ui_mesh_size.y / 2.0 if panel == main.ui_panel_3d else (main.virtual_keyboard.mesh_size.y / 2.0 if main.virtual_keyboard else 1.0)
	var nx = clampf((local_pos.x / half_w + 1.0) / 2.0, 0.0, 1.0)
	var ny = clampf(1.0 - (local_pos.y / half_h + 1.0) / 2.0, 0.0, 1.0)
	var vp_size = main._ui_viewport_size if panel == main.ui_panel_3d else (main.virtual_keyboard.viewport_size if main.virtual_keyboard else Vector2i(800, 400))
	var pixel_pos = Vector2(nx * vp_size.x, ny * vp_size.y)
	if panel == main.ui_panel_3d:
		pixel_pos.y += main.UI_TOOLTIP_STRIP_PX

	if panel == main.ui_panel_3d:
		_secondary_ui_pixel = pixel_pos
		if main.grabbed_node != main.ui_panel_3d:
			var primary_on_grab = _primary_ui_pixel.x >= 0 and _is_ui_grab_bar(_primary_ui_pixel)
			if not primary_on_grab:
				var is_sec_grab_bar = _is_ui_grab_bar(pixel_pos)
				main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.25) if (is_sec_grab_bar and main.grabbed_corner_idx < 0) else Color(1, 1, 1, 0.08))
	else:
		_secondary_ui_pixel = Vector2(-1, -1)
	var col_normal = rc.get_collision_normal()
	var dot_offset = col_normal * 0.025 if col_normal != Vector3() else (main.xr_camera.global_position - hit_pos).normalized() * 0.025
	if main.left_contact_dot:
		main.left_contact_dot.visible = false
	if main.comp.in_use and main.composition_pointers.has_secondary():
		main.composition_pointers.show_secondary(hit_pos, main.xr_camera.global_position)
		if main.left_comp_cursor:
			main.left_comp_cursor.visible = false
	elif main.left_comp_cursor:
		var to_cam = (main.xr_camera.global_position - hit_pos).normalized()
		main.left_comp_cursor.global_position = hit_pos + to_cam * 0.002
		main.left_comp_cursor.look_at(main.left_comp_cursor.global_position + to_cam, Vector3.UP)
		main.left_comp_cursor.rotate_object_local(Vector3.UP, PI)
		main.left_comp_cursor.visible = true
	if panel != main.ui_panel_3d and main.virtual_keyboard:
		main.virtual_keyboard.handle_secondary_pointer(pixel_pos)
	var hand = main.left_hand if other == "left" else main.right_hand
	if panel == main.ui_panel_3d and hand:
		var motion = InputEventMouseMotion.new()
		motion.position = pixel_pos
		motion.global_position = pixel_pos
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if (hand and hand.get_float("trigger") > 0.5) else 0
		wv.push_input(motion)
	if hand and hand.get_float("trigger") > 0.5:
		if not _other_hand_clicking:
			_other_hand_clicking = true
			_secondary_press_viewport = wv
			_secondary_press_was_keyboard = (main.virtual_keyboard and parent == main.virtual_keyboard.mesh_instance)
			var btn = InputEventMouseButton.new()
			btn.position = pixel_pos
			btn.global_position = pixel_pos
			btn.button_index = MOUSE_BUTTON_LEFT
			btn.pressed = true
			wv.push_input(btn)
			if _secondary_press_was_keyboard:
				main.virtual_keyboard.handle_secondary_key(pixel_pos, true)
	elif _other_hand_clicking:
		_end_secondary_press(pixel_pos)

func _end_secondary_press(pixel_pos := Vector2.ZERO):
	if not _other_hand_clicking:
		return
	_other_hand_clicking = false
	var btn = InputEventMouseButton.new()
	btn.position = pixel_pos
	btn.global_position = pixel_pos
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = false
	if is_instance_valid(_secondary_press_viewport):
		_secondary_press_viewport.push_input(btn)
	if _secondary_press_was_keyboard and main.virtual_keyboard:
		main.virtual_keyboard.handle_secondary_key(pixel_pos, false)
	_secondary_press_viewport = null
	_secondary_press_was_keyboard = false

func _hide_other_hand_ui():
	_secondary_ui_pixel = Vector2(-1, -1)
	if _other_hand_clicking:
		_end_secondary_press()
	if main.virtual_keyboard:
		main.virtual_keyboard.handle_secondary_pointer(Vector2(-1, -1))
	if main.left_contact_dot:
		main.left_contact_dot.visible = false
	if main.left_comp_cursor:
		main.left_comp_cursor.visible = false
	main.composition_pointers.hide_secondary()

# --- Gamepad mode: screen controls lock (Steam Frame) -------------------------
# In Gamepad mode the trigger also goes to the game, so stray pulls on the
# screen's grab bar, corners or icons do nothing. Only the gamepad icon shows
# (where the bar is, when you point near it); holding the trigger on it for
# a moment unlocks the bar and icons for a while, then they lock again.
# No popups, so nothing interrupts a game.
const UNLOCK_HOLD_MS := 1200
const UNLOCK_KEEP_MS := 10000
var _unlock_until_ms := 0
var _unlock_hold_ms := 0
var _unlock_hold_frame := -10
var _unlock_wait_release := false

func screen_controls_locked() -> bool:
	if not main.device_is_steam_frame or not main.controller_mapper or not main.controller_mapper.is_active():
		return false
	return Time.get_ticks_msec() > _unlock_until_ms

# Returns true when this press must not reach the screen controls. on_pad:
# the pointer is on the gamepad icon (or the bar, which it replaces).
func screen_controls_blocked(clicking: bool, on_pad: bool) -> bool:
	if _unlock_wait_release:
		if clicking:
			return true
		_unlock_wait_release = false
	if not screen_controls_locked():
		if _unlock_until_ms > 0 and main.controller_mapper and main.controller_mapper.is_active():
			_unlock_until_ms = Time.get_ticks_msec() + UNLOCK_KEEP_MS # still in use
		return false
	if not on_pad or not clicking:
		_unlock_hold_ms = 0
		return true
	var now := Time.get_ticks_msec()
	var frame := Engine.get_process_frames()
	if _unlock_hold_ms == 0 or frame - _unlock_hold_frame > 2:
		_unlock_hold_ms = now # (re)start: the pointer must stay on the icon
	_unlock_hold_frame = frame
	if now - _unlock_hold_ms < UNLOCK_HOLD_MS:
		return true
	_unlock_hold_ms = 0
	_unlock_until_ms = now + UNLOCK_KEEP_MS
	_unlock_wait_release = true # let go first, so this press doesn't click anything
	main.buzz(_active_hand, 0.6, 0.06)
	main._log("[GAMEPAD] Screen controls unlocked")
	return true

var _hover_btn_primary: Button = null
var _hover_btn_secondary: Button = null
const LONG_PRESS_MS := 900       # back to its default spot
const LONG_LONG_PRESS_MS := 3000  # right in front of your eyes

func _apply_ui_hover_states():
	if not main.ui_visible:
		if main.ui_controller:
			main.ui_controller.clear_tooltip()
		return
	var primary_tooltip_target: Button = null
	var secondary_tooltip_target: Button = null
	var primary_btn: Button = null
	var secondary_btn: Button = null
	for entry in _ui_button_states:
		# _ui_button_states is only refreshed by explicit populate_ui_buttons()
		# calls (UI init, tab rebuilds); it's not kept in sync with every place
		# that frees a Button (e.g. the monitor tab rebuilding its per-monitor
		# buttons on add/remove), so a stale entry pointing at an already-freed
		# Button is expected here, not a bug to chase at the population site -
		# guard against it directly instead of crashing every frame on it.
		if not is_instance_valid(entry["btn"]):
			continue
		var btn: Button = entry["btn"]
		if not btn.is_visible_in_tree():
			continue
		var primary_hovered := _point_in_ui_rect(_primary_ui_pixel, btn)
		var secondary_hovered := _point_in_ui_rect(_secondary_ui_pixel, btn)
		var hovered := primary_hovered or secondary_hovered
		if primary_hovered and primary_btn == null:
			primary_btn = btn
		if secondary_hovered and secondary_btn == null:
			secondary_btn = btn
		if primary_hovered and primary_tooltip_target == null:
			primary_tooltip_target = btn
		elif secondary_hovered and secondary_tooltip_target == null:
			secondary_tooltip_target = btn
		var use_style = entry["hover"] if hovered else entry["norm"]
		if _last_ui_style.get(btn) != use_style:
			_last_ui_style[btn] = use_style
			btn.add_theme_stylebox_override("normal", use_style)
	if primary_btn != _hover_btn_primary:
		_hover_btn_primary = primary_btn
		if primary_btn != null:
			main.hover_buzz(_active_hand)
	if secondary_btn != _hover_btn_secondary:
		_hover_btn_secondary = secondary_btn
		if secondary_btn != null:
			main.hover_buzz("left" if _active_hand == "right" else "right")
	if main.ui_controller:
		main.ui_controller.set_hovered_tooltip(
			primary_tooltip_target if primary_tooltip_target != null else secondary_tooltip_target
		)

func _point_in_ui_rect(p: Vector2, btn: Button) -> bool:
	if p.x < 0 or p.y < 0:
		return false
	# Buttons on the scrolling Settings page only count where they are
	# visible inside the scroll area (see UIController._make_scroll_friendly()).
	var clip = btn.get_meta(&"nightfall_clip") if btn.has_meta(&"nightfall_clip") else null
	if clip is Control and is_instance_valid(clip) and not clip.get_global_rect().has_point(p):
		return false
	# Hidden by UIController._cull_settings_page() while partly out of view.
	if clip != null and btn.modulate.a <= 0.0:
		return false
	var gp = btn.global_position
	return p.x >= gp.x and p.x <= gp.x + btn.size.x \
		and p.y >= gp.y and p.y <= gp.y + btn.size.y

func handle_grab():
	if not main.grabbed_node:
		return
	if main.device_is_steam_frame and _unlock_until_ms > 0:
		_unlock_until_ms = maxi(_unlock_until_ms, Time.get_ticks_msec() + UNLOCK_KEEP_MS)
	var active_raycast = get_active_raycast()
	var hand_pos = active_raycast.global_position
	var is_panel: bool = main.grabbed_node == main.ui_panel_3d or main.grabbed_node == main.virtual_keyboard
	# Steam Frame follows the grab step by step (see _grab_step); elsewhere
	# it is measured from where the grab began, as upstream does.
	var stepped: bool = main.device_is_steam_frame and main.is_xr_active
	var hand_delta = hand_pos - main.grab_start_hand_pos
	if stepped:
		# Close panels: a gentler multiplier than the far screens use, so
		# small hand moves don't fling the keyboard or menu away.
		var panel_gain := clampf(main.grab_distance * 2.5, 1.5, 6.0)
		_grab_step(hand_pos, panel_gain if is_panel else 6.0, panel_gain * 2.0 if is_panel else 12.0, active_raycast.global_transform.basis)
		_grab_stick_distance()
		hand_delta = _grab_own
	var depth = hand_delta.dot(main.grab_forward) * main.grab_forward
	var lateral = hand_delta - depth
	if main.device_is_steam_frame and is_panel:
		# Long press (hold still on the grab bar or an empty spot): put the
		# menu or keyboard back in its default place.
		if _grab_started_ms == 0:
			_grab_started_ms = Time.get_ticks_msec()
			_grab_reset_done = false
		if _grab_reset_done:
			if not _is_now_clicking():
				_end_grab()
				return
			# Keep holding (about 3 s): bring it right in front of your eyes.
			if not _grab_view_done and _grab_started_ms > 0 and Time.get_ticks_msec() - _grab_started_ms > LONG_LONG_PRESS_MS:
				_grab_view_done = true
				main.buzz(_active_hand, 0.6, 0.06)
				main.bring_to_view(main.grabbed_node, 0.8 if main.grabbed_node == main.ui_panel_3d else 0.6)
			return
		if hand_delta.length() > 0.03:
			_grab_started_ms = -1  # moved: no reset for this grab
		elif _grab_started_ms > 0 and Time.get_ticks_msec() - _grab_started_ms > LONG_PRESS_MS:
			_grab_reset_done = true
			_grab_view_done = false
			main.buzz(_active_hand, 0.4, 0.04)
			if main.grabbed_node == main.ui_panel_3d:
				main.reset_ui_position()
			else:
				main.virtual_keyboard.reset_to_default()
			main._log("[GRAB] Long press: %s back to its default place" % ("menu" if main.grabbed_node == main.ui_panel_3d else "keyboard"))
			return
	if stepped:
		if is_panel:
			_grab_limit(GRAB_NEAREST_PANEL, GRAB_FARTHEST_PANEL)
		else:
			_grab_limit(GRAB_NEAREST_SCREEN, GRAB_FARTHEST_SCREEN)
		main.grabbed_node.global_position = _grab_pos
	elif main.device_is_steam_frame and is_panel:
		var gain := clampf(main.grab_distance * 2.5, 1.5, 6.0)
		var target: Vector3 = main.grab_start_node_pos + lateral * gain + depth * gain * 2.0
		var cam: Vector3 = main.xr_camera.global_position
		var off := target - cam
		var dist := clampf(off.length(), 0.25, 4.0)
		main.grabbed_node.global_position = cam + off.normalized() * dist
	else:
		main.grabbed_node.global_position = main.grab_start_node_pos + lateral * 6.0 + depth * 12.0
	var cam_pos = main.xr_camera.global_position
	if main.device_is_steam_frame and main.is_xr_active:
		_frame_orient_grabbed(active_raycast, cam_pos)
	else:
		main.grabbed_node.rotation.y = atan2(cam_pos.x - main.grabbed_node.global_position.x, cam_pos.z - main.grabbed_node.global_position.z)
		if main.is_xr_active and main.grab_start_hand_basis != Basis():
			var hand_fwd = -active_raycast.global_transform.basis.z
			var hand_pitch = atan2(-hand_fwd.y, Vector2(hand_fwd.x, hand_fwd.z).length())
			var start_fwd = -main.grab_start_hand_basis.z
			var start_pitch = atan2(-start_fwd.y, Vector2(start_fwd.x, start_fwd.z).length())
			var pitch_delta = start_pitch - hand_pitch
			var euler = main.grabbed_node.rotation
			euler.x = main.grab_start_node_euler.x + pitch_delta * 0.66
			euler.z = 0.0
			if absf(euler.x) < 0.052:
				euler.x = 0.0
			main.grabbed_node.rotation = euler

	if main.grabbed_node is VRScreen:
		main.comp.update_cylinder_params()

	if main.grabbed_node == main.primary_screen and not main.grab_group_start_transforms.is_empty():
		var group_delta = main.grabbed_node.global_transform * main.grab_start_primary_transform.affine_inverse()
		if main.device_is_steam_frame and main.is_xr_active and _orient_init:
			# The menu and keyboard follow where the screen goes and how it
			# turns to face you, but not the tilt and roll your wrist gives
			# it: they sit a metre or two in front of the screen, and at
			# that distance every degree of wrist swung them up and down.
			group_delta = Transform3D(_orient_base, main.grabbed_node.global_position) \
				* Transform3D(_orient_base0, main.grab_start_primary_transform.origin).affine_inverse()
		for other in main.grab_group_start_transforms:
			var start_t: Transform3D = main.grab_group_start_transforms[other]
			var nt: Transform3D = group_delta * start_t
			# Everything rides along rigidly, menu and keyboard included, as if
			# attached to the screen (like Head Lock).
			other.global_transform = nt

	# Primary is exempt by construction - it's always free-mode (moving it
	# rigidly drags every grid-consistent secondary along via the group-move
	# block above, which is what "primary moves the whole grid" reduces to).
	# Secondaries snap live, every frame, to the nearest valid grid cell to
	# wherever they're currently being dragged - not just once on release.
	if main.grabbed_node is VRScreen and main.grabbed_node != main.primary_screen and main.settings.grid_mode_enabled and main.grabbed_node.grid_mode:
		_apply_live_grid_snap(main.grabbed_node)

	if main.grabbed_node is VRScreen:
		main.comp.update_cylinder_params()
		main._debug_log_cyl("grab")

	var still_clicking = _is_now_clicking()
	if not still_clicking:
		# Commit grid_mode/grid_pos on release: a screen dragged with Grid Mode
		# on ends up grid_mode=true at wherever it last snapped to; dragged with
		# Grid Mode off, it becomes grid_mode=false (free) and is left alone by
		# the grid system until it's grabbed again with Grid Mode on.
		if main.grabbed_node is VRScreen and main.grabbed_node != main.primary_screen:
			main.grabbed_node.grid_mode = main.settings.grid_mode_enabled
			if main.settings.grid_mode_enabled and main.grab_snap_candidate.x >= 0:
				main.grabbed_node.grid_pos = main.grab_snap_candidate
			main.grab_snap_candidate = Vector2i(-1, -1)
		if main.grabbed_bar:
			_set_grab_bar_color(main.grabbed_bar, _bar_base_color(main.grabbed_node), 0.01)
			main.grabbed_bar = null
		if main.grabbed_node == main.ui_panel_3d:
			main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.08))
		if main.grabbed_node == main.virtual_keyboard:
			main.set_comp_grab_bar_color(main.virtual_keyboard.viewport, Color(1, 1, 1, 0.08))
		_end_grab()

# --- Steam Frame grab orientation ---------------------------------------------
# The grabbed screen (or panel) turns to face your head in full 3D, so it can
# go straight overhead and beyond while still facing you; "up" is carried
# over from the previous frame where facing alone can't decide it (straight
# above or below you). Lying down, your head's up is used instead of the
# room's. On top of that: tilt (top/bottom toward you) follows the hand's
# up/down angle as before, and holding grip while dragging lets you twist
# your wrist to roll the screen (a corner up or down).
var _orient_init := false
var _tilt_rel0 := 0.0
var _orient_up := Vector3.UP
var _orient_base := Basis()        # facing you, before the wrist's tilt and roll: now...
var _orient_base0 := Basis()       # ...and when the grab began
var _orient_tilt0 := 0.0
var _orient_roll := 0.0
var _orient_scale := Vector3.ONE
var _roll_grip_active := false
var _roll_base := 0.0
var _roll_base_hand_up := Vector3.UP

static func _signed_angle(a: Vector3, b: Vector3, axis: Vector3) -> float:
	return atan2(axis.dot(a.cross(b)), a.dot(b))

func _reference_up() -> Vector3:
	var cb: Basis = main.xr_camera.global_transform.basis
	var fy := absf((-cb.z).normalized().y)
	var a := clampf((0.85 - fy) / 0.35, 0.0, 1.0)
	var r := Vector3.UP * a + cb.y.normalized() * (1.0 - a)
	return r.normalized() if r.length() > 0.001 else Vector3.UP

func _facing_basis(node_pos: Vector3, cam_pos: Vector3, hint: Vector3) -> Basis:
	var z := cam_pos - node_pos
	z = z.normalized() if z.length() > 0.01 else Vector3.BACK
	var ref := _reference_up()
	var side := sqrt(maxf(0.0, 1.0 - pow(z.dot(ref), 2.0)))  # 0 when z is along "up"
	var w := clampf((side - 0.15) / 0.5, 0.0, 1.0)
	# Past straight overhead the room's up points the other way from the
	# screen's current up; follow it only where the two agree, so the screen
	# never flips (it keeps facing you as you carry it over).
	var ref_p := ref - z * ref.dot(z)
	var hint_p := hint - z * hint.dot(z)
	if ref_p.length() > 0.001 and hint_p.length() > 0.001:
		w *= clampf(ref_p.normalized().dot(hint_p.normalized()) * 2.0, 0.0, 1.0)
	var up := ref * w + hint * (1.0 - w)
	up -= z * up.dot(z)
	if up.length() < 0.001:
		up = hint - z * hint.dot(z)
	if up.length() < 0.001:
		up = Vector3.FORWARD - z * Vector3.FORWARD.dot(z)
	up = up.normalized()
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)

# How far the controller points above (+) or below (-) the line from your
# head through your hand, measured around the screen's left-right axis.
func _wrist_pitch(ray: RayCast3D, cam_pos: Vector3, axis: Vector3) -> float:
	var arm: Vector3 = ray.global_position - cam_pos
	var f: Vector3 = -ray.global_transform.basis.z
	arm -= axis * arm.dot(axis)
	f -= axis * f.dot(axis)
	if arm.length() < 0.02 or f.length() < 0.01:
		return 0.0
	return _signed_angle(arm.normalized(), f.normalized(), axis)

func _frame_orient_grabbed(active_raycast: RayCast3D, cam_pos: Vector3) -> void:
	var node: Node3D = main.grabbed_node
	var pos := node.global_position
	if not _orient_init:
		_orient_init = true
		var sb: Basis = main.grab_start_node_basis if main.grab_start_node_basis != Basis() else node.global_transform.basis
		_orient_scale = sb.get_scale()
		var so := sb.orthonormalized()
		_orient_up = so.y
		var base0 := _facing_basis(pos, cam_pos, so.y)
		_orient_up = base0.y
		_orient_base0 = base0
		_orient_tilt0 = _signed_angle(base0.z, so.z, base0.x)
		_tilt_rel0 = _wrist_pitch(active_raycast, cam_pos, base0.x)
		var bt0 := Basis(base0.x, _orient_tilt0) * base0
		_orient_roll = _signed_angle(bt0.y, so.y, so.z)
		_roll_grip_active = false
	var base := _facing_basis(pos, cam_pos, _orient_up)
	_orient_up = base.y
	_orient_base = base
	# Tilt from the hand's up/down angle (as before).
	# Tilt follows the wrist bending up/down relative to your arm, so swinging
	# your arm up to carry the screen overhead doesn't tilt it by itself.
	var tilt := _orient_tilt0 + (_wrist_pitch(active_raycast, cam_pos, base.x) - _tilt_rel0) * 0.66
	if absf(tilt) < 0.052:
		tilt = 0.0
	# Roll: hold grip and twist the wrist.
	var hand: XRController3D = main.left_hand if _active_hand == "left" else main.right_hand
	var hb: Basis = active_raycast.global_transform.basis.orthonormalized()
	var gripping: bool = hand != null and hand.get_float("grip") > 0.6
	if gripping and not _roll_grip_active:
		_roll_grip_active = true
		_roll_base = _orient_roll
		_roll_base_hand_up = hb.y
		main.buzz(_active_hand, 0.3, 0.03)
	elif not gripping:
		_roll_grip_active = false
	if _roll_grip_active:
		var f: Vector3 = -hb.z
		var a0: Vector3 = _roll_base_hand_up - f * _roll_base_hand_up.dot(f)
		var a1: Vector3 = hb.y - f * hb.y.dot(f)
		if a0.length() > 0.01 and a1.length() > 0.01:
			_orient_roll = _roll_base - _signed_angle(a0.normalized(), a1.normalized(), f)
	var roll := _orient_roll if absf(_orient_roll) >= 0.05 else 0.0
	var bt := Basis(base.x, tilt) * base
	var br := Basis(bt.z, roll) * bt
	node.global_transform = Transform3D(br * Basis.from_scale(_orient_scale), pos)

var _grab_started_ms := 0
var _grab_reset_done := false
var _grab_view_done := false

# --- Steam Frame: how a grab moves things --------------------------------------
# A grab multiplies the hand's movement (x6 sideways, x12 toward/away for a
# screen). Upstream measures that movement in the room, from where the grab
# began, which goes wrong as soon as your body moves: walking with the bar
# held threw the screen metres away, and turning on the spot dragged it
# through you and flipped it (the "away" direction stayed where it was when
# you grabbed, so the arc your hand makes as you turn read as a hard pull).
#
# Here the grab is followed step by step instead, and each frame the hand's
# movement is split in two:
#  - what your body did: the turn that your head and your arm make together,
#    and the travel that your head and hand make together (plus, while you
#    are walking, the swing of your arm). This carries the grabbed thing with
#    you exactly as if it were fixed to you - it orbits as you turn and keeps
#    its distance as you walk;
#  - what your hand did on its own: the push, pull or sweep. Only this is
#    multiplied.
# "Away" is always the line from your head through the grabbed thing, so a
# push never changes how high it sits in your view.
var _carry_init := false
var _grab_pos := Vector3.ZERO      # where the grabbed thing belongs (before any limits)
var _grab_own := Vector3.ZERO      # the hand's own movement so far (for the long press)
var _carry_prev_head := Vector3.ZERO
var _carry_prev_hand := Vector3.ZERO
var _carry_prev_head_yaw := 0.0
var _carry_prev_hand_yaw := 0.0
var _carry_prev_yaw_ok := false
var _carry_head_speed := 0.0
var _carry_hand_speed := 0.0
var _carry_head_turn := 0.0        # how far the head has turned since the grab began
var _carry_hand_turn := 0.0        # how far the hand has gone round the head
var _carry_body_turn := 0.0        # how much of that has been taken as the body turning
var _carry_prev_slope := 0.0       # how far above (+) or below (-) eye level the thing was, as an angle
var _carry_prev_slope_ok := false
var _carry_prev_hand_basis := Basis()
var _carry_prev_hand_basis_ok := false

# hand_pos is the controller's front end, which swings a few centimetres
# toward or away from you whenever the wrist bends (to tilt or roll what is
# held). Times 12 that pushed a screen 10 to 30 cm, and the menu and keyboard
# with it, where it shows: tilting the screen moved them nearer and farther
# (5p). So of each step's toward/away movement, the part a wrist turn of that
# size could have made (the turn's angle times this lever) is not counted.
# A straight push or pull doesn't turn the controller and is counted in full.
const GRAB_WRIST_LEVER := 0.12
const GRAB_WRIST_IDLE := 0.15  # radians per second

const GRAB_NEAREST_SCREEN := 0.4
const GRAB_FARTHEST_SCREEN := 30.0
const GRAB_NEAREST_PANEL := 0.25
const GRAB_FARTHEST_PANEL := 4.0

static func _flat_yaw(v: Vector3) -> float:
	return atan2(v.x, v.z)

static func _slope_of(v: Vector3) -> float:
	return atan2(v.y, Vector2(v.x, v.z).length())

func _grab_step(hand_pos: Vector3, lateral_gain: float, depth_gain: float, hand_basis: Basis = Basis()) -> void:
	var cam_xf: Transform3D = main.xr_camera.global_transform
	var head: Vector3 = cam_xf.origin
	var arm: Vector3 = hand_pos - head
	# Headings: the head's from its "right" axis (steady even looking straight
	# up or down), the arm's from where the hand is around the head. Either is
	# skipped when it is too close to vertical to have a heading.
	var right: Vector3 = cam_xf.basis.x
	var yaw_ok: bool = Vector2(right.x, right.z).length() > 0.3 and Vector2(arm.x, arm.z).length() > 0.12
	var head_yaw: float = _flat_yaw(right)
	var hand_yaw: float = _flat_yaw(arm)
	if not _carry_init:
		_carry_init = true
		_grab_pos = main.grab_start_node_pos
		_grab_own = Vector3.ZERO
		_carry_head_speed = 0.0
		_carry_hand_speed = 0.0
		_carry_head_turn = 0.0
		_carry_hand_turn = 0.0
		_carry_body_turn = 0.0
		_carry_prev_slope_ok = false
		_carry_prev_hand_basis_ok = false
	else:
		var dt: float = maxf(main.get_process_delta_time(), 0.001)
		var head_step: Vector3 = head - _carry_prev_head
		var hand_step: Vector3 = hand_pos - _carry_prev_hand
		var h2: float = head_step.length_squared()
		# (Steps over half a metre in one frame are tracking jumps: skipped.)
		if h2 < 0.25 and hand_step.length_squared() < 0.25:
			# The turn your body made: what your head and your arm have both
			# turned since the grab began (the smaller of the two, when they
			# went the same way). Counted over the whole grab, not frame by
			# frame, because in a real turn the head leads and the arm catches
			# up. It is taken up only as fast as the hand is actually going
			# round, so turning your head alone never moves anything.
			var turn := 0.0
			if yaw_ok and _carry_prev_yaw_ok:
				var d_hand: float = wrapf(hand_yaw - _carry_prev_hand_yaw, -PI, PI)
				_carry_head_turn += wrapf(head_yaw - _carry_prev_head_yaw, -PI, PI)
				_carry_hand_turn += d_hand
				var body := 0.0
				if _carry_head_turn * _carry_hand_turn > 0.0:
					body = signf(_carry_head_turn) * minf(absf(_carry_head_turn), absf(_carry_hand_turn))
				var want: float = body - _carry_body_turn
				if want * d_hand > 0.0:
					turn = signf(want) * minf(minf(absf(want), absf(d_hand)), 0.35)
				_carry_body_turn += turn
			var prev_arm: Vector3 = _carry_prev_hand - _carry_prev_head
			var rest: Vector3 = hand_step - (prev_arm.rotated(Vector3.UP, turn) - prev_arm)
			# The travel head and hand make together.
			var shared := Vector3.ZERO
			if h2 > 1e-10:
				shared = head_step * clampf(rest.dot(head_step) / h2, 0.0, 1.0)
			var own: Vector3 = rest - shared
			# Walking: the head travels at 0.4 m/s or more (blending in from
			# 0.15) and the hand mostly goes with it - an arm swinging as you
			# step moves well under half as fast as you walk. Then the arm's
			# swing is carried too, or multiplied by 12 it shoves the screen about.
			# (The head's speed is picked up quickly and let go slowly, so the
			# first step of a walk is already counted as walking.)
			var blend: float = 1.0 - exp(-dt / 0.2)
			var head_speed: float = sqrt(h2) / dt
			_carry_head_speed = lerpf(_carry_head_speed, head_speed, 1.0 - exp(-dt / 0.05) if head_speed > _carry_head_speed else blend)
			_carry_hand_speed = lerpf(_carry_hand_speed, own.length() / dt, blend)
			var with_head: float = 1.0 - smoothstep(0.5, 1.0, _carry_hand_speed / maxf(_carry_head_speed, 0.05))
			var walking: float = smoothstep(0.15, 0.4, _carry_head_speed) * with_head
			# Carried with the body: travel, then the turn about the head.
			_grab_pos += shared + own * walking
			_grab_pos = head + (_grab_pos - head).rotated(Vector3.UP, turn)
			main.grab_forward = main.grab_forward.rotated(Vector3.UP, turn)
			# The hand's own movement, multiplied: how far it went along the
			# way it was pointing moves the thing along the line from the head.
			var push: Vector3 = own * (1.0 - walking)
			var along: float = push.dot(main.grab_forward)
			var counted: float = along
			if _carry_prev_hand_basis_ok:
				# (Turning slower than GRAB_WRIST_IDLE is a hand held still.)
				var wrist: float = _carry_prev_hand_basis.orthonormalized().get_rotation_quaternion() \
					.angle_to(hand_basis.orthonormalized().get_rotation_quaternion())
				wrist = maxf(0.0, wrist - GRAB_WRIST_IDLE * dt)
				counted = signf(along) * maxf(0.0, absf(along) - wrist * GRAB_WRIST_LEVER)
			var away: Vector3 = _grab_pos - head
			away = away.normalized() if away.length_squared() > 1e-6 else main.grab_forward
			_grab_pos += (push - main.grab_forward * along) * lateral_gain + away * counted * depth_gain
			_grab_own += push
			# "Toward/away" for the hand started as the way the controller
			# pointed. As the thing goes up or down in your view, that
			# direction tips up or down with it. Otherwise, lowering a menu
			# with a straight arm (the hand swings back toward your legs at
			# the bottom) read as a pull and swooped it up into your face.
			var slope: float = _slope_of(_grab_pos - head)
			var side: Vector3 = main.grab_forward.cross(Vector3.UP)
			if _carry_prev_slope_ok and side.length_squared() > 1e-4:
				var tipped: Vector3 = main.grab_forward.rotated(side.normalized(), clampf(slope - _carry_prev_slope, -0.2, 0.2))
				if absf(_slope_of(tipped)) < 1.4: # never over the top
					main.grab_forward = tipped
			_carry_prev_slope = slope
			_carry_prev_slope_ok = true
	_carry_prev_head = head
	_carry_prev_hand = hand_pos
	_carry_prev_hand_basis = hand_basis
	_carry_prev_hand_basis_ok = hand_basis != Basis()
	_carry_prev_head_yaw = head_yaw
	_carry_prev_hand_yaw = hand_yaw
	_carry_prev_yaw_ok = yaw_ok

# Keeps the grabbed thing between its nearest and farthest distance from the head.
func _grab_limit(nearest: float, farthest: float) -> void:
	var head: Vector3 = main.xr_camera.global_position
	var off: Vector3 = _grab_pos - head
	if off.length_squared() < 1e-6:
		off = main.grab_forward
	_grab_pos = head + off.normalized() * clampf(off.length(), nearest, farthest)

# --- Steam Frame: thumbstick sets the distance while grabbing ------------------
# Holding a grab, the same hand's stick moves the grabbed screen, menu or
# keyboard away (up) or closer (down), as SteamOS's own windows do. The speed
# scales with the distance, so it feels the same near and far.
const GRAB_STICK_DEADZONE := 0.25
const GRAB_STICK_RATE := 0.9 # e-folds per second at full tilt (about 2.5x)

func _grab_stick_distance() -> void:
	var hand: XRController3D = main.left_hand if _active_hand == "left" else main.right_hand
	if hand == null:
		return
	var y: float = hand.get_vector2("primary").y
	if absf(y) < GRAB_STICK_DEADZONE:
		return
	var off: Vector3 = _grab_pos - main.xr_camera.global_position
	var dist: float = off.length()
	if dist < 0.01:
		return
	var tilt: float = (absf(y) - GRAB_STICK_DEADZONE) / (1.0 - GRAB_STICK_DEADZONE) * signf(y)
	_grab_pos += off / dist * (dist * exp(tilt * GRAB_STICK_RATE * main.get_process_delta_time()) - dist)

## True while the thumbstick of `hand` ("left"/"right") is steering a grab's
## distance, so it shouldn't also scroll the PC or reach a game.
func grab_owns_stick(hand: String) -> bool:
	return hand == _active_hand and main.get("grabbed_node") != null and main.get("device_is_steam_frame") == true

func _end_grab() -> void:
	if main.device_is_steam_frame and main.grabbed_node == main.primary_screen and main.xr_camera and _orient_init:
		var head: Vector3 = main.xr_camera.global_position
		var at: Transform3D = main.primary_screen.global_transform
		var parts := ["screen %.2f m away (was %.2f), tilted %d deg" % [
			at.origin.distance_to(head), main.grab_start_primary_transform.origin.distance_to(head),
			roundi(rad_to_deg(_signed_angle(_orient_base.z, at.basis.z.normalized(), _orient_base.x)))]]
		if main.ui_visible and main.ui_panel_3d:
			parts.append("menu %.2f m" % main.ui_panel_3d.global_position.distance_to(head))
		if main.virtual_keyboard and main.virtual_keyboard.visible:
			parts.append("keyboard %.2f m" % main.virtual_keyboard.global_position.distance_to(head))
		main._log("[GRAB] released: " + ", ".join(parts))
	if main.grabbed_node == main.ui_panel_3d:
		main.set_comp_grab_bar_color(main.ui_viewport, Color(1, 1, 1, 0.08))
		main._save_ui_offset()
	elif main.grabbed_node == main.virtual_keyboard:
		main.set_comp_grab_bar_color(main.virtual_keyboard.viewport, Color(1, 1, 1, 0.08))
		main.virtual_keyboard._save_offset()
	main.grabbed_node = null
	main.grab_start_hand_basis = Basis()
	main.grab_start_node_basis = Basis()
	main.grab_start_node_euler = Vector3.ZERO
	if main.virtual_keyboard and main.grab_group_start_transforms.has(main.virtual_keyboard):
		main.virtual_keyboard._save_offset()
	if main.grab_group_start_transforms.has(main.ui_panel_3d):
		main._save_ui_offset()
	main.grab_group_start_transforms.clear()
	_orient_init = false
	_carry_init = false
	_roll_grip_active = false
	_grab_started_ms = 0
	_grab_reset_done = false
	main.state_manager.save_state()

# Snaps s (a grabbed, non-primary, grid-mode screen) to the nearest free grid
# cell relative to primary's CURRENT (possibly itself mid-drag, for a rigid
# primary-group-move) transform - called every frame during a drag, not just
# on release, per spec ("snap to the nearest valid position according to
# where I am pointing the controller" while dragging).
func _apply_live_grid_snap(s: VRScreen):
	var primary: VRScreen = main.primary_screen
	if not primary:
		return
	var occupied: Array = []
	for other in main.screens:
		if other != s and other.grid_mode:
			occupied.append(other.grid_pos)
	var cand = main.nearest_free_grid_cell(s.global_position, occupied, primary.grid_pos.x, primary.grid_pos.y)
	if cand.x < 0:
		return
	main.grab_snap_candidate = cand
	s.global_transform = main.grid_cell_transform(cand.x, cand.y, primary.grid_pos.x, primary.grid_pos.y)

func handle_corner_resize():
	if main.grabbed_corner_idx < 0 or not main.grabbed_corner_screen:
		return
	var s = main.grabbed_corner_screen
	var active_raycast = get_active_raycast()
	var ray_origin = active_raycast.global_position
	var ray_dir = -active_raycast.global_transform.basis.z
	var tile_aspect = float(s.monitor.frame_rect.size.x) / float(s.monitor.frame_rect.size.y) if s.monitor and s.monitor.frame_rect.size.y > 0 else 16.0 / 9.0

	if not _corner_resize_started:
		s.begin_corner_resize()
		_corner_resize_started = true
	s.apply_corner_resize(ray_origin, ray_dir, main.grabbed_corner_idx, tile_aspect)

	main.comp.update_layer_size()

	var still_clicking = _is_now_clicking()
	if not still_clicking:
		var handle = s.corner_handles[main.grabbed_corner_idx]
		_set_corner_color(handle, Color.WHITE, 0.05)
		main.grabbed_corner_idx = -1
		main.grabbed_corner_screen = null
		_corner_resize_started = false
		s.end_corner_resize()
		main.state_manager.save_state()
		if main._ui_screen_size_btn:
			main.settings_controller.refresh_screen_size_btn()



func _push_ui_click(pos: Vector2, pressed: bool):
	var event = InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	main.ui_viewport.push_input(event)
	if not pressed:
		var focused = main.ui_viewport.gui_get_hovered_control()
		if focused and not (focused is BaseButton) and focused.get_parent() is BaseButton:
			focused = focused.get_parent()
		var label = ""
		if focused is Button:
			label = (focused as Button).text
		main._log("[UI] Click at %s -> %s %s%s" % [str(pos), focused.name if focused else "nothing",
			"'%s'" % label.replace("\n", " ") if label != "" else "",
			" (disabled)" if focused is BaseButton and (focused as BaseButton).disabled else ""])

const PRIMARY_BAR_COLOR := Color(0.55, 0.78, 1.0)

# Light blue for the primary screen's grab bar, white for every other screen -
# a quick visual cue for which screen is primary (drag it and the whole
# constellation moves; drag anything else and only that screen moves/snaps).
func _bar_base_color(screen: VRScreen) -> Color:
	return PRIMARY_BAR_COLOR if screen == main.primary_screen else Color.WHITE

func _set_grab_bar_color(bar: MeshInstance3D, color: Color, alpha: float = 1.0):
	var desired_color = Color(color.r, color.g, color.b, alpha)
	if bar.material_override.albedo_color != desired_color:
		bar.material_override.albedo_color = desired_color
	# Mirror onto the composition-space equivalent (2026-08-24) - same
	# pattern as _set_corner_color(). grab_bar is a %-unique-named node
	# from VRScreen's own packed scene, not necessarily a direct child, so
	# walk up to find the owning VRScreen rather than assuming get_parent().
	var screen = bar.get_parent()
	while screen and not (screen is VRScreen):
		screen = screen.get_parent()
	if screen is VRScreen:
		main.composition_screen_controls.set_grab_bar_color(screen, desired_color)

func _set_corner_color(handle: MeshInstance3D, color: Color, alpha: float = 1.0):
	var c = Color(color.r, color.g, color.b, alpha)
	if handle.material_override:
		handle.material_override.albedo_color = c
	for child in handle.get_children():
		if child is MeshInstance3D:
			child.material_override.albedo_color = c
	# Mirror onto the composition-space equivalent. CompositionScreenControls
	# applies modulate.a to the viewport's corner TextureRect. Changing a child
	# inside an already-visible viewport is the same
	# safe category as the per-screen stream cursors (not the composition
	# layer's own `visible` toggling that caused the earlier crash).
	var screen = handle.get_parent()
	if screen is VRScreen and handle.has_meta(&"nf_corner_idx"):
		var idx: int = handle.get_meta(&"nf_corner_idx")
		main.composition_screen_controls.set_corner_alpha(screen, idx, alpha)

# AI-3D draws only the primary screen in depth, so only clicks there are
# shifted to meet the image. Secondary screens are flat: shifting them put
# every click to the right of the pointer, untouched by the cursor setting.
func _stereo_click_uv_x(screen: VRScreen, uv_x: float) -> float:
	if screen != main.primary_screen or main.settings_controller.get_stereo_mode() < 3:
		return uv_x
	return clampf(uv_x + _compute_parallax_shift(uv_x) + _click_3d_bias(), 0.0, 1.0)

# A fixed nudge added to clicks in 3D. On the Steam Frame it put the PC
# cursor to the right of the drawn cursor in BOTH eyes (a constant bias, not
# a parallax mismatch), so it's off there.
func _click_3d_bias() -> float:
	return 0.0 if main.device_is_steam_frame else 0.0075

# Squeezing the grip shakes the aim. With Cursor Follow on, the PC saw that
# as moving the mouse with the right button down: dragging a tray icon, say,
# instead of opening its menu. So the PC cursor stays where the right click
# began until the pointer has clearly moved away (a real right-button drag,
# as for turning a camera), and follows as before from then on.
const RIGHT_DRAG_START := 0.0125 # of the stream's width: 24 px at 1920
var _rclick_start_pt := Vector2(-1, -1)
var _rclick_dragging := false

func _right_click_holding_still(host_pt) -> bool:
	if not main.was_right_clicking or _rclick_dragging or _rclick_start_pt.x < 0.0:
		return false
	if Vector2(host_pt).distance_to(_rclick_start_pt) > main.layout.host_ref().x * RIGHT_DRAG_START:
		_rclick_dragging = true
		return false
	return true

func is_cursor_following() -> bool:
	return main.settings.cursor_follow or main.settings.cursor_mode == 2

func _compute_parallax_shift(uv_x: float) -> float:
	if not main.depth_estimator or not main.depth_estimator.depth_texture:
		return 0.0
	var mat = main.screen_mesh.material_override
	if not mat or not mat is ShaderMaterial:
		return 0.0
	var tex = main.depth_estimator.depth_texture
	var img = tex.get_image()
	if not img or img.is_empty():
		return 0.0
	var parallax = 0.042
	var half_parallax = parallax * 0.5
	var convergence = mat.get_shader_parameter("convergence")
	if convergence == null:
		convergence = 0.5
	var balance_shift = mat.get_shader_parameter("balance_shift")
	if balance_shift == null:
		balance_shift = 0.5
	var depth_x = int(clampf(uv_x - half_parallax, 0.0, 1.0) * (img.get_width() - 1))
	var depth_y = int(img.get_height() * 0.5)
	depth_x = clampi(depth_x, 0, img.get_width() - 1)
	depth_y = clampi(depth_y, 0, img.get_height() - 1)
	var depth = img.get_pixel(depth_x, depth_y).r
	var depth_diff = clampf(depth - convergence, -convergence, 1.0 - convergence)
	var dist_from_convergence = absf(depth - convergence)
	var zone_radius = 0.70
	var fade_multiplier = smoothstep(0.0, zone_radius, dist_from_convergence)
	depth_diff *= fade_multiplier
	var shift = parallax * depth_diff
	if (depth - convergence) < 0.0:
		shift *= (1.0 - balance_shift)
	else:
		shift *= balance_shift
	var h_dist = absf(uv_x - 0.5) * 2.0
	var vignette_start = 0.7
	var vignette = 1.0 - smoothstep(vignette_start, 1.0, pow(h_dist, 1.5))
	shift *= vignette
	return shift

var _scroll_cooldown: float = 0.0

## Moves the PC cursor to where the VR pointer is on the stream (for button
## actions such as a mapped right click). False if the pointer isn't on it.
## "Hides" the PC cursor by parking it on the last column of pixels at the
## right edge: the arrow is drawn down and right of its tip, so it ends up
## off screen. Moving the pointer onto the screen (or clicking) brings it back.
func park_host_cursor() -> void:
	if not main.is_streaming:
		return
	var ref = main.layout.host_ref()
	# Middle of the right edge: the bottom-right corner is Windows' "Show
	# desktop" button (its tooltip stayed up). Only the arrow's tip stays on
	# screen here, and video players hide an idle cursor that's over them.
	main.stream_backend.send_mouse_position_event(ref.x - 1, ref.y / 2, ref.x, ref.y)
	# Cursor Follow stays quiet until the pointer actually moves.
	_parked_at_pointer = _last_follow_pt
	_cursor_parked = true
	main._log("[CURSOR] parked the PC cursor on the right edge")

func move_host_cursor_to_pointer() -> bool:
	var rc = get_active_raycast()
	if rc == null or not rc.is_colliding():
		return false
	var t = PointerTarget.resolve(rc.get_collider())
	if t.role != &"screen" or not t.screen:
		return false
	var uv = t.screen.hit_point_to_uv(main._get_steady_hit(rc.get_collision_point()))
	var uv_x = uv.x
	if main.settings_controller.get_stereo_mode() >= 3:
		uv_x = clampf(uv_x + _compute_parallax_shift(uv_x) + _click_3d_bias(), 0.0, 1.0)
	var host_pt = main.layout.uv_to_host_point(t.screen.monitor, Vector2(uv_x, uv.y))
	var ref = main.layout.host_ref()
	main.stream_backend.send_mouse_position_event(host_pt.x, host_pt.y, ref.x, ref.y)
	return true

# Thumbstick scrolls whatever scrollable menu page the pointer is over.
func _ui_stick_scroll() -> bool:
	if not main.is_xr_active or not pointer_on_ui or not main.ui_visible or _primary_ui_pixel.x < 0:
		return false
	var y := 0.0
	for hand in [main.right_hand, main.left_hand]:
		if hand:
			var v: float = hand.get_vector2("primary").y
			if absf(v) > absf(y):
				y = v
	if absf(y) < 0.15:
		return true # on the menu: never scroll the PC underneath
	for sc in main.ui_viewport.find_children("*", "ScrollContainer", true, false):
		if sc.is_visible_in_tree() and sc.get_global_rect().has_point(_primary_ui_pixel):
			var step := y * 1600.0 * main.get_process_delta_time()
			_ui_scroll_accum += step
			var whole := int(_ui_scroll_accum)
			if whole != 0:
				sc.scroll_vertical -= whole
				_ui_scroll_accum -= whole
			return true
	return true

var _ui_scroll_accum := 0.0

func handle_scroll():
	if grab_owns_stick("right"):
		return # the stick is setting the grabbed thing's distance
	if _ui_stick_scroll():
		return
	var browser = main.screen_sources.focused_browser()
	var ray := get_active_raycast()
	if ray and ray.is_colliding():
		var target := PointerTarget.resolve(ray.get_collider())
		if target.role == &"screen":
			browser = main.screen_sources.browser_for_screen(target.screen)
	var browser_active: bool = browser != null and browser.active
	if not main.is_xr_active or (not main.is_streaming and not browser_active):
		return
	if browser_active and main.ui_visible:
		return
	if main.controller_mapper and main.controller_mapper.is_active():
		if main.controller_mapper.ctrl_type != ControllerMapper.CtrlType.KBMOUSE:
			return
	if main.virtual_keyboard and main.virtual_keyboard.trackpad_active:
		return
	var now = Time.get_ticks_msec() / 1000.0
	if _scroll_cooldown > now:
		return
	# Only the Quest controller's stick scrolls. A gamepad's right stick is
	# already forwarded to the host (or the page) as a gamepad; also scrolling
	# with it changes weapons in shooters (#60).
	var right_stick_y = main.right_hand.get_vector2("primary").y if main.right_hand else 0.0
	var clicks := scroll_clicks(right_stick_y)
	if clicks != 0:
		if browser_active:
			browser.scroll(clicks)
		else:
			main.stream_backend.send_scroll_event(clicks)
		_scroll_cooldown = now + 0.15

static func scroll_clicks(stick_y: float) -> int:
	if absf(stick_y) <= 0.5:
		return 0
	return 1 if stick_y > 0 else -1
# Steam Frame: the whole menu works as a grab bar - pulling the trigger on any
# spot that isn't a button (or other control) picks the menu up.
var _ui_controls_cache: Array = []
var _ui_controls_frame := -1000

func _ui_point_is_empty(pixel_pos: Vector2) -> bool:
	var frame := Engine.get_process_frames()
	if frame - _ui_controls_frame > 30:
		_ui_controls_frame = frame
		_ui_controls_cache = main.ui_viewport.find_children("*", "BaseButton", true, false) \
			+ main.ui_viewport.find_children("*", "LineEdit", true, false) \
			+ main.ui_viewport.find_children("*", "Range", true, false)
	for c in _ui_controls_cache:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pixel_pos):
			return false
	return true

func _is_ui_grab_bar(pixel_pos: Vector2) -> bool:
	var bar = main.ui_viewport.find_child("CompGrabBar", true, false)
	# Hidden on the Advanced Settings page, where its old rect is page content.
	if not bar or not bar is Control or not bar.is_visible_in_tree():
		return false
	var bar_rect = bar.get_global_rect()
	return pixel_pos.x >= bar_rect.position.x and pixel_pos.x <= bar_rect.end.x and pixel_pos.y >= bar_rect.position.y and pixel_pos.y <= bar_rect.end.y

func _is_kb_grab_bar(pixel_pos: Vector2) -> bool:
	if not main.virtual_keyboard or not main.virtual_keyboard.viewport:
		return false
	var bar = main.virtual_keyboard.viewport.find_child("CompGrabBar", true, false)
	if not bar or not bar is Control:
		return false
	var bar_rect = bar.get_global_rect()
	return pixel_pos.x >= bar_rect.position.x and pixel_pos.x <= bar_rect.end.x and pixel_pos.y >= bar_rect.position.y and pixel_pos.y <= bar_rect.end.y
