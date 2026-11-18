class_name StateManager
extends RefCounted

var main: Node3D

func _init(owner: Node3D):
	main = owner

## True once Reset Settings has written the defaults: nothing saves over
## them before Nightfall closes.
var reset_done := false

## Advanced Settings > Reset Settings (Steam Frame). Writes the settings a
## first start has, keeping FrameDefaults.keep_across_reset()'s few, and
## removes the per-PC stream settings and screen layouts. Paired PCs, button
## mappings and profiles, saved screen layouts and the speech models are in
## other files and are not touched. The next start reads this file; the
## "frame_first_start" mark makes that start treat the screen's size and the
## first PC's stream settings as a first start does.
func reset_to_defaults() -> void:
	var fresh := AppSettings.new()
	FrameDefaults.apply(fresh, VoiceTyping.size_installed(0), VoiceTyping.size_installed(1))
	FrameDefaults.keep_across_reset(fresh, main.settings)
	var save := ConfigFile.new()
	SettingsPersistence.write_app(save, fresh)
	save.set_value("screen", "curvature", 0)
	save.set_value("screen", "frame_curve_v1", true)
	save.set_value("screen", "frame_first_start", true)
	save.save("user://app_state.cfg")
	if FileAccess.file_exists(HOST_STATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HOST_STATE_PATH))
	reset_done = true

func save_state():
	if reset_done:
		return
	var save = ConfigFile.new()
	SettingsPersistence.write_app(save, main.settings)
	save.set_value("screen", "curvature", main.curvature)
	save.set_value("screen", "frame_curve_v1", true)
	if main.device_is_steam_frame and main.primary_screen and main.is_xr_active and main._startup_reposition == -1:
		save.set_value("screen", "room_transform", main.primary_screen.global_transform)
	main.controller_mapper.write_settings(save)
	save.save("user://app_state.cfg")
	save_host_state()

const HOST_STATE_PATH := "user://host_state.cfg"

## The saved PC the address field means right now; empty when it isn't paired.
func saved_host(address: String) -> Dictionary:
	# The stream backend's list is the one pairing, renaming and removing change.
	if main.stream_backend == null:
		return {}
	return SavedHosts.pick(main.stream_backend.get_hosts(), main.current_host_id, main.parse_ip_port(address)[0])

## The part of host_state.cfg holding the settings of the PC at `address`.
func host_section(address: String) -> String:
	return SavedHosts.settings_section(saved_host(address), address)

func save_host_state():
	if reset_done:
		return
	var address = main.get_node("%IPInput").text
	if address.is_empty():
		return
	var section := host_section(address)
	var save = ConfigFile.new()
	save.load(HOST_STATE_PATH)
	var host: HostSettings = main.settings.host
	SettingsPersistence.write_host(save, section, host)
	save.set_value(section, "screen_layout", JSON.stringify(main.layout.to_dict()))
	var placements := []
	for s in main.screens:
		placements.append({
			"id": String(s.monitor_id),
			"pos": [s.position.x, s.position.y, s.position.z],
			"rot": [s.rotation.x, s.rotation.y, s.rotation.z],
			"size": [s.mesh_size.x, s.mesh_size.y],
			"curvature": s.curvature,
			"fc": true,
			"grid_mode": s.grid_mode,
			"grid_pos": [s.grid_pos.x, s.grid_pos.y],
		})
	save.set_value(section, "screen_placements", JSON.stringify(placements))
	save.save(HOST_STATE_PATH)

## Removes a PC's saved settings along with the PC. Settings filed under its
## address by builds before 6s stay while another saved PC is at that address:
## they are that one's starting point too.
func forget_host_state(host: Dictionary, remaining_hosts: Array) -> void:
	var save := ConfigFile.new()
	if save.load(HOST_STATE_PATH) != OK:
		return
	var sections := PackedStringArray([SavedHosts.settings_section(host, "")])
	var bare := str(host.get("localaddress", ""))
	if SavedHosts.pick(remaining_hosts, -1, bare).is_empty():
		sections.append(bare)
	var changed := false
	for section in sections:
		if not section.is_empty() and save.has_section(section):
			save.erase_section(section)
			changed = true
	if changed:
		save.save(HOST_STATE_PATH)

