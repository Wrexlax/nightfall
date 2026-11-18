extends Node3D

var settings: AppSettings = AppSettings.new()
var session_lifecycle: SessionLifecycle = SessionLifecycle.new()
var pcvr_test = preload("res://src/pcvr_test_controller.gd").new(self)
var pcvr_handover = preload("res://src/pcvr_workspace_handover.gd").new(self)
var _pcvr_screen_retirements := 0
var telemetry: PerformanceTelemetry = PerformanceTelemetry.new()

@onready var screen_mesh = $MeshInstance3D
@onready var ui_panel_3d = %UIPanel3D
@onready var ui_viewport = %UIViewport
@onready var stream_viewport = %StreamViewport
@onready var stream_target = %StreamTarget
@onready var detection_viewport = %DetectionViewport
@onready var detection_target = %DetectionTarget
@onready var welcome_viewport = %WelcomeViewport
@onready var config_mgr = ClassDB.instantiate("NightfallConfigManager") if ClassDB.class_exists("NightfallConfigManager") else null
@onready var comp_mgr = ClassDB.instantiate("NightfallComputerManager") if ClassDB.class_exists("NightfallComputerManager") else null
var mdns
var stream_backend: StreamBackend

func _get_mdns():
	if not mdns and ClassDB.class_exists("MdnsBrowser"):
		mdns = ClassDB.instantiate("MdnsBrowser")
	return mdns

var startup_hand_fallback = preload("res://src/startup_hand_fallback.gd").new()

func effective_tracking_mode() -> int:
	return startup_hand_fallback.effective_mode(settings.tracking_mode)

func tracking_mode_label() -> String:
	return tracking_labels[clampi(effective_tracking_mode(), 0, tracking_labels.size() - 1)] + (" (Auto)" if startup_hand_fallback.auto_enabled else "")

func _process_startup_hand_fallback(delta: float) -> void:
	if startup_hand_fallback.decided and not startup_hand_fallback.auto_enabled: return
	var physical := false
	for path in [&"/user/hand/left", &"/user/hand/right"]:
		if startup_hand_fallback.physical_controller_available(XRServer.get_tracker(path)):
			physical = true
	var hands := false
	for path in [&"/user/hand_tracker/left", &"/user/hand_tracker/right"]:
		var tracker = XRServer.get_tracker(path)
		if tracker is XRHandTracker and tracker.get_has_tracking_data(): hands = true
	if startup_hand_fallback.step(delta, settings.tracking_mode, physical, hands):
		_log("[HAND] No physical controller at startup; enabled session-only hand tracking" if startup_hand_fallback.auto_enabled else "[HAND] Physical controller detected; retired startup hand fallback")
		state_manager.sync_ui_to_settings(false)

func get_is_hand_tracking() -> bool:
	if effective_tracking_mode() not in [1, 3]:
		return false
	for tracker_name in ["/user/hand_tracker/right", "/user/hand_tracker/left"]:
		var tracker = XRServer.get_tracker(tracker_name)
		if tracker and tracker is XRHandTracker:
			return true
	return false

func get_hand_tracking_has_data() -> bool:
	if effective_tracking_mode() not in [1, 3]:
		return false
	for tracker_name in ["/user/hand_tracker/right", "/user/hand_tracker/left"]:
		var tracker = XRServer.get_tracker(tracker_name)
		if tracker and tracker is XRHandTracker:
			if tracker.get_has_tracking_data():
				# Steam Frame: SteamVR also reports a hand skeleton guessed from
				# the controller's finger sensors. That isn't real hand tracking
				# and fights the controller pointer, so only camera-tracked
				# (unobstructed) hands take over there.
				if device_is_steam_frame and tracker.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
					continue
				return true
	return false
@onready var xr_origin = $XROrigin3D
@onready var xr_camera = $XROrigin3D/XRCamera3D
@onready var mouse_raycast = %RayCast3D
@onready var hand_raycast = %HandRayCast
@onready var right_hand = %RightHand
@onready var left_hand = %LeftHand
@onready var audio_player = %StreamAudioPlayer
@onready var world_env = $WorldEnvironment

var current_host_id: int = -1
var _last_hostname: String = ""
var _selected_app_id: int = 881448767
var _selected_app_idx: int = 0
var _available_apps: Array = []
var _welcome_screen: String = "welcome"
var _pair_pin: String = ""
var _connecting_ip: String = ""
# Whether the host is drawing its own cursor into the captured frame (Polaris-only:
# a POST /polaris/v1/session/cursor endpoint neither Sunshine nor Apollo expose today).
# Support is detected per-connection from the launch response, not guessed up front,
# since a version-string heuristic already burned us once for microphone detection.
var host_cursor_visible: bool = false
var _host_cursor_toggle_supported: bool = false
var _did_initial_monitor_trim: bool = false
var _stream_start_seq: int = 0
var is_streaming: bool:
	get: return session_lifecycle.media_active
var is_xr_active: bool = false
var was_clicking: bool = false
var was_right_clicking: bool = false
var right_click_cooldown: float = 0.0
var primary_controller_shortcuts = preload("res://src/primary_controller_shortcuts.gd").new()
var _startup_reposition: int = 0  # 0=waiting for tracking, 1=centered, 2=positioning
## Steam Frame: no saved state was found at this start (StateManager.load_state()).
## The first time the screen is put in front of you it gets FrameDefaults' width.
var frame_first_start := false
var _saved_room_transform = null  # Transform3D of the main screen last session (Steam Frame)
var _state_loaded := false  # load_state() has run; the launch placement waits for it
var _startup_last_cam := Vector3.ZERO
var _startup_still_frames := 0
var _startup_cover: MeshInstance3D
var _startup_ready: bool = false

var _is_using_hands: bool = false
var tracking_labels: Array = ["Off", "Hands", "Off", "UI Only"] # 2: retired head-tracking setting
var _hand_menu_pressed: bool = false

# OS/runtime controller render models (2026-08-25, see the archived
# docs/archive/plans/gles-quest-projectionless.md plan's
# "Controller and hand experiment" section) - OpenXRFbRenderModel wraps
# XR_FB_render_model, letting the runtime hand us its own real controller
# mesh instead of the bundled MetaQuestTouchPlus FBX (_load_controller_models()
# below, which stays as the fallback, and is no longer even bundled in the
# Android export - see export_presets.cfg). Default OFF. Tried routing it
# through a composition-space 3D capture (2026-08-27, same technique as the
# hand-skeleton indicator that used to live below) - pulled back out along
# with that whole approach: rendering a real 3D scene into an offscreen
# viewport every frame was too expensive even throttled to 14fps (see the
# composite-only hand indicator that replaced it), and there's every reason
# to expect the same cost for controllers. Back to its original scope:
# normal (mesh) projection mode only - projectionless/composition mode
# would need a genuinely cheap 3D-in-composition-layer renderer, which this
# isn't, so it stays out of scope until one exists.
const DEBUG_RENDER_MODEL_CONTROLLERS := false
var right_render_model: Node3D = null
var left_render_model: Node3D = null
var _right_render_model_ready: bool = false
var _left_render_model_ready: bool = false
var left_hand_raycast: RayCast3D = null
var mouse_captured_by_stream: bool = false
var suppress_input_frames: int = 0
var auto_detect_enabled: bool = false
var auto_detect_timer: float = 0.0
var auto_detect_running: bool = false
var detection_history: Array = []
var mouse_sensitivity: float = 0.002
var grabbed_node: Node3D = null
var grab_distance: float = 0.0
var grab_offset: Vector3 = Vector3.ZERO
var grabbed_bar: MeshInstance3D = null
var grab_start_hand_pos: Vector3 = Vector3.ZERO
var grab_start_node_pos: Vector3 = Vector3.ZERO
var grab_forward: Vector3 = Vector3.FORWARD
var grab_start_hand_basis: Basis = Basis()
var grab_start_node_basis: Basis = Basis()
var grab_start_node_euler: Vector3 = Vector3.ZERO
var grab_start_primary_transform: Transform3D = Transform3D.IDENTITY
var grab_group_start_transforms: Dictionary = {}
var grab_snap_candidate: Vector2i = Vector2i(-1, -1)
# Passthrough is real extra GPU cost (native OpenXR alpha-blend, composited
# by the system compositor, confirmed via on-device benchmark 2026-08-25) -
# no in-app UI disclaimer for this by design; settings_controller.gd's
# AUTO_TABLE already accounts for it directly in its tier/model picks.
var passthrough_supported: bool = false
var background_labels: Array = ["Black", "Ash", "Snow", "Data"]
var bg_names: Array = ["Ash", "Snow", "Data"]
var bg_offsets: Array = [Vector3.ZERO, Vector3(0, 10, 0), Vector3(0, -3, 0)]
var ui_visible: bool = false
var bezel_mesh: MeshInstance3D:
	get: return primary_screen.bezel_mesh if primary_screen else null
	set(v):
		if primary_screen: primary_screen.bezel_mesh = v
var curvature: int:
	get: return primary_screen.curvature if primary_screen else 2
	set(v):
		if primary_screen: primary_screen.curvature = v
var curvature_labels: Array = ["Flat", "Slight Curve", "Curved"]
const SHARPEN_RUNTIME_NORMAL := 6
const SHARPEN_RUNTIME_QUALITY := 7
# Keep the existing shader modes in their original saved-state slots for a
# direct A/B comparison. The two runtime modes bypass those expensive video
# neighbourhood samples when the OpenXR extension is available.
var sharpen_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%", "Runtime", "Runtime Quality"]
# Picture tab (2026-08-31) - brightness/contrast/gamma grade applied as a
# final step after YUV->RGB conversion (and after HDR tonemap, on the HDR
# shader variant) - see settings_controller.gd's apply_filter() for the
# percent->shader-uniform mapping and each shader's apply_picture().
# Ambient screen lighting is a separate low-resolution composition layer,
# so it stays out of the main YUV/HDR/AI-3D shader path. Reactive modes use
# the already-rendered primary screen as their colour source.
var ambient_mode_labels: Array = ["Off", "Static", "Slow", "Live"]
var ambient_color_labels: Array = ["White", "Warm", "Red", "Green", "Blue", "Purple"]
var _xr_base_render_scale: float = 1.0
var _xr_render_width: int = 2064
var _mesh_size: Vector2:
	get: return primary_screen.mesh_size if primary_screen else Vector2(2.24, 1.26)
	set(v):
		if primary_screen: primary_screen.mesh_size = v
var _cached_sharpen: float = -1.0
var _cached_blur_scale: float = -1.0
# host_resolution is the actual WxH about to be (or last) requested from the
# host - computed from the selected host's native size and resolution scale,
# not set directly. It always matches whatever the host's real desktop/composite
# shape is (single monitor or multi-monitor composite alike), instead of a
# fixed target size that would force the host to letterbox/squeeze a
# mismatched-aspect composite to fit.
var host_resolution: Vector2i = Vector2i(1920, 1080)
# Last known real desktop/composite size for the currently selected host, as
# reported by its display manifest (or session_optimization's negotiated
# width/height for hosts without one). Cached per-host in host_state.cfg so a
# repeat connection can request the correctly-scaled resolution on the first
# try instead of needing the mismatch-triggered reconnect every time.
const RESOLUTION_PRESETS: Array = [100, 90, 80, 70, 60, 50]
# Kept around for state_manager.gd's old-save-file validation fallback; the UI
# itself now uses compute_resolution_options() instead of this static list -
# see that function for why (this doesn't know about the per-codec/per-native-
# resolution caps below, so a preset here can silently be unreachable).
var resolution_scale_options: Array = RESOLUTION_PRESETS
# True once SettingsController.detect_polaris_host() confirms this host answers
# the Polaris-only /polaris/v1/display/manifest probe. Polaris is host-driven -
# it reports its real (possibly multi-monitor) desktop size, so the
# percentage-of-native-resolution system above gives an accurate result. Every
# other GameStream-compatible host (Sunshine, GFE, etc.) is client-driven -
# there is no equivalent "ask the host its resolution" mechanism at all, the
# client is expected to just request what it wants and the host adapts to
# match. The cached native resolution has nothing real to hold for them, so the
# percentage system's "MAX"/percent labels would just describe the wrong
# thing (confirmed: reported "1080p" against a real 2560x1440 Sunshine
# display, because the cached value never left its 1920x1080 fallback).
# Defaults false (the old fixed-list picker) so a host that hasn't been probed
# yet - or a probe that's still in flight - never shows a percentage of a
# guess as if it meant something.
# Detected once at startup via stream_backend.get_device_model() (Android's
# Build.MODEL, read through DepthBridge's JNI bridge - see GodotApp.java's
# getDeviceModel()). Quest 2's Snapdragon XR2 Gen 1 GPU benchmarks at
# roughly 2-2.5x slower than Quest 3/3s's XR2 Gen 2 (Meta's own published
# figures), and our AI-3D depth inference runs on the GLES GPU delegate -
# the same GPU used for rendering, not the (much bigger, but NNAPI-gated
# and unavailable to us) NPU gap - so the existing AUTO_TABLE (hand-tuned
# entirely on Quest 3/3s) is a poor fit there. Added 2026-08-27 after a
# Quest 2 user reported AI-3D tanking performance; see settings_controller.
# gd's QUEST2_AUTO_TABLE and main.gd's QUEST2_MAX_RESOLUTION.
var device_is_quest2: bool = false
var device_is_quest3: bool = false
# Steam Frame (Build.DEVICE 'lepton_arm64_only'). Its SteamVR OpenXR runtime
# lacks cylinder/equirect composition layers, so projectionless mode leaves
# the welcome screen and menus invisible - render the normal 3D scene there.
var device_is_steam_frame: bool = false
# See device_is_quest2's comment. Quest 2's own per-eye display resolution
# (~1832x1920) is already below Quest 3's, so there's no real benefit
# requesting more than this regardless of AI-3D state - applied in
# compute_requested_resolution() as a hard ceiling before any other cap.
const QUEST2_MAX_RESOLUTION := Vector2i(1920, 1080)

# The pre-percentage fixed-resolution picker, used for any non-Polaris host
# (see the Polaris detection comment above) - the user picks what they actually want
# instead of the client trying to detect anything, matching how Sunshine
# itself expects to be driven. Untouched by the H264/HEVC dimension/pixel
# caps in compute_max_resolution_pct() below - every entry here is well
# under all of those caps on its own (largest is 3840x2160), so there's
# nothing to filter for the single-screen case this picker is used for.
var resolutions: Array = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1600, 1200), Vector2i(2560, 1080), Vector2i(3440, 1440)]
# 21:9 split into two tiers (2026-08-20, GitHub issue #17) - was a single
# 3440x1440 entry, which meant there was no way to request a 21:9 source at a
# more modest pixel budget (matching the HD/2K split every other aspect
# already gets). 2560x1080 (UWFHD, 64:27) and 3440x1440 (UWQHD, 43:18) are
# the two real, common ultrawide monitor resolutions - not arbitrary picks.
var resolution_labels: Array = ["720", "HD", "2K", "4K", "4:3", "21:9 HD", "21:9 2K"]
var bitrates: Array = [5, 10, 15, 20, 30, 40, 50, 60, 80, 100, 120]
var bitrate_labels: Array = ["Auto", "5", "10", "15", "20", "30", "40", "50", "60", "80", "100", "120"]
var display_refresh_rate: float = 72.0

# Third mode: the VR cursor is hidden on stream screens. On the Steam Frame it
# is called "PC Cursor" and the PC's own cursor also follows the pointer there
# (see XRInteraction.is_cursor_following()).
var cursor_labels: Array = ["Circle", "Pointer", "PC Cursor" if MenuSchema._IS_FRAME else "Hidden"]
# "Adaptive" is the published "1 euro" filter (Casiez, Roussel and Vogel, 2012);
# upstream's label is "One Euro", which told the user nothing (2026-11-16).
var pointer_steady_labels: Array = ["Off", "Low", "High", "Adaptive", "Max"]
## The order Cursor Steady's button goes through them: Max follows High, and
## One Euro (a different kind of smoothing) stays last. The numbers are the
## saved ones, which is why Max, the newest, is 4.
const POINTER_STEADY_ORDER: Array[int] = [0, 1, 2, 4, 3]
const POINTER_STEADY_MAX := 4
## Max: for hands that can't keep still (2026-11-16: a much
## heavier level than High). The
## pointer closes this share of the gap to where the hand points every
## STEADY_MAX_SECONDS, whatever the display rate: a 2.5-a-second bounce comes
## through at under a fifth of its size (High at 90 Hz: about half), and the
## pointer trails a deliberate move by about a third of a second. First
## figures, to be tuned by feel.
const STEADY_MAX_SECONDS := 0.35
const STEADY_MAX_DEAD_ZONE := 0.005
# Touch-controller double-click gesture. Standard leaves host-side recognition
# untouched; Chord maps a near-simultaneous trigger+grip press to two left
# clicks. Hand tracking always retains its normal pinch-twice behaviour.
var double_click_mode_labels: Array = ["Click Twice", "Trigger + Grip"]
var _steady_hit: Vector3 = Vector3.ZERO
var _steady_active: bool = false
var _steady_factor: float = 0.3
var _steady_dead_zone: float = 0.002
var _steady_velocity: Vector3 = Vector3.ZERO
var _steady_raw_hit: Vector3 = Vector3.ZERO
var _steady_last_usec: int = 0
var _steady_last_frame: int = -1
var codec_labels: Array = ["H.264", "HEVC", "AV1", "Raw", "PyroWave"]
var _client_codec_support: Dictionary = {}
var _server_codec_support: Dictionary = {}
var corner_handles: Array:
	get: return primary_screen.corner_handles if primary_screen else []
	set(v):
		if primary_screen: primary_screen.corner_handles = v
var grabbed_corner_idx: int = -1
var grabbed_corner_screen: VRScreen = null
var corner_anchor_world: Vector3 = Vector3.ZERO
var screen_registry: ScreenRegistry = ScreenRegistry.new()
var screens: Array[VRScreen]:
	get: return screen_registry.screens
var primary_screen: VRScreen:
	get: return screen_registry.primary
var layout: ScreenLayout = null

# Staging state for the Monitors tab's Row1 (counts) + Row2 (preset) - Apply
# commits these together via SettingsController.apply_staged_monitor_config();
# nothing here touches the live layout/stream on its own.
var _staged_physical_count: int = 1
var _staged_virtual_count: int = 0
var _staged_preset_id: StringName = &""
# Set by apply_staged_monitor_config() when it restarted the stream to pick up
# a real monitor-selection change; cleared once stream_manager.gd's launch
# response finishes applying the fresh manifest that follows (see
# SettingsController.finish_pending_monitor_apply()).
var _pending_monitor_apply: bool = false

var stream_manager: StreamManager
var xr_interaction: XRInteraction
var input_handler: InputHandler
var ui_controller: UIController
var auto_detect: AutoDetect
var depth_estimator: DepthEstimatorModule
var meteor_microphone: MeteorMicrophone
var native_xr_renderer: NativeXrRendererManager
var video_presentation: VideoPresentation
var virtual_keyboard: VirtualKeyboard
var welcome_screen: WelcomeScreen
var browser_prototype: RefCounted
var screen_sources: ScreenSources
var screen_manager: ScreenManager
var settings_controller: SettingsController
var state_manager: StateManager
var controller_mapper: ControllerMapper
var button_bindings: ButtonBindings
var screen_shortcuts: ScreenShortcutBar
var screen_tab_strip: ScreenTabStrip
var comp: CompositionLayerManager
var bg_manager: BackgroundManager
var composition_panels: CompositionPanelLayers = CompositionPanelLayers.new()
var composition_environment: CompositionEnvironmentLayer = CompositionEnvironmentLayer.new()
var composition_pointers: CompositionPointerLayers = CompositionPointerLayers.new()
var composition_controller_rays: CompositionControllerRays = CompositionControllerRays.new()
var composition_controller_markers: CompositionControllerMarkers = CompositionControllerMarkers.new()
var composition_hand_indicators: CompositionHandIndicators = CompositionHandIndicators.new()
var composition_screen_controls: CompositionScreenControls = CompositionScreenControls.new()
var _xr_resume_refresh_attempts := 0
var _xr_resume_refresh_wait_frames := 0

# Temporary on-device A/B flags (2026-08-24) to isolate which of today's new
# composition-space additions (laser/grab-bar/corners/background-equirect,
# all added this session) is contending with the GLES GPU TFLite delegate
# for depth inference - MiDaS-256-GPU measured ~13-15Hz today vs. an
# earlier-session ~20Hz. Each gates both its composition layer's visibility
# AND its backing SubViewport's render_target_update_mode (UPDATE_ALWAYS
# viewports render every frame regardless of the layer's own visibility, so
# hiding alone doesn't stop the GPU cost) - see
# _update_laser_layers()/_update_grab_bar_layers()/_sync_comp_background().
# Toggle one at a time and rebuild; remove once the
# regression is isolated (see the diagnosis plan). Confirmed 2026-08-24 the
# regression was a debug-build-vs-release-build artifact, not caused by any
# of these - release build hits ~19.5-20.2Hz with all four enabled. Kept
# around (all true) in case it's needed again rather than deleting outright.
const DEBUG_COMP_BG_EQUIRECT := true
const DEBUG_COMP_LASER := true
const DEBUG_COMP_GRAB_BAR := true
const DEBUG_COMP_CORNERS := true
const DEBUG_COMP_MARKER := true
const DEBUG_COMP_HANDS := true

# Composition-space environment-background replacement (2026-08-24,
# GLES projectionless polish) - the ambient particle backgrounds
# (Ash/Snow/Data, background_manager.gd) are real GPUParticles3D
# in the normal 3D scene, invisible under projectionless mode like
# everything else plain-3D. Unlike the cursor/laser/grab-bar/corners (flat
# 2D UI content on a quad), this needs an actual 3D scene capture -
# comp_bg_capture_viewport (disable_3d=false, a real mini 3D scene, not
# just a Control tree) holding a wide-FOV camera and a standalone duplicate
# of whichever background is active (background_manager.create_capture_
# instance()), fed into comp_bg_equirect (OpenXRCompositionLayerEquirect,
# a real 360-capable OpenXR layer type - confirmed natively supported by
# WiVRn on this device). A single perspective camera can't capture a true
# full sphere without heavy edge distortion, so this deliberately covers a
# wide-but-partial angular range (BG_CAPTURE_FOV_DEG) rather than claiming
# full 360 coverage - turning far enough away may show black instead of
# the effect, unlike the original always-surrounding particle system.
var comp_bg_equirect: Node3D:
	get: return composition_environment.layer
var comp_bg_capture_viewport: SubViewport:
	get: return composition_environment.capture_viewport
var comp_bg_capture_camera: Camera3D:
	get: return composition_environment.capture_camera
var comp_bg_capture_instance: GPUParticles3D = null
var comp_bg_capture_index: int = -1
const BG_CAPTURE_FOV_DEG := 160.0
const BG_EQUIRECT_ANGLE_DEG := 150.0

var comp_cylinder: Node3D:
	get: return primary_screen.comp_cylinder if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_cylinder = v
var _comp_cyl_center: Vector3:
	get: return primary_screen._comp_cyl_center if primary_screen else Vector3.ZERO
	set(v):
		if primary_screen: primary_screen._comp_cyl_center = v
var _comp_cyl_radius: float:
	get: return primary_screen._comp_cyl_radius if primary_screen else 0.0
	set(v):
		if primary_screen: primary_screen._comp_cyl_radius = v
var _comp_cyl_central_angle: float:
	get: return primary_screen._comp_cyl_central_angle if primary_screen else 0.0
	set(v):
		if primary_screen: primary_screen._comp_cyl_central_angle = v
var comp_layer: Node3D:
	get: return primary_screen.comp_layer if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_layer = v
var comp_viewport: SubViewport:
	get: return primary_screen.comp_viewport if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_viewport = v
var comp_yuv_rect: ColorRect:
	get: return primary_screen.comp_yuv_rect if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_yuv_rect = v
var comp_bezel_rect: ColorRect:
	get: return primary_screen.comp_bezel_rect if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_bezel_rect = v
var comp_shader_mat: ShaderMaterial:
	get: return primary_screen.comp_shader_mat if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_shader_mat = v
var comp_cylinder_left: Node3D:
	get: return primary_screen.comp_cylinder_left if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_cylinder_left = v
var comp_cylinder_right: Node3D:
	get: return primary_screen.comp_cylinder_right if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_cylinder_right = v
var comp_viewport_left: SubViewport:
	get: return primary_screen.comp_viewport_left if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_viewport_left = v
var comp_viewport_right: SubViewport:
	get: return primary_screen.comp_viewport_right if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_viewport_right = v
var comp_yuv_rect_left: ColorRect:
	get: return primary_screen.comp_yuv_rect_left if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_yuv_rect_left = v
var comp_yuv_rect_right: ColorRect:
	get: return primary_screen.comp_yuv_rect_right if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_yuv_rect_right = v
var comp_bezel_rect_left: ColorRect:
	get: return primary_screen.comp_bezel_rect_left if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_bezel_rect_left = v
var comp_bezel_rect_right: ColorRect:
	get: return primary_screen.comp_bezel_rect_right if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_bezel_rect_right = v
var comp_shader_mat_left: ShaderMaterial:
	get: return primary_screen.comp_shader_mat_left if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_shader_mat_left = v
var comp_shader_mat_right: ShaderMaterial:
	get: return primary_screen.comp_shader_mat_right if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_shader_mat_right = v
var comp_stream_cursor: TextureRect:
	get: return primary_screen.comp_stream_cursor if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_stream_cursor = v
var comp_stream_cursor_circle: ColorRect:
	get: return primary_screen.comp_stream_cursor_circle if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_stream_cursor_circle = v
var comp_stream_cursor_left: TextureRect:
	get: return primary_screen.comp_stream_cursor_left if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_stream_cursor_left = v
var comp_stream_cursor_circle_left: ColorRect:
	get: return primary_screen.comp_stream_cursor_circle_left if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_stream_cursor_circle_left = v
var comp_stream_cursor_right: TextureRect:
	get: return primary_screen.comp_stream_cursor_right if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_stream_cursor_right = v
var comp_stream_cursor_circle_right: ColorRect:
	get: return primary_screen.comp_stream_cursor_circle_right if primary_screen else null
	set(v):
		if primary_screen: primary_screen.comp_stream_cursor_circle_right = v
var _screen_mesh_original_mat: Material:
	get: return primary_screen._original_mat if primary_screen else null
	set(v):
		if primary_screen: primary_screen._original_mat = v

