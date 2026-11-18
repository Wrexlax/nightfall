class_name MenuSchema
extends RefCounted

const TARGET_UI := &"ui"
const TARGET_SETTINGS := &"settings"
const TARGET_SCREEN := &"screen"
const TARGET_CONTROLLER := &"controller"

## Head Lock's tooltip for each of its choices (the button shows the one for
## the choice it is on). One tooltip for all three took four lines in a bar
## that shows two, so half of it was never seen.
const HEAD_LOCK_TIPS := {
	"Off": "The screen stays where you put it. Level keeps it upright in front of you wherever you look;\nTilt also tilts it with your head. Place the screen first: you can still grab it afterwards.",
	"Level": "The screen stays upright in front of you wherever you look, following smoothly.\nYou can still grab it to move it. By voice: 'head lock on', 'head lock off'.",
	"Tilt": "The screen stays in front of you and tilts with your head, for lying down.\nYou can still grab it to move it. By voice: 'head lock tilt', 'head lock off'.",
}

## Steam Frame: Commands' tooltip says what the current choice does.
const VOICE_COMMANDS_TIPS := {
	"On": "On: a command said on its own while voice typing is carried out.\nOff: nothing you say is run as a command; everything is typed.",
	"Off": "Off: nothing you say is run as a command; everything is typed.\nOn: a command said on its own while voice typing is carried out.",
}

## Steam Frame: Logging's tooltip likewise.
const LOGGING_TIPS := {
	"On": "On: each run is logged, with a copy cleaned for sharing in Downloads > Nightfall-logs.\nA change takes effect the next time Nightfall starts.",
	"Off": "Off: nothing is logged. To report a problem: turn it on, restart Nightfall, repeat the problem.\nA change takes effect the next time Nightfall starts.",
}

## Steam Frame: Advanced Settings in the order and groups agreed 2026-11-17:
## what is used most first, the voice and
## microphone options together, and diagnostics last. Changed after a
## first look: AI 3D's one option has no category to itself (it is in
## General) and Stream Link moved to the Stream tab (FRAME_MOVES). Each entry: the row's node name, its title, its options
## by field, in order. Upstream's rows are built as before and regrouped by
## regroup_for_frame(); an option this table doesn't name stays in the row
## upstream gave it, after these, so a new option can't get lost.
const FRAME_SETTINGS_GROUPS := [
	[&"SettingsViewRow", "View & Feel", [&"_ui_recenter_btn", &"_ui_bezel_btn", &"_ui_haptics_btn", &"_ui_icon_backdrop_btn"]],
	[&"SettingsScreenPositionRow", "Screen Position", [&"_ui_start_distance_btn", &"_ui_screen_size_btn", &"_ui_keep_room_btn"]],
	[&"SettingsPositionsRow", "Menu & Keyboard Position", [&"_ui_save_spots_btn", &"_ui_reset_spots_btn", &"_ui_kb_follow_btn"]],
	[&"SettingsVoiceRow", "Voice & Microphone", [&"_ui_voice_list_btn", &"_ui_voice_commands_btn", &"_ui_voice_prefix_btn", &"_ui_voice_confirm_btn"]],
	# A row takes five options at most; a group's second row has no title.
	[&"SettingsVoiceMoreRow", "", [&"_ui_voice_model_btn", &"_ui_voice_ease_btn", &"_ui_mic_key_btn", &"_ui_microphone_btn"]],
	[&"SettingsConnectionRow", "Connection", [&"_ui_reconnect_btn", &"_ui_quick_start_btn", &"_ui_idle_btn", &"_ui_forget_meteor_btn"]],
	[&"SettingsGeneralRow", "General", [&"_ui_language_btn", &"_ui_3d_cursor_position_btn", &"_ui_stats_btn", &"_ui_camera_limit_btn", &"_ui_reset_settings_btn"]],
	[&"SettingsAboutRow", "About", [&"_ui_licences_btn", &"_ui_logging_btn"]],
]

## Steam Frame: the Picture tab's two rows: the picture's look on top, how
## the screen is drawn below.
const FRAME_PICTURE_GROUPS := [
	[&"PictureRow1", "", [&"_ui_brightness_btn", &"_ui_contrast_btn", &"_ui_gamma_btn", &"_ui_sharpen_btn", &"_ui_foveation_btn"]],
	[&"PictureRow2", "", [&"_ui_flat_mode_btn", &"_ui_flat_detail_btn", &"_ui_curved_filter_btn", &"_ui_pt_fade_btn"]],
]