func load_host_state(address: String):
	if address.is_empty():
		return
	var save = ConfigFile.new()
	if save.load(HOST_STATE_PATH) != OK:
		return
	var host_record := saved_host(address)
	var section := SavedHosts.settings_section(host_record, address)
	if not save.has_section(section):
		# First use since each paired PC got its own section: start from what
		# was saved under its address.
		section = ""
		for older in SavedHosts.older_sections(host_record, address):
			if save.has_section(older):
				section = older
				break
		if section.is_empty():
			return
	var host: HostSettings = main.settings.host
	SettingsPersistence.read_host(
		save,
		section,
		host,
		main.settings_controller.STREAM_FPS_RATES,
		main.resolution_scale_options,
		main.resolutions.size(),
		main.settings_controller.ai_3d_models.size())
	if main.device_is_steam_frame:
		# A rate saved before the Frame's list stopped at its display's highest.
		host.stream_fps = mini(host.stream_fps, SettingsController.FRAME_MAX_STREAM_FPS)
	# Model may not actually belong to the loaded Type (main.settings.host.ai_3d_backend_pref) -
	# persistence-codec migrations (including pre-Type legacy formats) can land here with
	# them disagreeing. Snaps Model to Type's first matching entry if so;
	# a no-op otherwise. Covers every branch above in one place rather than
	# repeating it in each.
	main.settings_controller.normalize_ai_3d_model_for_type()
	# Same "covers every branch above in one place" reasoning as
	# normalize_ai_3d_model_for_type() just above - Android locks Type/Model/
	# 3D Mode to GPU/ZipDepth-384-GPU/Standard regardless of what any branch
	# in the typed host settings. No-op on Linux.
	main.settings_controller.enforce_ai3d_platform_lock()
	# update_stereo_shader() (2026-08-28 - replaces a hand-duplicated copy of
	# its own logic that lived here, "since this doesn't call that function
	# directly" per its own old comment) already sets the stereo_mode
	# uniform, every AI-3D button label (including the new AI 3D tab's
	# controls, which that duplicate never knew about), and
	# update_3d_btn_state() - no reason to keep two copies of this in sync.
	main.ui_controller.update_stereo_shader()
	main.ui_controller.update_option_btn(main._ui_fps_btn, main.settings_controller.fps_label())
	main.settings_controller.refresh_pcvr_timing_ui()
	main.host_resolution = main.compute_requested_resolution()
	main.settings_controller.refresh_resolution_btn_label()
	main.ui_controller.update_monitor_tab()
	var bitrate_label = main.bitrate_labels[main.settings.host.bitrate_idx + 1] if main.settings.host.bitrate_idx >= 0 else "Auto"
	main.ui_controller.update_option_btn(main._ui_bitrate_btn, bitrate_label)
	main.settings_controller.apply_stereo()
	if main.depth_estimator:
		main.depth_estimator.set_enabled(main.settings_controller.get_stereo_mode() >= 3)
	main.settings_controller.apply_stereo()

	var layout_json = save.get_value(section, "screen_layout", "")
	var loaded_layout: ScreenLayout = null
	if not layout_json.is_empty():
		var parsed = JSON.parse_string(layout_json)
		if parsed is Dictionary:
			var candidate = ScreenLayout.from_dict(parsed)
			if candidate.validate(candidate.frame_size) == "":
				loaded_layout = candidate
			else:
				main._log("[LAYOUT] Saved layout failed validation, using single()")
	if loaded_layout == null:
		loaded_layout = ScreenLayout.single(main.layout.frame_size if main.layout else Vector2i(1920, 1080))
	main.settings_controller.apply_screen_layout(loaded_layout)

	var placements_json = save.get_value(section, "screen_placements", "")
	if not placements_json.is_empty():
		var placements = JSON.parse_string(placements_json)
		var primary_before: Transform3D = main.primary_screen.global_transform if main.primary_screen else Transform3D()
		if placements is Array:
			for entry in placements:
				var mid = StringName(entry.get("id", ""))
				for s in main.screens:
					if s.monitor_id == mid:
						var pos = entry.get("pos", [0, 0, 0])
						var rot = entry.get("rot", [0, 0, 0])
						var size = entry.get("size", [s.mesh_size.x, s.mesh_size.y])
						s.position = Vector3(pos[0], pos[1], pos[2])
						s.rotation = Vector3(rot[0], rot[1], rot[2])
						s.mesh_size = Vector2(size[0], size[1])
						s.curvature = entry.get("curvature", s.curvature)
						if main.device_is_steam_frame:
							s.curvature = 1 if main.settings.frame_curve_amount > 0 else 0
						s.grid_mode = entry.get("grid_mode", s.grid_mode)
						var gp = entry.get("grid_pos", [s.grid_pos.x, s.grid_pos.y])
						s.grid_pos = Vector2i(gp[0], gp[1])
						s.apply_curvature()
						break
			# Steam Frame: the saved spot is in room coordinates, which change
			# between sessions. Unless "At Launch: Same Spot" is chosen, keep the
			# main screen where it is now (in front of you) and only restore how
			# the screens sit relative to each other.
			if main.device_is_steam_frame and main.primary_screen and not main.settings.keep_room_position:
				var keep: Transform3D = primary_before * main.primary_screen.global_transform.affine_inverse()
				for s in main.screens:
					s.global_transform = keep * s.global_transform
			main.cap_screen_sizes()
		# The composition layer cylinder (the surface actually visible in the
		# headset) is a separate node with its own world position/radius, only
		# ever synced by an explicit update_cylinder_params() call - it does NOT
		# follow along automatically just because a screen's mesh transform above
		# was restored. Without this, the flat mesh (and its grab_bar child) jump
		# to the saved position/rotation while the cylinder stays wherever the
		# generic startup pass left it, until a manual grab forces a resync.
		if main.comp:
			main.comp.update_cylinder_params()
		# These placements describe how screens should look while actively
		# streaming to this host, not the pre-connect welcome UI - but this runs
		# during boot (_init_textures_and_ui(), called after _init_ui() already
		# reset the welcome screen to a fixed 16:9), so a saved non-16:9 layout
		# would otherwise squish the welcome screen the user sees before they've
		# even connected. Re-assert the welcome layout now if we're not
		# streaming; it'll be replaced by the host's real manifest/layout once a
		# connection actually starts.
		if not main.is_streaming and main.welcome_screen:
			main.welcome_screen.show_welcome_screen(main._welcome_screen)