const LOG_CURRENT_PATH := "user://nightfall-current.log"
const LOG_PREVIOUS_PATH := "user://nightfall-previous.log"
const LEGACY_LOG_PATH := "user://debug.log"
var _log_lines: PackedStringArray = []
var _log_file_initialized: bool = false
## Steam Frame: the launcher says whether this run is logged (Advanced
## Settings > Logging, as saved when Nightfall started). Run any other way,
## Nightfall logs.
var _logging := OS.get_environment("NIGHTFALL_LOGGING") != "0"
var _log_session_rotated: bool = false
var _log_flush_timer: float = 0.0
# Steam Frame: a wider menu, so rows of five options fit.
var _ui_viewport_size := Vector2i(1400, 580) if MenuSchema._IS_FRAME else Vector2i(1200, 580)
var _ui_mesh_size := Vector2(1.40, 0.58) if MenuSchema._IS_FRAME else Vector2(1.20, 0.58)
const UI_TOOLTIP_STRIP_PX := 102
const UI_TOOLTIP_STRIP_METERS := 0.102
var _ui_status_label: Label
var _ui_pt_btn: Button
var _ui_bg_btn: Button
var _ui_curve_btn: Button
var _ui_bezel_btn: Button
var _ui_monitors_btn: Button
var _ui_virtual_monitors_btn: Button
var _ui_apply_preset_btn: Button
var _ui_save_preset_btn: Button
var _ui_remove_preset_btn: Button
var _ui_grid_mode_btn: Button
var _ui_hand_tracking_btn: Button
var _ui_sbs_btn: Button
var _ui_3d_speed_btn: Button
var _ui_3d_enable_btn: Button
var _ui_3d_btn: Button
var _ui_3d_gpu_api_btn: Button
var _ui_3d_depth_view_btn: Button
var _ui_3d_debug_btn: Button
var _ui_3d_process_debug_btn: Button
var _ui_3d_priority_btn: Button
# AI 3D tab (2026-08-28) - see ui_controller.gd's build_ui() for layout.
var _ui_3d_mode_btn: Button
var _ui_3d_type_btn: Button
var _ui_3d_hz_cap_btn: Button
var _ui_3d_separation_btn: Button
var _ui_3d_convergence_btn: Button
var _ui_3d_cursor_position_btn: Button
var _ui_3d_depth_sync_btn: Button
var _ui_3d_edge_alignment_btn: Button
var _ui_3d_contour_cleanup_btn: Button
var _ui_3d_reset_btn: Button
var _ui_res_btn: Button
var _ui_fps_btn: Button
var _ui_bitrate_btn: Button
var _ui_ctrl_type_btn: Button
var _ui_face_swap_btn: Button
var _ui_cursor_follow_btn: Button
var _ui_pointer_ray_btn: Button
var _ui_flat_mode_btn: Button
var _ui_curved_filter_btn: Button
var _ui_foveation_btn: Button
var _ui_flat_detail_btn: Button
var _ui_glow_strength_btn: Button
var _ui_glow_size_btn: Button
var _ui_save_spots_btn: Button
var _ui_recenter_btn: Button
var _ui_keep_room_btn: Button
var _ui_start_distance_btn: Button
var _ui_screen_size_btn: Button
var _ui_voice_list_btn: Button
var _ui_voice_prefix_btn: Button
var _ui_voice_commands_btn: Button
var _ui_voice_confirm_btn: Button
var _ui_voice_model_btn: Button
var _ui_voice_ease_btn: Button
var _ui_second_link_btn: Button
var _ui_kb_follow_btn: Button
var eye_gaze: EyeGaze = null
var _ui_head_lock_btn: Button
var _ui_haptics_btn: Button
var _ui_mic_key_btn: Button
var _ui_reset_spots_btn: Button
var _ui_hide_cursor_btn: Button
var _ui_btn_toggle_btn: Button
var _ui_primary_btn: Button
var _ui_ctrl_models_btn: Button
var frame_controller_models: Node3D = null
var _ui_quick_start_btn: Button
var _ui_audio_boost_btn: Button
var _ui_icon_backdrop_btn: Button
var _ui_audio_output_btn: Button
var _ui_usb_link_btn: Button
var _ui_hdr_btn: Button
var _ui_audio_on_pc_btn: Button
var _ui_host_cursor_btn: Button
var _ui_sharpen_btn: Button
# Picture tab (2026-08-31) - see ui_controller.gd's build_ui() for layout.
var _ui_brightness_btn: Button
var _ui_contrast_btn: Button
var _ui_gamma_btn: Button
var _ui_ambient_btn: Button
var _ui_ambient_color_btn: Button
var _ui_ctrl_mode_btn: Button
var _ui_cursor_btn: Button
var _ui_steady_btn: Button
var _ui_double_click_btn: Button
var _ui_codec_btn: Button
var _last_activity_time: float = 0.0
var _ui_idle_btn: Button
var _ui_reconnect_btn: Button
var _ui_mouse_follows_btn: Button
var _ui_high_refresh_btn: Button
var _ui_camera_limit_btn: Button
var _ui_reset_settings_btn: Button
var _ui_pt_fade_btn: Button
var passthrough_fade := PassthroughFade.new()
var _ui_exit_btn: Button
var _ui_disconnect_btn: Button
var _ui_close_btn: Button
var _ui_center_btn: Button
var _ui_log_btn: Button
var _ui_stats_btn: Button
var _ui_language_btn: Button
var _ui_licences_btn: Button
var _ui_logging_btn: Button
var _ui_microphone_btn: Button
var _ui_forget_meteor_btn: Button

var _btn_style: StyleBoxFlat
var _btn_hover: StyleBoxFlat


# 2026-08-07: settled at 4032, this time with real evidence it's a genuine
# hardware/driver width ceiling, not a software bug we can fix. Two real,
# separate software bugs WERE found and fixed along the way (both worth
# keeping): (1) AndroidMediaCodec's input buffer was sized at width*height,
# too tight for a real H264 keyframe - widened to width*height*3
# (mediacodec_native.cpp); (2) that fix itself overshot a ~16MiB Android
# graphics-buffer-allocation ceiling at wide resolutions, so it's now clamped
# to 12MiB. But testing at 6912x1944 with both fixes in place still failed
# completely (zero frames ever decoded), and critically: CCodec's own log
# showed it silently overrode our 12MiB request UP to 13.27MB (its own
# platform-computed minimum for that resolution) and decode still never
# produced a single frame - proving buffer size was never the bottleneck at
# this width. That points to a real hardware/HAL line-buffer width limit
# around 4032px on this SoC's H264 decoder, independent of buffer sizing or
# total pixel count - the MediaCodec capability query's claimed 8192px
# support just doesn't hold up in practice (a known class of gap on
# Qualcomm HALs). HEVC has no equivalent cap; prefer it for wide layouts.
const H264_MAX_DIMENSION = 4032
# Confirmed via on-device MediaCodec capability query (getSupportedWidths/
# getSupportedHeights against real candidate resolutions - see
# docs/architecture/multi-monitor-encode-budget-and-layout.md): HEVC on this hardware is
# dual-limited, not just axis-limited - each dimension independently caps at
# 8192px, AND the total canvas is separately capped at ~138,240 macroblocks
# (16x16 each) regardless of aspect. A 4-monitor row can hit the axis cap
# (e.g. 8320px wide) while sitting nowhere near the total-pixel cap, so both
# constraints have to be checked - clamping only the axis would silently
# allow a request that's still invalid for the other reason, and vice versa.
const HEVC_MAX_DIMENSION = 8192
const HEVC_MAX_TOTAL_PIXELS = 35389440
# A SEPARATE, lower ceiling from the two above - those reflect what the decoder
# can technically decode at all; this reflects what the headset can actually
# sustain in real time while also running its own tracking/compositor/etc.
# Confirmed live testing 4x4K HEVC (2x2 grid, 7680x4320 base): 80% scale
# (21,233,664 total pixels) ran smoothly; 90% (26,873,856 pixels - still well
# under HEVC_MAX_TOTAL_PIXELS, so the decode-capability cap never caught it)
# caused the headset's own tracking-camera watchdog to report multi-second
# frame delays and visible corruption/freezing - a real-time throughput
# problem, not a decode failure. Set at exactly the confirmed-good boundary
# (80% of that specific 4-monitor test), not a round-number guess.
const HEVC_MAX_SUSTAINED_PIXELS = 21233664

# Extra resolution ceiling applied whenever MiDaS-Fast is the active stereo
# mode (2026-08-18, redesigned 2026-08-25) - unlike every knob AI-3D's own
# pipeline exposes (pre-pass resolution/throttle, Newton-refinement cadence,
# depth-capture throttle), none of which moved FPS at 4K when tested,
# capping the actual decoded/composited stream size directly attacks the
# real cost: general per-pixel video decode + compositing work, which
# scales with resolution regardless of AI-3D. MiDaS-Std is intentionally
# NOT capped here - it stays the uncapped/known-good reference. See
# compute_requested_resolution().
#
# 2026-08-25: replaced the old flat MIDAS_FAST_MAX_PIXELS/
# MIDAS_FASTEST_MAX_PIXELS constants (one budget per tier, applied
# regardless of resolution/passthrough) with settings_controller.gd's
# AUTO_TABLE, whose cap_px varies per (resolution-class, passthrough) combo
# from an on-device GPU-inference benchmark matrix - e.g. Fast is uncapped
# at HD-passthrough-on but capped to 2K's pixel budget at 4K-passthrough-on.
# Applies to MANUAL Fast selection too, not just Auto - see
# compute_requested_resolution()'s cap block below.
#
# History: capped both tiers, then MiDaS-Fast/-Fastest's 3D quality looked
# visibly worse than MiDaS-Std. [DEPTH]-tagged logging in depth_estimator.gd
# ruled out the depth pipeline itself (capture/submission/polling equally
# healthy across all tiers) and the bitrate cliff bug (fixed separately,
# stream_manager.gd's _auto_bitrate() now scales from the UNCAPPED
# resolution). Root cause found 2026-08-18: these caps were width/height
# pairs, aspect-scaled with min(target_w/w, target_h/h) - on a WIDE source
# (the native size here can be a 2.96:1 multi-monitor composite, not 16:9),
# the width dimension binds first, so "cap to 2560x1440" actually produced
# 2560x864 (2.21M px) instead of the 3.69M px the "1440p" label implied -
# confirmed directly: manually selecting 1440p and letting Fastest's cap
# reduce down to "1440p" were NOT delivering the same pixel count at all,
# despite looking like they should be equal. Fixed by capping to a total
# PIXEL BUDGET via sqrt(target_px/actual_px) instead of a width/height pair
# - same approach this file already uses for HEVC_MAX_TOTAL_PIXELS just
# below, which doesn't have this problem because it already works in pixels.
const MIDAS_RES_CAP_ENABLED := true

# The highest resolution scale that keeps compute_requested_resolution()'s
# result under every constraint that applies to the given codec at the
# current native size, i.e. the point past which compute_requested_resolution()
# would otherwise silently downscale further than the requested percentage
# implied. Used to build the UI's resolution option list (compute_resolution_options())
# so a user can never select a percentage compute_requested_resolution() would
# have quietly overridden anyway.
func compute_max_resolution_pct(codec: int) -> int:
	if settings.host.native_resolution.x <= 0 or settings.host.native_resolution.y <= 0:
		return 100
	var nw = float(settings.host.native_resolution.x)
	var nh = float(settings.host.native_resolution.y)
	var max_pct = 100.0
	if codec == 0:
		max_pct = minf(max_pct, 100.0 * H264_MAX_DIMENSION / maxf(nw, nh))
	elif codec == 1:
		max_pct = minf(max_pct, 100.0 * HEVC_MAX_DIMENSION / maxf(nw, nh))
		max_pct = minf(max_pct, 100.0 * sqrt(HEVC_MAX_TOTAL_PIXELS / (nw * nh)))
		max_pct = minf(max_pct, 100.0 * sqrt(HEVC_MAX_SUSTAINED_PIXELS / (nw * nh)))
	return clampi(int(floor(max_pct)), 10, 100)

# The dynamic option list for the resolution cycle button: RESOLUTION_PRESETS
# below the current max get kept as-is; the max itself always occupies the top
# slot (labeled "MAX" by the UI, not a number) instead of whatever presets
# would otherwise have sat above an unreachable ceiling - so there's never an
# option in the list that silently does something other than what its label says.
func compute_resolution_options() -> Array:
	var max_pct = compute_max_resolution_pct(settings.codec_preference)
	var opts: Array = [max_pct]
	for p in RESOLUTION_PRESETS:
		if p < max_pct:
			opts.append(p)
	return opts

func compute_requested_resolution(apply_midas_cap: bool = true) -> Vector2i:
	var w: int
	var h: int
	if settings.host.is_polaris_host:
		w = int(settings.host.native_resolution.x * settings.host.resolution_scale_pct / 100.0)
		h = int(settings.host.native_resolution.y * settings.host.resolution_scale_pct / 100.0)
	else:
		var res: Vector2i = resolutions[settings.host.resolution_idx]
		w = res.x
		h = res.y
	# H.264 hardware decoders on this class of mobile SoC commonly cap out at 4096px
	# per dimension (HEVC decoders on the same hardware typically go up to 8192) -
	# requesting wider/taller than that doesn't error, it just silently never produces
	# a decoded frame. Confirmed live: at 100% (4480x1440) H.264 decode stalls
	# completely right after connecting; at 90% (4032x1296, under the limit) it works
	# fine. Scale both dimensions down together to preserve aspect ratio rather than
	# only clamping the offending one, which would mismatch the server's capture
	# aspect and trigger its own letterbox/pillarbox scaling instead.
	if settings.codec_preference == 0 and (w > H264_MAX_DIMENSION or h > H264_MAX_DIMENSION):
		var scale = minf(float(H264_MAX_DIMENSION) / w, float(H264_MAX_DIMENSION) / h)
		w = int(w * scale)
		h = int(h * scale)
	elif settings.codec_preference == 1:
		var scale = 1.0
		if w > HEVC_MAX_DIMENSION or h > HEVC_MAX_DIMENSION:
			scale = minf(scale, minf(float(HEVC_MAX_DIMENSION) / w, float(HEVC_MAX_DIMENSION) / h))
		if w * h > HEVC_MAX_TOTAL_PIXELS:
			scale = minf(scale, sqrt(float(HEVC_MAX_TOTAL_PIXELS) / float(w * h)))
		if w * h > HEVC_MAX_SUSTAINED_PIXELS:
			scale = minf(scale, sqrt(float(HEVC_MAX_SUSTAINED_PIXELS) / float(w * h)))
		if scale < 1.0:
			w = int(w * scale)
			h = int(h * scale)
	# Quest 2 hard resolution ceiling (2026-08-27, see device_is_quest2's own
	# comment) - unconditional (not gated on apply_midas_cap, unlike the
	# AI-3D cap_px block below) since this reflects real hardware/display
	# limits, not an AI-3D-specific tradeoff: Quest 2's own per-eye panel
	# resolution is already below Quest 3's, so there's no benefit
	# requesting more than this regardless of AI-3D state. Applied BEFORE
	# the AI-3D cap block, so get_auto_selection()'s own classification
	# (which reads this same function with apply_midas_cap=false) always
	# sees the already-1080p-capped value too.
	if device_is_quest2 and w * h > QUEST2_MAX_RESOLUTION.x * QUEST2_MAX_RESOLUTION.y:
		var quest2_scale = sqrt(float(QUEST2_MAX_RESOLUTION.x * QUEST2_MAX_RESOLUTION.y) / float(w * h))
		w = int(w * quest2_scale)
		h = int(h * quest2_scale)
	# MiDaS-Fast only - see MIDAS_RES_CAP_ENABLED's comment above. Keyed off
	# the actually-active stereo mode (accounts for settings.host.sbs_mode overriding
	# settings.host.ai_3d_speed/model/debug, same as settings_controller.get_stereo_mode()
	# itself), not those raw fields directly. Caps by total pixel budget
	# (like HEVC_MAX_TOTAL_PIXELS above), NOT a width/height pair scaled by
	# min(target_w/w, target_h/h) - that approach silently delivered far
	# fewer pixels than intended on a non-16:9 source (see history above).
	# apply_midas_cap=false lets a caller ask "what would this resolution be
	# WITHOUT the AI-3D cap" - see stream_manager.gd's start_stream(), which
	# uses that to pick Auto bitrate from the uncapped resolution instead of
	# the capped encode resolution (same bitrate, fewer pixels should mean
	# MORE bits per pixel, not fewer). get_auto_selection() always reads the
	# UNCAPPED resolution internally (apply_midas_cap=false), so this can't
	# recurse into itself.
	#
	# cap_px comes from settings_controller.gd's AUTO_TABLE UNCONDITIONALLY
	# whenever the resulting tier is Fast (stereo_mode 10) - not gated on
	# settings.host.ai_3d_speed==1 - so a MANUAL Fast selection gets the same per-combo cap
	# Auto's own Fast pick would use at that resolution/passthrough combo,
	# matching this cap's pre-2026-08-25 behavior of applying to manual Fast
	# too (it just used one flat constant then instead of a per-combo table).
	if apply_midas_cap and MIDAS_RES_CAP_ENABLED and settings_controller:
		var stereo_mode = settings_controller.get_stereo_mode()
		var max_pixels := 0
		if stereo_mode == 10:
			max_pixels = settings_controller.get_auto_selection().cap_px
		if max_pixels > 0 and w * h > max_pixels:
			var cap_scale = sqrt(float(max_pixels) / float(w * h))
			w = int(w * cap_scale)
			h = int(h * cap_scale)
	w = maxi(w - (w % 2), 320)
	h = maxi(h - (h % 2), 180)
	return Vector2i(w, h)

# %IPInput accepts an optional ":port" suffix now (2026-08-26, GitHub-reported
# need for a custom Apollo/Sunshine HTTP port) - splits on the LAST ":" so a
# bare IP with no port still works unchanged. Returns [ip: String, port: int],
# defaulting to DEFAULT_PAIR_PORT when no ":" is present or the suffix isn't a
# valid number. Callers that just DISPLAY the field text or use it as a
# per-host settings-persistence key (state_manager.gd's save_host_state())
# should keep using the raw text as-is - only callers that actually connect
# somewhere (pairing, host-record matching, Wake-on-LAN's host lookup) need
# the parsed ip/port.
const DEFAULT_PAIR_PORT := 47989

# Host records saved before USB Link addresses carried a "%<iface>" zone hold
# the bare link-local address; the zone never distinguishes two machines.
func same_host_address(a: String, b: String) -> bool:
	return SavedHosts.same_address(a, b)

# A saved host is reachable at its network address and, once seen over USB
# Link, its usb_address too - either identifies the same machine.
func host_matches_address(h: Dictionary, addr: String) -> bool:
	return SavedHosts.reached_at(h, addr)

func parse_ip_port(text: String) -> Array:
	# "[v6addr]:port", or a bare IPv6 address (2+ colons) with no port at all -
	# its last group can be all digits, so it must never be split on ":".
	if text.begins_with("["):
		var close = text.find("]")
		if close != -1:
			var inner = text.substr(1, close - 1)
			var rest = text.substr(close + 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				var p = rest.substr(1).to_int()
				if p > 0 and p <= 65535:
					return [inner, p]
			return [inner, DEFAULT_PAIR_PORT]
	if text.count(":") > 1:
		return [text, DEFAULT_PAIR_PORT]
	var colon = text.rfind(":")
	if colon == -1:
		return [text, DEFAULT_PAIR_PORT]
	var ip_part = text.substr(0, colon)
	var port_part = text.substr(colon + 1)
	if not port_part.is_valid_int():
		return [text, DEFAULT_PAIR_PORT]
	var port = port_part.to_int()
	if port <= 0 or port > 65535:
		return [text, DEFAULT_PAIR_PORT]
	return [ip_part, port]

# Steam Frame: what happens while SteamVR isn't showing Nightfall (the headset
# off, or another app in front): see FrameSessionWatch.
var _session_watch: FrameSessionWatch

func _log(msg: String):
	if not _logging:
		return
	if _session_watch != null and _session_watch.holds_back(msg):
		return
	_log_lines.append("[%s] %s" % [Time.get_datetime_string_from_system(false, true), msg])
	push_warning("NF: %s" % msg)

func _rotate_session_log():
	if _log_session_rotated:
		return
	_log_session_rotated = true
	var current_path = ProjectSettings.globalize_path(LOG_CURRENT_PATH)
	var previous_path = ProjectSettings.globalize_path(LOG_PREVIOUS_PATH)
	if FileAccess.file_exists(previous_path):
		DirAccess.remove_absolute(previous_path)
	if FileAccess.file_exists(current_path):
		DirAccess.rename_absolute(current_path, previous_path)
	elif FileAccess.file_exists(LEGACY_LOG_PATH):
		# Preserve the final pre-rotation session once when upgrading.
		DirAccess.rename_absolute(ProjectSettings.globalize_path(LEGACY_LOG_PATH), previous_path)

func _flush_log():
	if _log_lines.is_empty():
		return
	_rotate_session_log()
	var mode = FileAccess.READ_WRITE if _log_file_initialized else FileAccess.WRITE
	var f = FileAccess.open(LOG_CURRENT_PATH, mode)
	if f:
		if _log_file_initialized:
			f.seek_end()
		for line in _log_lines:
			f.store_line(line)
		f.close()
		_log_lines.clear()
		_log_file_initialized = true

func export_diagnostics():
	var device_codename = stream_backend.get_device_model() if stream_backend else "unknown"
	_log("[DIAGNOSTICS] Export requested: phase=%s streaming=%s device=%s requested_resolution=%s fps=%d codec=%d ai3d_mode=%d model=%d backend=%d priority=%d hz_cap=%d" % [
		session_lifecycle.phase_name() if session_lifecycle else "unknown",
		str(is_streaming), device_codename, str(compute_requested_resolution(false)),
		settings.host.stream_fps, settings.codec_preference, settings.host.ai_3d_speed,
		settings.host.ai_3d_model, settings.host.ai_3d_backend_pref,
		settings.ai_3d_gpu_priority, settings.host.ai_3d_hz_cap])
	_flush_log()
	var result = stream_backend.export_diagnostics() if stream_backend else "ERROR: Streaming backend unavailable"
	if result.begins_with("ERROR:"):
		ui_controller.show_temporary_status("Log export failed", 1.0)
		_log("[DIAGNOSTICS] %s" % result)
	else:
		ui_controller.show_temporary_status("Log downloaded to %s" % result, 1.0)
		_log("[DIAGNOSTICS] Saved to %s" % result)

func _setup_comp_layer():
	comp = CompositionLayerManager.new(self)
	video_presentation.set_legacy_renderer(comp)
	comp.setup()

func _update_comp_bezel():
	comp.update_bezel()

func _update_cylinder_params():
	comp.update_cylinder_params()

func _make_screen_transparent():
	comp.make_screen_transparent()

func _make_ui_transparent():
	comp.make_ui_transparent()

func _make_kb_transparent():
	comp.make_kb_transparent()

func _restore_screen_material():
	comp.restore_screen_material()

func _restore_ui_material():
	comp.restore_ui_material()

func _restore_kb_material():
	comp.restore_kb_material()

var _comp_base_size: Vector2i:
	get: return primary_screen.comp_base_size if primary_screen else Vector2i(1920, 1080)
	set(v):
		if primary_screen: primary_screen.comp_base_size = v

func get_blur_scale(s: VRScreen) -> float:
	if _xr_render_width <= 0:
		return 1.0
	var source_size: Vector2i = stream_manager.get_current_stream_size() if stream_manager else stream_viewport.size
	return (s.uv_region.z * float(source_size.x)) / float(_xr_render_width)

func _reset_steady_filter():
	_steady_active = false
	_steady_velocity = Vector3.ZERO
	_steady_raw_hit = Vector3.ZERO
	_steady_last_usec = 0
	_steady_last_frame = -1

## How much of the gap Max closes in `seconds` (0 to 1).
static func steady_max_share(seconds: float) -> float:
	return 1.0 - exp(-maxf(seconds, 0.0) / STEADY_MAX_SECONDS)

func _one_euro_alpha(cutoff_hz: float, delta: float) -> float:
	var tau := 1.0 / (TAU * maxf(cutoff_hz, 0.001))
	return 1.0 / (1.0 + tau / maxf(delta, 0.000001))

func _get_steady_hit(raw: Vector3) -> Vector3:
	if settings.pointer_steady == 0 or not is_xr_active:
		_reset_steady_filter()
		return raw
	var frame := Engine.get_process_frames()
	# Several interaction paths ask for the same ray hit in one frame. Advancing
	# a time-based filter for every caller would make its response depend on UI
	# state rather than elapsed time.
	if _steady_active and frame == _steady_last_frame:
		return _steady_hit
	var now_usec := Time.get_ticks_usec()
	if not _steady_active:
		_steady_hit = raw
		_steady_active = true
		_steady_velocity = Vector3.ZERO
		_steady_raw_hit = raw
		_steady_last_usec = now_usec
		_steady_last_frame = frame
		return raw
	if settings.pointer_steady == 3:
		var delta := float(now_usec - _steady_last_usec) / 1000000.0
		# A long gap means the ray left the screen or tracking was interrupted.
		# Reset rather than letting the old point pull the cursor back onscreen.
		if delta <= 0.0 or delta > 0.25:
			_steady_hit = raw
			_steady_velocity = Vector3.ZERO
			_steady_raw_hit = raw
		else:
			# The derivative must be measured between consecutive raw samples.
			# Measuring it against the filtered position makes accumulated filter
			# lag look like movement and defeats One Euro's stationary cutoff.
			var raw_velocity := (raw - _steady_raw_hit) / delta
			var derivative_alpha := _one_euro_alpha(1.0, delta)
			_steady_velocity = _steady_velocity.lerp(raw_velocity, derivative_alpha)
			# Low cutoff while stationary removes controller tremor; movement raises
			# it immediately so deliberate aiming does not inherit High's lag.
			var cutoff := 1.2 + 8.0 * _steady_velocity.length()
			_steady_hit = _steady_hit.lerp(raw, _one_euro_alpha(cutoff, delta))
			_steady_raw_hit = raw
		_steady_last_usec = now_usec
		_steady_last_frame = frame
		return _steady_hit
	if settings.pointer_steady == POINTER_STEADY_MAX:
		var seconds := float(now_usec - _steady_last_usec) / 1000000.0
		_steady_last_usec = now_usec
		_steady_last_frame = frame
		# A long gap: the ray left the screen. Start again where it is now.
		if seconds <= 0.0 or seconds > 0.25:
			_steady_hit = raw
		elif (raw - _steady_hit).length() >= STEADY_MAX_DEAD_ZONE:
			_steady_hit = _steady_hit.lerp(raw, steady_max_share(seconds))
		return _steady_hit
	var factor := 0.3 if settings.pointer_steady == 1 else 0.1
	var dead_zone := 0.002 if settings.pointer_steady == 1 else 0.005
	var delta = raw - _steady_hit
	if delta.length() < dead_zone:
		_steady_last_usec = now_usec
		_steady_last_frame = frame
		return _steady_hit
	_steady_hit = _steady_hit.lerp(raw, factor)
	_steady_last_usec = now_usec
	_steady_last_frame = frame
	return _steady_hit

func _get_cylinder_normal_at(hit_point: Vector3) -> Vector3:
	return primary_screen.get_cylinder_normal_at(hit_point)

func _hit_point_to_uv(hit_point: Vector3) -> Vector2:
	return primary_screen.hit_point_to_uv(hit_point)

## Cursor Type Hidden: no VR pointer over a stream screen. Browser screens
## have no PC cursor to point with, so they keep theirs.
func hides_screen_cursor(screen: VRScreen) -> bool:
	return settings.cursor_mode == AppSettings.CURSOR_MODE_HIDDEN and screen != null \
		and is_streaming and not screen_sources.is_browser_screen(screen)

func screen_cursor_mode(screen: VRScreen) -> int:
	if settings.cursor_mode == AppSettings.CURSOR_MODE_HIDDEN and not hides_screen_cursor(screen):
		return 0 # Welcome, browsers and menus always retain a circle pointer.
	return settings.cursor_mode

func _update_cursor_layer():
	if comp == null:
		return # comp is created after the first frames (native Steam Frame startup)
	if not comp.in_use and not pcvr_handover.menu_only:
		composition_pointers.hide_primary()
		composition_pointers.hide_all_embedded(screens)
		return
	var active_raycast = xr_interaction.get_active_raycast() if xr_interaction else (hand_raycast if is_xr_active else mouse_raycast)
	var on_screen = false
	var pad_on_screen = controller_mapper and controller_mapper.is_active() and controller_mapper.is_gamepad_mode()
	var tp_capturing = virtual_keyboard and virtual_keyboard.visible and virtual_keyboard.trackpad_active
	var stereo = settings_controller.get_stereo_mode() if settings_controller else 0
	var use_embedded_cursor = on_screen and not pad_on_screen and not tp_capturing
	var hovered_screen: VRScreen = null
	if active_raycast.is_colliding():
		var hit_point = active_raycast.get_collision_point()
		var col = active_raycast.get_collider()
		var t = PointerTarget.resolve(col) if col else {"role": &""}
		# Tabs use raw hits for input; smoothing their cursor makes it trail
		# behind and resurrect at the previous tab after pointing away.
		if t.role == &"screen_tab":
			_reset_steady_filter()
		else:
			hit_point = _get_steady_hit(hit_point)
		on_screen = (t.role == &"screen")
		hovered_screen = t.screen if on_screen else null
		# Keep the screen cursor in one composition layer across mono, SBS, and
		# native presentation. Switching between embedded eye-viewport cursors and
		# this layer made the pointer disappear after returning from SBS.
		var independent_cursor = VideoPresentation.uses_independent_screen_cursor(
			comp.in_use, video_presentation.is_native_active())
		use_embedded_cursor = on_screen and not pad_on_screen and not tp_capturing \
			and not independent_cursor
		if on_screen and (pad_on_screen or tp_capturing or hides_screen_cursor(hovered_screen)):
			composition_pointers.hide_primary()
			composition_pointers.hide_all_embedded(screens)
		elif use_embedded_cursor and on_screen:
			composition_pointers.hide_primary()
			if pointer_cursor:
				pointer_cursor.visible = false
			if contact_dot:
				contact_dot.visible = false
			composition_pointers.show_embedded(
				hovered_screen,
				screens,
				hit_point,
				settings.bezel_enabled,
				screen_cursor_mode(hovered_screen),
				stereo if hovered_screen == primary_screen else 0,
				-1 if screen_sources.is_browser_screen(hovered_screen) else settings.host.ai_3d_cursor_position,
				depth_estimator._pass_parallax if depth_estimator else 0.0,
				primary_screen)
		elif composition_pointers.has_primary():
			composition_pointers.hide_all_embedded(screens)
			var surf_normal = hovered_screen.get_cylinder_normal_at(hit_point) \
				if on_screen and hovered_screen \
				else (xr_camera.global_position - hit_point).normalized()
			# The native renderer cannot embed the pointer into its video texture,
			# so apply the AI-3D cursor calibration to this independent composition
			# layer in world space. Convert the legacy branch's exact pixel offset
			# into screen metres so Left/Default/Right remain resolution-independent.
			var native_ai_cursor_offset := Vector3.ZERO
			if on_screen and stereo >= 3 and video_presentation.is_native_active() and hovered_screen == primary_screen:
				var base_w := maxf(float(hovered_screen.comp_base_size.x), 1.0)
				var base_h := maxf(float(hovered_screen.comp_base_size.y), 1.0)
				var correction_px := VideoPresentation.cursor_calibration_pixels(
					settings.host.ai_3d_cursor_position, base_h,
					screen_sources.is_browser_screen(hovered_screen))
				var screen_right := hovered_screen.global_transform.basis.x.normalized()
				native_ai_cursor_offset = screen_right * (correction_px / base_w) * hovered_screen.mesh_size.x
			composition_pointers.show_primary(
				hit_point,
				surf_normal,
				xr_camera.global_position,
				hovered_screen.global_position if hovered_screen else hit_point,
				on_screen,
				screen_cursor_mode(hovered_screen),
				native_ai_cursor_offset)
	else:
		_reset_steady_filter()
		composition_pointers.hide_primary()
		composition_pointers.hide_all_embedded(screens)
	if composition_pointers.has_primary():
		if pointer_cursor:
			pointer_cursor.visible = false
		if contact_dot:
			contact_dot.visible = false

func _sync_composition_panels():
	if comp == null:
		return # comp is created after the first frames (native Steam Frame startup)
	if not comp.in_use and not pcvr_handover.menu_only:
		return
	var keyboard_action := composition_panels.sync_transforms(ui_panel_3d, virtual_keyboard)
	match keyboard_action:
		CompositionPanelLayers.KeyboardMaterialAction.MAKE_TRANSPARENT:
			_make_kb_transparent()
		CompositionPanelLayers.KeyboardMaterialAction.RESTORE:
			_restore_kb_material()

func _update_laser_layers():
	if comp == null:
		return # comp is created after the first frames (native Steam Frame startup)
	# Only the selected hand gets a beam. Keep both raycasts enabled for
	# hit-testing so Auto can still discover and switch to the other hand.
	var right_ray: RayCast3D = hand_raycast
	var left_ray: RayCast3D = left_hand_raycast
	if _is_using_hands:
		if xr_interaction._active_hand == "left":
			right_ray = null
		else:
			left_ray = null
	composition_controller_rays.update(
		DEBUG_COMP_LASER and settings.show_pointer_ray,
		(comp.in_use or pcvr_handover.menu_only) and is_xr_active,
		xr_camera.global_position,
		right_ray,
		left_ray)

func _update_marker_layers(_delta: float):
	if comp == null:
		return # comp is created after the first frames (native Steam Frame startup)
	composition_controller_markers.update(
		DEBUG_COMP_MARKER and comp.in_use and is_xr_active,
		xr_camera.global_transform.basis,
		right_hand,
		left_hand,
		right_hand_resting,
		left_hand_resting,
		_is_using_hands)

func set_comp_grab_bar_color(viewport: SubViewport, color: Color):
	CompositionLayerManager.set_grab_bar_color(viewport, color)

func _update_grab_bar_layers():
	if comp == null:
		return # comp is created after the first frames (native Steam Frame startup)
	# One shared atlas per screen holds grab bar, shortcuts, corners and tabs. Only the
	# screen being pointed at submits it (see ScreenShortcutBar.pointed_screen).
	composition_screen_controls.update(
		screens,
		comp.in_use,
		DEBUG_COMP_GRAB_BAR,
		DEBUG_COMP_CORNERS,
		screen_shortcuts.revealed_screen if screen_shortcuts else null,
		screen_shortcuts.pointed_screen if screen_shortcuts else null)

func exit_app():
	if browser_prototype:
		browser_prototype.stop()
	get_tree().quit()

## Steam Frame: closes Nightfall with the exit code that its launcher
## (nightfall.sh) answers by starting it again. Started any other way,
## Nightfall just closes.
const RESTART_EXIT_CODE := 75
func restart_app():
	if browser_prototype:
		browser_prototype.stop()
	get_tree().quit(RESTART_EXIT_CODE)

func disconnect_stream():
	session_lifecycle.request_disconnect()
	if current_host_id >= 0:
		stream_backend.cancel_host_stream(current_host_id)
	stream_backend.stop_play_stream()
	# A stream that was still connecting reports nothing when stopped, so nothing
	# else would clean up. Deferred: anything it does report runs first.
	_finish_disconnect.call_deferred()

func _finish_disconnect() -> void:
	if session_lifecycle.phase == SessionLifecycle.Phase.DISCONNECTING:
		_full_disconnect_cleanup("Disconnected")

func start_connect_timeout():
	if pcvr_test.is_exclusive(): return
	var generation := session_lifecycle.arm_connect_timeout()
	get_tree().create_timer(10.0).timeout.connect(func(): _on_connect_timeout(generation))

func _on_connect_timeout(generation: int):
	if pcvr_test.is_exclusive(): return
	if not session_lifecycle.is_connect_timeout_current(generation):
		return
	_log("[CONNECT] Connection timed out")
	stream_backend.stop_play_stream()
	restore_after_failed_connect("Failed to connect (timeout)")

func restore_after_failed_connect(status_msg: String, welcome_name: String = "server"):
	if pcvr_test.is_exclusive(): return
	# start_stream() resizes the shared source/composition viewports before the
	# asynchronous launch request is sent. If that request fails, no decoder was
	# started and therefore no stream_terminated signal arrives to run the normal
	# disconnect cleanup. Leaving comp_base_size at the attempted stream size
	# makes the 1920x1080 welcome cursor use the wrong pixel coordinate space.
	# Treat this as a complete non-streaming transition, including cancelling the
	# still-armed Connect timeout and clearing restart state so the viewport reset
	# below cannot take the native-restart preserve path.
	_log("[DBG] restore_after_failed_connect 1")
	session_lifecycle.fail()
	_log("[DBG] restore_after_failed_connect 2")
	_full_disconnect_cleanup(status_msg, welcome_name)

func _bind_yuv_textures():
	comp.bind_yuv_textures()

func _retry_yuv_bind(seq: int):
	for i in range(6):
		await get_tree().create_timer(0.25).timeout
		if seq != _stream_start_seq or not is_streaming:
			return
		_bind_yuv_textures()

func _bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode: int, cmt, cr):
	comp.bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode, cmt, cr)