## Steam Frame: options that leave Advanced Settings for another tab's row.
## Stream Link sits on the Stream tab, because it is changed
## fairly often and is about the stream.
## Head Lock and Bezel change places (Bezel is set once and left alone,
## while Head Lock is used all the time): Head Lock ends the Display tab's first row,
## Bezel is in Advanced Settings. An option is added after those its new row
## already has; one that FRAME_SETTINGS_GROUPS names takes its place there.
const FRAME_MOVES := [
	[&"_ui_second_link_btn", &"stream", &"StreamRow2"],
	[&"_ui_bezel_btn", &"settings", &"SettingsViewRow"],
	[&"_ui_head_lock_btn", &"display", &"DispRow1"],
]

# Native Steam Frame build (SteamOS on arm64).
static var _IS_FRAME: bool = OS.get_name() == "Linux" and Engine.get_architecture_name() == "arm64"

static func get_tab_buttons() -> Array:
	return [
		_tab_button(&"_tab_btn_display", "Display", 0, "Configure the screen and its surrounding environment."),
		_tab_button(&"_tab_btn_stream", "Stream", 1, "Configure stream quality, frame rate, and encoding."),
		_tab_button(&"_tab_btn_control", "Control", 2, "Configure pointers, hand tracking, and controller mapping."),
		# Steam Frame (native Linux arm64) only: controller button bindings.
		_tab_button(&"_tab_btn_buttons", "Buttons", 8, "Choose what each Steam Frame controller button does.", _IS_FRAME),
		_tab_button(&"_tab_btn_ai3d", "AI 3D", 3, "Configure local AI stereoscopic depth conversion."),
		_tab_button(&"_tab_btn_picture", "Picture", 4, "Adjust the streamed image."),
		# Screens: PC monitors, virtual monitors and (Quest only) browser screens.
		# Upstream enables it on Android alone. On the Steam Frame it is open
		# from 6p for the PC's monitors and virtual ones; the in-headset browser
		# doesn't exist there, and its controls are left out (see
		# UIController._build_screen_sources()).
		_tab_button(&"_tab_btn_monitors", "Screens", 5,
			"Choose which of the PC's monitors to show, and add virtual ones." if _IS_FRAME else "Choose screen content: PC or browser.",
			true, OS.get_name() != "Android" and not _IS_FRAME, 1.0 if OS.get_name() == "Android" or _IS_FRAME else 0.3),
		# Settings has no tab button: the gear in the top bar opens it.
		_tab_button(&"_tab_btn_settings", "Settings", 6, "Configure language, diagnostics, and connection options.", false, true),
	]

static func get_tabs() -> Array:
	var tabs := _upstream_tabs()
	if _IS_FRAME:
		# Moves are made before the regrouping: an option that goes into
		# Advanced Settings is then given its place by FRAME_SETTINGS_GROUPS,
		# and one that leaves doesn't keep an empty row of upstream's alive.
		for move in FRAME_MOVES:
			if move[1] == &"settings":
				_move_into_tab(tabs, move[0], move[1])
			else:
				_move_option(tabs, move[0], move[1], move[2])
		for tab in tabs:
			if tab["id"] == &"settings":
				tab["rows"] = regroup_for_frame(tab["rows"], FRAME_SETTINGS_GROUPS)
			elif tab["id"] == &"picture":
				tab["rows"] = regroup_for_frame(tab["rows"], FRAME_PICTURE_GROUPS)
		for move in FRAME_MOVES:
			_move_option(tabs, move[0], move[1], move[2])
	return tabs

# Takes the option out of whichever row has it and adds it to the first row
# of tab `tab_id`.
static func _move_into_tab(tabs: Array, field: StringName, tab_id: StringName) -> void:
	var target = null
	for tab in tabs:
		if tab["id"] == tab_id and not tab["rows"].is_empty():
			target = tab["rows"][0]
	if target == null:
		return
	for tab in tabs:
		if tab["id"] == tab_id:
			continue
		for row in tab["rows"]:
			for option in row["options"]:
				if option["field"] == field:
					row["options"].erase(option)
					target["options"].append(option)
					return

# Takes the option out of whichever row has it and adds it to `row_name` on
# tab `tab_id`. Left where it is if that row isn't there.
static func _move_option(tabs: Array, field: StringName, tab_id: StringName, row_name: StringName) -> void:
	var target = null
	for tab in tabs:
		if tab["id"] == tab_id:
			for row in tab["rows"]:
				if row["node_name"] == row_name:
					target = row
	if target == null:
		return
	for tab in tabs:
		for row in tab["rows"]:
			for option in row["options"]:
				if option["field"] == field and row != target:
					row["options"].erase(option)
					target["options"].append(option)
					return

