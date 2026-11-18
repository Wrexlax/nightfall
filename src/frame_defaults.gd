class_name FrameDefaults
extends RefCounted

## Steam Frame: what a first start looks like, for someone who has never used
## Nightfall. Applied once, when there is no saved state at all; whoever has
## settings keeps them, and nothing here is ever applied again. (Chosen
## 2026-11-17, going through the menus, so that a fresh install isn't
## confusing.)
##
## Only what differs from AppSettings' and HostSettings' own defaults is
## here; those two stay as upstream has them, with no platform checks.

## How wide the screen starts, in metres (at AppSettings' start distance, 6 m).
const SCREEN_WIDTH := 7.5
const STREAM_FPS := 90

static func apply(settings: AppSettings, base_model_installed: bool, small_model_installed: bool) -> void:
	# Display
	settings.bezel_enabled = false
	settings.ambient_color = 4 # Blue, for when Ambient is set to Static
	settings.frame_curve_amount = 0 # flat
	settings.icon_backdrop = false
	# Control: the PC's own cursor, following the pointer, steadied.
	settings.cursor_mode = AppSettings.CURSOR_MODE_HIDDEN # "PC Cursor" on the Frame
	settings.cursor_follow = true
	settings.sleep_when_put_down = false # Standard; Capacitive Touch is the next choice
	settings.pointer_steady = 2 # High
	settings.haptics = 2 # Clicks + Hover
	# Moving the screen leaves the menu and keyboard where they are.
	settings.keyboard_follows_screen = false
	# Voice typing: the larger model if it was installed; the Mic key does
	# what works.
	var voice := voice_choices(base_model_installed, small_model_installed)
	settings.voice_model = voice["model"]
	settings.mic_key_mode = voice["mic_key"]
	# Nothing is logged until someone asks for it (Advanced Settings > Logging).
	settings.frame_logging = false
	apply_host(settings.host)

## Reset Settings puts everything in the menu back to these defaults, except
## what isn't a mistake someone made in the menu: the language, and the
## gamepad layout choice, which goes with the button mappings and profiles
## that a reset never touches.
static func keep_across_reset(fresh: AppSettings, current: AppSettings) -> void:
	fresh.language = current.language
	fresh.gamepad_layout = current.gamepad_layout
	fresh.gamepad_face_swap = current.gamepad_face_swap

## The first PC's stream: 90 a second, AI 3D on.
static func apply_host(host: HostSettings) -> void:
	host.stream_fps = STREAM_FPS
	host.ai_3d_speed = 1 # on (Auto)

## Speech Model: Small (1) when it is installed, else Base (0). Keyboard Mic
## Key: Nightfall's voice typing (0) when either is, else Windows dictation (1).
static func voice_choices(base_installed: bool, small_installed: bool) -> Dictionary:
	return {
		"model": 1 if small_installed else 0,
		"mic_key": 0 if (base_installed or small_installed) else 1,
	}