func _bind_comp_fallback_texture(stream_tex):
	comp.bind_fallback_texture(stream_tex)

func _on_stream_started():
	if pcvr_test.is_exclusive():
		pcvr_test.request_stop()
		return
	# The selected display rate was already applied and awaited by
	# StreamManager.start_stream() before decoder and native swapchain setup.
	# Do not request it again here: a display transition racing newly-created
	# GLES resources crashes the Quest GL thread.
	var was_restarting := session_lifecycle.stream_started()
	# Complete any bounded handshake correction before exposing video or
	# replacing the welcome screen. Buffer allocation is not display geometry.
	if await _restart_for_layout_correction(): return
	telemetry.reset_session()
	_last_activity_time = Time.get_ticks_msec() / 1000.0
	ui_controller.set_status("Connecting...")
	welcome_screen.reset_connect_button()
	ui_controller.set_disconnect_visible(true)
	_log("[STREAM] Connection started!")
	if device_is_steam_frame:
		settings_controller.tell_camera_limit(true)
		_log_network(_network_watch.stream_started(stream_manager.stream_host_address))
		refresh_second_link()
	settings_controller.apply_audio_boost()
	# Meteor's depth offer only counts once streaming, so refresh the AI 3D
	# tab now (its "needs Meteor" notice otherwise stayed up until 3D was
	# toggled).
	if ui_controller:
		ui_controller.update_3d_btn_state()
	if device_is_steam_frame:
		_meteor_depth_flag = -1
		_meteor_depth_retries = 0
		_say_if_meteor_offers_no_depth()
		if ui_controller:
			ui_controller.refresh_link_tip()
	if not comp.in_use:
		stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stream_manager.bind_texture()
	var native_expected := video_presentation.can_render_native()
	# bind_yuv_textures() skips rebinding the composition-layer cylinder's
	# shader when the decoder's texture RIDs "look unchanged" from the last
	# bind - a real optimization for the steady-state per-frame case, but
	# wrong right after a (re)connect: a restart's new decoder session can
	# end up with the exact same RIDs reused (resource pooling) even though
	# the actual texture is a fresh one, leaving the cylinder showing a
	# stale/blank frame while decode stats keep updating normally. A stream
	# genuinely (re)starting here should always force a real rebind.
	if comp.available and not native_expected:
		comp.invalidate_yuv_cache()
		_bind_yuv_textures()
	# The decoder's shader material is reused across a restart, not recreated -
	# right here, right at connection start, it can still be holding a
	# reference to the just-torn-down previous session's (now GPU-invalid)
	# texture, which bind_yuv_textures() now correctly refuses to bind (see its
	# RID validity check) rather than crashing the renderer on it. But nothing
	# else ever retries the real YUV path afterward (binding is purely
	# event-driven, no periodic re-check), so without this the stream would be
	# stuck on the SubViewport fallback for the rest of the session. Retry a
	# few times shortly after connecting, by which point the new session's
	# first real frame should have landed.
	_stream_start_seq += 1
	if not native_expected:
		_retry_yuv_bind(_stream_start_seq)
	else:
		_log("[NATIVE-XR] Skipping legacy decoder-texture bind during native connect")
	# Was an unconditional _switch_to_comp_layer() (plain/mono), which reset
	# AI-3D/SBS to 2D on EVERY (re)connect, silently, with nothing re-
	# applying the real mode afterward unless the user happened to touch a
	# mode button again post-restart - root cause of "3D effect stopped
	# working after a restart, only came back after manually cycling modes"
	# (2026-08-18, user diagnosed this from watching a MiDaS-Fast switch
	# visibly apply against the OLD pre-restart video, then get lost when
	# the restart landed). apply_stereo() re-derives and applies the actual
	# current stereo mode (2D/SBS/AI-3D) against the freshly (re)started
	# session instead of blindly resetting to 2D - settings_controller.gd's
	# _schedule_ai_3d_commit() now deliberately skips its own apply_stereo()
	# call when a restart is about to happen, relying on this one instead,
	# so the mode is only ever applied against a session that's actually live.
	settings_controller.apply_stereo()
	# Meteor host depth is offered per stream (see meteor_depth_selected()).
	ui_controller.update_option_btn(_ui_3d_btn, settings_controller.get_depth_model_label())
	if not was_restarting:
		ui_visible = false
		_set_ui_visible(false)
		_ui_has_saved_offset = false
		composition_panels.hide_ui()
	if settings.passthrough_enabled:
		_hide_all_backgrounds()
	# Pads announce themselves to the host on their first input (see
	# InputHandler.send_pad_state), so a session with only a physical pad
	# doesn't also get an idle controller 0.
	input_handler.reset_gamepads()


	state_manager.save_host_state()

func _restart_for_layout_correction() -> bool:
	# The host's real desktop can be a very different shape than settings.host.native_resolution
	# assumed (first-ever connection to a host, or its desktop layout changed since
	# last time) - requesting the wrong aspect makes the host letterbox/squeeze its
	# real composite to fit. Reconnect once at the correctly-scaled size instead, so
	# the *next* launch requests the right shape from the start, and cache the real
	# size afterward so a repeat connection to this host doesn't need to. Only ever
	# retries once per session, so a host that free-scales regardless of requested
	# resolution can't loop us forever.
	#
	# Deliberately done AFTER the stream has genuinely started (not by aborting the
	# first launch response before ever calling start_stream_v2): a launch that's
	# never followed through to an actual RTSP/media connection leaves the host
	# waiting on a handshake that will never come, which held its session-launch
	# lock forever and made every subsequent connect attempt fail with "the active
	# session is stopping or changing" - the exact regression this replaces. Tearing
	# an ACTUALLY-STARTED stream down with stop_play_stream() (same pattern as
	# settings_controller.gd's _schedule_stream_restart()) gives the host a real,
	# clean teardown to work with instead of an abandoned half-launch.
	# Start every session on just the primary monitor - makes multi-monitor
	# testing much easier to reason about (add monitors one at a time from a
	# known-good baseline instead of whatever the host's own multi-monitor
	# default happens to be) and is simpler for real use too. Deliberately a
	# true one-shot for the whole app run (never reset), not per-host/per-
	# reconnect - once trimmed, later manual monitor changes this session are
	# left alone; relaunch the app to get the primary-only starting point again.
	if layout and not _did_initial_monitor_trim and layout.source == &"host_manifest":
		_did_initial_monitor_trim = true
		# Only extra physical screens are trimmed. A virtual screen is there because the
		# user asked for it (the host keeps it for the session), not a host default.
		var enabled_at_connect = layout.enabled_monitors().filter(
			func(m): return not m.hint.get("virtual", false))
		if enabled_at_connect.size() > 1:
			var primary_m = layout.get_primary()
			for m in layout.monitors:
				if not m.is_primary and not m.hint.get("virtual", false):
					m.enabled = false
			settings_controller.apply_screen_layout(layout)
			if primary_m:
				settings.host.native_resolution = primary_m.frame_rect.size
			host_resolution = compute_requested_resolution()
			settings_controller.refresh_resolution_btn_label()
			stream_manager._resolution_retry_done = true
			var retry_host_id = current_host_id
			var retry_app_id = _selected_app_id
			var retry_resolution = host_resolution
			_log("[LAYOUT] Trimming to primary-only on first connect (host defaulted to %d monitors)" % enabled_at_connect.size())
			session_lifecycle.request_restart()
			_clear_comp_yuv_textures()
			await get_tree().process_frame
			await get_tree().process_frame
			stream_backend.stop_play_stream()
			await get_tree().create_timer(0.5).timeout
			if not session_lifecycle.is_restarting(): return true
			stream_manager.start_stream(retry_host_id, retry_app_id, retry_resolution)
			return true

	# Polaris-only: this whole comparison is "does the manifest-reported real
	# desktop size match what settings.host.native_resolution assumed" - meaningless (and,
	# confirmed live, actively harmful) for any host that never populates a
	# real manifest, since layout.frame_size then never reflects this actual
	# connection at all. Against a Sunshine host this fired repeatedly every
	# single connect, restarting over and over chasing a comparison that could
	# never converge - each restart also being a real cost (see
	# stream_connection.cpp's deferred-free GPU resource queue).
	if settings.host.is_polaris_host and layout and layout.source == &"host_manifest" and layout.frame_size != Vector2i.ZERO:
		settings.host.native_resolution = layout.frame_size
		host_resolution = compute_requested_resolution()
		settings_controller.refresh_resolution_btn_label()
		var corrected_resolution := compute_requested_resolution()
		if settings.host.double_h: corrected_resolution.x *= 2
		# Deliberately NOT gated on "not was_restarting" (this used to be) - that
		# blocked the retry for exactly the case that needs it most: removing/
		# adding a monitor changes the server's real captured composite size,
		# triggering a genuine restart (settings_controller.gd's
		# _schedule_stream_restart()), which left the stream stuck requesting the
		# old (now mismatched) aspect for that whole session - the same
		# squished-with-black-bars server-side letterbox symptom this retry
		# exists to fix in the first place, just not caught because a restart
		# was already in flight. _resolution_retry_done alone already prevents
		# this from cascading (the retry's own reconnect passes a non-zero
		# forced_resolution, which does not reset it), so was_restarting was
		# never actually needed for that protection.
		# The launch manifest already updates native_resolution. Compare the
		# actual request, not that refreshed cache, or a changed capture can
		# remain letterboxed at the previous monitor selection's dimensions.
		if stream_manager.capture_resolution_retry_needed(stream_manager.requested_resolution, corrected_resolution, stream_manager._resolution_retry_done):
			stream_manager._resolution_retry_done = true
			var retry_host_id = current_host_id
			var retry_app_id = _selected_app_id
			var retry_resolution = corrected_resolution
			_log("[STREAM] Host's real desktop %s doesn't match cached size - reconnecting at %s (%d%%)" % [
				str(layout.frame_size), str(retry_resolution), settings.host.resolution_scale_pct])
			session_lifecycle.request_restart()
			# See settings_controller.gd's _schedule_stream_restart() for why this
			# has to happen (and yield a frame) before stop_play_stream(), not after.
			_clear_comp_yuv_textures()
			await get_tree().process_frame
			await get_tree().process_frame
			stream_backend.stop_play_stream()
			await get_tree().create_timer(0.5).timeout
			if not session_lifecycle.is_restarting(): return true
			stream_manager.start_stream(retry_host_id, retry_app_id, retry_resolution)
			return true
	return false

func _switch_to_comp_layer():
	comp.switch_to_comp_layer()

func _switch_to_stereo_comp_layer():
	comp.switch_to_stereo_comp_layer()

func _switch_to_mesh_rendering():
	comp.switch_to_mesh_rendering()

func _update_comp_layer_size():
	comp.update_layer_size()

func _on_stream_terminated(msg: String, err_code: int = 0):
	if pcvr_test.is_exclusive(): return
	_log("[NF] _on_stream_terminated: phase=" + session_lifecycle.phase_name() + " msg=" + str(msg) + " err=" + str(err_code))
	if video_presentation:
		video_presentation.deactivate_native(false)
	if session_lifecycle.is_restarting():
		session_lifecycle.stream_terminated(false, err_code)
		_server_codec_support = {}
		ui_controller.update_codec_btn()
		stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_clear_comp_yuv_textures()
		if not comp.in_use and screen_mesh.material_override is ShaderMaterial:
			screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
			screen_mesh.material_override.set_shader_parameter("tex_y", null)
			screen_mesh.material_override.set_shader_parameter("tex_u", null)
			screen_mesh.material_override.set_shader_parameter("tex_v", null)
		return
	if device_is_steam_frame and err_code != 0:
		_log_network(_network_watch.stream_lost(stream_manager.stream_host_address))
	if settings.auto_reconnect_enabled and err_code != 0:
		_log("[RECONNECT] Keeping stream alive for auto-reconnect")
		session_lifecycle.stream_terminated(true, err_code)
		ui_controller.set_status("Connection lost, reconnecting...")
		return
	session_lifecycle.stream_terminated(false, err_code)
	_full_disconnect_cleanup("Disconnected: " + str(msg))

func _full_disconnect_cleanup(status_msg: String, welcome_name: String = "welcome"):
	if pcvr_test.is_exclusive(): return
	if depth_estimator:
		depth_estimator.set_enabled(false)
	session_lifecycle.finish_cleanup()
	_server_codec_support = {}
	_host_cursor_toggle_supported = false
	ui_controller.update_codec_btn()
	ui_controller.update_host_cursor_btn_state()
	ui_controller.set_status(status_msg)
	ui_controller.set_disconnect_visible(false)
	_log("[STREAM] Full disconnect: %s" % status_msg)
	_log("[DBG] _full_disconnect_cleanup 1")
	welcome_screen.show_welcome_screen(welcome_name)
	_log("[DBG] _full_disconnect_cleanup 2")
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_log("[DBG] _full_disconnect_cleanup 3")
	_clear_comp_yuv_textures()
	# _clear_comp_yuv_textures() shows the ". . ." loading indicator (meant
	# for mid-restart, waiting-on-real-decoder-frames), but a full disconnect
	# goes straight to the welcome screen instead of a fresh stream - hide it
	# again so it doesn't blink away on top of the welcome screen content.
	_log("[DBG] _full_disconnect_cleanup 4")
	comp.hide_loading_dots()
	_log("[DBG] _full_disconnect_cleanup 5")
	if comp_shader_mat:
		comp_shader_mat.set_shader_parameter("main_texture", get_welcome_content_texture())
		comp_shader_mat.set_shader_parameter("yuv_mode", 0)
	_log("[DBG] _full_disconnect_cleanup 6")
	if comp_shader_mat_left:
		comp_shader_mat_left.set_shader_parameter("main_texture", get_welcome_content_texture())
		comp_shader_mat_left.set_shader_parameter("yuv_mode", 0)
	_log("[DBG] _full_disconnect_cleanup 7")
	if comp_shader_mat_right:
		comp_shader_mat_right.set_shader_parameter("main_texture", get_welcome_content_texture())
		comp_shader_mat_right.set_shader_parameter("yuv_mode", 0)
	_log("[DBG] _full_disconnect_cleanup 8")
	if not comp.in_use and screen_mesh.material_override is ShaderMaterial:
		screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		screen_mesh.material_override.set_shader_parameter("tex_y", null)
		screen_mesh.material_override.set_shader_parameter("tex_u", null)
		screen_mesh.material_override.set_shader_parameter("tex_v", null)
	_log("[DBG] _full_disconnect_cleanup 9")
	stream_manager.teardown_v2_yuv_rect()
	_log("[DBG] _full_disconnect_cleanup 10")
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_log("[DBG] _full_disconnect_cleanup 11")
	if comp.available:
		_switch_to_comp_layer()
		comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_log("[DBG] _full_disconnect_cleanup 12a mesh branch")
		if not comp.in_use:
			screen_mesh.material_override.set_shader_parameter("main_texture", get_welcome_content_texture())
		_log("[DBG] _full_disconnect_cleanup 12b")
		_switch_to_mesh_rendering()
	_log("[DBG] _full_disconnect_cleanup 13")
	if mouse_captured_by_stream:
		input_handler.release_stream_mouse()
	_log("[DBG] _full_disconnect_cleanup 14")
	audio_player.stop()
	_log("[DBG] _full_disconnect_cleanup 15")
	ui_visible = false
	_log("[DBG] _full_disconnect_cleanup 16")
	_set_ui_visible(false)
	_log("[DBG] _full_disconnect_cleanup 17")
	composition_panels.hide_ui()
	_log("[DBG] _full_disconnect_cleanup 18")
	welcome_screen.reset_connect_button()
	_log("[DBG] _full_disconnect_cleanup 19")
	settings_controller.apply_passthrough(settings.passthrough_enabled)
	_log("[DBG] _full_disconnect_cleanup 20")
	welcome_screen.update_welcome_info()
	_log("[DBG] _full_disconnect_cleanup 21")
	stream_manager.resize_stream_viewport(1920, 1080)

func _clear_comp_yuv_textures():
	comp.clear_yuv_textures()

func _ready():
	session_lifecycle.phase_changed.connect(_on_session_phase_changed)
	_log("=== Nightfall started ===")
	# Steam Frame running natively (SteamOS, not Lepton/Android): the Frame is
	# the only arm64 Linux headset SteamVR runs on, so treat linux.arm64 as it.
	if OS.get_name() == "Linux" and Engine.get_architecture_name() == "arm64":
		device_is_steam_frame = true
		_log("[DEVICE] Linux arm64 - assuming native Steam Frame (SteamOS)")
	Engine.max_fps = 0

	_startup_cover = MeshInstance3D.new()
	_startup_cover.name = "StartupCover"
	var quad = QuadMesh.new()
	quad.size = Vector2(20.0, 20.0)
	_startup_cover.mesh = quad
	_startup_cover.position = Vector3(0, 0, -0.3)
	var cov_mat = StandardMaterial3D.new()
	cov_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cov_mat.albedo_color = Color(0, 0, 0, 1)
	cov_mat.render_priority = 127
	_startup_cover.material_override = cov_mat
	xr_camera.add_child(_startup_cover)
	_log("[COVER] Startup cover active")

	if OS.get_name() == "Android":
		OS.set_environment("CURL_CA_BUNDLE", "/system/etc/security/cacerts/")
		OS.set_environment("SSL_CERT_FILE", "/system/etc/security/cacerts/")
	else:
		OS.set_environment("CURL_CA_BUNDLE", "/etc/ssl/certs/ca-certificates.crt")
		OS.set_environment("SSL_CERT_FILE", "/etc/ssl/certs/")

	_init_modules()
	_init_android_setup()
	_init_ui()
	_init_stream_backend()
	if DevBridge.wanted():
		add_child(DevBridge.new(self))

	var interface = XRServer.find_interface("OpenXR")
	if not interface or not interface.is_initialized():
		if "--nf-no-xr" in OS.get_cmdline_user_args():
			_log("[XR] --nf-no-xr set, continuing without OpenXR for desktop testing")
			# The XR startup that would lift it never runs.
			_startup_cover.queue_free()
			_startup_cover = null
			return
		_log("[XR] OpenXR not available - cannot run without VR runtime")
		if not Engine.is_editor_hint():
			get_tree().quit()
		return

	if Engine.is_editor_hint():
		get_viewport().use_xr = false
		if interface:
			interface.uninitialize()
		return

	_init_xr(interface)
	if device_is_steam_frame:
		_session_watch = FrameSessionWatch.new()
		_session_watch.setup(self, interface)
	video_presentation.setup_native()
	pcvr_test.setup()
	# Composition providers must be registered before the OpenXR session starts.
	# Only after registration may the refresh transition settle before layer and
	# stream swapchains are allocated.
	await settings_controller.apply_display_refresh_rate(false)
	_init_backgrounds_and_comp_layer()
	await get_tree().create_timer(0.5).timeout
	screen_mesh.extra_cull_margin = 10.0
	ui_panel_3d.extra_cull_margin = 10.0
	_init_post_xr()
	_init_textures_and_ui()

	if settings.quick_start_enabled:
		_try_auto_connect()

	Input.joy_connection_changed.connect(func(device, connected):
		_on_joy_changed(device, connected)
	)
	input_handler.scan_connected_pads()

	if right_hand:
		right_hand.pose = "aim"
	if left_hand:
		left_hand.pose = "aim"

	_post_ready_check.call_deferred()

func _on_session_phase_changed(previous: int, current: int) -> void:
	_log("[SESSION] %s -> %s" % [
		SessionLifecycle.Phase.keys()[previous].to_lower(),
		SessionLifecycle.Phase.keys()[current].to_lower(),
	])
	if ui_controller and screen_sources:
		ui_controller.update_screen_sources()
	if settings_controller:
		settings_controller.on_session_phase(current)