## A tab's rows as upstream builds them, put into `groups`' order and rows.
static func regroup_for_frame(rows: Array, groups: Array) -> Array:
	var by_field := {}
	for row in rows:
		for option in row["options"]:
			by_field[option["field"]] = option
	var grouped: Array = []
	var placed := {}
	for group in groups:
		var options: Array = []
		for field in group[2]:
			if by_field.has(field):
				options.append(by_field[field])
				placed[field] = true
		var row := {"node_name": group[0], "options": options}
		if group[1] != "":
			row["title"] = group[1]
		grouped.append(row)
		placed[group[0]] = true
	# What the table doesn't name (options hidden on the Frame, and any new
	# one) keeps its row, after the groups. A row taken over by a group gets
	# another node name, since a name can only be used once.
	for row in rows:
		var rest: Array = row["options"].filter(func(option): return not placed.has(option["field"]))
		if rest.is_empty():
			continue
		var kept: Dictionary = row.duplicate()
		kept["options"] = rest
		if placed.has(row["node_name"]):
			kept["node_name"] = StringName(String(row["node_name"]) + "Rest")
		grouped.append(kept)
	return grouped

static func _upstream_tabs() -> Array:
	return [
	{
		"id": &"display",
		"node_name": &"TabDisplay",
		"rows": [
			{
				"node_name": &"DispRow1",
				"options": [
					_option(&"_ui_pt_btn", "Passthrough", "On", "Show your physical surroundings behind the screen.", TARGET_SETTINGS, &"toggle_passthrough"),
					_option(&"_ui_sbs_btn", "SBS", "Off", "Display side-by-side 3D content using Stretch or Crop.", TARGET_UI, &"on_sbs_toggled"),
					_option(&"_ui_3d_speed_btn", "AI 3D", "Off", "Convert normal video into stereoscopic 3D using local depth inference.", TARGET_UI, &"on_ai_3d_speed_toggled"),
					(_slider(&"_ui_curve_btn", "Curve", "Drag across to set how much the screen curves. Far left is flat.", TARGET_SCREEN, &"set_curve_amount") if _IS_FRAME else _option(&"_ui_curve_btn", "Curve", "Flat", "Change the physical curvature of the virtual screen.", TARGET_SCREEN, &"cycle_curvature")),
				] + ([
					# Steam Frame keeps Bezel here (rows of five); elsewhere it is on the Picture tab.
					_option(&"_ui_bezel_btn", "Bezel", "On", "Show or hide the frame around the screen. A curved screen has no frame.", TARGET_SCREEN, &"toggle_bezel"),
				] if _IS_FRAME else []),
			},
			{
				"node_name": &"DispRow2",
				"options": [
					_option(&"_ui_bg_btn", "Background", "Black", "Choose the virtual background used when passthrough is off.", TARGET_SETTINGS, &"cycle_background"),
					_option(&"_ui_ambient_btn", "Ambient", "Off", "Add screen lighting using a fixed, slowly sampled, or live sampled color.", TARGET_SETTINGS, &"cycle_ambient_mode"),
					_option(&"_ui_ambient_color_btn", "Color", "White", "Choose the fixed ambient color. Available in Static mode only.", TARGET_SETTINGS, &"cycle_ambient_color"),
				] + ([
					# Steam Frame: glow sliders here (rows of five); PT Fade is on the Picture tab.
					_slider(&"_ui_glow_strength_btn", "Glow Strength", "Drag across to set how bright the ambient glow is. Default 50%.", TARGET_SETTINGS, &"set_glow_strength", true, 50),
					_slider(&"_ui_glow_size_btn", "Glow Size", "Drag across to set how far the ambient glow reaches. Default 35%.", TARGET_SETTINGS, &"set_glow_size", true, 35),
				] if _IS_FRAME else [
					_option(&"_ui_pt_fade_btn", "PT Fade", "Off", "Darken your surroundings in passthrough so the screen stands out.", TARGET_SETTINGS, &"cycle_passthrough_fade"),
				]),
			},
		],
	},
	{
		"id": &"stream",
		"node_name": &"TabStream",
		"rows": [
			{
				"node_name": &"StreamRow1",
				"options": [
					_option(&"_ui_res_btn", "Resolution", "100%", "Choose the resolution requested from the host.", TARGET_SETTINGS, &"cycle_resolution"),
					_option(&"_ui_fps_btn", "FPS", "60", fps_tooltip(), TARGET_SETTINGS, &"cycle_fps"),
					_option(&"_ui_bitrate_btn", "Bitrate", "Auto", "Control stream bandwidth and image quality.", TARGET_SETTINGS, &"cycle_bitrate"),
					_option(&"_ui_host_cursor_btn", "Host Cursor", "Off", "Show or hide the host operating system cursor when supported.", TARGET_SETTINGS, &"toggle_host_cursor"),
				],
			},
			{
				"node_name": &"StreamRow2",
				"options": [
					_option(&"_ui_codec_btn", "Codec", "HEVC", "Video codec. PyroWave suits fast 2D streaming; avoid it with AI 3D.", TARGET_SETTINGS, &"cycle_codec"),
					_option(&"_ui_hdr_btn", "HDR", "Off", "Request HDR when the host display uses it; tone-mapped for the headset.", TARGET_SETTINGS, &"toggle_hdr", OS.get_name() == "Android"),
					_option(&"_ui_audio_on_pc_btn", "Reconnect Stream", "", "Restarts the stream, to get sound or depth back if either has stopped coming through.", TARGET_SETTINGS, &"reconnect_audio", OS.get_name() == "Linux"),
					(_slider(&"_ui_audio_boost_btn", "Volume", "Drag across to set the stream's volume. All the way left mutes it; boosts above Normal softly limit loud peaks.", TARGET_SETTINGS, &"set_volume", true, 80) if _IS_FRAME else _option(&"_ui_audio_boost_btn", "Volume", "Normal", "Stream volume on the headset (boosts above Normal softly limit loud peaks).", TARGET_SETTINGS, &"cycle_audio_boost")),
					_option(&"_ui_usb_link_btn", "USB Link", "Off", "Stream over a USB-C cable instead of Wi-Fi, once the host is reachable over it.", TARGET_SETTINGS, &"toggle_usb_link", OS.get_name() == "Android"),
				],
			},
		],
	},
	{
		"id": &"control",
		"node_name": &"TabControl",
		"rows": [
			{
				"node_name": &"ControlRow1",
				"options": [
					_option(&"_ui_cursor_btn", "Cursor Type", "Circle", ("Circle or Pointer: Nightfall draws its own cursor. PC Cursor: no VR cursor - the PC's own cursor follows your pointer instead." if _IS_FRAME else "Choose the appearance of the VR pointer, or hide it on the screen."), TARGET_SETTINGS, &"cycle_cursor_mode"),
					# Steam Frame's own "PC cursor follows the pointer"; elsewhere upstream's Follows Pointer (below) does it.
					_option(&"_ui_cursor_follow_btn", "Cursor Follow", "Off", "Off: the PC's cursor only moves when you click. Standard: it follows your pointer.\nCapacitive Touch: uses capacitive touch to enable/disable VR control of the PC cursor.", TARGET_SETTINGS, &"cycle_cursor_follow", _IS_FRAME),
					_option(&"_ui_steady_btn", "Cursor Steady", "Low", "The amount of stabilization applied to the pointer. Adaptive steadies more the slower you move.", TARGET_SETTINGS, &"cycle_steady"),
					_option(&"_ui_hide_cursor_btn", "Cursor Off Screen", "", "Move the PC's mouse cursor to the right edge, out of the way. Over a full-screen video, the player then hides it. Click on the screen to bring it back.", TARGET_SETTINGS, &"hide_pc_cursor", _IS_FRAME),
					# Last in its row, so it sits above Controller Models: the two things you
					# see of your controllers together, and the cursor options side by side.
					_option(&"_ui_pointer_ray_btn", "Pointer Ray", "On", "Show or hide the beam from your controller to the screen.", TARGET_SETTINGS, &"toggle_pointer_ray", _IS_FRAME),
					_option(&"_ui_hand_tracking_btn", "Tracking", "Off", "Enable or disable hand tracking.", TARGET_SETTINGS, &"toggle_hand_tracking", not _IS_FRAME),
					_option(&"_ui_mouse_follows_btn", "Follows Pointer", "Off", "Move the PC cursor wherever you point, without clicking.", TARGET_SETTINGS, &"toggle_mouse_follows_pointer", not _IS_FRAME),
				],
			},
			{
				"node_name": &"ControlRow2",
				"options": [
					_option(&"_ui_ctrl_mode_btn", "Game Controller", "Off", "Use the controllers as a gamepad or keyboard and mouse for games. If a game doesn't react, Alt+Tab to it once. If the desktop doesn't react after turning this off, Alt+Tab once.", TARGET_CONTROLLER, &"check_toggle_ui"),
					_option(&"_ui_ctrl_type_btn", "Emulate", "PAD-HAND", "Choose which controls are sent to the PC. Gamepad needs a gamepad driver for Sunshine (such as ViGEmBus); Keyboard+Mouse works without one.", TARGET_CONTROLLER, &"cycle_type"),
					_option(&"_ui_face_swap_btn", "Gamepad Layout", "Standard", "Standard: as labelled. Swapped: A/B and X/Y trade places. Custom: your own layout (Buttons tab > Custom Gamepad).", TARGET_SETTINGS, &"toggle_face_swap", _IS_FRAME),
					_option(&"_ui_btn_toggle_btn", "Alternate Mode", "Head", "Choose how the secondary button mapping is activated.", TARGET_CONTROLLER, &"cycle_btn_toggle", not _IS_FRAME),
					_option(&"_ui_primary_btn", "Primary Hand", "Right", "Choose which hand provides primary pointer input.", TARGET_CONTROLLER, &"cycle_primary_hand"),
					_option(&"_ui_ctrl_models_btn", "Controller Models", "On", "Show your real Steam Frame controllers in Nightfall, using SteamVR's own models.", TARGET_SETTINGS, &"toggle_controller_models", _IS_FRAME),
				],
			},
		],
	},
	{
		"id": &"picture",
		"node_name": &"TabPicture",
		"rows": [
			{
				"node_name": &"PictureRow1",
				"options": [
					_option(&"_ui_brightness_btn", "Brightness", "+0%", "Adjust the overall image brightness.", TARGET_SETTINGS, &"cycle_brightness"),
					_option(&"_ui_contrast_btn", "Contrast", "100%", "Adjust the difference between light and dark areas.", TARGET_SETTINGS, &"cycle_contrast"),
					_option(&"_ui_gamma_btn", "Gamma", "100%", "Adjust midtone brightness without equally changing highlights.", TARGET_SETTINGS, &"cycle_gamma"),
				] + ([
					_option(&"_ui_foveation_btn", "Foveation", "Off", "Experimental. What you aren't looking at is drawn less finely. It follows your eyes.\nOnly affects a curved or 3D Scene screen. A flat Layer screen is unchanged, and Off is faster.", TARGET_SETTINGS, &"cycle_foveation"),
					_option(&"_ui_flat_detail_btn", "Flat Screen Detail", "Stream Size", "For a flat Layer screen. Stream Size draws its picture at the stream's own size. Full always draws\nit at 4K, as older builds did: much heavier with AI 3D, and kept so the two can be compared.", TARGET_SETTINGS, &"toggle_flat_screen_detail"),
				] if _IS_FRAME else []),
			},
			{
				"node_name": &"PictureRow2",
				"options": [
					_option(&"_ui_sharpen_btn", "Sharpen", "Off", "Apply native runtime sharpening to the streamed image.", TARGET_SETTINGS, &"cycle_sharpen_mode"),
				] + ([
					_option(&"_ui_flat_mode_btn", "Flat Screen", "Layer", "How a flat screen is drawn. Layer: handed to SteamVR to draw. 3D Scene: drawn by Nightfall like the curved screen, so controllers show in front of it.", TARGET_SETTINGS, &"toggle_flat_screen_mode"),
					_option(&"_ui_curved_filter_btn", "Curved Filter", "Fast", "How a curved (or 3D Scene) screen is smoothed where it is shown smaller than the video.\nFast: lighter on the headset. Full: the original, a touch finer on small text.", TARGET_SETTINGS, &"toggle_curved_filter"),
					_slider(&"_ui_pt_fade_btn", "PT Fade", "Drag across to darken your surroundings in passthrough so the screen stands out. 100% is black.", TARGET_SETTINGS, &"set_passthrough_fade"),
				] if _IS_FRAME else [
					# Steam Frame has Bezel on the Display tab's first row instead.
					_option(&"_ui_bezel_btn", "Bezel", "On", "Show or hide the frame around the screen.", TARGET_SCREEN, &"toggle_bezel"),
				]),
			},
		],
	},
	{
		# Unlike the other tabs, Settings scrolls, so it can grow past the
		# two rows that fit the menu. Each row may carry a section title.
		"id": &"settings",
		"node_name": &"TabSettings",
		"scrollable": true,
		"rows": [
			{
				"node_name": &"SettingsDiagnosticsRow",
				"title": "Diagnostics",
				"options": [
					_option(&"_ui_log_btn", "Save Log", "", "Save diagnostic logs to Download/Nightfall.", TARGET_UI, &"on_export_logs_pressed", OS.get_name() == "Android"),
					_option(&"_ui_stats_btn", "Stats", "Off", "Show or hide live stream performance statistics.", TARGET_UI, &"on_stats_toggled"),
				] + ([] if OS.get_name() == "Android" else [
					# Android exposes this diagnostic on the AI 3D tab. The
					# desktop copy stays hidden, as it was on Advanced.
					_option(&"_ui_3d_debug_btn", "3D Debug", "Off", "Display intermediate AI depth data for troubleshooting.", TARGET_UI, &"on_ai_3d_debug_toggled", false, true),
				]),
			},
			{
				"node_name": &"SettingsAi3dRow",
				"title": "AI 3D",
				"options": [
					_option(&"_ui_3d_cursor_position_btn", "Cursor Position", "Default", "With AI 3D on, nudges the drawn cursor left or right so it lines up with where your clicks land. It moves the cursor you see, not the click.", TARGET_UI, &"on_ai_3d_cursor_position_toggled"),
					_option(&"_ui_3d_depth_sync_btn", "Depth Sync", "Off", "Delay video slightly so it matches the frame used by AI depth inference.", TARGET_UI, &"on_ai_3d_depth_sync_toggled", OS.get_name() == "Android"),
					_option(&"_ui_3d_edge_alignment_btn", "Edge Alignment", "On", "Align on-headset depth edges to colour. Meteor uses server controls.", TARGET_SETTINGS, &"toggle_ai_3d_edge_alignment", OS.get_name() == "Android"),
					_option(&"_ui_3d_contour_cleanup_btn", "Contour Cleanup", "On", "Smooth depth contours. Requires Edge Alignment.", TARGET_SETTINGS, &"toggle_ai_3d_contour_cleanup", OS.get_name() == "Android"),
				],
			},
			{
				"node_name": &"SettingsViewRow",
				"title": "View & Feel",
				"options": [
					_option(&"_ui_recenter_btn", "Recenter", "", "Bring the screen, menu and keyboard in front of where you're looking now. Also a button action (Buttons tab), or say 'recenter' with voice typing.", TARGET_SETTINGS, &"recenter_view", _IS_FRAME),
					_option(&"_ui_head_lock_btn", "Head Lock", "Off", HEAD_LOCK_TIPS["Off"], TARGET_SETTINGS, &"toggle_head_lock", _IS_FRAME),
					_option(&"_ui_haptics_btn", "Vibration", "Clicks", "Clicks: a light controller tick when you click something, and a stronger one when you grab. Clicks + Hover: also a faint tick as the pointer moves onto a button or key.", TARGET_SETTINGS, &"toggle_haptics", _IS_FRAME),
					_option(&"_ui_mic_key_btn", "Keyboard Mic Key", "Nightfall", "What the Mic key on Nightfall's keyboard does. Nightfall: voice typing on the headset (tap to start and stop, or hold while talking). Windows: opens Windows dictation (Win+H).", TARGET_SETTINGS, &"cycle_mic_key_mode", _IS_FRAME),
				],
			},
			{
				"node_name": &"SettingsVoiceRow",
				"title": "Voice Commands",
				"options": [
					_option(&"_ui_voice_list_btn", "Voice Commands", "", "Show every voice command. Say a command on its own (not inside a sentence) while voice typing.", TARGET_SETTINGS, &"show_voice_commands", _IS_FRAME),
					_option(&"_ui_voice_commands_btn", "Commands", "On", VOICE_COMMANDS_TIPS["On"], TARGET_SETTINGS, &"toggle_voice_commands", _IS_FRAME),
					_option(&"_ui_voice_prefix_btn", "Require 'Nightfall'", "Off", "On: commands only run when you start with 'Nightfall' (for example 'Nightfall select all'). Use this if commands go off by accident. Off: just say the command; 'Nightfall' first still works.", TARGET_SETTINGS, &"toggle_voice_prefix", _IS_FRAME),
					_option(&"_ui_voice_confirm_btn", "Confirm Commands", "On", "On: a short popup says what each voice command did. Off: commands run silently.", TARGET_SETTINGS, &"toggle_voice_confirm", _IS_FRAME),
					_option(&"_ui_voice_model_btn", "Speech Model", "Base", "Which speech model voice typing listens with. Small hears words more correctly and takes longer to type them out; Base is quicker.", TARGET_SETTINGS, &"cycle_voice_model", _IS_FRAME),
					_option(&"_ui_voice_ease_btn", "Faster Voice Typing", "On", "While your words are being worked out, the headset's depth model slows right down so the\ntext comes sooner. The 3D depth trails for those seconds. Only with Headset: Detail or Light.", TARGET_SETTINGS, &"toggle_voice_eases_depth", _IS_FRAME),
				],
			},
			{
				"node_name": &"SettingsScreenPositionRow",
				"title": "Screen Position",
				"options": [
					_slider(&"_ui_start_distance_btn", "Start Distance", "Drag across to set how far away the screen starts when Nightfall opens (At Launch: In Front). The screen moves there when you let go, so you can see it. Default 6 m.", TARGET_SETTINGS, &"set_screen_start_distance", _IS_FRAME, 100),
					_slider(&"_ui_screen_size_btn", "Screen Size", "Drag across to make the screen smaller or larger. Dragging a corner of the screen does the same; this also brings back a screen that has grown out of reach.", TARGET_SETTINGS, &"set_screen_size", _IS_FRAME, 25),
					_option(&"_ui_keep_room_btn", "At Launch", "In Front", "In Front: the screen starts in front of you each time. Same Spot: it starts where it was last time, in your room (for a fixed setup).", TARGET_SETTINGS, &"toggle_keep_room_position", _IS_FRAME),
				],
			},
			{
				"node_name": &"SettingsPositionsRow",
				"title": "Menu & Keyboard Position",
				"options": [
					_option(&"_ui_save_spots_btn", "Save As Default", "", "Remember where the menu and keyboard are now (relative to you) as their default spots. A long press on their grab bars puts them back there.", TARGET_SETTINGS, &"save_panel_spots", _IS_FRAME),
					_option(&"_ui_reset_spots_btn", "Original Default", "", "Forget your saved spots and go back to Nightfall's own default spots for the menu and keyboard.", TARGET_SETTINGS, &"reset_panel_spots", _IS_FRAME),
					_option(&"_ui_kb_follow_btn", "Menu & Keyboard Follow", "On", "On: moving the screen with its grab bar brings the menu and keyboard along. Their own grab bars still move just them. Off: they move separately.", TARGET_SETTINGS, &"toggle_keyboard_follows_screen", _IS_FRAME),
				],
			},
			{
				"node_name": &"SettingsGeneralRow",
				"title": "General",
				"options": [
					_option(&"_ui_language_btn", "Language", "English", "Choose the language used by Nightfall's menus.", TARGET_UI, &"on_language_pressed"),
					# Steam Frame: the way back for someone whose settings have got into a mess.
					_option(&"_ui_reset_settings_btn", "Reset Settings", "", "Every setting in the menu goes back to Nightfall's defaults; then Nightfall restarts. Press twice.\nYour paired PCs, button mappings and profiles, language and speech models are kept.", TARGET_SETTINGS, &"reset_settings", _IS_FRAME),
				],
			},
			{
				"node_name": &"SettingsInputRow",
				"title": "Input",
				"options": [
					# Steam Frame: hidden (grip is right click there; the Buttons tab has a Double Click action).
					_option(&"_ui_double_click_btn", "Double Click", "Click Twice", "Click Twice: pull the trigger twice quickly. Trigger + Grip: squeeze both together for one double-click.", TARGET_SETTINGS, &"cycle_double_click_mode", not _IS_FRAME),
				],
			},
			{
				"node_name": &"SettingsDisplayRow",
				"title": "Display",
				"options": [
					# Not on the Steam Frame: its display doesn't go that high.
					_option(&"_ui_high_refresh_btn", "High Refresh Rates", "Off", "Offer 200 and 207 Hz. They can glitch the headset.", TARGET_SETTINGS, &"toggle_high_refresh_rates", not _IS_FRAME),
					_option(&"_ui_icon_backdrop_btn", "Icon Backdrop", "On", "The dark panel behind the icons under the screen. Off: the icons float on their own and are fainter.", TARGET_SETTINGS, &"toggle_icon_backdrop", _IS_FRAME),
					# Shown only while a camera add-on is fitted (SettingsController.refresh_addon_cameras()).
					_option(&"_ui_camera_limit_btn", "Camera FPS Limit", "Auto", "With a color camera add-on: 90 fps while Passthrough is on, so head turns don't hitch.\nAuto: only while the color camera is the one showing the room. On: whenever it is fitted.", TARGET_SETTINGS, &"cycle_camera_limit", _IS_FRAME),
					_option(&"_ui_second_link_btn", "Stream Link", "Multi-Link", "Picture and sound over Wi-Fi and the wireless adapter at once; the first copy to arrive is used.\nThe steadiest. Needs the adapter and Meteor on the PC; can also be chosen in Meteor's menu.", TARGET_SETTINGS, &"cycle_link_mode", _IS_FRAME),
				],
			},
			{
				"node_name": &"SettingsConnectionRow",
				"title": "Connection",
				"options": [
					_option(&"_ui_reconnect_btn", "Auto-Reconnect", "On", "Automatically attempt to restore an interrupted stream.", TARGET_SETTINGS, &"cycle_auto_reconnect"),
					_option(&"_ui_idle_btn", "Idle Disconnect", "Off", "Disconnect after the selected period without input.", TARGET_SETTINGS, &"cycle_idle_timeout"),
					_option(&"_ui_quick_start_btn", "Quick Start", "Off", "Automatically reconnect to the most recently used host and application.", TARGET_SETTINGS, &"cycle_quick_start"),
					_option(&"_ui_forget_meteor_btn", "Forget Meteor Keys", "", "Trust the next key Nightfall Meteor sends, after reinstalling it.", TARGET_SETTINGS, &"forget_meteor_keys"),
				],
			},
			{
				"node_name": &"SettingsMicrophoneRow",
				"title": "Microphone",
				"options": [
					_option(&"_ui_microphone_btn", "Microphone", "Off", "Send the headset microphone to the PC through Nightfall Meteor, for voice chat and calls. Needs VB-CABLE installed on the PC.", TARGET_SETTINGS, &"toggle_microphone"),
					_option(&"_ui_audio_output_btn", "Audio Output", "Native", "Compare Native / AudioTrack playback; reconnects. Test with Volume: Normal.", TARGET_SETTINGS, &"cycle_audio_output", OS.get_name() == "Android"),
				],
			},
			{
				"node_name": &"SettingsAboutRow",
				"title": "About",
				"options": [
					_option(&"_ui_licences_btn", "Licences", "", "Show the licences of Nightfall and the software it includes.", TARGET_UI, &"on_licences_pressed"),
					_option(&"_ui_logging_btn", "Logging", "On", LOGGING_TIPS["On"], TARGET_SETTINGS, &"toggle_logging", _IS_FRAME),
				],
			},
		],
	},
]

