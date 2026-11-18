class_name AppSettings
extends RefCounted

## Typed, side-effect-free application settings.
##
## Runtime controllers may react to these values, but this object deliberately
## owns no UI nodes, renderer objects, persistence paths, or platform checks.
## Runtime code reads this store directly; main.gd does not mirror these values.

const APP_STATE_VERSION := 1

var host: HostSettings = HostSettings.new()

const DEFAULT_BEZEL_ENABLED := true
const DEFAULT_PASSTHROUGH_ENABLED := false
const DEFAULT_BACKGROUND_MODE := 0
const DEFAULT_SHARPEN_MODE := 0
const DEFAULT_BRIGHTNESS_PCT := 0
const DEFAULT_CONTRAST_PCT := 100
const DEFAULT_GAMMA_PCT := 100
const DEFAULT_AMBIENT_MODE := 0
const DEFAULT_AMBIENT_COLOR := 0
const DEFAULT_BROWSER_RESOLUTION := 0 # 0=1080p, 1=1440p
const DEFAULT_CURSOR_MODE := 1
const DEFAULT_POINTER_STEADY := 1
const DEFAULT_DOUBLE_CLICK_MODE := 0
const DEFAULT_MOUSE_FOLLOWS_POINTER := false
const DEFAULT_HIGH_REFRESH_RATES := false
const DEFAULT_PASSTHROUGH_FADE_PCT := 0
const DEFAULT_TRACKING_MODE := 0
const DEFAULT_CODEC_PREFERENCE := 1
const DEFAULT_GRID_MODE_ENABLED := true
const DEFAULT_PERFORMANCE_OVERLAY_ENABLED := false
const DEFAULT_AI_3D_GPU_PRIORITY := 0
const DEFAULT_AUTO_RECONNECT_ENABLED := true
const DEFAULT_QUICK_START_ENABLED := false
const DEFAULT_AUDIO_BOOST_DB := 0
const DEFAULT_IDLE_TIMEOUT_MIN := 0
const DEFAULT_PIPEWIRE_RESTORE_TOKEN := ""
const DEFAULT_USB_LINK_ENABLED := false
const DEFAULT_HDR_ENABLED := false
const DEFAULT_MICROPHONE_ENABLED := false
# Empty means "follow the OS language" (see Localization.resolve_language()).
const DEFAULT_LANGUAGE := ""