func _init_modules():
	stream_manager = StreamManager.new(self)
	xr_interaction = XRInteraction.new(self)
	input_handler = InputHandler.new(self)
	ui_controller = UIController.new(self)
	auto_detect = AutoDetect.new(self)
	depth_estimator = DepthEstimatorModule.new(self)
	meteor_microphone = MeteorMicrophone.new(self)
	native_xr_renderer = NativeXrRendererManager.new(self)
	video_presentation = VideoPresentation.new(null, native_xr_renderer)
	welcome_screen = WelcomeScreen.new(self)
	browser_prototype = preload("res://src/browser_prototype.gd").new(self)
	screen_sources = ScreenSources.new(self)
	screen_sources.changed.connect(ui_controller.update_screen_sources)
	screen_manager = ScreenManager.new(self)
	settings_controller = SettingsController.new(self)
	state_manager = StateManager.new(self)
	controller_mapper = ControllerMapper.new(self)
	if device_is_steam_frame:
		controller_touch = ControllerTouch.new()
		button_bindings = ButtonBindings.new(self)
		voice_typing = VoiceTyping.new()
		voice_typing.setup(self)
	add_child(controller_mapper)
	screen_shortcuts = ScreenShortcutBar.new(self)
	screen_tab_strip = ScreenTabStrip.new(self)

func _init_android_setup():
	# AI-3D depth estimation is native (no JNI/JVM) on Linux as of 2026-08-20
	# (see depth_bridge.cpp's NIGHTFALL_PLATFORM_LINUX branch/MidasDepthEngine,
	# and settings_controller.gd's _ai_3d_supported()) - depth_estimator.setup()
	# needs to run there too now, split out from the rest of this genuinely
	# Android-only setup (controller models, hand fade materials, mouse
	# capture - none of which apply to a desktop Linux client). Must run
	# BEFORE _init_backgrounds_and_comp_layer() creates comp_viewport_left/
	# right - depth_estimator's upsample/offset SubViewports (stereo_mode 5)
	# produce the warp data those actually-displayed per-eye viewports
	# consume every frame (via yuv_display.gdshader), and Godot updates
	# SubViewports in scene-tree order, so the producer must be added to the
	# tree first. (The upsample pass used to also depend on comp_viewport -
	# the OPPOSITE direction - which was the real source of a stutter/
	# double-image bug; that dependency was removed by having it decode YUV
	# directly instead, see depth_upsample.gdshader.)
	if OS.get_name() == "Android" or OS.get_name() == "Linux":
		depth_estimator.setup()
	if OS.get_name() == "Android":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Projectionless (gl_compatibility) builds never render the mesh
		# controller models - comp.in_use always ends up true (see _init_xr's
		# set_submit_projection_layer(false)), and composition-space ray
		# indicators are used instead. The bundled FBX assets are excluded
		# from the Android export (export_presets.cfg exclude_filter) for
		# this reason, so skip trying to load them here too.
		if RenderingServer.get_current_rendering_method() != "gl_compatibility":
			_load_controller_models()
			if DEBUG_RENDER_MODEL_CONTROLLERS:
				_setup_render_model_controllers()
		_prepare_fade_materials("right")
		_prepare_fade_materials("left")
	settings.host.sbs_mode = clampi(settings.host.sbs_mode, 0, 2)
	settings.host.ai_3d_model = clampi(settings.host.ai_3d_model, 0, settings_controller.ai_3d_models.size() - 1)
	settings.host.ai_3d_speed = clampi(settings.host.ai_3d_speed, 0, 3)
	settings.host.ai_3d_last_mode = clampi(settings.host.ai_3d_last_mode, 1, 3)
	settings.host.ai_3d_backend_pref = 1 if settings.host.ai_3d_backend_pref == 1 else 2
	# Runs before any per-host state (state_manager.gd's load_host_state()
	# has its own call for that, and its own comment) - also covers a
	# brand-new install/host, which never reaches that call at all (see
	# load_host_state()'s early return when the host has no saved section
	# yet), so a fresh Android install can't boot pointed at settings.host.ai_3d_model's
	# compiled-in default (MiDaS-256-GPU, not bundled there).
	settings_controller.enforce_ai3d_platform_lock(true)
	if not [12, 15, 20, 30, 40, 60].has(settings.host.ai_3d_hz_cap):
		settings.host.ai_3d_hz_cap = 20
	if not HostSettings.separation_valid(settings.host.ai_3d_separation_pct):
		settings.host.ai_3d_separation_pct = 75
	if not HostSettings.convergence_valid(settings.host.ai_3d_convergence_pct):
		settings.host.ai_3d_convergence_pct = 50
	settings.host.ai_3d_debug = clampi(settings.host.ai_3d_debug, 0, 4)

	if right_hand and left_hand:
		var right_ray = right_hand.get_node_or_null("HandRayCast")
		if right_ray:
			var right_laser_node = right_ray.get_node_or_null("Laser")
			if right_laser_node:
				var tex = _make_laser_gradient()
				if tex:
					var mat = StandardMaterial3D.new()
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.albedo_color = Color(1, 1, 1, 0.5)
					mat.albedo_texture = tex
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.render_priority = 127
					mat.no_depth_test = true
					right_laser_node.material_override = mat
			left_hand_raycast = right_ray.duplicate()
			left_hand_raycast.name = "LeftHandRayCast"
			left_hand.add_child(left_hand_raycast)

func _init_ui():
	virtual_keyboard = VirtualKeyboard.new(self)
	add_child(virtual_keyboard)
	virtual_keyboard.build()

	screen_mesh.setup(self, &"m0")
	screen_registry.initialize(screen_mesh)
	screen_shortcuts.setup_screen(screen_mesh)
	primary_screen.grid_pos = Vector2i(3, 1)
	layout = ScreenLayout.single(Vector2i(1920, 1080))
	primary_screen.apply_monitor(layout.get_primary(), layout.frame_size)
	_mesh_size = screen_mesh.mesh.size
	screen_manager.create_corner_handles()
	screen_manager.create_bezel()
	_create_contact_dot()
	ui_panel_3d.set_meta(&"nf_role", &"panel")

	ui_controller.build_ui()
	welcome_screen.build_welcome_ui()
	_set_viewport_active(ui_viewport, false)

	%IPInput.gui_input.connect(func(e): ui_controller.on_ipinput_gui_input(e))
	ui_controller.setup_numpad()
	ui_controller.refresh_ui_buttons()

const VR_SCREEN_SCENE := preload("res://src/vr_screen.tscn")
const MAX_SCREENS := ScreenRegistry.MAX_SCREENS
# Gap between adjacent screen edges, in meters. Shared with MonitorGrid so
# grid-mode spacing and add_screen()'s free-placement spacing can't drift apart.
const SCREEN_GAP := 0.05

# Local-space offset (from mesh center) of a curved screen's left/right edge,
# matching the vertex math in VRScreen.apply_curvature(): the edge sits at
# chord half-width (not mesh_size.x * 0.5) and bows back in +Z.
func _curve_edge_local_offset(mesh_w: float, radius: float, curvature: int, sign: float) -> Vector3:
	if curvature == 0 or radius <= 0.0:
		return Vector3(sign * mesh_w * 0.5, 0, 0)
	var angle = mesh_w / radius
	var half_w = sin(angle * 0.5) * radius
	var edge_z = radius * (1.0 - cos(angle * 0.5))
	return Vector3(sign * half_w, 0, edge_z)

# Euler angles (same convention as Node3D.rotation) that orient something at
# `pos` to face the headset: yaw via atan2(cam.x-pos.x, cam.z-pos.z) (this
# mesh's front faces local +Z, not -Z, so Node3D.look_at() is 180 degrees off
# and must not be used here). with_pitch also tilts up/down toward the
# headset, for screens placed above/below primary's height. Pure function (no
# node mutation) so grid_cell_transform() below can use it mid-walk, before a
# screen has actually been moved to the position being evaluated.
func _face_camera_angles(pos: Vector3, cam_pos: Vector3, with_pitch: bool) -> Vector3:
	var yaw = atan2(cam_pos.x - pos.x, cam_pos.z - pos.z)
	var pitch = 0.0
	if with_pitch:
		var to_cam = cam_pos - pos
		var dist = to_cam.length()
		pitch = -asin(clampf(to_cam.y / dist, -1.0, 1.0)) if dist > 0.001 else 0.0
	return Vector3(pitch, yaw, 0.0)

func _face_camera(node: Node3D, cam_pos: Vector3, with_pitch: bool) -> void:
	node.rotation = _face_camera_angles(node.global_position, cam_pos, with_pitch)

# Degrees each grid square is turned from its neighbor square (a 155-degree
# dihedral fold between adjacent squares) - a fixed, constant spacing,
# deliberately NOT derived from curvature/radius: the grid's own angle stays
# "a standard size" regardless of whatever Flat/Slight/Curved the screens
# themselves are set to, and the screens' own existing curve/bow rendering
# (VRScreen.apply_curvature(), _curve_edge_local_offset()) is completely
# unaffected by any of this - it stays exactly as it already is. Sized for the
# common case (3 screens = 6 squares, not the full 8), hence sharper than a
# naive 120deg/8 would give. A screen is 2 squares wide, so consecutive
# SCREENS are rotated by 2x this amount from each other.
const GRID_SQUARE_TURN_DEG := 25.0

# Transform of the screen `n` screen-widths to the right (n>0) or left (n<0)
# of primary (n=0 = primary itself), for every n from -max_n to +max_n,
# computed via a single outward walk in each direction (used to be recomputed
# from scratch for every one of nearest_free_grid_cell()'s ~21 candidates,
# every frame during a live drag - real cost saver to do it once and look up).
#
# Each hop places the next screen's near edge exactly SCREEN_GAP from the
# current screen's far edge - same anchor+near_offset edge math add_screen()
# already uses for its own hops (_curve_edge_local_offset(), so a genuinely
# curved screen's real bowed-backward edge is what the gap is measured from,
# not an idealized flat one - a curved screen's edge sits well behind its
# flat mesh_size.x width, and measuring the gap against the flat width was
# exactly why curved screens kept touching even though the gap looked correct
# on paper), just with a fixed rotation increment instead of a
# curvature-derived one - then rotates by 2*GRID_SQUARE_TURN_DEG for the next
# screen. Using an explicit edge-to-edge gap term like this (rather than
# deriving screen spacing from a folded multi-square chord) is what
# guarantees screens never drift closer than SCREEN_GAP as the turn angle
# increases - an earlier version derived spacing from a chord across 2
# individually-folded squares, which shrank as the angle increased.
func _grid_screen_transforms(max_n: int) -> Dictionary:
	var transforms := {0: Transform3D(primary_screen.global_transform.basis, primary_screen.global_position)}
	var mesh_w = primary_screen.mesh_size.x
	var curvature = primary_screen.curvature
	var radius = primary_screen.get_cylinder_radius() if curvature > 0 else 0.0
	var turn = deg_to_rad(GRID_SQUARE_TURN_DEG * 2.0)
	for dir in [1.0, -1.0]:
		var pos = primary_screen.global_position
		var basis = primary_screen.global_transform.basis
		for n in range(1, max_n + 1):
			var far_edge = _curve_edge_local_offset(mesh_w, radius, curvature, dir)
			var anchor = pos + basis * far_edge
			anchor += basis.x * dir * SCREEN_GAP
			basis = basis.rotated(Vector3.UP, -dir * turn)
			var near_edge = _curve_edge_local_offset(mesh_w, radius, curvature, -dir)
			pos = anchor - basis * near_edge
			transforms[int(dir) * n] = Transform3D(basis, pos)
	return transforms

# World transform for grid cell (gx,gy), given a screen-transform cache from
# _grid_screen_transforms() above. Row (vertical) offsets stay horizontally
# unrotated (curvature has always been horizontal-only here) but DO pitch to
# face the viewer, same as add_screen()'s existing "above" placement always
# has - a row that ends up above eye height needs to tilt down to read
# comfortably, and a row below needs to tilt up.
func _cell_transform_from_screens(gx: int, gy: int, anchor_gx: int, anchor_gy: int, transforms: Dictionary) -> Transform3D:
	var n = (gx - anchor_gx) / MonitorGrid.SPAN
	var t: Transform3D = transforms[n]

	var row_steps = (gy - anchor_gy) / MonitorGrid.SPAN
	if row_steps != 0:
		# gy increases downward in the grid, which is -Y (lower) in world space.
		var row_span = primary_screen.mesh_size.y + SCREEN_GAP
		t.origin += t.basis.y * (-row_steps) * row_span
		var yaw = t.basis.get_euler().y
		var pitch = _face_camera_angles(t.origin, xr_camera.global_position, true).x
		t.basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))

	return t

# Single-cell convenience wrapper around _cell_transform_from_screens() - fine
# for the one-off calls (preset apply, default placement); the live-drag hot
# path below builds one shared cache instead of using this per candidate.
func grid_cell_transform(gx: int, gy: int, anchor_gx: int, anchor_gy: int) -> Transform3D:
	var n = absi((gx - anchor_gx) / MonitorGrid.SPAN)
	return _cell_transform_from_screens(gx, gy, anchor_gx, anchor_gy, _grid_screen_transforms(n))

# Nearest unoccupied SPANxSPAN cell to raw_pos. Brute-forces all
# (COLS-SPAN+1)*(ROWS-SPAN+1) = 21 candidate cells against a single shared
# transform cache - cheap enough to run every frame during a live drag.
# occupied is an Array[Vector2i] of other screens' current grid cells.
# Returns Vector2i(-1,-1) if every cell is blocked.
func nearest_free_grid_cell(raw_pos: Vector3, occupied: Array, anchor_gx: int, anchor_gy: int) -> Vector2i:
	var transforms = _grid_screen_transforms(MonitorGrid.COLS / MonitorGrid.SPAN)
	var best := Vector2i(-1, -1)
	var best_dist := INF
	for gy in range(MonitorGrid.ROWS - MonitorGrid.SPAN + 1):
		for gx in range(MonitorGrid.COLS - MonitorGrid.SPAN + 1):
			var cand := Vector2i(gx, gy)
			var blocked := false
			for occ in occupied:
				if MonitorGrid.cells_overlap(cand, occ):
					blocked = true
					break
			if blocked:
				continue
			var t = _cell_transform_from_screens(gx, gy, anchor_gx, anchor_gy, transforms)
			var d = t.origin.distance_to(raw_pos)
			if d < best_dist:
				best_dist = d
				best = cand
	return best

func add_screen(monitor_id: StringName, real_x_hint: float = INF, with_stereo: bool = false, browser_provider: RefCounted = null) -> VRScreen:
	if not screen_registry.can_add():
		_log("[SCREEN] Refusing to add screen %s: MAX_SCREENS=%d reached" % [String(monitor_id), MAX_SCREENS])
		return null
	var s: VRScreen = VR_SCREEN_SCENE.instantiate()
	add_child(s)
	s.setup(self, monitor_id)
	if browser_provider != null:
		screen_sources.register_browser(s, browser_provider)
	s.mesh_size = primary_screen.mesh_size if primary_screen else Vector2(2.24, 1.26)
	s.curvature = primary_screen.curvature if primary_screen else 2
	if primary_screen:
		var gap = SCREEN_GAP
		var cam_pos = xr_camera.global_position
		var new_radius = primary_screen.get_cylinder_radius() if primary_screen.curvature > 0 else 0.0
		# Prefer the monitor's real desktop x-position (when the caller has one,
		# i.e. apply_screen_layout() passing a manifest-backed MonitorSpec) to
		# decide which side of the chain a new screen extends, and which
		# existing screen it attaches next to. The old approach only tracked
		# "is there already anything on the left/right" - it can't distinguish
		# "further right than the current rightmost" from "should go on the
		# left", so a 3rd non-primary monitor could land on the wrong side, or
		# (once both sides already had one) get forced to stack "above" even
		# when it was really just the next one over in the row. That
		# visual/real mismatch mattered beyond looks: uv_to_host_point() maps
		# clicks using the real desktop_rect regardless of where the screen
		# visually ended up, so a wrongly-placed screen made clicks land on
		# whatever content was really at that position - often the primary.
		var have_hint = real_x_hint != INF and primary_screen.monitor != null
		var primary_real_x = primary_screen.monitor.desktop_rect.position.x if have_hint else 0.0
		var slot: String
		if have_hint:
			slot = "left" if real_x_hint < primary_real_x else "right"
		else:
			var eps = 0.05
			var has_left = false
			var has_right = false
			for existing in screens:
				if existing == primary_screen:
					continue
				var offset_x := ScreenManager.horizontal_offset(existing.global_transform, primary_screen.global_transform)
				if offset_x < -eps:
					has_left = true
				elif offset_x > eps:
					has_right = true
			slot = "above" if (has_left and has_right) else ("left" if has_right else "right")
		if slot == "above":
			var ref_offset = Vector3(0, primary_screen.mesh_size.y * 0.5, 0)
			var anchor = primary_screen.global_transform * ref_offset
			anchor += primary_screen.global_transform.basis.y * gap
			var near_offset = Vector3(0, -s.mesh_size.y * 0.5, 0)
			s.global_position = anchor - near_offset
			_face_camera(s, cam_pos, true)
			var rotated_near_offset = s.global_transform.basis * near_offset
			s.global_position = anchor - rotated_near_offset
			_face_camera(s, cam_pos, true)
		else:
			var dir = -1.0 if slot == "left" else 1.0
			var edge_screen = primary_screen
			var edge_key = primary_real_x
			for existing in screens:
				if existing == primary_screen:
					continue
				var existing_key = existing.monitor.desktop_rect.position.x if (have_hint and existing.monitor) else ScreenManager.horizontal_offset(existing.global_transform, primary_screen.global_transform)
				var cmp_key = edge_key
				if dir > 0 and existing_key > cmp_key:
					edge_screen = existing
					edge_key = existing_key
				elif dir < 0 and existing_key < cmp_key:
					edge_screen = existing
					edge_key = existing_key
			var ref_radius = edge_screen.get_cylinder_radius() if edge_screen.curvature > 0 else 0.0
			var ref_offset = _curve_edge_local_offset(edge_screen.mesh_size.x, ref_radius, edge_screen.curvature, dir)
			var anchor = edge_screen.global_transform * ref_offset
			anchor += edge_screen.global_transform.basis.x * dir * gap
			var near_offset = _curve_edge_local_offset(s.mesh_size.x, new_radius, s.curvature, -dir)
			s.global_position = anchor - near_offset
			_face_camera(s, cam_pos, false)
			var rotated_near_offset = s.global_transform.basis * near_offset
			s.global_position = anchor - rotated_near_offset
			_face_camera(s, cam_pos, false)
	screen_manager.create_corner_handles_for(s)
	screen_shortcuts.setup_screen(s)
	screen_manager.create_bezel_for(s)
	s.apply_curvature()
	if comp.available:
		comp.setup_screen(s, with_stereo)
		if is_streaming and stream_viewport:
			var stream_size: Vector2i = stream_manager.get_current_stream_size() if stream_manager else stream_viewport.size
			if stream_size.x > 0 and stream_size.y > 0:
				s.comp_base_size = stream_size
				s.comp_viewport.size = (s.comp_base_size + Vector2i(16, 16)) if device_is_steam_frame else stream_size
	if not screen_registry.add(s):
		push_error("Screen registry rejected prepared screen %s" % String(monitor_id))
		s.queue_free()
		return null
	_log("[SCREEN] Added screen %s (total=%d)" % [String(monitor_id), screens.size()])
	if comp.available and comp.in_use and s.comp_cylinder:
		s.comp_cylinder.visible = true
		s.comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		s.comp_shader_mat.set_shader_parameter("stereo_mode", 0)
		s.bezel_mesh.visible = false
		comp.make_screen_transparent()
		comp.update_cylinder_params()
		comp.update_bezel()
	if comp.available and is_streaming:
		comp.invalidate_yuv_cache()
		_bind_yuv_textures()
	_log("[COMP] screens=%d controls_layers=%d (one shared atlas per screen; not a total runtime layer count)" % [screens.size(), screens.size()])
	if comp.available and s.comp_cylinder and not s.comp_cylinder.is_natively_supported():
		_log("[COMP] Screen %s cylinder not natively supported, falling back to mesh rendering for this screen" % String(monitor_id))
	return s

func remove_screen(monitor_id: StringName) -> void:
	for i in range(screens.size()):
		if screens[i].monitor_id == monitor_id:
			var s = screens[i]
			if s == primary_screen:
				_log("[SCREEN] Refusing to remove the primary screen %s" % String(monitor_id))
				return
			if not screen_registry.remove(s):
				return
			# Per-screen controls are parented under the XR origin, not the
			# screen node: retire them explicitly when closing a browser screen.
			var retired_controls: Array = []
			for layer in [s.comp_grab_bar, s.comp_corner_layer]:
				if is_instance_valid(layer):
					if retired_controls.has(layer): continue
					retired_controls.append(layer)
					layer.visible = false
					layer.set_layer_viewport(null)
					layer.queue_free()
			var retired_viewports: Array = []
			for viewport in [s.comp_grab_bar_viewport, s.comp_corner_viewport]:
				if is_instance_valid(viewport) and not retired_viewports.has(viewport):
					retired_viewports.append(viewport)
					# Freed after the render-thread layer detachment below.
			if comp.available:
				if s.comp_cylinder:
					s.comp_cylinder.visible = false
					s.comp_cylinder.set_layer_viewport(null)
					xr_origin.remove_child(s.comp_cylinder)
					s.comp_cylinder.queue_free()
				if s.comp_cylinder_left:
					s.comp_cylinder_left.visible = false
					s.comp_cylinder_left.set_layer_viewport(null)
					xr_origin.remove_child(s.comp_cylinder_left)
					s.comp_cylinder_left.queue_free()
				if s.comp_cylinder_right:
					s.comp_cylinder_right.visible = false
					s.comp_cylinder_right.set_layer_viewport(null)
					xr_origin.remove_child(s.comp_cylinder_right)
					s.comp_cylinder_right.queue_free()
				if s.comp_viewport:
					retired_viewports.append(s.comp_viewport)
				if s.comp_viewport_left:
					retired_viewports.append(s.comp_viewport_left)
				if s.comp_viewport_right:
					retired_viewports.append(s.comp_viewport_right)
			_retire_screen_viewports(retired_viewports)
			# screen_mesh is main.gd's own permanent $MeshInstance3D (see
			# _init_ui()'s screens = [screen_mesh]/primary_screen = screen_mesh) -
			# reused for the welcome screen and referenced directly all over this
			# codebase (dozens of call sites), not a disposable VR_SCREEN_SCENE
			# instance like every screen add_screen() creates. It's already been
			# demoted out of the screens[] array and had its comp-layer resources
			# torn down above by this point (the normal "replace the welcome
			# placeholder with the real primary" flow on first connect always
			# reaches here for it, once it's no longer primary_screen) - freeing
			# the node itself as well would free a node the rest of the app still
			# holds direct references to, producing "previously freed" errors on
			# every subsequent access (confirmed live: repeating every frame via
			# whatever still reads screen_mesh.* after this).
			if s != screen_mesh:
				s.queue_free()
			else:
				# Kept alive, but it must stop being a target: its collision
				# stays in the scene at its old place, so the laser could hit
				# it in front of the screen now standing there and send clicks
				# through its stale monitor mapping. It is never re-added.
				s.visible = false
				s.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
			_log("[SCREEN] Removed screen %s (total=%d)" % [String(monitor_id), screens.size()])
			if comp.available and is_streaming:
				comp.invalidate_yuv_cache()
				_bind_yuv_textures()
			_update_cursor_layer()
			return

func _retire_screen_viewports(viewports: Array) -> void:
	_pcvr_screen_retirements += 1
	# Layer detachment is queued on the render thread and accesses the old
	# render target. Keep viewports alive until that work has drained.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for viewport in viewports:
		if is_instance_valid(viewport):
			viewport.queue_free()
	_pcvr_screen_retirements -= 1

func _init_stream_backend():
	if config_mgr and comp_mgr:
		comp_mgr.set_config_manager(config_mgr)
	if not ClassDB.class_exists("NightfallStream"):
		_log("[FATAL] NightfallStream GDExtension failed to load - missing .so or incompatible glibc")
		if not Engine.is_editor_hint():
			get_tree().quit()
		return
	var v2_node = ClassDB.instantiate("NightfallStream")
	add_child(v2_node)
	v2_node.set_auto_reconnect(settings.auto_reconnect_enabled)
	settings_controller.apply_audio_boost()
	v2_node.set_max_reconnect_attempts(5)
	v2_node.set_reconnect_delay_ms(2000)
	if v2_node.has_method("set_reconnect_via_launch"):
		v2_node.set_reconnect_via_launch(true)
	stream_backend = StreamBackend.new(v2_node)
	settings_controller.apply_audio_boost()
	stream_backend.set_config_manager(config_mgr)
	stream_backend.set_computer_manager(comp_mgr)
	if OS.get_name() == "Android":
		# "hollywood" (Quest 2's real device codename) - Build.MODEL itself is
		# useless (confirmed on a real Quest 3 to just return "Quest", not the
		# generation), see GodotApp.java's getDeviceModel() comment.
		var device_codename = stream_backend.get_device_model()
		device_is_quest2 = device_codename.to_lower() == "hollywood"
		device_is_quest3 = device_codename.to_lower() == "eureka"
		device_is_steam_frame = device_codename.to_lower().begins_with("lepton")
		_log("[DEVICE] Build.DEVICE='%s' device_is_quest2=%s device_is_quest3=%s device_is_steam_frame=%s" % [device_codename, str(device_is_quest2), str(device_is_quest3), str(device_is_steam_frame)])
	_client_codec_support = stream_backend.probe_all_video_formats()
	# PyroWave (docs/plans/active/pyrowave-codec.md) isn't probed through
	# probe_all_video_formats() - that queries FfmpegDecoder's own
	# capabilities (used on Linux), which has nothing to do with Android's
	# MediaCodec-based decode path PyroWave actually uses there. Scoped to
	# Quest 3 only for now (see the plan doc's own reasoning).
	_client_codec_support["pyrowave"] = device_is_quest3
	# Raw frames only make sense for the Linux build's local-capture pipeline.
	# A saved Raw preference falls back once server info arrives
	# (stream_manager.gd's is_codec_available() check).
	if OS.get_name() == "Android":
		_client_codec_support["raw"] = false
	# Native Steam Frame: the hardware decoder path handles H.264/HEVC only
	# (FFmpeg here has no usable AV1 decoder), and Raw is local-capture only.
	if OS.get_name() == "Linux" and device_is_steam_frame:
		_client_codec_support["av1"] = false
		_client_codec_support["raw"] = false
	_log("[CODEC] Client support: h264=%s hevc=%s av1=%s raw=%s pyrowave=%s" % [
		str(_client_codec_support.get("h264", false)),
		str(_client_codec_support.get("hevc", false)),
		str(_client_codec_support.get("av1", false)),
		str(_client_codec_support.get("raw", true)),
		str(_client_codec_support.get("pyrowave", false))])
	v2_node.pair_completed.connect(func(s, m): stream_manager.on_pair_completed(s, m))
	if v2_node.has_signal("log_message"):
		v2_node.log_message.connect(func(message: String):
			_log("[MOONLIGHT] %s" % message)
		)
	v2_node.stream_started.connect(func():
		_on_stream_started()
	)
	v2_node.stream_terminated.connect(func(err_code, err_msg):
		_on_stream_terminated(err_msg, err_code)
	)
	if v2_node.has_signal("restore_token_updated"):
		v2_node.restore_token_updated.connect(func(tok):
			_log("[PORTAL] Restore token updated")
			settings.pipewire_restore_token = tok
			state_manager.save_state()
		)
	if v2_node.has_signal("reconnect_scheduled"):
		v2_node.reconnect_scheduled.connect(func(attempt, max_attempts, delay_ms):
			session_lifecycle.reconnect_scheduled()
			ui_controller.set_status(Localization.t("Reconnecting %d/%d in %ds...") % [attempt, max_attempts, delay_ms / 1000])
			_log("[RECONNECT] Attempt %d/%d in %dms" % [attempt, max_attempts, delay_ms])
		)
	if v2_node.has_signal("reconnect_requested"):
		v2_node.reconnect_requested.connect(func(attempt, max_attempts):
			_log("[RECONNECT] Relaunching session (attempt %d/%d)" % [attempt, max_attempts])
			ui_controller.set_status(Localization.t("Reconnecting %d/%d...") % [attempt, max_attempts])
			stream_manager.relaunch_for_reconnect()
		)
	if v2_node.has_signal("reconnect_failed"):
		v2_node.reconnect_failed.connect(func():
			session_lifecycle.fail()
			_log("[RECONNECT] All attempts failed")
			_full_disconnect_cleanup("Reconnect failed")
		)
	if v2_node.has_signal("h264_hw_upgraded"):
		v2_node.h264_hw_upgraded.connect(func():
			_bind_yuv_textures()
			_log("[H264] HW upgrade: re-bound YUV textures for NV12")
		)
	if v2_node.has_signal("hdr_mode_changed"):
		v2_node.hdr_mode_changed.connect(func(enabled: bool, metadata: Dictionary):
			_log("[HDR] Protocol mode changed: enabled=%s metadata=%s" % [str(enabled), str(metadata)])
			# The native callback persists transfer metadata immediately, then
			# applies it on the render thread. Rebind on this frame and once more
			# after a rendered frame so either ordering updates the composition
			# shader variant without relying on stream-start retry timing.
			comp.invalidate_yuv_cache()
			_bind_yuv_textures()
			await get_tree().process_frame
			comp.invalidate_yuv_cache()
			_bind_yuv_textures()
		)
	if v2_node.has_signal("controller_rumble"):
		v2_node.controller_rumble.connect(func(controller, low_freq, high_freq):
			_trigger_haptic(controller, low_freq, high_freq)
		)
	if v2_node.has_signal("controller_trigger_rumble"):
		v2_node.controller_trigger_rumble.connect(func(controller, left_motor, right_motor):
			_trigger_haptic(controller, left_motor, right_motor)
		)