# A slider in option-button form: drag across it (or click a spot) to set
# 0-100. The action is called as action(value: int, commit: bool).
## `detent` (0-100, the bar's fill) marks the default value, which is easier to land on.
static func _slider(field: StringName, label: String, tooltip: String, target: StringName, action: StringName, visible: bool = true, detent: int = -1) -> Dictionary:
	var o := _option(field, label, "", tooltip, target, action, visible)
	o["slider"] = true
	o["detent"] = detent
	return o

## The FPS option's tooltip; SettingsController.refresh_pcvr_timing_ui() puts
## it back after PCVR has borrowed the button.
const FPS_TOOLTIP := "Choose the stream frame rate and matching headset refresh rate."
const FPS_TOOLTIP_FRAME := "The stream's frame rate, and the headset's display rate with it (72, 90, 120 or 144).\nLower is lighter and cooler. With a camera add-on, Passthrough holds it at 90 (see Advanced)."

static func fps_tooltip() -> String:
	return FPS_TOOLTIP_FRAME if _IS_FRAME else FPS_TOOLTIP

static func _option(
	field: StringName,
	label: String,
	value: String,
	tooltip: String,
	target: StringName,
	action: StringName,
	visible: bool = true,
	disabled: bool = false
) -> Dictionary:
	return {
		"field": field,
		"label": label,
		"value": value,
		"tooltip": tooltip,
		"target": target,
		"action": action,
		"visible": visible,
		"disabled": disabled,
	}