func sync_ui_to_settings(apply_runtime: bool = true):
	# Opening the menu only needs fresh labels. Reapplying shaders, ambient
	# sources, and bezel geometry while a native/legacy viewport is live can
	# disturb the GLES render targets without any setting having changed.
	if apply_runtime and main.bezel_mesh:
		main.bezel_mesh.visible = main.settings.bezel_enabled and not main.comp.in_use
	if main.ui_controller:
		main.ui_controller.update_option_btn(main._ui_bezel_btn, "On" if main.settings.bezel_enabled else "Off")
		main.ui_controller.update_option_btn(main._ui_hand_tracking_btn, main.tracking_mode_label())
		if main.device_is_steam_frame:
			main.ui_controller.set_slider_value(main._ui_curve_btn, main.settings.frame_curve_amount)
			main.ui_controller.set_slider_value(main._ui_glow_strength_btn, main.settings.ambient_strength)
			main.ui_controller.set_slider_value(main._ui_glow_size_btn, main.settings.ambient_size)
		if main._ui_voice_confirm_btn:
			main.ui_controller.update_option_btn(main._ui_voice_confirm_btn, "On" if main.settings.voice_confirm else "Off")
		if main._ui_voice_model_btn:
			main.ui_controller.update_option_btn(main._ui_voice_model_btn, VoiceTyping.MODEL_LABELS[main.settings.voice_model])
		if main._ui_voice_ease_btn:
			main.ui_controller.update_option_btn(main._ui_voice_ease_btn, "On" if main.settings.frame_voice_eases_depth else "Off")
		if main._ui_voice_commands_btn:
			main.ui_controller.update_option_btn(main._ui_voice_commands_btn, "On" if main.settings.voice_commands else "Off")
		if main._ui_logging_btn:
			main.ui_controller.update_option_btn(main._ui_logging_btn, "On" if main.settings.frame_logging else "Off")
		if main._ui_voice_prefix_btn:
			main.ui_controller.update_option_btn(main._ui_voice_prefix_btn, "On" if main.settings.voice_require_prefix else "Off")
		if main._ui_screen_size_btn:
			main.settings_controller.refresh_screen_size_btn()
		if main._ui_start_distance_btn:
			main.settings_controller.refresh_start_distance_btn()
		if main._ui_keep_room_btn:
			main.ui_controller.update_option_btn(main._ui_keep_room_btn, "Same Spot" if main.settings.keep_room_position else "In Front")
		if main._ui_kb_follow_btn:
			main.ui_controller.update_option_btn(main._ui_kb_follow_btn, "On" if main.settings.keyboard_follows_screen else "Off")
		if main._ui_head_lock_btn:
			main.ui_controller.update_option_btn(main._ui_head_lock_btn, main.settings_controller.HEAD_LOCK_LABELS[main.settings.head_lock])
		if main._ui_haptics_btn:
			main.ui_controller.update_option_btn(main._ui_haptics_btn, main.settings_controller.HAPTICS_LABELS[main.settings.haptics])
		if main._ui_mic_key_btn:
			main.ui_controller.update_option_btn(main._ui_mic_key_btn, "Windows" if main.settings.mic_key_mode == 1 else "Nightfall")
		if main._ui_flat_mode_btn:
			main.ui_controller.update_option_btn(main._ui_flat_mode_btn, "3D Scene" if main.settings.frame_flat_3d else "Layer")
			if main._ui_foveation_btn:
				main.ui_controller.update_option_btn(main._ui_foveation_btn, main.settings_controller.FOVEATION_LABELS[main.settings.frame_foveation])
			if main._ui_flat_detail_btn:
				main.ui_controller.update_option_btn(main._ui_flat_detail_btn, main.settings_controller.flat_screen_detail_label())
			if main._ui_curved_filter_btn:
				main.ui_controller.update_option_btn(main._ui_curved_filter_btn, "Fast" if main.settings.frame_fast_filter else "Full")
		if main._ui_pointer_ray_btn:
			main.ui_controller.update_option_btn(main._ui_pointer_ray_btn, "On" if main.settings.show_pointer_ray else "Off")
		if main._ui_cursor_follow_btn:
			main.ui_controller.update_option_btn(main._ui_cursor_follow_btn, main.settings_controller.cursor_follow_label())
		if main._ui_face_swap_btn:
			main.ui_controller.update_option_btn(main._ui_face_swap_btn, main.settings_controller.GAMEPAD_LAYOUT_LABELS[clampi(main.settings.gamepad_layout, 0, 2)])
		if main._ui_ctrl_models_btn:
			main.ui_controller.update_option_btn(main._ui_ctrl_models_btn, "On" if main.settings.show_controller_models else "Off")
		main.update_frame_controller_models()
		main.ui_controller.update_option_btn(main._ui_curve_btn, main.curvature_labels[clampi(main.curvature, 0, main.curvature_labels.size() - 1)])
		main.ui_controller.update_option_btn(main._ui_pt_btn, "On" if main.settings.passthrough_enabled else "Off")
		main.ui_controller.update_option_btn(main._ui_bg_btn, main.background_labels[clampi(main.settings.background_mode, 0, main.background_labels.size() - 1)])
		main.ui_controller.update_option_btn(main._ui_sharpen_btn, main.settings_controller.get_sharpen_label(main.settings.sharpen_mode))
		main.ui_controller.update_option_btn(main._ui_brightness_btn, "%+d%%" % main.settings.brightness_pct)
		main.ui_controller.update_option_btn(main._ui_contrast_btn, "%d%%" % main.settings.contrast_pct)
		main.ui_controller.update_option_btn(main._ui_gamma_btn, "%d%%" % main.settings.gamma_pct)
		main.ui_controller.update_ambient_btn_state()
		main.ui_controller.update_option_btn(main._ui_3d_cursor_position_btn, main.settings_controller.get_ai_3d_cursor_position_label())
		main.ui_controller.update_option_btn(main._ui_cursor_btn, main.cursor_labels[clampi(main.settings.cursor_mode, 0, main.cursor_labels.size() - 1)])
		main.ui_controller.update_option_btn(main._ui_steady_btn, main.pointer_steady_labels[clampi(main.settings.pointer_steady, 0, main.pointer_steady_labels.size() - 1)])
		main.ui_controller.update_option_btn(main._ui_3d_priority_btn, main.settings_controller.ai_3d_gpu_priority_labels[main.settings.ai_3d_gpu_priority])
		main.ui_controller.update_option_btn(main._ui_double_click_btn, main.double_click_mode_labels[clampi(main.settings.double_click_mode, 0, main.double_click_mode_labels.size() - 1)])
		main.ui_controller.update_codec_btn()
		main.ui_controller.update_option_btn(main._ui_reconnect_btn, "On" if main.settings.auto_reconnect_enabled else "Off")
		main.ui_controller.update_option_btn(main._ui_mouse_follows_btn, "On" if main.settings.mouse_follows_pointer else "Off")
		main.ui_controller.update_option_btn(main._ui_high_refresh_btn, "On" if main.settings.high_refresh_rates else "Off")
		if main._ui_second_link_btn:
			main.ui_controller.update_option_btn(main._ui_second_link_btn, FrameSecondLink.MODE_LABELS[main.settings.frame_link_mode])
		if main._ui_camera_limit_btn:
			main.ui_controller.update_option_btn(main._ui_camera_limit_btn, main.settings_controller.CAMERA_LIMIT_LABELS[main.settings.frame_camera_limit])
			main._ui_camera_limit_btn.visible = not main.settings_controller.addon_cameras.is_empty()
		main.settings_controller.refresh_passthrough_fade_btn()
		if main._ui_icon_backdrop_btn:
			main.ui_controller.update_option_btn(main._ui_icon_backdrop_btn, "On" if main.settings.icon_backdrop else "Off")
		if main._ui_quick_start_btn:
			main.ui_controller.update_option_btn(main._ui_quick_start_btn, "On" if main.settings.quick_start_enabled else "Off")
		if main._ui_audio_boost_btn:
			main.settings_controller.refresh_volume_btn()
		if main._ui_audio_output_btn:
			main.ui_controller.update_option_btn(main._ui_audio_output_btn, main.settings_controller.get_audio_output_label())
		if main._ui_hdr_btn:
			main.ui_controller.update_option_btn(main._ui_hdr_btn, "On" if main.settings.hdr_enabled else "Off")
		if main._ui_audio_on_pc_btn:
			main.ui_controller.update_option_btn(main._ui_audio_on_pc_btn, "")
		if main._ui_microphone_btn:
			main.ui_controller.update_option_btn(main._ui_microphone_btn, "On" if main.settings.microphone_enabled else "Off")
		if main._ui_usb_link_btn:
			main.ui_controller.update_option_btn(main._ui_usb_link_btn, "On" if main.settings.usb_link_enabled else "Off")
		var idle_idx = main.settings_controller.idle_values.find(main.settings.idle_timeout_min)
		if idle_idx < 0: idle_idx = 0
		main.ui_controller.update_option_btn(main._ui_idle_btn, main.settings_controller.idle_labels[idle_idx])
		main.ui_controller.update_stats_btn_state()
		main.ui_controller.update_language_btn()
		if main.controller_mapper:
			main.ui_controller.update_btn_toggle_btn()
			main.ui_controller.update_primary_btn()
		main.ui_controller.update_monitor_tab()
	if apply_runtime and main.screen_manager:
		main.screen_manager.update_bezel_size()
	if apply_runtime and main.settings_controller:
		main.settings_controller.apply_filter()
	if apply_runtime and main.comp:
		main.comp.apply_ambient_settings()