func _init_xr(interface):
	var render_size = interface.get_render_target_size()
	_xr_render_width = int(render_size.x)
	_log("[XR] OpenXR render target: %dx%d" % [render_size.x, render_size.y])
	_log("[XR] Blend modes: %s" % str(interface.get_supported_environment_blend_modes()))
	if OS.get_name() == "Android" and RenderingServer.get_current_rendering_method() == "gl_compatibility" and interface.has_method("set_submit_projection_layer"):
		if device_is_steam_frame:
			_log("[XR] Steam Frame detected; projectionless mode disabled, rendering normal 3D scene")
		else:
			interface.set_submit_projection_layer(false)
			_log("[XR] Projectionless mode enabled; submitting composition layers only")

	if device_is_steam_frame:
		_setup_frame_controller_models()
		# Give SteamOS's compositor a real full-screen window to send keys to.
		var win_mode := DisplayServer.window_get_mode()
		_log("[FOCUS] window mode %d size %s focused=%s display=%s" % [win_mode, str(DisplayServer.window_get_size()),
			str(get_window().has_focus()), DisplayServer.get_name()])
		# (2j tried forcing full screen and focus here; it made no difference to
		# the volume runaway, and the window already has focus, so it's gone.)
	var blend_modes = interface.get_supported_environment_blend_modes()
	passthrough_supported = false
	for bm in blend_modes:
		if bm == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
			passthrough_supported = true
			break

	if passthrough_supported:
		get_viewport().transparent_bg = true
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0, 0, 0, 0)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	else:
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0, 0, 0, 1)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE

	get_viewport().size = render_size
	get_viewport().use_xr = true
	# Steam Frame: no multisampling of the 3D scene. It costs 2 to 5 ms a
	# frame for a difference nobody could see, and together with foveation it
	# garbles the scene and takes ten times as long to draw (Godot issue
	# 124165; 61 to 71 ms a frame in 6r). Builds 5n to 6t had it as the
	# Picture option "Edge Smoothing".
	if OS.get_name() == "Android" or device_is_steam_frame:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	else:
		get_viewport().msaa_3d = Viewport.MSAA_2X
	_xr_base_render_scale = get_viewport().scaling_3d_scale
	is_xr_active = true
	# Godot's own comp-layer/texture bindings (connect_welcome_texture() et al)
	# only ever run once, here at boot, regardless of whether the OpenXR
	# session is actually visible yet - is_initialized() (checked before this
	# function is even called) only means a session exists, not that the
	# headset is being worn: the proximity sensor is a separate state Quest
	# tracks independently of session creation. Launching headlessly (e.g. via
	# adb) and only putting the headset on afterward left the welcome screen
	# showing its plain grey placeholder texture, because nothing ever
	# re-touched the binding once the session actually became visible.
	# user_presence_changed is the proximity-sensor signal itself - re-run the
	# one-time welcome-texture binding whenever the headset is (re-)donned,
	# which is cheap and idempotent, so it's safe even on a session that was
	# already correctly bound.
	if interface.has_signal("user_presence_changed"):
		interface.user_presence_changed.connect(_on_user_presence_changed)
	if device_is_steam_frame and interface.has_signal("pose_recentered"):
		interface.pose_recentered.connect(_on_pose_recentered)
	settings.host.sbs_mode = 0
	settings.host.ai_3d_speed = 0
	# Establish the default 60fps -> 120Hz mapping before composition-layer
	# swapchains are created. Delaying this until stream startup makes the
	# runtime transition every live layer from 72Hz to 120Hz at once, which is
	# measurably less stable on Quest. StreamManager applies the selected host's
	# saved FPS again at the actual connection boundary.
	# Applied and awaited by _ready() immediately after native-provider setup.
	# Yielding here would let OpenXR start its session first, after which provider
	# registration is rejected for the lifetime of this launch.

# Steam Frame: the system recenter (Steam button) moves the room around you;
# follow it by bringing the screen back in front.
func _on_pose_recentered():
	if _startup_reposition != -1:
		return
	_log("[VIEW] System recenter")
	await get_tree().process_frame
	await get_tree().process_frame
	recenter_view()

func _on_user_presence_changed(is_present: bool):
	if not is_present:
		if xr_interaction:
			xr_interaction.cancel_transient_interactions("headset removed")
		return
	if xr_interaction:
		xr_interaction.cancel_transient_interactions("headset present")
	_schedule_xr_surface_refresh("headset present")

func _schedule_xr_surface_refresh(reason: String) -> void:
	# Activity resume and user-presence signals can arrive before Godot has
	# recreated its Android EGL surface and composition-layer swapchains. Retry
	# across several rendered frames instead of betting the screen on one early
	# callback. Menu and keyboard use independent layers, which is why they can
	# survive while only the main screen disappears.
	_xr_resume_refresh_attempts = 3
	_xr_resume_refresh_wait_frames = 1
	_log("[XR] Scheduled composition refresh: %s" % reason)

func _process_xr_surface_refresh() -> void:
	if _xr_resume_refresh_attempts <= 0:
		return
	_xr_resume_refresh_wait_frames -= 1
	if _xr_resume_refresh_wait_frames > 0:
		return
	_xr_resume_refresh_attempts -= 1
	_xr_resume_refresh_wait_frames = 4
	if is_streaming:
		if native_xr_renderer and native_xr_renderer.active:
			native_xr_renderer.request_redraw()
		else:
			_bind_yuv_textures()
	else:
		# Rebind the welcome texture and reassert the mono layer after Godot has
		# rebuilt its viewport swapchain following Android activity resume.
		if comp and comp.available:
			comp.connect_welcome_texture()
			if comp.in_use:
				comp.switch_to_comp_layer()
	_log("[XR] Composition refresh attempt completed (%d remaining)" % _xr_resume_refresh_attempts)

func _init_backgrounds_and_comp_layer():
	_create_backgrounds()
	_screen_mesh_original_mat = screen_mesh.material_override
	_setup_comp_layer()
	comp.connect_welcome_texture()

func _init_post_xr():
	state_manager.load_state()
	_state_loaded = true
	if voice_typing:
		voice_typing.use_chosen_model()
	if device_is_steam_frame:
		_log("[TOUCH] Cursor Follow: %s; capacitive touch: %s" % [settings_controller.cursor_follow_label(), "on" if (settings.cursor_follow and settings.sleep_when_put_down) else "off"])
		settings_controller.apply_foveation()
		settings_controller.apply_flat_screen_detail()
		# The Mobile renderer keeps the 3D scene in a 10-bit linear buffer
		# with twice the range, so the darkest tones get few levels: below
		# about 36 of 255 they are 2 to 6 steps apart. A screen drawn in the
		# scene (curved, or Flat Screen: 3D Scene) showed that as bands in
		# shadows and skin; a Layer screen never passes through the buffer.
		# The engine's own remedy: a half-level pixel pattern added before
		# the buffer is written, so the levels in between come out on average.
		RenderingServer.material_set_use_debanding(true)
		_log("[PICTURE] 3D scene debanding on")
		_log_steamvr_app_settings()
		_check_addon_cameras()

	if comp.available:
		_switch_to_comp_layer()

	settings_controller.apply_passthrough(settings.passthrough_enabled)

	ui_visible = false
	_set_ui_visible(false)
	_ui_has_saved_offset = false
	# _reposition_screen_and_ui() (triggered from _process()) can race with the
	# await above, so re-sync everything one last time now that load_state()/
	# switch_to_comp_layer() have both definitely finished - the same fix a
	# manual grab performs, just run automatically before the cover lifts.
	for s in screens:
		s.apply_curvature()
	if comp.available:
		comp.update_cylinder_params()
	_debug_log_cyl("init_post_xr")
	_startup_ready = true
	if device_is_steam_frame:
		_announce_build()

# Steam Frame: after installing a new build, say so once, so it's clear the
# new version is the one running. The build name comes from the VERSION file
# the installer copies next to the app.
func _announce_build() -> void:
	var f := FileAccess.open(OS.get_executable_path().get_base_dir() + "/VERSION", FileAccess.READ)
	if f == null:
		return
	var build := f.get_as_text().strip_edges()
	f.close()
	if build.is_empty():
		return
	_log("[BUILD] Nightfall build %s" % build)
	# Which folder the settings are in (the Frame's own since 8u).
	_log("[BUILD] settings folder: %s" % OS.get_user_data_dir())
	if device_is_steam_frame and settings_controller:
		_log("[SPOTS] Saved default spots: %s" % settings_controller.spots_text())
	var cfg := ConfigFile.new()
	cfg.load("user://build.cfg")
	var last: String = cfg.get_value("build", "last", "")
	if last == build:
		return
	cfg.set_value("build", "last", build)
	cfg.save("user://build.cfg")
	await get_tree().create_timer(3.0).timeout
	if last.is_empty():
		comp.show_notice(Localization.t("Welcome to Nightfall (build %s).") % build, 5.0)
	else:
		comp.show_notice(Localization.t("Nightfall updated to build %s.") % build, 5.0)

func _init_textures_and_ui():
	var saved_ip = ""
	if config_mgr:
		config_mgr.load_config()
		var save = ConfigFile.new()
		if save.load("user://last_connection.cfg") == OK:
			saved_ip = save.get_value("connection", "ip", "")
			var saved_unique_id: String = save.get_value("connection", "server_unique_id", "")
			if saved_ip != "":
				%IPInput.text = saved_ip
				# The field can hold "ip:port"; localaddress and
				# detect_polaris_host() need the bare ip, see parse_ip_port().
				var saved_host_ip: String = parse_ip_port(saved_ip)[0]
				# Match by server_unique_id first (2026-08-27) - a host reached
				# via NAT port-forwarding can share a bare IP with a different,
				# already-paired host (see stream_manager.gd's
				# on_pair_completed() fix). Fall back to bare-IP matching only
				# if no unique_id was saved (e.g. an older last_connection.cfg).
				if not saved_unique_id.is_empty():
					for h in config_mgr.get_hosts():
						if h.get("server_unique_id", "") == saved_unique_id:
							current_host_id = h.id
							break
				if current_host_id < 0:
					current_host_id = SavedHosts.pick(config_mgr.get_hosts(), -1, saved_host_ip).get("id", -1)
				# After the PC is known: its saved settings are filed under its
				# identity, not its address (SavedHosts.settings_section()).
				state_manager.load_host_state(saved_ip)
				if current_host_id >= 0:
					settings_controller.detect_polaris_host(saved_host_ip, current_host_id)
				welcome_screen.update_welcome_info()

	stream_manager.bind_texture()
	# Saved host layouts can replace primary after the boot-time binding.
	# Bind the welcome image to the final screen, not its retired predecessor.
	if comp.available:
		comp.connect_welcome_texture()
	if screen_mesh.material_override is ShaderMaterial:
		screen_mesh.material_override.set_shader_parameter("main_texture", get_welcome_content_texture())
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var _wt = get_welcome_content_texture()

	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ui_controller.update_ui()
	ui_controller.update_stereo_shader()
	# Layout restoration preserves panel world transforms and saves offsets.
	# At boot those are uninitialized; first opening must use the left anchor.
	_ui_has_saved_offset = false
	session_lifecycle.show_server_selection()

func _try_auto_connect():
	if pcvr_test.is_exclusive(): return
	var saved_ip = parse_ip_port(%IPInput.text)[0]
	var saved_unique_id: String = ""
	var save = ConfigFile.new()
	if save.load("user://last_connection.cfg") == OK:
		saved_unique_id = save.get_value("connection", "server_unique_id", "")
	var v2_cm = stream_backend.get_config_manager()
	if v2_cm:
		var v2_hosts = v2_cm.get_hosts()
		if v2_hosts.size() > 0:
			var h: Dictionary = {}
			# Match by server_unique_id first (2026-08-27) - see
			# _init_textures_and_ui()'s identical fix above for why bare-IP
			# matching alone can pick the wrong host (NAT port-forwarding
			# sharing one IP across different, already-paired servers).
			if not saved_unique_id.is_empty():
				for candidate in v2_hosts:
					if candidate.get("server_unique_id", "") == saved_unique_id:
						h = candidate
						break
			if h.is_empty():
				for candidate in v2_hosts:
					if candidate.get("localaddress", "") == saved_ip:
						h = candidate
						break
			if h.is_empty():
				h = v2_hosts[0]
			var host_ip = h.get("localaddress", "") if h.has("localaddress") else saved_ip
			var host_id = h.get("id", -1) if h.has("id") else -1
			if host_id != -1 and host_ip != "":
				current_host_id = host_id
				%IPInput.text = host_ip
				_log("[AUTO-CONNECT] Auto-connecting to host_id=%d ip=%s" % [host_id, host_ip])
				pcvr_test.auto_connect_pending = true
				await get_tree().create_timer(1.0).timeout
				pcvr_test.auto_connect_pending = false
				if pcvr_test.is_exclusive(): return
				# Connect was pressed during that second: that connection stands.
				if StreamManager.connection_under_way(session_lifecycle.phase):
					_log("[AUTO-CONNECT] Left out: a connection was started by hand meanwhile")
					return
				stream_manager.start_stream(host_id, _selected_app_id)

func _post_ready_check():
	await get_tree().create_timer(0.5).timeout
	# Browser activation is user-driven. Automated rendering probes must not
	# leave the app running in a different source when handed back for testing.



func _on_joy_changed(device: int, connected: bool):
	input_handler.on_joy_connection_changed(device, connected)

func get_welcome_content_texture() -> Texture2D:
	if browser_prototype and browser_prototype.active and browser_prototype.texture:
		return browser_prototype.texture
	return welcome_viewport.get_texture()

func browser_content_active() -> bool:
	return browser_prototype != null and browser_prototype.active and browser_prototype.texture != null

func primary_media_active() -> bool:
	if screen_sources != null and screen_sources.switching_primary: return false
	return is_streaming or browser_content_active()

func primary_capture_source():
	return browser_prototype.uploader if browser_content_active() else stream_backend

func primary_media_size() -> Vector2i:
	if browser_content_active():
		return browser_prototype.render_size
	return Vector2i(stream_backend.get_video_width(), stream_backend.get_video_height())
# Steam Frame fix: the GLES SurfaceTexture path puts already-converted RGB in
# tex_y with no U/V planes. TextureUploader::update_colorspace() keeps resetting
# color_matrix_type to the stream's YUV matrix on its own material, which the
# shader then applies to RGB (white U/V samplers -> pink tint). Re-assert RGB
# passthrough (3) every frame on every material that samples tex_y.
var _sf_rgb_logged := false
func _steam_frame_force_rgb_passthrough() -> void:
	if not device_is_steam_frame or not is_streaming or not stream_backend:
		return
	var mats: Array = []
	var bm = stream_backend.get_shader_material()
	if bm is ShaderMaterial:
		mats.append(bm)
	for s in screens:
		if s and s.material_override is ShaderMaterial:
			mats.append(s.material_override)
		if comp:
			for m in comp.get_shader_mats(s):
				if m is ShaderMaterial:
					mats.append(m)
	for m in mats:
		if m.get_shader_parameter("tex_y") != null and m.get_shader_parameter("tex_u") == null and m.get_shader_parameter("color_matrix_type") != 3:
			m.set_shader_parameter("color_matrix_type", 3)
			if not _sf_rgb_logged:
				_sf_rgb_logged = true
				_log("[SF-COLOR] Forcing RGB passthrough on GLES SurfaceTexture material")

# Steam Frame flat-screen sharpness: SteamVR has no cylinder layers, so the
# screen is a mesh in the projection layer and gets resampled twice. For a FLAT
# screen, show the stream picture as a quad composition layer instead, placed
# over the screen as an underlay with a hole punched in the projection layer,
# so menus, pointer and grab bar still draw in front. Curved keeps the mesh.
#
# The layer is bound to its OWN fixed-size SubViewport (a copy of
# stream_viewport), never to stream_viewport itself: binding a layer takes over
# the viewport's render target, and Nightfall resizes stream_viewport on every
# resolution change, which crashed the GL thread (fix10/fix11). This viewport
# is created once and never resized; the quad is sized to the screen mesh, so
# the stretched copy keeps the stream's aspect ratio.
const SF_QUAD_VP_SIZE := Vector2i(3840, 2160)
var _sf_quad: OpenXRCompositionLayerQuad = null
var _sf_vp: SubViewport = null
var _sf_rect: TextureRect = null
var _sf_quad_failed := false
var _sf_quad_active := false
var _sf_screen_layers := 1

func _steam_frame_flat_quad_create() -> bool:
	_sf_vp = SubViewport.new()
	_sf_vp.name = "SteamFrameQuadViewport"
	_sf_vp.size = SF_QUAD_VP_SIZE
	_sf_vp.disable_3d = true
	_sf_vp.transparent_bg = false
	_sf_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_sf_vp)
	_sf_rect = TextureRect.new()
	_sf_rect.name = "SteamFrameQuadCopy"
	_sf_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sf_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_sf_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sf_rect.position = Vector2.ZERO
	_sf_rect.size = Vector2(SF_QUAD_VP_SIZE)
	_sf_rect.texture = stream_viewport.get_texture()
	_sf_vp.add_child(_sf_rect)
	_sf_quad = OpenXRCompositionLayerQuad.new()
	_sf_quad.name = "SteamFrameFlatQuad"
	_sf_quad.set_sort_order(-1)
	_sf_quad.set_enable_hole_punch(true)
	_sf_quad.set_alpha_blend(false)
	_sf_quad.visible = false
	xr_origin.add_child(_sf_quad)
	if not _sf_quad.is_natively_supported():
		_log("[SF-QUAD] Quad layer not supported; keeping mesh screen")
		return false
	_sf_quad.set_layer_viewport(_sf_vp)
	_log("[SF-QUAD] Flat screen quad layer created (own %dx%d viewport)" % [SF_QUAD_VP_SIZE.x, SF_QUAD_VP_SIZE.y])
	return true

func _steam_frame_flat_quad_update() -> void:
	if not device_is_steam_frame or _sf_quad_failed or not is_xr_active:
		return
	var s = primary_screen
	var want: bool = is_streaming and s != null and s.curvature == 0 \
		and stream_viewport != null and screens.size() == 1 \
		and settings_controller != null and settings_controller.get_stereo_mode() == 0 \
		and not (comp != null and comp.in_use)
	if want and _sf_quad == null:
		if not _steam_frame_flat_quad_create():
			_sf_quad_failed = true
			return
	if _sf_quad == null:
		return
	if want:
		var t: Transform3D = s.global_transform
		_sf_quad.global_transform = Transform3D(t.basis.orthonormalized(), t.origin)
		_sf_quad.set_quad_size(s.mesh_size)
		if stream_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if _sf_vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			_sf_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if s.layers != 0:
			_sf_screen_layers = s.layers
			s.layers = 0
		if not _sf_quad.visible:
			_sf_quad.visible = true
		if not _sf_quad_active:
			_sf_quad_active = true
			_log("[SF-QUAD] Flat screen now shown as quad layer (stream %dx%d)" % [stream_viewport.size.x, stream_viewport.size.y])
	elif _sf_quad_active:
		_sf_quad.visible = false
		_sf_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if s:
			s.layers = _sf_screen_layers
		_sf_quad_active = false
		_log("[SF-QUAD] Back to mesh screen")

func _process(delta):
	# A frame that took this long is a visible stall; say so in the log, so
	# "the picture went away for a moment" can be matched to what was going on.
	if delta > 0.15 and is_streaming:
		_log("[HITCH] a frame took %d ms" % int(delta * 1000.0))
	if _startup_ready and is_xr_active: _process_startup_hand_fallback(delta)
	if _startup_ready and controller_mapper: controller_mapper.update_available_hands(delta)
	if welcome_screen: welcome_screen.process_auto_xr(delta)
	pcvr_test.process_standby(delta)
	pcvr_handover.process(delta)
	if ui_visible: ui_controller.process_pcvr_menu(delta)
	if pcvr_handover.menu_only and not pcvr_handover.blocks_workspace():
		# Settings-only presentation must not run ordinary screen/ambient/grab
		# updates which would reactivate hidden desktop layers behind the menu.
		# Ownership and hand poses still need updating: controllers may have
		# replaced hands while the XR game owned input and this loop was skipped.
		if is_xr_active: _process_hand_tracking(delta)
		_process_controller_fade(delta)
		xr_interaction.process_pointer_frame(delta)
		_update_cursor_layer()
		_sync_composition_panels()
		_sync_interaction_viewports()
		_update_laser_layers()
		return
	if pcvr_test.is_exclusive() or pcvr_handover.blocks_workspace():
		if pcvr_test.is_exclusive(): pcvr_test.process(delta)
		_log_flush_timer += delta
		if _log_flush_timer >= 2.0:
			_log_flush_timer = 0.0
			_flush_log()
		return
	if browser_prototype:
		browser_prototype.process()
	if screen_sources:
		screen_sources.process_secondary_browsers()
	_steam_frame_force_rgb_passthrough()
	_steam_frame_flat_quad_update()
	if is_xr_active:
		_process_hand_tracking(delta)

	if DEBUG_RENDER_MODEL_CONTROLLERS:
		_process_render_model_controllers(delta)

	_log_flush_timer += delta
	if _log_flush_timer >= 2.0:
		_log_flush_timer = 0.0
		_flush_log()

	_process_button_input()
	if pcvr_test.is_exclusive():
		pcvr_test.process(0.0)
		return

	if right_click_cooldown > 0.0:
		right_click_cooldown -= delta

	_process_input_release()
	_process_xr_surface_refresh()
	# Resolve controller rest/wake before selecting the pointer and drawing
	# beams, so a pickup takes effect in this frame rather than the next.
	_process_controller_fade(delta)

	if device_is_steam_frame and is_xr_active:
		_process_head_lock(delta)
		_process_click_haptics()
		# Eye tracking isn't used for anything yet; Nightfall only notes in its
		# log whether the headset provides it (for future features).
		if eye_gaze == null:
			eye_gaze = EyeGaze.new(self)
		eye_gaze.log_status()

	xr_interaction.process_pointer_frame(delta)
	# A welcome click can enter exclusivity inside pointer dispatch. Finish
	# this frame without ordinary code re-enabling composition/UI layers.
	if pcvr_test.is_exclusive():
		pcvr_test.process(0.0)
		return
	xr_interaction.handle_scroll()
	# Without OpenXR (--nf-no-xr, desktop testing) there are no composition
	# layers to update.
	if comp:
		_update_cursor_layer()
		_sync_composition_panels()
		_sync_interaction_viewports()
		_update_laser_layers()
		_update_marker_layers(delta)
		_update_hand_indicator_layers()
		_update_grab_bar_layers()
		_sync_comp_background()
		comp.process_frame_curve()
		comp.process_ambient(delta)

	_process_background_follow()

	auto_detect.process(delta)

	if depth_estimator:
		depth_estimator.process(delta)
		if depth_estimator.depth_texture and settings.host.ai_3d_speed > 0 and comp and comp.in_use:
			var dt = depth_estimator.depth_texture
			if comp_shader_mat_left and not comp_shader_mat_left.get_shader_parameter("depth_texture"):
				comp_shader_mat_left.set_shader_parameter("depth_texture", dt)
			if comp_shader_mat_right and not comp_shader_mat_right.get_shader_parameter("depth_texture"):
				comp_shader_mat_right.set_shader_parameter("depth_texture", dt)

	if meteor_microphone:
		meteor_microphone.process()

	_process_stats(delta)

	if grabbed_node:
		xr_interaction.handle_grab()

	if grabbed_corner_idx >= 0:
		xr_interaction.handle_corner_resize()

	if _startup_cover:
		if _startup_ready and _startup_reposition == -1:
			_debug_log_cyl("cover_removed")
			_startup_cover.queue_free()
			_startup_cover = null
			_log("[COVER] Startup cover removed")


func _prepare_fade_materials(side: String):
	var hand = right_hand if side == "right" else left_hand
	if not hand:
		return
	_fade_materials[side].clear()
	_collect_fade_materials(hand, _fade_materials[side])

func _collect_fade_materials(node: Node, result: Array):
	for child in node.get_children():
		if child is MeshInstance3D and child.name != "Laser":
			var mi := child as MeshInstance3D
			if mi.mesh:
				for surface_idx in mi.mesh.get_surface_count():
					var source := mi.get_active_material(surface_idx) as BaseMaterial3D
					if source:
						var material := source.duplicate() as BaseMaterial3D
						material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						mi.set_surface_override_material(surface_idx, material)
						result.append(material)
		_collect_fade_materials(child, result)

func _set_hand_alpha(side: String, alpha: float):
	if is_equal_approx(_hand_alpha[side], alpha):
		return
	_hand_alpha[side] = alpha
	for material: BaseMaterial3D in _fade_materials[side]:
		var c = material.albedo_color
		c.a = alpha
		material.albedo_color = c

func _hand_has_activity(hand: XRController3D, side: String) -> bool:
	if not hand:
		return false
	# Local poses exclude movement/recentering of the shared XR origin,
	# which otherwise wakes BOTH controllers when only one was picked up.
	var pos = hand.position
	var rot = hand.rotation
	var pressed := hand.get_float("trigger") > 0.1 or hand.get_float("grip") > 0.1 \
		or hand.is_button_pressed("ax_button") or hand.is_button_pressed("by_button")
	var vec = hand.get_vector2("primary")
	pressed = pressed or absf(vec.x) > 0.1 or absf(vec.y) > 0.1
	if not _controller_pose_initialized.has(side):
		_controller_pose_initialized[side] = true
		if side == "right":
			xr_interaction._last_known_right_pos = pos
			xr_interaction._last_known_right_rot = rot
		else:
			xr_interaction._last_known_left_pos = pos
			xr_interaction._last_known_left_rot = rot
		return pressed
	var last_pos = xr_interaction._last_known_right_pos if side == "right" else xr_interaction._last_known_left_pos
	var last_rot = xr_interaction._last_known_right_rot if side == "right" else xr_interaction._last_known_left_rot
	var resting := right_hand_resting if side == "right" else left_hand_resting
	# Resting controllers need deliberate motion, not small tracking jitter.
	# Keep the baseline until activity so slow pickup motion accumulates.
	var moved = last_pos.distance_squared_to(pos) > (0.0001 if resting else 0.00001)
	var rotated = Basis.from_euler(last_rot).get_rotation_quaternion().angle_to(
		Basis.from_euler(rot).get_rotation_quaternion()) > (0.035 if resting else 0.01)
	if not moved and not rotated and not pressed:
		return false
	if side == "right":
		xr_interaction._last_known_right_pos = pos
		xr_interaction._last_known_right_rot = rot
	else:
		xr_interaction._last_known_left_pos = pos
		xr_interaction._last_known_left_rot = rot
	return true