var bezel_enabled: bool = DEFAULT_BEZEL_ENABLED
var passthrough_enabled: bool = DEFAULT_PASSTHROUGH_ENABLED
var background_mode: int = DEFAULT_BACKGROUND_MODE
var sharpen_mode: int = DEFAULT_SHARPEN_MODE
var brightness_pct: int = DEFAULT_BRIGHTNESS_PCT
var contrast_pct: int = DEFAULT_CONTRAST_PCT
var gamma_pct: int = DEFAULT_GAMMA_PCT
var ambient_mode: int = DEFAULT_AMBIENT_MODE
var ambient_color: int = DEFAULT_AMBIENT_COLOR
var browser_resolution: int = DEFAULT_BROWSER_RESOLUTION
## Hidden draws no VR pointer on stream screens, for Mouse Follows Pointer,
## where the PC's own cursor already shows where you point.
const CURSOR_MODE_HIDDEN := 2
var cursor_mode: int = DEFAULT_CURSOR_MODE
var pointer_steady: int = DEFAULT_POINTER_STEADY
var double_click_mode: int = DEFAULT_DOUBLE_CLICK_MODE
## Move the host cursor wherever the pointer is on the screen, without a click.
var mouse_follows_pointer: bool = DEFAULT_MOUSE_FOLLOWS_POINTER
## Offer the 200 and 207 Hz stream rates, which can glitch the headset.
var high_refresh_rates: bool = DEFAULT_HIGH_REFRESH_RATES
## How much to darken passthrough, in percent (PassthroughFade.FADE_VALUES).
var passthrough_fade_pct: int = DEFAULT_PASSTHROUGH_FADE_PCT
var tracking_mode: int = DEFAULT_TRACKING_MODE
var codec_preference: int = DEFAULT_CODEC_PREFERENCE
var grid_mode_enabled: bool = DEFAULT_GRID_MODE_ENABLED
var performance_overlay_enabled: bool = DEFAULT_PERFORMANCE_OVERLAY_ENABLED
var ai_3d_gpu_priority: int = DEFAULT_AI_3D_GPU_PRIORITY
var auto_reconnect_enabled: bool = DEFAULT_AUTO_RECONNECT_ENABLED
var quick_start_enabled: bool = DEFAULT_QUICK_START_ENABLED
## Stream audio gain in dB, one of SettingsPersistence.AUDIO_BOOST_VALUES.
var audio_boost_db: int = DEFAULT_AUDIO_BOOST_DB
## Diagnostic Android output: 0 native (default), 1 AudioTrack.
var android_audio_output: int = 0
var idle_timeout_min: int = DEFAULT_IDLE_TIMEOUT_MIN
var pipewire_restore_token: String = DEFAULT_PIPEWIRE_RESTORE_TOKEN
var usb_link_enabled: bool = DEFAULT_USB_LINK_ENABLED
## Ask the host for an HDR10 stream (10-bit, PQ) and tone-map it for the
## headset, instead of the host squashing its HDR desktop to SDR.
var hdr_enabled: bool = DEFAULT_HDR_ENABLED
## Steam Frame: ask the host to keep playing audio on the PC as well.
var play_audio_on_pc: bool = false
var show_controller_models: bool = true
# Steam Frame: a controller no hand is touching stops pointing while the
# pointer moves the PC's cursor (ControllerTouch). Set through Cursor Follow:
# Capacitive Touch (SettingsController.cycle_cursor_follow()).
var sleep_when_put_down: bool = true
var gamepad_face_swap: bool = false
var gamepad_layout: int = 0 # 0 Standard, 1 Swapped, 2 Custom (Buttons tab > Custom Gamepad)
var cursor_follow: bool = false
var show_pointer_ray: bool = true
## Steam Frame: the dark panel behind the icons under the screen (upstream's
## look). Off: no panel and the fainter icons the port had before 0.9.
var icon_backdrop: bool = true
# Steam Frame: draw a flat screen in the 3D scene too (like a curved one)
# instead of as a SteamVR quad layer.
var frame_flat_3d: bool = false
# Steam Frame: the lighter minification filter for a screen drawn in the scene
# (stereo_screen_core's footprint_stream_fast). Measured on the headset with a
# 10 m wide curved screen: about 2 to 3 ms of GPU time per frame.
var frame_fast_filter: bool = true
# Steam Frame: 2x multisampling of the 3D scene (smooth edges on the curved
# screen and the controllers). Measured: about 5 ms of GPU time per frame at
# 3408x3408 per eye (13.5 ms with, 8.4 ms without; the budget at 72 Hz is
# 13.9 ms), so it is off unless asked for. Upstream has it off on Quest too.
# Steam Frame: the flat screen's layer pictures are drawn at the stream's
# size (the default from 6o) instead of always at 4K, as up to 6m. See
# VRScreen.sf_match_stream.
var frame_layer_match_stream: bool = true
# Steam Frame: which on-headset depth model AI 3D uses when Meteor isn't
# making the depth (SettingsController.FRAME_DEPTH_LABELS).
# 2 is Headset: GPU (SettingsController.FRAME_DEPTH_GPU_MODEL), the choice
# for a new install since 7r: measured against Detail (0) on the same film it
# looks alike, uses about 2 W less, leaves the processor free and holds every
# display rate. A build without that engine or its files falls back to Detail
# by itself (SettingsController.frame_depth_model).
var frame_depth_model: int = 2
# Steam Frame: depth maps a second from the headset's own model (the AI 3D
# tab's Hz Cap there). Not the per-PC ai_3d_hz_cap: that one was hidden on the
# Frame and may hold anything.
# 0 is Auto (SettingsController.FRAME_DEPTH_RATE_AUTO), the default.
var frame_depth_rate: int = 0
# Steam Frame: keep to 90 fps while a camera add-on shows the room (Advanced
# Settings > Camera FPS Limit: 0 Auto, 1 On, 2 Off; see
# SettingsController.CAMERA_LIMIT_FPS).
var frame_camera_limit: int = 0
# Steam Frame, experimental (5v): the edges of the view are drawn at lower
# resolution (fixed foveated rendering). 0 Off, 1 Low, 2 Medium, 3 High.
var frame_foveation: int = 0
# Steam Frame sliders (0-100). Curve: 0 = flat; the cylinder radius is
# view distance x (1 + 3 x (1 - amount)), as in Moonlight XR. -1 = not set yet
# (derived once from the old Flat/Slight/Curved choice).
var frame_curve_amount: int = -1
var ambient_strength: int = 50
var ambient_size: int = 35
# Steam Frame: show the area beside the keyboard's keys (hidden by default).
var keyboard_trackpad: bool = false
# Steam Frame: which panel that area shows - 0 Trackpad, 1 Arrows, 2 Number pad, 3 Media, 4 Window keys.
var keyboard_panel: int = 0
# Steam Frame: controller vibration - 0 Off, 1 Clicks (clicks and grabs), 2 Clicks + Hover.
var haptics: int = 1
# Steam Frame: keyboard Mic key - 0 = Nightfall voice typing, 1 = Windows dictation (Win+H).
var mic_key_mode: int = 0
# Steam Frame: the screen follows your view - 0 Off, 1 Level (stays upright), 2 Tilt (tilts with your head).
var head_lock: int = 0
var head_lock_last_on: int = 1
# Steam Frame: false (default) = put the screen in front of you at launch;
# true = keep it where it was last time, in room coordinates.
var keep_room_position: bool = false
# Steam Frame: how far away the screen starts (At Launch: In Front), in metres.
## 6 m since 8e (chosen for a first start, 2026-11-17); 2.25 m before.
const SCREEN_START_DISTANCE_DEFAULT := 6.0
const SCREEN_START_DISTANCE_MIN := 1.0
const SCREEN_START_DISTANCE_MAX := 6.0
var screen_start_distance: float = SCREEN_START_DISTANCE_DEFAULT
# Steam Frame: voice commands only run when they start with "Nightfall".
var voice_require_prefix: bool = false
## Steam Frame: Off types everything that is said; nothing is run as a command.
var voice_commands: bool = true
# Steam Frame: a short popup confirms each voice command.
var voice_confirm: bool = true
# Steam Frame voice typing: which speech model listens. 0 Base (142 MB, the
# one installed since 3x), 1 Small (466 MB: hears more correctly, takes about
# three times the work). Falls back to Base when the file isn't installed.
var voice_model: int = 0
# Steam Frame: slow the headset's depth model right down while voice typing
# works a clip out (Advanced Settings > Faster Voice Typing).
var frame_voice_eases_depth: bool = true
# Steam Frame: which of the headset's two links to the PC carry the picture
# and sound (FrameSecondLink.MODE_*): 0 both (Multi-Link), 1 Wi-Fi only,
# 2 the wireless adapter first (alone while its signal holds).
var frame_link_mode: int = 0
# Steam Frame: Stream Link was changed here and the PC's Meteor hasn't been told
# yet (no stream at the time), so its own older pick must not undo the change.
var frame_link_untold: bool = false
# Steam Frame: dragging the screen also moves the keyboard (its own bar moves just the keyboard).
var keyboard_follows_screen: bool = true
## Steam Frame: the AI 3D page's suggestion to install Meteor was clicked away.
var frame_meteor_hint_hidden: bool = false
# Steam Frame: Advanced Settings > Logging. Read by the launcher at the next
# start (nightfall.sh), which is what writes the log files; off on a new
# install (FrameDefaults), on for an install that never had the option.
var frame_logging: bool = true
# Steam Frame: saved default spots for the menu and keyboard, relative to you:
# [x, y, z, yaw, pitch] in a frame facing the screen. Empty = built-in spot.
var menu_spot: Array = []
var keyboard_spot: Array = []
## Send the headset microphone to Nightfall Meteor (MeteorMicrophone).
var microphone_enabled: bool = DEFAULT_MICROPHONE_ENABLED
# Not reset with the other general settings: a settings reset should not
# switch the menus to another language.
var language: String = DEFAULT_LANGUAGE