static func _tab_button(
	field: StringName,
	label: String,
	index: int,
	tooltip: String,
	visible: bool = true,
	disabled: bool = false,
	alpha: float = 1.0
) -> Dictionary:
	return {
		"field": field,
		"label": label,
		"index": index,
		"tooltip": tooltip,
		"visible": visible,
		"disabled": disabled,
		"alpha": alpha,
	}

static func get_tab(id: StringName) -> Dictionary:
	for tab in get_tabs():
		if tab["id"] == id:
			return tab
	return {}

static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var tab_ids := {}
	var fields := {}
	var valid_targets := {
		TARGET_UI: true,
		TARGET_SETTINGS: true,
		TARGET_SCREEN: true,
		TARGET_CONTROLLER: true,
	}
	var tab_indexes := {}
	for button in get_tab_buttons():
		var tab_index: int = button.get("index", -1)
		if tab_index < 0 or tab_indexes.has(tab_index):
			errors.append("Menu tab indexes must be non-negative and unique: %d" % tab_index)
		tab_indexes[tab_index] = true
		if button.get("field", &"") == &"" or button.get("label", "") == "" or button.get("tooltip", "") == "":
			errors.append("Menu tab buttons require a field, label, and tooltip")
	for tab in get_tabs():
		var tab_id: StringName = tab.get("id", &"")
		if tab_id == &"" or tab_ids.has(tab_id):
			errors.append("Menu tab IDs must be non-empty and unique: %s" % tab_id)
		tab_ids[tab_id] = true
		for row in tab.get("rows", []):
			var options: Array = row.get("options", [])
			# What counts is what shows on this device: the Steam Frame port
			# adds options that are hidden elsewhere, and its wider menu
			# takes rows of five.
			var shown := 0
			for option in options:
				if option.get("visible", true):
					shown += 1
			var most := 5 if _IS_FRAME else 4
			if options.is_empty() or shown > most:
				errors.append("Menu row %s must contain one to %d visible options" % [row.get("node_name", &""), most])
			for option in options:
				var field: StringName = option.get("field", &"")
				if field == &"" or fields.has(field):
					errors.append("Menu option fields must be non-empty and unique: %s" % field)
				fields[field] = true
				if not valid_targets.has(option.get("target", &"")):
					errors.append("Menu option %s has an unknown command target" % field)
				if option.get("action", &"") == &"":
					errors.append("Menu option %s has no command" % field)
				if option.get("tooltip", "") == "":
					errors.append("Menu option %s has no tooltip" % field)
	return errors