const HAND_REST_THRESHOLD := 4.0

# Steam Frame, Cursor Follow: Capacitive Touch: a controller no hand is on rests at once
# and stays resting however it moves (in a lap it moves with you), until a
# finger is back on it. See ControllerTouch.
var controller_touch: ControllerTouch = null
var _hand_put_down := {"left": false, "right": false}

func _hand_inactive_time(side: String, hand: XRController3D, inactive_time: float, delta: float) -> float:
	var put_down := false
	if controller_touch:
		controller_touch.update(side, hand, delta)
		# Only with Cursor Follow: Capacitive Touch. Off and Standard never
		# use the touch sensors, whatever the Cursor Type.
		put_down = settings.cursor_follow and settings.sleep_when_put_down \
			and controller_touch.put_down(side)
	if put_down != _hand_put_down[side]:
		_hand_put_down[side] = put_down
		_log("[TOUCH] %s controller: %s" % [side, "no finger on it: asleep" if put_down else "a finger is back on it: awake"])
		if not put_down:
			return 0.0  # awake at once, without waiting for it to be moved
	if put_down:
		return maxf(inactive_time + delta, HAND_REST_THRESHOLD)
	if _hand_has_activity(hand, side):
		return 0.0
	return inactive_time + delta
var right_hand_resting: bool = false
var left_hand_resting: bool = false
var _controller_pose_initialized: Dictionary = {}

func _raycast_points_at_stream(raycast: RayCast3D) -> bool:
	if not raycast or not raycast.enabled or not raycast.is_colliding():
		return false
	return PointerTarget.resolve(raycast.get_collider()).role == &"screen"

func _process_controller_fade(delta: float):
	if _is_using_hands or not is_xr_active:
		return
	if _controller_pose_initialized.is_empty():
		_apply_hand_rest("right", true)
		_apply_hand_rest("left", true)
	xr_interaction._right_inactive_time = _hand_inactive_time("right", right_hand, xr_interaction._right_inactive_time, delta)
	xr_interaction._left_inactive_time = _hand_inactive_time("left", left_hand, xr_interaction._left_inactive_time, delta)
	_apply_hand_fade("right", xr_interaction._right_inactive_time, delta)
	_apply_hand_fade("left", xr_interaction._left_inactive_time, delta)
	# A controller placed down should rest regardless of where its last ray
	# pointed (menu, keyboard, screen or empty space). Movement/buttons wake
	# each controller independently on the next activity check.
	_apply_hand_rest("right", xr_interaction._right_inactive_time >= HAND_REST_THRESHOLD \
		or (tracking_guard != null and tracking_guard.is_lost("right")))
	_apply_hand_rest("left", xr_interaction._left_inactive_time >= HAND_REST_THRESHOLD \
		or (tracking_guard != null and tracking_guard.is_lost("left")))

func _apply_hand_fade(side: String, inactive_time: float, delta: float):
	var lost: bool = tracking_guard != null and tracking_guard.is_lost(side)
	var target_alpha = 1.0 if inactive_time < HAND_REST_THRESHOLD and not lost else 0.02
	var new_alpha = move_toward(_hand_alpha[side], target_alpha, delta * 2.0)
	_set_hand_alpha(side, new_alpha)

func _apply_hand_rest(side: String, resting: bool):
	var was_resting = right_hand_resting if side == "right" else left_hand_resting
	if resting == was_resting:
		return
	if side == "right":
		right_hand_resting = resting
		if hand_raycast: hand_raycast.enabled = not resting
	else:
		left_hand_resting = resting
		if left_hand_raycast: left_hand_raycast.enabled = not resting
	if not resting and controller_mapper and controller_mapper.effective_primary_hand() == ControllerMapper.PrimaryHand.AUTO \
			and not was_clicking and not was_right_clicking and not grabbed_node and grabbed_corner_idx < 0:
		xr_interaction._auto_primary = side
		xr_interaction._active_hand = side
	_log("[HAND] %s controller %s" % [side, "resting (disabled)" if resting else "picked up (re-enabled)"])

func _process_hand_tracking(_delta):
	var hands_active = get_is_hand_tracking() and get_hand_tracking_has_data()
	# Aim trackers exist throughout the session, including controller use.
	# A physical button press must never be routed into the hand-pinch path.
	for controller in [right_hand, left_hand]:
		if controller and (controller.get_float("trigger") > 0.1 or controller.get_float("grip") > 0.1
				or controller.is_button_pressed("ax_button") or controller.is_button_pressed("by_button")):
			hands_active = false
	if hands_active != _is_using_hands:
		xr_interaction.cancel_transient_interactions("hand/controller ownership changed")
		_log("[HAND] ownership=%s runtime_aim=%s tracking_mode=%d" % ["hands" if hands_active else "controllers", xr_interaction.hand_aim_available(), settings.tracking_mode])
		_is_using_hands = hands_active
		if _is_using_hands:
			# The controller nodes below are about to be overwritten with hand
			# joints. Preserve the physical controllers' last positions for their
			# resting markers, and ensure both hand pointers are available even if
			# controller-idle detection had disabled one of their shared raycasts.
			composition_controller_markers.capture_controller_positions(right_hand, left_hand)
			if hand_raycast:
				hand_raycast.enabled = true
			if left_hand_raycast:
				left_hand_raycast.enabled = true
			_log("[INPUT] Hand Tracking active, hiding controller models")
			_set_controller_models_visible(false)
		else:
			# Controllers have taken ownership of these nodes/rays again. Restart
			# inactivity detection from an unambiguous active state.
			right_hand_resting = false
			left_hand_resting = false
			xr_interaction._right_inactive_time = 0.0
			xr_interaction._left_inactive_time = 0.0
			if hand_raycast:
				hand_raycast.top_level = false
				hand_raycast.transform = Transform3D.IDENTITY
				hand_raycast.enabled = true
			if left_hand_raycast:
				left_hand_raycast.top_level = false
				left_hand_raycast.transform = Transform3D.IDENTITY
				left_hand_raycast.enabled = true
			_log("[INPUT] Controllers active, showing controller models")
			_set_controller_models_visible(true)

	if _is_using_hands:
		var right_tracker = XRServer.get_tracker("/user/hand_tracker/right")
		var left_tracker = XRServer.get_tracker("/user/hand_tracker/left")
		if right_tracker:
			_update_hand_tracker_transform(right_hand, right_tracker)
		if left_tracker:
			_update_hand_tracker_transform(left_hand, left_tracker)
		var menu_tracker = XRServer.get_tracker("/user/fbhandaim/left")
		var menu_pressed := menu_tracker != null and bool(menu_tracker.get_input("menu_pressed"))
		if menu_pressed and not _hand_menu_pressed:
			screen_shortcuts.invoke(ScreenShortcutBar.ACTION_MENU)
		_hand_menu_pressed = menu_pressed
		if xr_interaction.hand_aim_available() and not xr_interaction.hand_aim_valid(xr_interaction._active_hand):
			xr_interaction.cancel_transient_interactions()
	else:
		_hand_menu_pressed = false

func _process_button_input():
	if not is_xr_active:
		return
	if button_bindings:
		button_bindings.process()
	if button_bindings and button_bindings.owns_buttons():
		pass # A, B and stick clicks are handled by ButtonBindings (Steam Frame)
	else:
		var side: String = xr_interaction._active_hand if controller_mapper and controller_mapper.effective_primary_hand() == ControllerMapper.PrimaryHand.AUTO else ("left" if controller_mapper and controller_mapper.effective_primary_hand() == ControllerMapper.PrimaryHand.LEFT else "right")
		var hand = left_hand if side == "left" else right_hand
		var other = right_hand if side == "left" else left_hand
		var menu: bool = hand != null and hand.is_button_pressed("by_button")
		var keyboard: bool = hand != null and hand.is_button_pressed("ax_button")
		var stick: bool = hand != null and hand.is_button_pressed("primary_click")
		var other_stick: bool = other != null and other.is_button_pressed("primary_click")
		var blocked: bool = _is_using_hands or (controller_mapper != null and controller_mapper.is_active())
		var trackpad_blocked: bool = virtual_keyboard != null and (virtual_keyboard.trackpad_active or virtual_keyboard.thumbstick_exit_flag)
		for action in primary_controller_shortcuts.poll(side, menu, keyboard, stick, other_stick, blocked, trackpad_blocked):
			screen_shortcuts.invoke(action)
		if not stick and virtual_keyboard: virtual_keyboard.thumbstick_exit_flag = false
	if _startup_reposition >= 0 and is_xr_active:
		match _startup_reposition:
			0:  # Waiting for tracking to produce a meaningful camera position
				if xr_camera.global_position.length_squared() > 0.01:
					_startup_reposition = 1
					_startup_last_cam = xr_camera.global_position
					_startup_still_frames = 0
			1:  # Wait for tracking to stabilize
				if not device_is_steam_frame:
					_startup_reposition = 2
				else:
					# Steam Frame: the first poses can be stale or jump while
					# SteamVR settles, which left the screen off to the side.
					# Wait for about a third of a second of steady head pose.
					var cp: Vector3 = xr_camera.global_position
					if cp.distance_to(_startup_last_cam) < 0.02:
						_startup_still_frames += 1
					else:
						_startup_still_frames = 0
					_startup_last_cam = cp
					# ...and for the saved settings: _ready() loads them after
					# an await, and this used to win the race, so Start
					# Distance and At Launch: Same Spot were still at their
					# defaults when the screen was placed (5j log).
					if _startup_still_frames >= 30 and _state_loaded:
						_startup_reposition = 2
			2:  # Position screen in front of user
				_reposition_screen_and_ui(true)
				if device_is_steam_frame:
					if settings.keep_room_position and _saved_room_transform is Transform3D:
						_move_screen_group(_saved_room_transform)
						_log("[POS] Keeping last session's room position")
					else:
						# In front of where you're looking, even lying down.
						_move_screen_group(_transform_in_view(settings.screen_start_distance))
						_log("[POS] Launch: screen placed where you're looking")
				_startup_reposition = -1

# Quitting: the depth receiver's thread must end before the scripts are
# unloaded (it ended in a script error and an unfinished Thread otherwise).
func _exit_tree() -> void:
	if depth_estimator and depth_estimator.meteor:
		depth_estimator.meteor.stop()

func reset_primary_shortcuts() -> void:
	primary_controller_shortcuts.reset()

func _process_input_release():
	if Input.is_action_just_pressed("ui_focus_next"):
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()

	if Input.is_key_pressed(KEY_CTRL) and Input.is_key_pressed(KEY_ALT) and Input.is_key_pressed(KEY_SHIFT):
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()

func _process_idle_activity():
	if not is_streaming or settings.idle_timeout_min <= 0:
		return
	if right_hand:
		var trigger = right_hand.get_float("trigger")
		var primary = right_hand.get_float("primary")
		var grip = right_hand.get_float("grip")
		if trigger > 0.1 or primary > 0.1 or grip > 0.1:
			_last_activity_time = Time.get_ticks_msec() / 1000.0
	if left_hand:
		var l_trigger = left_hand.get_float("trigger")
		var l_primary = left_hand.get_float("primary")
		var l_grip = left_hand.get_float("grip")
		if l_trigger > 0.1 or l_primary > 0.1 or l_grip > 0.1:
			_last_activity_time = Time.get_ticks_msec() / 1000.0

func _process_background_follow():
	if not is_xr_active:
		return
	for i in range(bg_names.size()):
		var bg = get_node_or_null(bg_names[i])
		if bg and bg.visible:
			bg.global_position = xr_camera.global_position + bg_offsets[i]
			break
	# Position-only follow (2026-08-24), matching the real particle
	# systems above - comp_bg_equirect's rotation deliberately stays fixed
	# (world-locked skybox feel, not spinning with head-look) while its
	# position re-centers on the camera every frame, same as the
	# GPUParticles3D backgrounds re-centering via bg_offsets.
	if comp_bg_equirect and comp_bg_equirect.visible:
		comp_bg_equirect.global_position = xr_camera.global_position

# Keeps comp_bg_capture_instance in sync with the currently selected
# background (settings.background_mode) and shows/hides comp_bg_equirect to match
# whether an environment background should currently be visible (passthrough
# off, a background selected, in composition mode). Called from
# apply_background()/apply_passthrough() on real transitions, and also every
# frame from _process() as a safety net (e.g. entering/leaving composition
# mode without touching background/passthrough settings) - safe because the
# work below only runs on an actual state change (bg_idx/want_visible), and
# Unlike the pointer layers, this never repeatedly toggles the composition
# background's visibility.
# once shown, so it doesn't hit the swapchain-teardown crash from earlier.
func _sync_comp_background():
	if not comp_bg_equirect or not comp_bg_capture_viewport:
		return
	var bg_idx = settings.background_mode - 1
	var want_visible = DEBUG_COMP_BG_EQUIRECT and comp.available and comp.in_use and is_xr_active and not settings.passthrough_enabled and bg_idx >= 0 and bg_idx < bg_names.size()
	if not want_visible:
		if comp_bg_equirect.visible:
			comp_bg_equirect.visible = false
		if comp_bg_capture_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			comp_bg_capture_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if comp_bg_capture_instance:
			comp_bg_capture_instance.queue_free()
			comp_bg_capture_instance = null
			comp_bg_capture_index = -1
		return
	if comp_bg_capture_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		comp_bg_capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if bg_idx != comp_bg_capture_index:
		if comp_bg_capture_instance:
			comp_bg_capture_instance.queue_free()
			comp_bg_capture_instance = null
		comp_bg_capture_instance = bg_manager.create_capture_instance(bg_idx, comp_bg_capture_viewport)
		comp_bg_capture_instance.visible = true
		comp_bg_capture_instance.emitting = true
		comp_bg_capture_index = bg_idx
	if not comp_bg_equirect.visible:
		comp_bg_equirect.visible = true

func _process_stats(delta):
	# Deliberately ahead of the is_streaming early-return below - USB Link's
	# status has to be visible on the welcome screen (that's the whole point
	# of the toggle: know it's "Up" before trying to connect over it), not
	# just while a stream using it is already running.
	settings_controller.poll_usb_link_status(delta)
	# Also ahead of it: the network is watched hardest after a stream is lost.
	if device_is_steam_frame:
		_log_network(_network_watch.tick(delta, is_streaming, stream_manager.stream_host_address))
	if not is_streaming:
		telemetry.record_frame(delta, browser_content_active() and browser_prototype.new_frame)
		if telemetry.status_update_due(delta, 1.0) and ui_controller:
			ui_controller.refresh_app_fps()
		if browser_content_active() and video_presentation:
			video_presentation.process_frame(browser_prototype.new_frame)
		if comp:
			comp.set_stats_visible(false)
		return
	if comp.in_use:
		var cur_sharpen = float(settings.sharpen_mode) * 0.5
		var cur_blur_scale = get_blur_scale(primary_screen)
		if cur_sharpen != _cached_sharpen or cur_blur_scale != _cached_blur_scale:
			_cached_sharpen = cur_sharpen
			_cached_blur_scale = cur_blur_scale
			settings_controller.apply_filter()
	var new_video_frame := stream_backend != null and stream_backend.consume_new_frame()
	if video_presentation:
		video_presentation.process_frame(new_video_frame)
	if device_is_steam_frame:
		_sample_frame_cost()
	var frame_sample := telemetry.record_frame(delta, new_video_frame)
	if not frame_sample.is_empty():
		settings_controller.on_performance_sample(frame_sample)
		# Diagnostic (2026-09-06): video update FPS is inherently capped at app
		# FPS (consume_new_frame() can report at most one "yes" per
		# script tick, no matter how many render-thread completions happened
		# since the last tick) - now that decode-thread throughput and native
		# render cost are both confirmed to track target Hz closely, this
		# checks whether the script tick rate itself is also
		# hitting target, and exactly how close video_update_fps tracks it.
		_log("[STATS] app=%.1ffps video_update=%.1ffps (%.1f%% of app) frames=%d/%d" % [
			frame_sample["app_fps"], frame_sample["video_update_fps"],
			100.0 * frame_sample["video_update_fps"] / maxf(frame_sample["app_fps"], 0.001),
			frame_sample["video_updates"], frame_sample["app_frames"]])
		if device_is_steam_frame:
			_log_frame_cost()
			_log_network(_network_watch.video_second(int(frame_sample["video_updates"]), stream_manager.stream_host_address))
			_second_link_tick()
			_power_watch.sample()
			_power_wait -= 1
			if _power_wait <= 0:
				_power_wait = POWER_LOG_SECONDS
				_log("[POWER] %s %s" % [Time.get_time_string_from_system(), _power_watch.line()])
			_camera_check_wait -= 1
			if _camera_check_wait <= 0:
				_check_addon_cameras()
			elif _camera_check_wait % CAMERA_IN_USE_SECONDS == 0:
				settings_controller.check_addon_in_use()
	if telemetry.status_update_due(delta):
		stream_manager.update_stats()
	_process_performance_overlay(delta)

# Steam Frame: a camera add-on can be fitted or taken off while Nightfall
# runs, so it is looked for again every 20 seconds (SettingsController's
# Camera FPS Limit depends on it).
const CAMERA_CHECK_SECONDS := 20
## Which camera is running is looked at more often: the hitching starts the
## moment the add-on's camera takes over.
const CAMERA_IN_USE_SECONDS := 3
var _camera_check_wait := 0

func _check_addon_cameras() -> void:
	_camera_check_wait = CAMERA_CHECK_SECONDS
	settings_controller.refresh_addon_cameras()

# Steam Frame: the stream's second link (FrameSecondLink).
# The two links' names and the PC's address on the second, once this stream's
# Meteor has been found there; the counts at the last log line; a number that
# tells an old "is that the same Meteor?" answer from a current one.
var _second_link_names: Array = []
var _second_link_address := ""
var _second_link_before: Dictionary = {}
var _second_link_wait := 0.0
var _second_link_generation := 0
# While it isn't found: the reason last logged, the wait until the next look,
# and whether a look is under way.
const SECOND_LINK_RETRY_SECONDS := 5.0
var _second_link_why := ""
var _second_link_retry_wait := 0.0
var _second_link_searching := false
# Keeping the choice in step with Meteor's own menu: the number of the last
# pick made there that this headset has seen (-1: not looked yet) and the
# wait until the next look. (Whether the choice was changed here while Meteor
# couldn't be told is kept with the settings: frame_link_untold.)
const LINK_POLL_SECONDS := 2.0
var _link_rev_seen := -1
var _link_poll_wait := 0.0
var _link_poll_busy := false
# Whether Meteor said it was offering depth the last time it was asked (-1:
# not asked during this stream yet), for following "Host depth" being
# switched off and on in its menu while a stream runs.
var _meteor_depth_flag := -1
var _meteor_depth_busy := false
# How many times in a row asking for the offer hasn't given what Meteor had
# just said (no answer in time, most likely): asked again at the next look,
# three times at most.
var _meteor_depth_retries := 0
# "Adapter first": which link carried the stream a second ago, for the notice
# when that changes, and the counts then.
var _link_carrier := ""
var _link_carrier_counts: Dictionary = {}
# "Adapter first" with a Meteor that takes "both links for now" (0.9.0-sf6):
# the stream library judges the adapter's link itself. How many times it has
# asked for both, and gone back to the adapter alone, that the log knows of;
# and for how many seconds the log has waited to hear how quickly Wi-Fi's
# copies came (-1: not waiting).
var _link_holds_seen := 0
var _link_alones_seen := 0
var _link_hold_answer_wait := -1

## A stream has started: finds this stream's Meteor on the adapter's link,
## then asks it for whatever Stream Link says.
func refresh_second_link() -> void:
	if not device_is_steam_frame or stream_backend == null:
		return
	_second_link_generation += 1
	stream_backend.set_second_link("")
	_second_link_names = []
	_second_link_address = ""
	_second_link_why = ""
	_second_link_retry_wait = SECOND_LINK_RETRY_SECONDS
	_link_carrier = ""
	if is_streaming:
		_find_second_link()

## Looks for this stream's Meteor on the adapter's link. At a stream's start,
## and again every few seconds for as long as it isn't found: a stream that
## starts out of the adapter's reach (7u log: a reconnect two rooms away) must
## pick the adapter up when the headset comes back, not stay on Wi-Fi alone.
func _find_second_link() -> void:
	if _second_link_searching:
		return
	var generation := _second_link_generation
	if not stream_manager.meteor_offers_second_link():
		_second_link_not_found("this stream doesn't pass through Meteor" if stream_manager.meteor_address().is_empty()
			else "the PC's Meteor doesn't offer it (it needs this port's 0.9.0-sf3 or later, or the original's 0.9.1)")
		return
	var found := FrameSecondLink.candidates(stream_manager.meteor_address(),
		FrameNetworkWatch.file_text(FrameNetworkWatch.ROUTES), FrameNetworkWatch.file_text(FrameNetworkWatch.NEIGHBOURS))
	if found.has("why"):
		_second_link_not_found(String(found["why"]))
		return
	var key := stream_manager.meteor_key()
	var candidates: PackedStringArray = found["candidates"]
	_second_link_searching = true
	for address in candidates:
		var info: Dictionary = await stream_manager.probe_meteor_at(address)
		if generation != _second_link_generation or not is_streaming:
			_second_link_searching = false
			return
		# Only the stream's own Meteor is asked for anything: the same key.
		if not key.is_empty() and MeteorClient.meteor_key(info) == key:
			_second_link_searching = false
			_second_link_address = address
			_second_link_names = [found["first_iface"], found["iface"]]
			_log("[LINK] %s this stream's Meteor also answers on %s (the stream itself is on %s)" % [
				Time.get_time_string_from_system(), found["iface"], found["first_iface"]])
			apply_link_mode()
			return
	_second_link_searching = false
	_second_link_not_found("%d answered on %s, none of them this stream's Meteor" % [candidates.size(), found["iface"]])

## Says why there is no second link, once for each reason: the search is
## repeated every few seconds and would fill the log otherwise.
func _second_link_not_found(why: String) -> void:
	if why != _second_link_why:
		_second_link_why = why
		_log("[LINK] %s no second link: %s%s" % [Time.get_time_string_from_system(), why,
			"" if not stream_manager.meteor_offers_second_link() else "; looking again every %d seconds" % int(SECOND_LINK_RETRY_SECONDS)])

## Whether a change of Stream Link made now reaches Meteor: a stream is
## running over both links to a Meteor that keeps the choice, and this headset
## has seen its pick number (the pings carry that number, and Meteor only takes
## the choice from a ping with the current one).
func link_choice_reaches_meteor() -> bool:
	return is_streaming and not _second_link_address.is_empty() and _link_rev_seen >= 0 \
		and stream_manager.meteor_offers_link_sync()

## A stream that passes through Meteor while Meteor isn't offering depth
## (most likely "Host depth" switched off in its tray menu) used to leave
## Meteor out of the Quality choices without a word: a whole session went on
## finding that (2026-11-16). Say it, in the log and on screen.
func _say_if_meteor_offers_no_depth() -> void:
	if stream_manager.meteor_address().is_empty() or not MeteorDepthReceiver.is_supported() \
			or not stream_manager.meteor_depth_info().is_empty():
		return
	_log("[METEOR] This stream passes through Meteor, but Meteor is not offering depth (\"Host depth\" switched off in its menu on the PC, or its depth model not loaded)")
	if depth_estimator != null and depth_estimator.enabled:
		comp.show_notice("Meteor's depth is off on the PC (its menu: Host depth). Using the headset's.", 6.0)

## Meteor's address on the second link for the microphone and the depth maps
## to use as well, "" when they are to stay on the stream's own link: no
## second link, "Wi-Fi only", or a Meteor that would refuse them there.
func side_channel_second_address() -> String:
	if not is_streaming or _second_link_address.is_empty() or settings.frame_link_mode == FrameSecondLink.MODE_FIRST_ONLY \
			or not stream_manager.meteor_offers_side_both():
		return ""
	return _second_link_address

## Stream Link was changed on the headset.
func link_mode_changed() -> void:
	# Said when the choice can't take effect in this stream: it used to change
	# on the button and nothing else, with no word why.
	var note := FrameSecondLink.unavailable_note(is_streaming, stream_manager.through_meteor(),
		stream_manager.meteor_offers_second_link(), not _second_link_address.is_empty(), settings.frame_link_mode)
	if not note.is_empty():
		comp.show_notice(note, 6.0)
	if is_streaming and _second_link_address.is_empty():
		refresh_second_link()
	else:
		apply_link_mode()

## Tells the stream library, and through its pings Meteor, what Stream Link
## says. Needs the PC's address on the second link (refresh_second_link).
func apply_link_mode() -> void:
	if stream_backend == null or _second_link_address.is_empty() or not is_streaming:
		return
	var mode := settings.frame_link_mode
	var label: String = FrameSecondLink.MODE_LABELS[mode]
	_link_carrier = ""
	# Meteor 0.9.0-sf6: on "Adapter first" the library watches the adapter's
	# link and asks for Wi-Fi's copies as well the moment it falters.
	var watched := stream_manager.meteor_offers_link_hold()
	stream_backend.set_second_link_watch(watched)
	# Meteor 0.9.0-sf8: the controls go over both links too, in every choice
	# but "Wi-Fi only", so the stream outlives either link going silent.
	var controls := stream_manager.meteor_offers_control_both() and mode != FrameSecondLink.MODE_FIRST_ONLY
	stream_backend.set_second_link_control(controls)
	_link_holds_seen = 0
	_link_alones_seen = 0
	_link_hold_answer_wait = -1
	if stream_manager.meteor_offers_link_sync():
		# Meteor 0.9.0-sf5: the pings carry the choice and go on in every
		# choice, so that Meteor always knows it (and stops at once for
		# "Wi-Fi only", where an older Meteor took 5 seconds to notice).
		stream_backend.set_second_link_choice(FrameSecondLink.wire_choice(mode), _link_rev_seen)
		stream_backend.set_second_link(_second_link_address)
		_log("[LINK] %s Stream Link: %s (told to Meteor over %s%s%s)" % [Time.get_time_string_from_system(), label, _second_link_names[1],
			"; the headset watches the adapter's link" if watched and mode == FrameSecondLink.MODE_SECOND_ONLY else "",
			"; controls over both links" if controls else ""])
	elif mode == FrameSecondLink.MODE_FIRST_ONLY:
		stream_backend.set_second_link("")
		_log("[LINK] Stream Link: Wi-Fi only (no second link)")
	else:
		# "Adapter first" needs a Meteor that knows the request (sf4); an
		# older one is asked for both links, which it does know.
		var alone := mode == FrameSecondLink.MODE_SECOND_ONLY and stream_manager.meteor_offers_second_link_only()
		stream_backend.set_second_link_choice((1 if alone else 0) if stream_manager.meteor_offers_second_link_only() else -1, -1)
		stream_backend.set_second_link(_second_link_address)
		_log("[LINK] Stream Link: %s (asked of Meteor over %s%s%s)" % [label, _second_link_names[1],
			"" if alone or mode == FrameSecondLink.MODE_BOTH else "; this Meteor only knows both links, so both are used",
			"; the original Meteor's multipath: picture and sound over both links, the rest on %s" % _second_link_names[0]
				if stream_manager.meteor_speaks_plain_second_link() else ""])
	_second_link_before = {}
	_second_link_wait = FrameSecondLink.LOG_SECONDS
	_link_carrier_counts = {}