func reset_display() -> void:
	bezel_enabled = DEFAULT_BEZEL_ENABLED
	passthrough_enabled = DEFAULT_PASSTHROUGH_ENABLED
	background_mode = DEFAULT_BACKGROUND_MODE
	sharpen_mode = DEFAULT_SHARPEN_MODE
	brightness_pct = DEFAULT_BRIGHTNESS_PCT
	contrast_pct = DEFAULT_CONTRAST_PCT
	gamma_pct = DEFAULT_GAMMA_PCT
	ambient_mode = DEFAULT_AMBIENT_MODE
	ambient_color = DEFAULT_AMBIENT_COLOR

func reset_general() -> void:
	browser_resolution = DEFAULT_BROWSER_RESOLUTION
	cursor_mode = DEFAULT_CURSOR_MODE
	pointer_steady = DEFAULT_POINTER_STEADY
	double_click_mode = DEFAULT_DOUBLE_CLICK_MODE
	mouse_follows_pointer = DEFAULT_MOUSE_FOLLOWS_POINTER
	high_refresh_rates = DEFAULT_HIGH_REFRESH_RATES
	passthrough_fade_pct = DEFAULT_PASSTHROUGH_FADE_PCT
	tracking_mode = DEFAULT_TRACKING_MODE
	codec_preference = DEFAULT_CODEC_PREFERENCE
	grid_mode_enabled = DEFAULT_GRID_MODE_ENABLED
	performance_overlay_enabled = DEFAULT_PERFORMANCE_OVERLAY_ENABLED
	ai_3d_gpu_priority = DEFAULT_AI_3D_GPU_PRIORITY
	auto_reconnect_enabled = DEFAULT_AUTO_RECONNECT_ENABLED
	quick_start_enabled = DEFAULT_QUICK_START_ENABLED
	audio_boost_db = DEFAULT_AUDIO_BOOST_DB
	android_audio_output = 0
	microphone_enabled = DEFAULT_MICROPHONE_ENABLED
	idle_timeout_min = DEFAULT_IDLE_TIMEOUT_MIN
	pipewire_restore_token = DEFAULT_PIPEWIRE_RESTORE_TOKEN
	usb_link_enabled = DEFAULT_USB_LINK_ENABLED
	hdr_enabled = DEFAULT_HDR_ENABLED