func load_state():
	MonitorPresets.write_default_presets_snapshot()
	var save = ConfigFile.new()
	var err = save.load("user://app_state.cfg")
	main._log("[STATE] load_state called. Load result: %d" % err)
	if err != OK:
		main._log("[STATE] load failed or not found, applying default curvature and syncing...")
		if main.device_is_steam_frame:
			# A first start on the Frame: its own starting choices.
			FrameDefaults.apply(main.settings, VoiceTyping.size_installed(0), VoiceTyping.size_installed(1))
			main.curvature = 0
			main.frame_first_start = true
			main._log("[STATE] first start on the Steam Frame: its starting settings applied")
		main.settings_controller.apply_language()
		main.screen_manager.apply_curvature()
		sync_ui_to_settings()
		main.settings_controller.apply_depth_gpu_priority(false)
		main.settings_controller.apply_usb_link()
		return

	var load_info := SettingsPersistence.read_app(
		save,
		main.settings,
		main.passthrough_supported,
		main.settings_controller.get_sharpen_choices())
	main.curvature = save.get_value("screen", "curvature", 2)
	if main.device_is_steam_frame and save.get_value("screen", "frame_first_start", false):
		# The file Reset Settings wrote: the screen's size and the first PC's
		# stream settings as on a first start. The mark is gone with the
		# next save.
		main.frame_first_start = true
		FrameDefaults.apply_host(main.settings.host)
		main._log("[STATE] first start after Reset Settings")
	main._saved_room_transform = save.get_value("screen", "room_transform", null)
	# Steam Frame: Curve used to be hidden and the screen always flat, so the
	# saved value is a leftover default. Start flat until Curve is chosen.
	if main.device_is_steam_frame and not save.get_value("screen", "frame_curve_v1", false):
		main.curvature = 0
	if main.device_is_steam_frame:
		# Curve slider: derive it once from the old Flat/Slight/Curved choice,
		# then the slider alone decides (curvature is just flat / curved).
		if main.settings.frame_curve_amount < 0:
			main.settings.frame_curve_amount = [0, 35, 65][clampi(main.curvature, 0, 2)]
		main.curvature = 1 if main.settings.frame_curve_amount > 0 else 0
	main.settings_controller.apply_language()
	# Keep the existing diagnostic while migration details stay in the codec.
	if load_info.current_passthrough_value != null:
		var raw_saved = load_info.current_passthrough_value
		main._log("[PASSTHROUGH] load_state: raw_saved=%s passthrough_supported=%s -> passthrough_enabled=%s" % [str(raw_saved), str(main.passthrough_supported), str(main.settings.passthrough_enabled)])
	if main.controller_mapper:
		main.controller_mapper.read_settings(save)
		if main.ui_controller:
			main.ui_controller.update_ctrl_mode_btn()
			main.ui_controller.update_ctrl_type_btn()
		if main.ui_controller:
			main.ui_controller.update_btn_toggle_btn()
			main.ui_controller.update_primary_btn()
	main.screen_manager.apply_curvature()
	if main.stream_backend and main.stream_backend._v2:
		main.stream_backend._v2.set_auto_reconnect(main.settings.auto_reconnect_enabled)
	main.settings_controller.apply_audio_boost()

	sync_ui_to_settings()
	main.settings_controller.apply_depth_gpu_priority(false)
	main.settings_controller.apply_usb_link()