## Looks at the pick in Meteor's own menu and follows it if it is news.
func _poll_link_pick() -> void:
	if _link_poll_busy:
		return
	_link_poll_busy = true
	var link: Dictionary = await stream_manager.meteor_link_pick()
	_link_poll_busy = false
	if not is_streaming or link.is_empty():
		return
	if link.has("depth") and stream_manager.meteor_offers_depth_live():
		_follow_meteor_depth(bool(link["depth"]))
	var rev := int(link["rev"])
	var news := rev != _link_rev_seen
	var follow := FrameSecondLink.follows_pick(rev, _link_rev_seen, settings.frame_link_untold)
	_link_rev_seen = rev
	var mode := FrameSecondLink.mode_of_wire(int(link["choice"]))
	# A change made here that Meteor hadn't heard of has now had its turn:
	# the pings carry the number just seen, which is what makes Meteor take
	# this headset's choice as the choice.
	var was_untold := settings.frame_link_untold
	settings.frame_link_untold = false
	if follow and mode != settings.frame_link_mode:
		settings.frame_link_mode = mode
		settings_controller._save_setting(_ui_second_link_btn, FrameSecondLink.MODE_LABELS[mode])
		_log("[LINK] Stream Link: %s, picked in Meteor's menu on the PC" % FrameSecondLink.MODE_LABELS[mode])
		comp.show_notice(Localization.t("Stream Link: %s (chosen on the PC)") % Localization.t(FrameSecondLink.MODE_LABELS[mode]), 4.0)
	elif was_untold:
		state_manager.save_state()
	if news:
		apply_link_mode()

## Meteor has just said whether it offers depth at this moment. When that is
## news (it differs from the last time, or at the first look from what the
## stream started with), Meteor is asked for its offer again and the stream
## takes it: Meteor's depth starts or stops without a reconnect. Asked only on
## a change, because that question is one Meteor writes in its log.
func _follow_meteor_depth(offered: bool) -> void:
	var had := not stream_manager.meteor_depth_info().is_empty()
	var news := FrameSecondLink.depth_offer_is_news(_meteor_depth_flag, offered, had)
	_meteor_depth_flag = 1 if offered else 0
	if not news or _meteor_depth_busy:
		return
	_meteor_depth_busy = true
	var has: bool = await stream_manager.refresh_meteor_depth()
	_meteor_depth_busy = false
	if has == offered:
		_meteor_depth_retries = 0
	elif _meteor_depth_retries < 3:
		_meteor_depth_retries += 1
		_meteor_depth_flag = -1
	if not is_streaming or has == had:
		return
	_log("[METEOR] %s Meteor's depth offer changed during the stream: %s" % [Time.get_time_string_from_system(),
		"offered now" if has else "no longer offered (\"Host depth\" switched off in its menu on the PC)"])
	if ui_controller:
		ui_controller.update_3d_btn_state()
	if depth_estimator != null and depth_estimator.enabled:
		if not has:
			comp.show_notice("Meteor's depth is off on the PC (its menu: Host depth). Using the headset's.", 6.0)
		elif settings_controller.meteor_depth_selected():
			comp.show_notice("Meteor's depth is back on. Using it.", 4.0)

## "Adapter first", watched by the stream library: a log line each time it
## asks Meteor for Wi-Fi's copies as well, with how quickly they came, and
## each time it goes back to the adapter alone. These are the figures the 7u
## log lacked (how long each part of a fallback takes).
func _log_link_watch(counts: Dictionary) -> void:
	var now := Time.get_time_string_from_system()
	var holds := int(counts.get("holds", 0))
	if holds > _link_holds_seen:
		_log("[LINK] %s %s" % [now, FrameSecondLink.describe_hold(counts, holds - _link_holds_seen)])
		# And how the adapter's link looked to the headset at that moment.
		var adapter := _network_watch.adapter_line()
		if not adapter.is_empty():
			_log("[NET] %s %s" % [now, adapter])
		_link_hold_answer_wait = -1 if int(counts.get("hold_answered_ms", 0)) > 0 else 0
	elif _link_hold_answer_wait >= 0:
		var answered := int(counts.get("hold_answered_ms", 0))
		_link_hold_answer_wait += 1
		if answered > 0:
			_log("[LINK] %s Wi-Fi's first packet came %d ms after it was asked for" % [now, answered])
			_link_hold_answer_wait = -1
		elif _link_hold_answer_wait >= 10:
			_log("[LINK] %s 10 seconds on, nothing has come over Wi-Fi either" % now)
			_link_hold_answer_wait = -1
	_link_holds_seen = holds
	var alones := int(counts.get("alones", 0))
	if alones > _link_alones_seen:
		_log("[LINK] %s the adapter's link has been steady for 3 seconds: it carries the stream alone" % now)
	_link_alones_seen = alones

## Once a second while a stream runs: the log line, the look at Meteor's menu,
## and for "Adapter first" a notice when the stream changes link.
func _second_link_tick() -> void:
	if stream_manager.meteor_offers_link_sync():
		_link_poll_wait -= 1.0
		if _link_poll_wait <= 0.0:
			_link_poll_wait = LINK_POLL_SECONDS
			_poll_link_pick()
	if _second_link_address.is_empty():
		_second_link_retry_wait -= 1.0
		if _second_link_retry_wait <= 0.0:
			_second_link_retry_wait = SECOND_LINK_RETRY_SECONDS
			_find_second_link()
		return
	var counts: Dictionary = stream_backend.second_link_stats()
	_log_link_watch(counts)
	if settings.frame_link_mode == FrameSecondLink.MODE_SECOND_ONLY and not _link_carrier_counts.is_empty():
		var now_on := FrameSecondLink.carrier(
			int(counts.get("first_link", 0)) - int(_link_carrier_counts.get("first_link", 0)),
			int(counts.get("second_link", 0)) - int(_link_carrier_counts.get("second_link", 0)), _link_carrier)
		if now_on != _link_carrier:
			if not _link_carrier.is_empty():
				_log("[LINK] %s the stream is on %s" % [Time.get_time_string_from_system(),
					"the adapter again" if now_on == "adapter" else "Wi-Fi: the adapter's signal was lost"])
				comp.show_notice("Back on the adapter." if now_on == "adapter" else "Adapter signal lost: streaming over Wi-Fi.", 4.0)
			_link_carrier = now_on
	_link_carrier_counts = counts
	if settings.frame_link_mode == FrameSecondLink.MODE_FIRST_ONLY:
		return
	_second_link_wait -= 1.0
	if _second_link_wait <= 0.0:
		_second_link_wait = FrameSecondLink.LOG_SECONDS
		_log("[LINK] %s %s" % [Time.get_time_string_from_system(),
			FrameSecondLink.describe(counts, _second_link_before, _second_link_names[0], _second_link_names[1])])
		_second_link_before = counts

# Steam Frame: the battery's charge and the power being drawn, in the log,
# this often while a stream runs (see FramePowerWatch for why).
const POWER_LOG_SECONDS := 60
var _power_wait := POWER_LOG_SECONDS
var _power_watch := FramePowerWatch.new()

# Steam Frame: the headset's own network link, in the log. A line a minute
# while a stream runs, one every few seconds after a stream is lost (see
# FrameNetworkWatch for why and for what is deliberately left out).
var _network_watch := FrameNetworkWatch.new()

func _log_network(lines: PackedStringArray) -> void:
	for line in lines:
		_log("[NET] %s %s" % [Time.get_time_string_from_system(), line])

# Steam Frame: what SteamVR has set for this app (refresh rate, motion
# smoothing, resolution). The installer switches motion smoothing off; this
# shows in the log whether that took. Read-only.
func _log_steamvr_app_settings() -> void:
	var app_id := OS.get_environment("SteamAppId")
	var path := OS.get_environment("HOME").path_join(".config/openvr/config/steamvr.vrsettings")
	if app_id == "" or not FileAccess.file_exists(path):
		_log("[STEAMVR] per-app settings: not found (app id '%s')" % app_id)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var block = parsed.get("steam.app." + app_id) if parsed is Dictionary else null
	_log("[STEAMVR] per-app settings for %s: %s" % [app_id, JSON.stringify(block) if block is Dictionary else "none set"])

# Steam Frame diagnostic, temporary (5k). The 5j log had the app at half rate
# (36 fps) with a curved screen and PT Fade, but at 60 to 70 for stretches
# while the menu was being used, with nothing about the screen or the fade
# changed. This writes, once a second beside [STATS], where a frame's time
# goes and what the app was drawing and pointing at, to find the real cause.
var _cost_frames := 0
var _cost_gpu_sum := 0.0
var _cost_gpu_max := 0.0
var _cost_cpu_sum := 0.0
var _cost_measuring := false
var _cost_lines := 0
var _cost_longest := 0.0
var _cost_system: FrameSystemStats = null
var _cost_pictures: Array[SubViewport] = []
var _cost_pictures_gpu_sum := 0.0

func _sample_frame_cost() -> void:
	var view: RID = get_viewport().get_viewport_rid()
	if not _cost_measuring:
		RenderingServer.viewport_set_measure_render_time(view, true)
		_cost_measuring = true
		return
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(view)
	_cost_frames += 1
	_cost_gpu_sum += gpu
	_cost_gpu_max = maxf(_cost_gpu_max, gpu)
	_cost_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(view) + RenderingServer.get_frame_setup_time_cpu()
	_cost_longest = maxf(_cost_longest, get_process_delta_time() * 1000.0)
	# The pictures drawn beside the 3D scene every frame (the flat screen's
	# layer, one per eye with 3D; menus; pointers) have a cost of their own.
	for sub in _cost_pictures:
		if is_instance_valid(sub):
			_cost_pictures_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(sub.get_viewport_rid())

func _log_frame_cost() -> void:
	if _cost_frames == 0:
		return
	var off_ahead := -1.0
	var distance := -1.0
	if xr_camera and primary_screen:
		var to_screen: Vector3 = primary_screen.global_position - xr_camera.global_position
		distance = to_screen.length()
		if distance > 0.01:
			off_ahead = rad_to_deg((-xr_camera.global_transform.basis.z).angle_to(to_screen))
	var in_scene: bool = settings_controller._screen_drawn_in_scene()
	var width := primary_screen.mesh_size.x if primary_screen else 0.0
	if _cost_system == null:
		_cost_system = FrameSystemStats.new()
		_log("[FRAME-COST] system readings: %s" % _cost_system.setup())
	var system := _cost_system.sample()
	_log("[FRAME-COST] gpu %.1f ms (worst %.1f), %d draws | screen %s, %.1f m wide, %.1f m away, %.0f deg from straight ahead | filter %s, sharpen %d | menu %s, keyboard %s | %s, cpu %.1f ms, longest frame %.1f ms, foveation %s, other pictures gpu %.1f ms%s" % [
		_cost_gpu_sum / _cost_frames, _cost_gpu_max,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"in scene" if in_scene else "layer", width, distance, off_ahead,
		("fast" if settings.frame_fast_filter else "full") if in_scene else "-", settings.sharpen_mode,
		"open" if ui_visible else "closed",
		"open" if virtual_keyboard and virtual_keyboard.visible else "closed",
		Time.get_time_string_from_system(), _cost_cpu_sum / _cost_frames, _cost_longest,
		SettingsController.FOVEATION_LABELS[settings_controller.foveation_active].to_lower(),
		_cost_pictures_gpu_sum / _cost_frames,
		(" | " + system) if system != "" else ""])
	_cost_pictures_gpu_sum = 0.0
	_cost_frames = 0
	_cost_gpu_sum = 0.0
	_cost_gpu_max = 0.0
	_cost_cpu_sum = 0.0
	_cost_longest = 0.0
	# Which off-screen pictures are redrawn every frame: timed from now on,
	# and listed in the log every ten seconds.
	_cost_lines += 1
	var drawing: Array[String] = []
	_cost_pictures.clear()
	for node in get_tree().root.find_children("*", "SubViewport", true, false):
		var sub: SubViewport = node
		if sub.render_target_update_mode == SubViewport.UPDATE_ALWAYS \
				or sub.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE:
			drawing.append("%s %dx%d" % [sub.name, sub.size.x, sub.size.y])
			RenderingServer.viewport_set_measure_render_time(sub.get_viewport_rid(), true)
			_cost_pictures.append(sub)
	if _cost_lines % 10 == 1:
		_log("[FRAME-COST] redrawn every frame: %s" % (", ".join(drawing) if not drawing.is_empty() else "nothing"))

func toggle_performance_overlay():
	settings.performance_overlay_enabled = not settings.performance_overlay_enabled
	telemetry.reset_overlay()
	if stream_backend:
		stream_backend.take_performance_stats()
	# Only the active presentation path should draw the shared stats texture.
	# The legacy path uses TextureRects; native blends it into its video output.
	var native_active := video_presentation.is_native_active()
	if comp:
		comp.set_stats_visible(settings.performance_overlay_enabled and is_streaming and not native_active)
	video_presentation.set_stats_visible(settings.performance_overlay_enabled and is_streaming)
	if ui_controller:
		ui_controller.update_stats_btn_state()
	if state_manager:
		state_manager.save_state()

func _process_performance_overlay(delta: float):
	if not settings.performance_overlay_enabled or not stream_backend or not comp:
		return
	comp.set_stats_visible(true)
	if not telemetry.overlay_update_due(delta):
		return
	var current = stream_backend.take_performance_stats()
	if current.is_empty():
		return
	var stats = telemetry.combine_performance_window(current)
	var elapsed_s = maxf(float(stats.get("elapsed_us", 0)) / 1000000.0, 0.001)
	var total_frames = int(stats.get("total_frames", 0))
	var received_frames = int(stats.get("received_frames", 0))
	var rendered_frames = int(stats.get("rendered_frames", 0))
	var lost_frames = int(stats.get("network_lost_frames", 0))
	var decoder_queue_drops = int(stats.get("decoder_queue_drops", 0))
	var decoder_queue_size = int(stats.get("decoder_queue_size", 0))
	var total_fps = float(total_frames) / elapsed_s
	var incoming_fps = float(received_frames) / elapsed_s
	var rendering_fps = float(rendered_frames) / elapsed_s
	var lost_pct = 100.0 * float(lost_frames) / float(maxi(total_frames, 1))
	var decoder_ms = float(stats.get("decode_time_us", 0)) / 1000.0 / float(maxi(received_frames, 1))
	var width = stream_backend.get_video_width()
	var height = stream_backend.get_video_height()
	var decoder_name = stream_backend.get_decoder_name()
	if decoder_name.is_empty():
		decoder_name = "Unknown"
	var lines := PackedStringArray([
		"Connection: %s (%s)" % [stream_manager.connection_label(), stream_manager.stream_host_address],
		"Video stream: %dx%d %.0f FPS" % [width, height, total_fps],
		"Decoder: %s" % decoder_name,
		"Incoming frame rate from network: %.0f FPS" % incoming_fps,
		"Rendering frame rate: %.0f FPS" % rendering_fps,
		"Nightfall application frame rate: %.1f FPS" % telemetry.app_fps,
		"Nightfall video texture update rate: %.1f FPS" % telemetry.video_update_fps,
		"Frames dropped by your network connection: %.2f%%" % lost_pct,
		"Decoder queue drops: %d (queued: %d)" % [decoder_queue_drops, decoder_queue_size],
		"Average network latency: %d ms (variance: %d ms)" % [int(stats.get("network_latency_ms", 0)), int(stats.get("network_variance_ms", 0))],
	])
	var host_samples = int(stats.get("host_latency_samples", 0))
	if host_samples > 0:
		lines.append("Host processing latency min/max/average: %.1f/%.1f/%.1f ms" % [
			float(stats.get("host_latency_tenths_min", 0)) / 10.0,
			float(stats.get("host_latency_tenths_max", 0)) / 10.0,
			float(stats.get("host_latency_tenths_total", 0)) / 10.0 / float(host_samples),
		])
	lines.append("Average decoding time: %.2f ms" % decoder_ms)
	# Moonlight XR owns its native OpenXR renderer and times the warp command
	# buffer directly. Godot exposes no equivalent GPU timestamp to script;
	# retain the same field explicitly as unavailable rather than substituting
	# CPU frame time and creating a misleading comparison.
	var native_warp_ms := video_presentation.get_warp_gpu_ms()
	lines.append("Warp GPU: %.2f ms" % native_warp_ms if native_warp_ms > 0.0 else "Warp GPU: N/A")
	var host_depth: Dictionary = depth_estimator.meteor_stats if depth_estimator else {}
	if settings.host.ai_3d_speed > 0 and not host_depth.is_empty():
		var offer: Dictionary = stream_manager.meteor_depth_info()
		lines.append("Depth: Nightfall Meteor (%s)" % offer.get("model", "?"))
		lines.append("Host depth: %.0f maps/s received, %.0f shown, %.1f Mbit/s" % [
			host_depth["received_hz"], host_depth["shown_hz"], host_depth["mbit"]])
		lines.append("Meteor frame-to-map time: %.1f ms" % host_depth["host_ms"])
		lines.append("Depth match: %.0f%% exact, %.0f%% 1 frame old, %.0f%% older, %.0f%% none" % [
			host_depth["exact_pct"], host_depth["lag1_pct"], host_depth["older_pct"], host_depth["none_pct"]])
		lines.append("Depth Sync: %s" % ("on" if settings.host.ai_3d_depth_sync else "off"))
	elif settings.host.ai_3d_speed > 0 and settings_controller.get_stereo_mode() >= 3:
		if OS.get_name() == "Android":
			var depth_model_name := settings_controller.active_android_depth_model_name()
			lines.append("Depth: %s / %s" % [
				depth_model_name,
				settings_controller.get_ai_3d_gpu_api_label()])
		lines.append("Depth inference: %.2f ms" % stream_backend.get_depth_last_inference_ms())
		lines.append("Depth GPU priority: %s" % settings_controller.get_ai_3d_gpu_priority_label())
		lines.append("Depth age: %.1f ms" % stream_backend.get_depth_last_age_ms())
		lines.append("Depth frames skipped: %d" % stream_backend.get_depth_last_skipped_frames())
	comp.update_stats_text("\n".join(lines))
	video_presentation.request_stats_overlay_update()
	_log("[PERF] %dx%d stream=%.1f incoming=%.1f render=%.1f lost=%.2f%% queue_drops=%d queued=%d rtt=%dms decode=%.2fms depth=%.2fms" % [
		width, height, total_fps, incoming_fps, rendering_fps, lost_pct,
		decoder_queue_drops, decoder_queue_size,
		int(stats.get("network_latency_ms", 0)), decoder_ms,
		stream_backend.get_depth_last_inference_ms() if settings.host.ai_3d_speed > 0 else 0.0,
	])
	_log("[FRAME-BUDGET] app=%.1ffps process=%.2fms physics=%.2fms native=%s warp_gpu=%.2fms display=%.0fHz cap=%d menu=%s passthrough=%s background=%d screens=%d pcvr=%d" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		video_presentation.is_native_active(), native_xr_renderer.get_warp_gpu_ms(),
		display_refresh_rate, Engine.max_fps, ui_visible, settings.passthrough_enabled,
		settings.background_mode, screens.size(), pcvr_handover.state,
	])

func _process_idle_timeout():
	if not is_streaming or settings.idle_timeout_min <= 0:
		return
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_activity_time > settings.idle_timeout_min * 60.0:
		_log("[IDLE] Idle timeout (%d min), disconnecting" % settings.idle_timeout_min)
		disconnect_stream()
		# stop_stream() emits stream_terminated synchronously; that callback owns
		# the one full-disconnect cleanup. Calling it again here double-tore down
		# the welcome/composition state.

func _notification(what):
	# Steam Frame: log keyboard focus. The headset's volume buttons never reach
	# Nightfall (no [VOLKEY] lines) and SteamOS then keeps turning the volume;
	# Moonlight XR found Game Mode needs the app's window to hold focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_log("[FOCUS] window got focus (%s)" % ("app" if what == NOTIFICATION_APPLICATION_FOCUS_IN else "window"))
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_log("[FOCUS] window lost focus (%s)" % ("app" if what == NOTIFICATION_APPLICATION_FOCUS_OUT else "window"))
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if welcome_screen: welcome_screen.cancel_xr_control()
		if browser_prototype:
			browser_prototype.stop()
		state_manager.save_state()
		video_presentation.shutdown()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		# Keep Meteor's owned game/transport alive during headset handoffs.
		var preparing_xr := welcome_screen != null and welcome_screen.retains_xr_lease_during_timing_transition()
		if not pcvr_test.meteor_mode and not pcvr_test.standby_active and not preparing_xr:
			pcvr_handover.request_stop("Application paused")
			if welcome_screen: welcome_screen.cancel_xr_control()
		pcvr_test.set_application_paused(true)
		if xr_interaction:
			xr_interaction.set_application_suspended(true)
		if meteor_microphone:
			meteor_microphone.set_paused(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if welcome_screen: welcome_screen.resume_auto_xr()
		pcvr_test.set_application_paused(false)
		if meteor_microphone:
			meteor_microphone.set_paused(false)
		if xr_interaction:
			xr_interaction.set_application_suspended(false)
		_schedule_xr_surface_refresh("application resumed")

func _input(event):
	if pcvr_handover.menu_only:
		# The XR pointer dispatches settings clicks directly. Do not forward
		# physical keyboard/gamepad events to an invisible Sunshine desktop.
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			pcvr_handover.close_pcvr_menu()
		return
	if pcvr_handover.blocks_workspace():
		pcvr_handover.handle_input(event)
		return
	if pcvr_test.is_exclusive():
		pcvr_test.handle_input(event)
		return
	input_handler.handle_input(event)
	if is_streaming and (event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		_last_activity_time = Time.get_ticks_msec() / 1000.0

func _toggle_ui():
	if pcvr_handover.menu_only and ui_visible:
		pcvr_handover.close_pcvr_menu()
		return
	if pcvr_handover.blocks_workspace(): return
	if pcvr_test.is_exclusive(): return
	ui_visible = not ui_visible
	_log("[UI] Menu %s (streaming=%s native=%s comp=%s ambient=%s)" % [
		"opened" if ui_visible else "closed",
		str(is_streaming),
		str(video_presentation != null and video_presentation.is_native_active()),
		str(comp != null and comp.in_use),
		ambient_mode_labels[clampi(settings.ambient_mode, 0, ambient_mode_labels.size() - 1)],
	])
	_set_viewport_active(ui_viewport, ui_visible)
	if ui_visible:
		if state_manager:
			state_manager.sync_ui_to_settings(false)
		_set_ui_position()
		if (comp.in_use or pcvr_handover.menu_only) and composition_panels.has_ui():
			composition_panels.show_ui(ui_panel_3d)
			if RenderingServer.get_current_rendering_method() == "gl_compatibility":
				ui_panel_3d.visible = true
				var ui_material = ui_panel_3d.material_override as StandardMaterial3D
				if ui_material:
					ui_material.albedo_color = Color(1, 1, 1, 0.001)
			else:
				ui_panel_3d.visible = false
		else:
			ui_panel_3d.visible = true
			var ui_material = ui_panel_3d.material_override as StandardMaterial3D
			if ui_material:
				ui_material.albedo_color = Color(1, 1, 1, 1)
			var ui_tex = ui_viewport.get_texture()
			ui_panel_3d.material_override.albedo_texture = ui_tex
		var area = ui_panel_3d.get_node_or_null("Area3D")
		if area:
			area.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		composition_panels.hide_ui()
		var ui_material = ui_panel_3d.material_override as StandardMaterial3D
		if ui_material:
			ui_material.albedo_color = Color(1, 1, 1, 1)
		_save_ui_offset()
		ui_panel_3d.visible = false
		var area = ui_panel_3d.get_node_or_null("Area3D")
		if area:
			area.process_mode = Node.PROCESS_MODE_DISABLED
	ui_controller.set_disconnect_visible(is_streaming)

var _ui_saved_offset: Vector3 = Vector3.ZERO
var _ui_saved_rot_y: float = 0.0
var _ui_saved_rot_x: float = 0.0
var _ui_has_saved_offset: bool = false

func _anchor_to_primary(node: Node3D, offset: Vector3, rot_y: float, rot_x: float):
	node.global_position = primary_screen.global_position + primary_screen.global_transform.basis * offset
	node.rotation.y = primary_screen.global_rotation.y + rot_y
	node.rotation.x = rot_x

func set_primary_screen(s: VRScreen) -> void:
	if s == primary_screen or not screens.has(s):
		return
	var panels: Array = [ui_panel_3d]
	if virtual_keyboard:
		panels.append(virtual_keyboard)
	var world_transforms := {}
	for p in panels:
		world_transforms[p] = p.global_transform
	if not screen_registry.set_primary(s):
		return
	# Only the primary draws in 3D, and secondary screens are created without
	# stereo layers. A screen promoted later (a virtual monitor taking over when
	# the physical one is switched off) needs them, or it stays blank in 3D.
	if comp:
		comp.ensure_stereo_layers(s)
	for screen in screens:
		screen.update_shortcut_positions()
		screen_shortcuts.refresh_visuals(screen)
	for p in panels:
		p.global_transform = world_transforms[p]
		if p == ui_panel_3d:
			_save_ui_offset()
		elif p.has_method("_save_offset"):
			p._save_offset()
	state_manager.save_state()

func _set_ui_position():
	if not is_xr_active:
		return
	if _ui_has_saved_offset:
		_anchor_to_primary(ui_panel_3d, _ui_saved_offset, _ui_saved_rot_y, _ui_saved_rot_x)
	else:
		_place_ui_default()

func _place_ui_default():
	var cam_pos = xr_camera.global_position
	if device_is_steam_frame and apply_spot(ui_panel_3d, settings.menu_spot):
		_save_ui_offset()
		return
	if device_is_steam_frame:
		apply_spot(ui_panel_3d, FRAME_MENU_SPOT)
	else:
		var offset = Vector3(-1.0, -0.5, 0.8)
		ui_panel_3d.global_position = primary_screen.global_position + primary_screen.global_transform.basis * offset
		var to_cam = (cam_pos - ui_panel_3d.global_position).normalized()
		ui_panel_3d.rotation.y = atan2(to_cam.x, to_cam.z)
		ui_panel_3d.rotation.x = -0.15
	_save_ui_offset()

# --- Saved default spots (Steam Frame) ---------------------------------------
# Spots are stored relative to you and the screen: a frame at your head,
# looking at the screen, with the screen's "up". So they come back in the same
# place around the screen - also lying down with the screen on the ceiling.
func _viewer_frame() -> Transform3D:
	var cam_pos: Vector3 = xr_camera.global_position
	var fwd: Vector3 = primary_screen.global_position - cam_pos
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var up: Vector3 = primary_screen.global_transform.basis.y.normalized()
	up -= fwd * up.dot(fwd)
	if up.length() < 0.01:
		up = Vector3.UP - fwd * fwd.dot(Vector3.UP)
	if up.length() < 0.01:
		up = Vector3.BACK
	return Transform3D(Basis.looking_at(fwd, up.normalized()), cam_pos)

## Steam Frame: where the menu and the keyboard start when nothing has been
## saved (and where "Original Default" puts them back): x, y, z in metres
## from the viewer and yaw, pitch in radians, as spot_from_node() gives them.
## These are the spots settled on after weeks of daily use (the keyboard a
## little further away, the menu likewise), read from the 8d log and rounded. The menu is off to
## the left, turned toward you; the keyboard 0.86 m ahead and lower. Before:
## menu 0.3 m left and 0.8 m ahead, keyboard 0.55 m ahead.
const FRAME_MENU_SPOT := [-0.87, -0.45, -0.80, 0.86, -0.36]
const FRAME_KEYBOARD_SPOT := [0.11, -0.57, -0.86, -0.02, -0.44]

func spot_from_node(n: Node3D) -> Array:
	var local: Transform3D = _viewer_frame().affine_inverse() * n.global_transform.orthonormalized()
	var e: Vector3 = local.basis.get_euler()
	return [local.origin.x, local.origin.y, local.origin.z, e.y, e.x]

func apply_spot(n: Node3D, spot: Array) -> bool:
	if spot.size() != 5:
		return false
	var local := Transform3D(Basis.from_euler(Vector3(float(spot[4]), float(spot[3]), 0.0)),
		Vector3(float(spot[0]), float(spot[1]), float(spot[2])))
	n.global_transform = _viewer_frame() * local
	return true

func reset_ui_position():
	_place_ui_default()

# --- Recenter and Head Lock (Steam Frame) -------------------------------------
var _head_lock_offset := Transform3D()
var _head_lock_valid := false
var _head_lock_tilt := false
var _prev_click_trigger := {"left": 0.0, "right": 0.0}
var _was_grabbing := false

# Where you're looking: a frame at your eyes pointing along your gaze, kept
# level (no head tilt) so nothing ends up crooked.
func _gaze_frame(tilt: bool = false) -> Transform3D:
	var cam: Transform3D = xr_camera.global_transform
	if tilt:
		return Transform3D(cam.basis.orthonormalized(), cam.origin)
	var fwd: Vector3 = -cam.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.05:
		flat = Vector3(-cam.basis.z.x - cam.basis.y.x, 0.0, -cam.basis.z.z - cam.basis.y.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	var pitch := clampf(asin(clampf(fwd.y, -1.0, 1.0)), deg_to_rad(-40.0), deg_to_rad(40.0))
	var dir := (flat * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), cam.origin)

# Straight ahead of where you're looking (all the way up or down too, e.g.
# the ceiling when lying down), facing you. Upright by the room when you're
# looking roughly level; by your head when looking far up or down.
func _transform_in_view(dist: float) -> Transform3D:
	var cam: Transform3D = xr_camera.global_transform
	var dir: Vector3 = (-cam.basis.z).normalized()
	var pos: Vector3 = cam.origin + dir * dist
	var z: Vector3 = -dir
	var a := clampf((0.85 - absf(dir.y)) / 0.35, 0.0, 1.0)
	var head_up: Vector3 = cam.basis.y.normalized()
	var up: Vector3 = Vector3.UP * a + head_up * (1.0 - a)
	up -= z * up.dot(z)
	if up.length() < 0.001:
		up = head_up - z * head_up.dot(z)
	up = up.normalized()
	var x := up.cross(z).normalized()
	return Transform3D(Basis(x, z.cross(x), z), pos)

# Moves the main screen, and everything arranged around it, in one piece.
func _move_screen_group(new_primary: Transform3D) -> void:
	var delta_t: Transform3D = new_primary * primary_screen.global_transform.affine_inverse()
	for s in screens:
		s.global_transform = delta_t * s.global_transform
	if ui_panel_3d:
		ui_panel_3d.global_transform = delta_t * ui_panel_3d.global_transform
	if virtual_keyboard:
		virtual_keyboard.global_transform = delta_t * virtual_keyboard.global_transform
	if comp:
		comp.update_cylinder_params()

# A saved or dragged size past VRScreen's limit is brought back inside it, so
# a screen can't stay too large to reach its own corners and grab bar.
func cap_screen_sizes() -> void:
	if not xr_camera:
		return
	var changed := false
	for s in screens:
		if s.mesh_size.y <= 0.0:
			continue
		var distance: float = s.global_position.distance_to(xr_camera.global_position)
		var limit: float = VRScreen.max_width_at(distance)
		if s.mesh_size.x > limit:
			_log("[SCREEN] %.1f m wide at %.1f m away is past the limit; set to %.1f m" % [s.mesh_size.x, distance, limit])
			s.set_width(limit, s.mesh_size.x / s.mesh_size.y)
			changed = true
	if changed and comp and comp.available:
		comp.update_layer_size()

# Start Distance was changed (Steam Frame): shows the new distance by moving
# the screens to it along your line to the main screen. The menu and keyboard
# stay put, so the slider being dragged doesn't move away under the pointer.
func move_screens_to_distance(dist: float) -> void:
	if not is_xr_active or not primary_screen or not xr_camera:
		return
	var head: Vector3 = xr_camera.global_position
	var to_screen: Vector3 = primary_screen.global_position - head
	if to_screen.length() < 0.05:
		return
	var shift: Vector3 = head + to_screen.normalized() * dist - primary_screen.global_position
	for s in screens:
		s.global_position += shift
		s.apply_curvature()  # a curved screen's radius depends on its distance
	if comp:
		comp.update_cylinder_params()
	cap_screen_sizes()  # nearer, the widest allowed is smaller
	if _ui_screen_size_btn:
		settings_controller.refresh_screen_size_btn()
	# The menu and keyboard remember their places relative to the screen;
	# note the new ones, or they would jump after it the next time they open.
	if ui_panel_3d and ui_panel_3d.visible:
		_save_ui_offset()
	if virtual_keyboard and virtual_keyboard.visible:
		virtual_keyboard._save_offset()
	_head_lock_valid = false
	_log("[VIEW] screen moved to its start distance, %.2f m" % dist)

# Recenter: brings the screen in front of where you're looking now, at the
# same distance, with the menu and keyboard keeping their places around it.
func recenter_view() -> void:
	if not primary_screen or not xr_camera:
		return
	var dist: float = clampf((primary_screen.global_position - xr_camera.global_position).length(), 0.5, 6.0)
	var t := _transform_in_view(dist)
	_move_screen_group(Transform3D(t.basis * Basis.from_scale(primary_screen.global_transform.basis.get_scale()), t.origin))
	# The menu and keyboard go to their default spots (your saved ones, or
	# Nightfall's own), which are set relative to you and the screen.
	if ui_panel_3d:
		if ui_panel_3d.visible:
			reset_ui_position()
		else:
			_ui_has_saved_offset = false
	if virtual_keyboard:
		if virtual_keyboard.visible:
			virtual_keyboard.reset_to_default()
		else:
			virtual_keyboard._has_saved_offset = false
	_head_lock_valid = false
	state_manager.save_state()
	_log("[VIEW] recentered at %.2f m" % dist)

func capture_head_lock() -> void:
	_head_lock_tilt = settings.head_lock == 2
	_head_lock_offset = _gaze_frame(_head_lock_tilt).affine_inverse() * primary_screen.global_transform
	_head_lock_valid = true

# Head Lock: the screen keeps the same place in your view, following smoothly.
func _process_head_lock(delta: float) -> void:
	if not settings.head_lock or not primary_screen:
		return
	if grabbed_node != null:
		_head_lock_valid = false # you're moving something; pick up the new spot after
		return
	if not _head_lock_valid or _head_lock_tilt != (settings.head_lock == 2):
		capture_head_lock()
		return
	var target: Transform3D = _gaze_frame(_head_lock_tilt) * _head_lock_offset
	var cur: Transform3D = primary_screen.global_transform
	if cur.origin.distance_to(target.origin) < 0.002 and cur.basis.z.dot(target.basis.z) > 0.99999 * cur.basis.z.length() * target.basis.z.length():
		return
	var k := 1.0 - exp(-delta * 6.0)
	_move_screen_group(cur.interpolate_with(target, k))

# Vibration: a light tick when you click on something with the trigger.
func buzz(hand: String, strength: float, seconds: float) -> void:
	if settings.haptics <= 0:
		return
	var node: XRController3D = left_hand if hand == "left" else right_hand
	if node:
		node.trigger_haptic_pulse("haptic", 0.0, strength, seconds, 0.0)

# Faint tick as the pointer moves onto a button or key (Vibration: Clicks + Hover).
func hover_buzz(hand: String) -> void:
	if settings.haptics >= 2:
		buzz(hand, 0.05, 0.008)

# Puts the menu or keyboard right where you're looking, facing you.
func bring_to_view(n: Node3D, dist: float) -> void:
	var g := _gaze_frame()
	var dir: Vector3 = -g.basis.z
	n.global_position = g.origin + dir * dist
	var yaw := atan2(g.origin.x - n.global_position.x, g.origin.z - n.global_position.z)
	n.rotation = Vector3(asin(clampf(dir.y, -1.0, 1.0)), yaw, 0.0)
	if n == ui_panel_3d:
		_save_ui_offset()
	elif n == virtual_keyboard:
		virtual_keyboard._save_offset()
	_log("[VIEW] %s brought in front of you" % ("menu" if n == ui_panel_3d else "keyboard"))

func show_menu_in_view() -> void:
	if not ui_visible:
		_toggle_ui()
	bring_to_view(ui_panel_3d, 0.8)

func show_keyboard_in_view() -> void:
	if not virtual_keyboard:
		return
	if not virtual_keyboard.visible:
		virtual_keyboard.toggle()
	bring_to_view(virtual_keyboard, 0.6)

func _process_click_haptics() -> void:
	for hand in ["left", "right"]:
		var node: XRController3D = left_hand if hand == "left" else right_hand
		var v: float = node.get_float("trigger") if node else 0.0
		if v > 0.5 and _prev_click_trigger[hand] <= 0.5:
			var ray: RayCast3D = left_hand_raycast if hand == "left" else hand_raycast
			if ray and ray.is_colliding():
				buzz(hand, 0.4, 0.03)
		_prev_click_trigger[hand] = v
	var grabbing := grabbed_node != null
	if grabbing and not _was_grabbing:
		buzz(xr_interaction._active_hand, 0.6, 0.05)
	_was_grabbing = grabbing

# Windows key chords such as Win+H (dictation).
func send_win_chord(key: int) -> void:
	if not is_streaming:
		comp.show_notice("Connect to your PC first.", 2.0)
		return
	stream_backend.send_keyboard_event(KEY_META, 3, 0)
	stream_backend.send_keyboard_event(key, 3, 0x08)
	stream_backend.send_keyboard_event(key, 4, 0x08)
	stream_backend.send_keyboard_event(KEY_META, 4, 0)

func _save_ui_offset():
	var scr_basis = primary_screen.global_transform.basis.inverse()
	_ui_saved_offset = scr_basis * (ui_panel_3d.global_position - primary_screen.global_position)
	_ui_saved_rot_y = ui_panel_3d.rotation.y - primary_screen.global_rotation.y
	_ui_saved_rot_x = ui_panel_3d.rotation.x
	_ui_has_saved_offset = true

func _set_ui_visible(vis: bool):
	_set_viewport_active(ui_viewport, vis)
	if not vis and ui_controller:
		ui_controller.clear_tooltip()
	ui_panel_3d.visible = vis
	var area = ui_panel_3d.get_node_or_null("Area3D")
	if area:
		area.process_mode = Node.PROCESS_MODE_INHERIT if vis else Node.PROCESS_MODE_DISABLED
	if is_xr_active and vis:
		if _ui_has_saved_offset:
			_anchor_to_primary(ui_panel_3d, _ui_saved_offset, _ui_saved_rot_y, _ui_saved_rot_x)
		else:
			_place_ui_default()
	elif is_xr_active:
		_save_ui_offset()

func _set_viewport_active(viewport: SubViewport, active: bool):
	if not viewport:
		return
	var wanted = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if viewport.render_target_update_mode != wanted:
		viewport.render_target_update_mode = wanted

func _sync_interaction_viewports():
	if comp == null:
		return # comp is created after the first frames (native Steam Frame startup)
	# These two cursors are only needed for the separately composited menu and
	# keyboard. Screen pointing uses the cursor embedded in the eye viewports.
	var panel_visible = ui_visible or (virtual_keyboard and virtual_keyboard.visible)
	# Native video does not embed the pointer in a Godot video viewport, so
	# its independently composited cursor texture must keep updating even
	# while the menu and keyboard are hidden.
	var independent_screen_cursor := VideoPresentation.uses_independent_screen_cursor(
		comp.in_use, video_presentation.is_native_active())
	composition_pointers.sync_viewports(
		panel_visible or independent_screen_cursor,
		panel_visible)

func _trigger_haptic(_controller: int, low_freq: int, high_freq: int):
	var strength = clampf((low_freq + high_freq) / 510.0, 0.0, 1.0)
	if strength < 0.01:
		return
	if right_hand:
		right_hand.trigger_haptic_pulse("haptic", 0.0, strength, 0.05, 0.0)
	if left_hand:
		left_hand.trigger_haptic_pulse("haptic", 0.0, strength, 0.05, 0.0)

func _debug_log_cyl(tag: String):
	var mesh_pos = screen_mesh.global_position if screen_mesh else Vector3.ZERO
	var mesh_rot = screen_mesh.global_rotation if screen_mesh else Vector3.ZERO
	var cam_pos = xr_camera.global_position if xr_camera else Vector3.ZERO
	var cyl_pos = comp_cylinder.global_position if comp_cylinder else Vector3.ZERO
	var cyl_rot = comp_cylinder.global_rotation if comp_cylinder else Vector3.ZERO
	var cyl_vis = comp_cylinder.visible if comp_cylinder else false
	_log("[CYLDBG:%s] cam=%s mesh_pos=%s mesh_rot=%s cyl_pos=%s cyl_rot=%s cyl_vis=%s cyl_radius=%.3f cyl_center=%s" % [
		tag, str(cam_pos), str(mesh_pos), str(mesh_rot), str(cyl_pos), str(cyl_rot), str(cyl_vis), _comp_cyl_radius, str(_comp_cyl_center)
	])

func _reposition_screen_and_ui(use_cam_yaw: bool = true):
	if not is_xr_active:
		return
	var cam_pos = xr_camera.global_position
	var cam_fwd = -xr_camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	# The primary, not screen_mesh: the original node is retired when its
	# monitor is switched off, and a new screen takes the primary's place.
	var main_screen: VRScreen = primary_screen if primary_screen else screen_mesh
	var start_distance: float = settings.screen_start_distance if device_is_steam_frame else 2.16
	main_screen.global_position = cam_pos + cam_fwd * start_distance
	main_screen.rotation = Vector3.ZERO
	if use_cam_yaw:
		main_screen.rotation.y = atan2(-cam_fwd.x, -cam_fwd.z)
	if frame_first_start and main_screen.mesh_size.y > 0.0:
		frame_first_start = false
		main_screen.set_width(FrameDefaults.SCREEN_WIDTH, main_screen.mesh_size.x / main_screen.mesh_size.y)
		if comp and comp.available:
			comp.update_layer_size()
		_log("[SCREEN] first start: %.1f m wide at %.1f m" % [main_screen.mesh_size.x, start_distance])
	main_screen.apply_curvature()
	# get_cylinder_radius() is camera-position-derived, so any screen curved before
	# this point (e.g. _init_post_xr()'s early best-effort pass, which isn't gated on
	# _startup_reposition confirming a real tracking pose yet) may have baked in a
	# wrong radius - grab_bar/corner geometry is fully recomputed by apply_curvature()
	# each call, so re-running it here with a now-valid camera position is a full fix,
	# not just a partial one. Only screen_mesh's world position/rotation gets moved
	# above (it's the one placed relative to the camera); secondary screens are placed
	# relative to it and must keep their own position/rotation untouched here.
	for s in screens:
		if s != main_screen:
			s.apply_curvature()
	if comp_cylinder or comp_cylinder_left:
		_update_cylinder_params()
	_log("[POS] Screen at %s, Cam at %s" % [str(main_screen.global_position), str(cam_pos)])
	_debug_log_cyl("reposition")

func _reset_positions():
	if ui_visible:
		_toggle_ui()
	if virtual_keyboard and virtual_keyboard.visible:
		virtual_keyboard.toggle()
	_ui_has_saved_offset = false
	if virtual_keyboard:
		virtual_keyboard.reset_position()
	_reposition_screen_and_ui()
	state_manager.save_state()

func _load_controller_models():
	var left_scene = load("res://models/controllers/MetaQuestTouchPlus_Left.fbx")
	var right_scene = load("res://models/controllers/MetaQuestTouchPlus_Right.fbx")
	if left_scene:
		var left_model = left_scene.instantiate()
		left_hand.add_child(left_model)
		left_model.scale = Vector3(1.0, 1.0, 1.0)
		left_model.rotation = Vector3(0, PI, 0)
		_apply_controller_textures(left_model, true)
	if right_scene:
		var right_model = right_scene.instantiate()
		right_hand.add_child(right_model)
		right_model.scale = Vector3(1.0, 1.0, 1.0)
		right_model.rotation = Vector3(0, PI, 0)
		_apply_controller_textures(right_model, false)

# Steam Frame: SteamVR offers XR_EXT_render_model, so the runtime can hand us
# its own models of the controllers. Godot's OpenXRRenderModelManager places
# them itself; Settings > Controller Models turns them off.
func _setup_frame_controller_models() -> void:
	if not ClassDB.class_exists("OpenXRRenderModelManager"):
		_log("[MODELS] OpenXRRenderModelManager not available in this Godot build")
		return
	# One manager per hand, so each controller's model can be hidden on its
	# own while that controller isn't tracked (ControllerTrackingGuard).
	frame_controller_models = Node3D.new()
	frame_controller_models.name = "FrameControllerModels"
	xr_origin.add_child(frame_controller_models)
	for side in ["left", "right"]:
		var mgr = ClassDB.instantiate("OpenXRRenderModelManager")
		mgr.name = "Models_" + side
		mgr.set("tracker", 2 if side == "left" else 3) # RENDER_MODEL_TRACKER_LEFT/RIGHT_HAND
		frame_controller_models.add_child(mgr)
		_frame_model_managers[side] = mgr
		if mgr.has_signal("render_model_added"):
			mgr.connect("render_model_added", func(m): _log("[MODELS] %s controller model added: %s" % [side, str(m)]))
	if not tracking_guard:
		tracking_guard = ControllerTrackingGuard.new()
		tracking_guard.setup(self)
		add_child(tracking_guard)
	update_frame_controller_models()
	_log("[MODELS] Frame controller models set up (shown=%s)" % settings.show_controller_models)

var _frame_model_managers: Dictionary = {}
var tracking_guard: ControllerTrackingGuard = null
var voice_typing: VoiceTyping = null

func update_frame_controller_models() -> void:
	if frame_controller_models:
		frame_controller_models.visible = settings.show_controller_models and not _is_using_hands
	for side in _frame_model_managers:
		_frame_model_managers[side].visible = not (tracking_guard and tracking_guard.hide_model(side))

func on_controller_tracking_changed(side: String, lost: bool) -> void:
	update_frame_controller_models()
	_apply_hand_rest(side, lost or (xr_interaction != null and (xr_interaction._right_inactive_time if side == "right" else xr_interaction._left_inactive_time) >= HAND_REST_THRESHOLD))

func _set_controller_models_visible(visible_state: bool):
	update_frame_controller_models()
	_set_hand_local_model_visible(right_hand, visible_state)
	_set_hand_local_model_visible(left_hand, visible_state)

# Local FBX fallback model visibility, per-hand - factored out of
# _set_controller_models_visible() (2026-08-25) so the render-model
# experiment can hide just one hand's local model without touching the
# other, e.g. if the runtime only supplies a render model for one
# controller.
func _set_hand_local_model_visible(hand: Node3D, visible_state: bool):
	if not hand:
		return
	for child in hand.get_children():
		if child is Node3D and child.name != "HandRayCast" and child.name != "LeftHandRayCast":
			child.visible = visible_state

# OpenXRFbRenderModel is itself a Node3D that self-tracks the runtime's
# controller pose (confirmed via ClassDB introspection, 2026-08-25) - no
# separate XRController3D wrapper needed, unlike an earlier draft of this
# function. It exposes render_model_type (OpenXRFbRenderModel.MODEL_CONTROLLER_LEFT/
# _RIGHT), has_render_model_node()/get_render_model_node(), and an
# openxr_fb_render_model_loaded signal fired once the runtime actually
# supplies geometry - used below for proper async detection instead of a
# guessed timer delay.
func _setup_render_model_controllers():
	if not ClassDB.class_exists("OpenXRFbRenderModel"):
		_log("[CTRLMODEL] OpenXRFbRenderModel not available in this Godot build")
		return
	# Resolve the vendor enum through ClassDB so the project can still be parsed
	# by a stock Godot editor when the optional vendor binary is not installed.
	var right_model_type := ClassDB.class_get_integer_constant(
		"OpenXRFbRenderModel", "MODEL_CONTROLLER_RIGHT")
	var left_model_type := ClassDB.class_get_integer_constant(
		"OpenXRFbRenderModel", "MODEL_CONTROLLER_LEFT")
	right_render_model = ClassDB.instantiate("OpenXRFbRenderModel")
	right_render_model.name = "RightRenderModel"
	right_render_model.render_model_type = right_model_type
	xr_origin.add_child(right_render_model)
	right_render_model.openxr_fb_render_model_loaded.connect(_on_render_model_loaded.bind(true))

	left_render_model = ClassDB.instantiate("OpenXRFbRenderModel")
	left_render_model.name = "LeftRenderModel"
	left_render_model.render_model_type = left_model_type
	xr_origin.add_child(left_render_model)
	left_render_model.openxr_fb_render_model_loaded.connect(_on_render_model_loaded.bind(false))
	_log("[CTRLMODEL] OpenXRFbRenderModel nodes created, waiting on load signal")

# Fired by OpenXRFbRenderModel once the runtime actually supplies real
# geometry for that hand. Hides the local FBX fallback for just that hand
# (_set_hand_local_model_visible - the render model and the fallback should
# never both be visible at once) and leaves the other hand's fallback alone
# if its render model hasn't loaded (or never will - not every runtime
# supports XR_FB_render_model for every controller).
func _on_render_model_loaded(is_right: bool):
	if is_right:
		_right_render_model_ready = true
		_set_hand_local_model_visible(right_hand, false)
		_log("[CTRLMODEL] Right controller render model loaded")
	else:
		_left_render_model_ready = true
		_set_hand_local_model_visible(left_hand, false)
		_log("[CTRLMODEL] Left controller render model loaded")

# Called from _process() - see the DEBUG_RENDER_MODEL_CONTROLLERS var
# comment for why this only runs in normal (mesh) projection mode. Purely
# visibility gating each frame; the FBX-fallback-hiding decision itself
# happens once, in _on_render_model_loaded() above.
func _process_render_model_controllers(_delta: float):
	if not DEBUG_RENDER_MODEL_CONTROLLERS:
		return
	if right_render_model:
		right_render_model.visible = not comp.in_use and _right_render_model_ready
	if left_render_model:
		left_render_model.visible = not comp.in_use and _left_render_model_ready

func _apply_controller_textures(node: Node, is_left: bool):
	var base_color_path = "res://models/controllers/textures/MetaQuestTouchPlus_Left_BaseColor.png" if is_left else "res://models/controllers/textures/MetaQuestTouchPlus_right_BaseColor.png"
	var base_tex = load(base_color_path)
	if not base_tex:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			for i in range(child.get_surface_override_material_count()):
				var mat = child.get_surface_override_material(i)
				if not mat:
					mat = child.mesh.surface_get_material(i) if child.mesh else null
				if mat is StandardMaterial3D:
					mat = mat.duplicate()
					mat.albedo_texture = base_tex
					mat.render_priority = 127
					child.set_surface_override_material(i, mat)
				elif mat is BaseMaterial3D:
					mat = mat.duplicate()
					mat.albedo_texture = base_tex
					mat.render_priority = 127
					child.set_surface_override_material(i, mat)
		_apply_controller_textures(child, is_left)

var contact_dot: MeshInstance3D
var left_contact_dot: MeshInstance3D
var pointer_cursor: MeshInstance3D
var left_comp_cursor: MeshInstance3D
var _fade_materials: Dictionary = {"left": [], "right": []}
var _hand_alpha: Dictionary = {"left": 1.0, "right": 1.0}

func _create_contact_dot():
	var shared_mat = StandardMaterial3D.new()
	shared_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shared_mat.albedo_color = Color(1, 1, 1, 0.2)
	shared_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shared_mat.render_priority = 127
	shared_mat.no_depth_test = true

	contact_dot = _make_contact_dot(shared_mat)
	contact_dot.name = "ContactDot"
	add_child(contact_dot)
	left_contact_dot = _make_contact_dot(shared_mat)
	left_contact_dot.name = "LeftContactDot"
	add_child(left_contact_dot)

	pointer_cursor = MeshInstance3D.new()
	pointer_cursor.name = "PointerCursor"
	var ptr_mesh = QuadMesh.new()
	ptr_mesh.size = Vector2(0.06, 0.08)
	pointer_cursor.mesh = ptr_mesh
	var ptr_mat = StandardMaterial3D.new()
	ptr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ptr_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ptr_mat.render_priority = 127
	ptr_mat.no_depth_test = true
	ptr_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ptr_mat.albedo_texture = load("res://src/assets/mouse_pointer_01.png")
	ptr_mat.albedo_color = Color(1, 1, 1, 1.0)
	pointer_cursor.material_override = ptr_mat
	pointer_cursor.visible = false
	pointer_cursor.extra_cull_margin = 10.0
	add_child(pointer_cursor)

	left_comp_cursor = _make_circle_cursor()
	left_comp_cursor.name = "LeftCompCursor"
	add_child(left_comp_cursor)

func _make_circle_cursor() -> MeshInstance3D:
	var m = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	m.mesh = quad
	var tex_size = 64
	var img = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center = Vector2((tex_size - 1) * 0.5, (tex_size - 1) * 0.5)
	var radius = tex_size * 0.42
	var edge = max(tex_size * 0.015, 1.0)
	for x in range(tex_size):
		for y in range(tex_size):
			var d = Vector2(x, y).distance_to(center)
			var t = clampf((d - (radius - edge)) / edge, 0.0, 1.0)
			var alpha = (1.0 - t) * 0.3
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 127
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.visible = false
	m.extra_cull_margin = 10.0
	return m

func _make_contact_dot(mat: StandardMaterial3D = null) -> MeshInstance3D:
	var dot = MeshInstance3D.new()
	var m = SphereMesh.new()
	m.radius = 0.015
	m.height = 0.03
	dot.mesh = m
	dot.material_override = mat
	dot.visible = false
	return dot

func _hide_all_backgrounds():
	if bg_manager:
		bg_manager.hide_all()

func _create_backgrounds():
	bg_manager = BackgroundManager.new(self)
	bg_manager.create_backgrounds()

func _create_ash():
	bg_manager._create_ash()

func _create_snow():
	bg_manager._create_snow()

func _create_data():
	bg_manager._create_data()

func _update_hand_indicator_layers():
	if comp == null:
		return # comp is created after the first frames (native Steam Frame startup)
	composition_hand_indicators.update(
		DEBUG_COMP_HANDS and comp.in_use and is_xr_active and _is_using_hands,
		xr_camera.global_position)

func _update_hand_tracker_transform(hand_node: XRController3D, tracker: XRHandTracker):
	var hand_name := "left" if hand_node == left_hand else "right"
	var ray: RayCast3D = left_hand_raycast if hand_name == "left" else hand_raycast
	if not ray:
		return
	# XRController3D continues receiving physical-controller pose signals.
	# Keep hand aiming independent instead of overwriting its transform.
	ray.top_level = true
	var aim_tracker = XRServer.get_tracker("/user/fbhandaim/" + hand_name)
	if aim_tracker:
		var aim_pose = aim_tracker.get_pose("default")
		var valid: bool = aim_pose != null and aim_pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE
		if ray:
			ray.enabled = valid
		if valid:
			ray.global_transform = xr_origin.global_transform * aim_pose.get_adjusted_transform()
			ray.force_raycast_update()
		return
	var wrist_ok = (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST) & 8) != 0
	var middle_knuckle_ok = (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL) & 8) != 0
	
	if wrist_ok and middle_knuckle_ok:
		var wrist_trans = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST)
		var middle_knuckle_pos = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL).origin
		var wrist_pos = wrist_trans.origin
		
		var forward = (middle_knuckle_pos - wrist_pos).normalized()
		var temp_up = wrist_trans.basis.y
		var right = forward.cross(temp_up).normalized()
		var up = right.cross(forward).normalized()
		var basis = Basis(right, up, -forward)
		# Pitch down by 30 degrees for relaxed remote-like aiming
		basis = basis.rotated(right, deg_to_rad(-30))
		ray.global_transform = xr_origin.global_transform * Transform3D(basis, middle_knuckle_pos)
	elif wrist_ok:
		var t = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST)
		t.basis = t.basis.rotated(t.basis.y, PI)
		ray.global_transform = xr_origin.global_transform * t
	else:
		var palm_ok = (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM) & 8) != 0
		if palm_ok:
			var t = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
			t.basis = t.basis.rotated(t.basis.y, PI)
			ray.global_transform = xr_origin.global_transform * t

func _make_laser_gradient() -> ImageTexture:
	var img = Image.create(1, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		var a = 1.0 - float(y) / 255.0
		img.set_pixel(0, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
