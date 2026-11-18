class_name WelcomeScreen
extends RefCounted

var main: Node3D
var mdns_browsing: bool = false
var wol_sender: WolSender = WolSender.new()
var _xr_control: RefCounted
var _auto_retry := 0.0
var _auto_suppressed := false

func resume_auto_xr() -> void:
	_auto_suppressed = false
	_auto_retry = 2.0

func process_auto_xr(delta: float) -> void:
	if not main.is_streaming:
		_auto_suppressed = false
		if _xr_control and _xr_control.state == "watching": _xr_control.cancel()
		return
	_auto_retry -= delta
	if _auto_retry > 0 or _auto_suppressed: return
	# An established watcher already owns discovery. Do not reload its config
	# and enumerate hosts on every rendered desktop frame.
	if _xr_control != null and _xr_control.state not in ["idle", "failed"]: return
	_auto_retry = 5.0
	if not main.pcvr_test.available: return
	if main.pcvr_test.application_paused or main.pcvr_test.standby_active or main.pcvr_test.is_exclusive(): return
	if main.pcvr_handover.state != main.pcvr_handover.State.IDLE: return
	# Watching/authentication does not change the desktop workspace.
	if main.session_lifecycle.phase != SessionLifecycle.Phase.STREAMING: return
	var control = get_xr_control()
	var config: ConfigFile = control.current_config()
	if config == null: return
	if not bool(config.get_value("host","auto_xr",true)) or not bool(config.get_value("host","handover_on_ready",false)) or not bool(config.get_value("host","relay",false)): return
	var address := str(config.get_value("host","address",""))
	var same_host := false
	for host in main.stream_backend.get_hosts():
		if host.get("id") == main.current_host_id and address in [host.get("localaddress",""),host.get("remoteaddress","")]: same_host = true
	if not same_host: return
	if control.state not in ["idle","failed"]: return
	_auto_retry = 5.0
	control.connect_offer(true)

func _init(owner: Node3D):
	main = owner

func xr_settings_available() -> bool:
	# Show setup before approval; depth-only discovery still exposes no PCVR UI.
	return main.is_streaming and _xr_control != null and (_xr_control.state in ["watching", "prepared"] or _xr_control.discovered_service_available())

func xr_encoder_capabilities() -> Dictionary:
	return _xr_control.encoder_capabilities if _xr_control != null else {}

func xr_foveation_available() -> bool:
	return _xr_control != null and _xr_control.foveation_available()

func update_xr_foveation(enabled: bool) -> bool:
	return _xr_control != null and _xr_control.queue_foveation(enabled)

func update_xr_bitrate(mbps: int) -> bool:
	return _xr_control != null and _xr_control.has_method("queue_bitrate") and _xr_control.queue_bitrate(mbps)

func xr_bitrate_message() -> String:
	if _xr_control == null: return ""
	var text = _xr_control.get("bitrate_message")
	var foveation = _xr_control.get("foveation_message")
	var messages := PackedStringArray()
	if text != null and not str(text).is_empty(): messages.append(str(text))
	if foveation != null and not str(foveation).is_empty(): messages.append(str(foveation))
	return " • ".join(messages)

func build_welcome_ui():
	cancel_xr_control()
	var root = main.welcome_viewport.get_node("WelcomeRoot")
	for child in root.get_children():
		child.queue_free()

	var twilight_images = [
		"res://src/assets/early_twilight.png",
		"res://src/assets/late_twilight.png",
		"res://src/assets/twilight_of_life.png",
		"res://src/assets/jungle_twlight.png",
	]
	var bg = TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = load(twilight_images[randi() % twilight_images.size()])
	bg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var screens = Node.new()
	screens.name = "Screens"
	root.add_child(screens)

	build_welcome_screen(screens)
	build_server_screen(screens)
	build_ip_screen(screens)
	build_name_screen(screens)
	build_pin_screen(screens)
	build_language_picker(root)
	build_notice(root)
	if OS.has_feature("android"):
		build_browser_picker(root)

	show_welcome_screen("welcome")

# Why the last connection failed. A failed launch returns to the welcome
# screens, where the in-stream menu's status line isn't visible.
func build_notice(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "WelcomeNotice"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = 104
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.02, 0.82)
	style.border_color = Color(1.0, 0.75, 0.3, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "NoticeText"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	panel.add_child(label)
	root.add_child(panel)

func show_notice(text: String) -> void:
	var panel = main.welcome_viewport.get_node_or_null("WelcomeRoot/WelcomeNotice")
	if not panel:
		return
	panel.get_node("NoticeText").text = text
	panel.visible = not text.is_empty()

func clear_notice() -> void:
	show_notice("")

## A notice about this moment only ("Already connecting to your PC..."): it
## goes away by itself after `seconds`, unless another notice has taken its
## place. Shown with show_notice() it stayed on the welcome screen behind the
## stream and was still there after the next disconnect (8g, 2026-11-17).
func show_passing_notice(text: String, seconds: float = 4.0) -> void:
	show_notice(text)
	await main.get_tree().create_timer(seconds).timeout
	if notice_text() == text:
		clear_notice()

func notice_text() -> String:
	var panel = main.welcome_viewport.get_node_or_null("WelcomeRoot/WelcomeNotice") if main.welcome_viewport else null
	return panel.get_node("NoticeText").text if panel else ""

func get_xr_control() -> RefCounted:
	# Welcome and the in-stream DEV entry share one lease and one receiver.
	if not _xr_control:
		_xr_control = preload("res://src/meteor_xr_control.gd").new(main)
		_xr_control.library_open_requested.connect(func(): main.ui_controller.open_vr_apps())
	return _xr_control

func request_xr_control() -> void:
	var control = get_xr_control()
	if control.state not in ["idle", "failed", "offered"]: return
	var config: ConfigFile = control.current_config()
	if config == null: return
	var reason := _xr_entry_busy_reason(config)
	if not reason.is_empty():
		control.message = reason
		control.changed.emit()
		return
	if control.state == "offered": control.accept_offer()
	else: control.connect_offer()

func _xr_entry_busy_reason(config: ConfigFile) -> String:
	# An in-stream entry must never fall through to the old exclusive test,
	# which is deliberately restricted to a clean welcome workspace.
	var handover := bool(config.get_value("host", "handover_on_ready", false))
	return main.pcvr_test.standby_busy_reason() if handover else main.pcvr_test.busy_reason()

func cancel_xr_control(stop_projection: bool = true, suppress_auto: bool = true) -> void:
	# Native teardown also closes this connection. Ending a game must not
	# disable detection of the next game; an explicit user cancel still does.
	if suppress_auto: _auto_suppressed = true
	else: _auto_retry = maxf(_auto_retry, 1.0)
	if _xr_control: _xr_control.cancel(stop_projection)

func retains_xr_lease_during_timing_transition() -> bool:
	return _xr_control != null and _xr_control.retains_lease_during_timing_transition()

# Browser dropdown in the top-left corner, opposite the language picker. The
# options open below the toggle, so the toggle never moves.
func build_browser_picker(root: Control) -> void:
	# In-viewport buttons rather than a popup Window, so XR input reaches
	# every option without another composition layer.
	var picker := VBoxContainer.new()
	picker.name = "BrowserPicker"
	picker.position = Vector2(24, 24)
	picker.add_theme_constant_override("separation", 8)
	root.add_child(picker)
	var toggle := Button.new()
	toggle.name = "BrowserToggle"
	toggle.text = Localization.t("Open Browser") + " ▾"
	toggle.custom_minimum_size = Vector2(360, 64)
	toggle.add_theme_font_size_override("font_size", 26)
	picker.add_child(toggle)
	var options := VBoxContainer.new()
	options.name = "BrowserOptions"
	options.add_theme_constant_override("separation", 8)
	options.visible = false
	picker.add_child(options)
	for entry in [["Open browser here", false], ["New browser screen", true]]:
		var separate: bool = entry[1]
		var option := Button.new()
		option.text = Localization.t(entry[0])
		option.custom_minimum_size = Vector2(360, 64)
		option.add_theme_font_size_override("font_size", 26)
		options.add_child(option)
		option.pressed.connect(func():
			options.hide()
			if separate: main.screen_sources.add_browser_screen()
			else: main.screen_sources.choose_source(ScreenContentTab.BROWSER))
	toggle.pressed.connect(func():
		for i in options.get_child_count():
			options.get_child(i).disabled = not (main.screen_sources.can_add_browser_screen() if i == 1 else main.screen_sources.can_open_browser())
		options.visible = not options.visible)

# Language dropdown in the top-right corner, so a new user can switch language
# before reaching the in-stream Settings page. It is a plain grid of buttons rather
# than an OptionButton, whose popup is a separate window that the projected XR
# pointer can't reach.
func build_language_picker(root: Control):
	var picker = VBoxContainer.new()
	picker.name = "LanguagePicker"
	picker.add_theme_constant_override("separation", 4)
	picker.anchor_left = 1.0
	picker.anchor_right = 1.0
	picker.offset_left = -720
	picker.offset_right = -24
	picker.offset_top = 24
	picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(picker)

	var toggle = Button.new()
	toggle.name = "LanguageToggle"
	toggle.custom_minimum_size = Vector2(260, 56)
	toggle.add_theme_font_size_override("font_size", 24)
	toggle.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	toggle.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	picker.add_child(toggle)

	var options = GridContainer.new()
	options.name = "LanguageOptions"
	options.columns = 3
	options.add_theme_constant_override("h_separation", 6)
	options.add_theme_constant_override("v_separation", 6)
	options.size_flags_horizontal = Control.SIZE_SHRINK_END
	options.visible = false
	options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picker.add_child(options)
	for language in Localization.LANGUAGES:
		var code: String = language["code"]
		var option = Button.new()
		option.text = language["name"]
		option.custom_minimum_size = Vector2(228, 56)
		option.add_theme_font_size_override("font_size", 24)
		option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		options.add_child(option)
		option.pressed.connect(func():
			options.visible = false
			main.settings_controller.set_language(code)
		)
	toggle.pressed.connect(func(): options.visible = not options.visible)
	_update_language_toggle()

func _update_language_toggle():
	var toggle = main.welcome_viewport.get_node_or_null("WelcomeRoot/LanguagePicker/LanguageToggle")
	if toggle:
		toggle.text = "%s  \u25BC" % Localization.language_name(Localization.current())

## Labels and buttons translate themselves; this refreshes text composed at
## runtime after a language change.
func retranslate():
	_update_language_toggle()
	var app_btn = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens/WelcomeScreen/WelcomeAppBtn")
	if app_btn:
		var app_name = "Desktop"
		if not main._available_apps.is_empty():
			app_name = main._available_apps[main._selected_app_idx].get("name", "Desktop")
		app_btn.text = Localization.t("App: %s") % app_name

func build_welcome_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "WelcomeScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 120)
	top_spacer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var title = Label.new()
	title.text = "Nightfall"
	title.add_theme_font_size_override("font_size", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Moonlight Streaming for Quest"
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(subtitle)

	var mid_spacer = Control.new()
	mid_spacer.custom_minimum_size = Vector2(0, 14)
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(mid_spacer)

	var server_info = VBoxContainer.new()
	server_info.add_theme_constant_override("separation", 2)
	server_info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	server_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(server_info)

	var host_label = Label.new()
	host_label.name = "WelcomeHostName"
	host_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	host_label.add_theme_font_size_override("font_size", 32)
	host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	server_info.add_child(host_label)

	var ip_label = Label.new()
	ip_label.name = "WelcomeHostIP"
	ip_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ip_label.add_theme_font_size_override("font_size", 20)
	ip_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	server_info.add_child(ip_label)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 0)
	btn_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(btn_spacer)

	var pc_icon = TextureRect.new()
	pc_icon.texture = load("res://src/assets/pc_icon.svg")
	pc_icon.custom_minimum_size = Vector2(280, 280)
	pc_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pc_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pc_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(pc_icon)

	var connect_btn = Button.new()
	connect_btn.name = "WelcomeConnect"
	connect_btn.custom_minimum_size = Vector2(400, 80)
	connect_btn.add_theme_font_size_override("font_size", 32)
	connect_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	connect_btn.text = "Connect"
	screen.add_child(connect_btn)

	var wol_btn = Button.new()
	wol_btn.name = "WelcomeWol"
	wol_btn.custom_minimum_size = Vector2(400, 60)
	wol_btn.add_theme_font_size_override("font_size", 24)
	wol_btn.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 0.8))
	wol_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wol_btn.text = "Wake PC"
	wol_btn.visible = false
	screen.add_child(wol_btn)

	var spacer1 = Control.new()
	spacer1.name = "Spacer1"
	spacer1.custom_minimum_size = Vector2(0, 10)
	spacer1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(spacer1)

	var app_btn = Button.new()
	app_btn.name = "WelcomeAppBtn"
	app_btn.custom_minimum_size = Vector2(400, 60)
	app_btn.add_theme_font_size_override("font_size", 24)
	app_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	app_btn.text = Localization.t("App: %s") % "Desktop"
	app_btn.visible = false
	screen.add_child(app_btn)

	var spacer2 = Control.new()
	spacer2.name = "Spacer2"
	spacer2.custom_minimum_size = Vector2(0, 10)
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(spacer2)

	var change_btn = Button.new()
	change_btn.name = "WelcomeChangeServer"
	change_btn.custom_minimum_size = Vector2(400, 60)
	change_btn.add_theme_font_size_override("font_size", 24)
	change_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	change_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	change_btn.text = "Select Server"
	change_btn.visible = false
	screen.add_child(change_btn)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 10)
	spacer3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(spacer3)

	var exit_btn = Button.new()
	exit_btn.name = "WelcomeExit"
	exit_btn.custom_minimum_size = Vector2(400, 60)
	exit_btn.add_theme_font_size_override("font_size", 28)
	exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	exit_btn.text = "Exit"
	screen.add_child(exit_btn)

	var bottom_pad = Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 40)
	bottom_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_pad)

	connect_btn.pressed.connect(func():
		var btn_text = connect_btn.text
		var current_ip = main.get_node("%IPInput").text
		if btn_text == "Pair" or btn_text == "Select Server":
			show_welcome_screen("server")
		elif btn_text == "Connect" and current_ip.is_empty():
			show_welcome_screen("server")
		else:
			# Quick Start is already connecting: leave that launch alone
			# (StreamManager.launch_in_flight() says why, and why here).
			if main.stream_manager.launch_is_in_flight():
				main._log("[STREAM] Connect pressed while a launch is in flight: left alone")
				show_passing_notice("Already connecting to your PC...")
				return
			connect_btn.text = "Connecting..."
			connect_btn.disabled = true
			main.start_connect_timeout()
			main.stream_manager.on_pair_pressed()
	)
	wol_btn.pressed.connect(func():
		# Parsed (port-suffix stripped) - send_wol_to_host() below sends a
		# UDP packet DIRECTLY to this address (port 9, hardcoded, unrelated
		# to any pairing port in the field), so it needs a real bare IP.
		var current_ip = main.parse_ip_port(main.get_node("%IPInput").text)[0]
		var mac = _get_host_mac(current_ip)
		if mac.is_empty():
			main._log("[WOL] No MAC address found for " + current_ip)
			wol_btn.text = "No MAC"
			return
		main._log("[WOL] Sending WoL to " + mac + " via " + current_ip)
		wol_sender.send_wol_to_host(mac, current_ip)
		wol_btn.text = "Sent!"
		await main.get_tree().create_timer(2.0).timeout
		wol_btn.text = "Wake PC"
	)
	change_btn.pressed.connect(func(): show_welcome_screen("server"))
	app_btn.button_down.connect(func(): cycle_app())
	exit_btn.pressed.connect(func(): main.get_tree().quit())

func build_server_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "ServerScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var heading = Label.new()
	heading.text = "Select Server"
	heading.add_theme_font_size_override("font_size", 48)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(heading)

	# Pairing / connection feedback (Steam Frame build): shown under the heading
	# so a click on a server always visibly does something.
	var msg = Label.new()
	msg.name = "ServerMessage"
	msg.text = ""
	msg.visible = false
	msg.add_theme_font_size_override("font_size", 26)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(1100, 0)
	msg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(msg)

	var list_spacer = Control.new()
	list_spacer.custom_minimum_size = Vector2(0, 40)
	list_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(list_spacer)

	var server_list = VBoxContainer.new()
	server_list.name = "ServerList"
	server_list.add_theme_constant_override("separation", 12)
	server_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	server_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(server_list)

	var discover_list = VBoxContainer.new()
	discover_list.name = "DiscoverList"
	discover_list.add_theme_constant_override("separation", 8)
	discover_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	discover_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(discover_list)

	var scan_spacer = Control.new()
	scan_spacer.custom_minimum_size = Vector2(0, 12)
	scan_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(scan_spacer)

	var scan_btn = Button.new()
	scan_btn.name = "ScanBtn"
	scan_btn.custom_minimum_size = Vector2(400, 70)
	scan_btn.add_theme_font_size_override("font_size", 28)
	scan_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1.0))
	scan_btn.text = "Scan Network"
	scan_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(scan_btn)

	var add_btn = Button.new()
	add_btn.name = "AddServerBtn"
	add_btn.custom_minimum_size = Vector2(400, 80)
	add_btn.add_theme_font_size_override("font_size", 36)
	add_btn.text = "+"
	add_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(add_btn)

	var bottom_spacer = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_spacer)

	var back_btn = Button.new()
	back_btn.custom_minimum_size = Vector2(300, 60)
	back_btn.add_theme_font_size_override("font_size", 28)
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(back_btn)

	var bottom_margin = Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 40)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_margin)

	add_btn.pressed.connect(func(): show_welcome_screen("ip"))
	scan_btn.pressed.connect(func(): browse_mdns())
	back_btn.pressed.connect(func(): show_welcome_screen("welcome"))

## The longest address with a port: "255.255.255.255:65535".
const IP_FIELD_MAX := 21

## What is highlighted in a text field, as [from, to]; equal when nothing is.
static func _highlighted(field: LineEdit) -> Array:
	if field.has_selection():
		return [field.get_selection_from_column(), field.get_selection_to_column()]
	return [0, 0]

static func _apply_edit(field: LineEdit, edit: Array) -> void:
	field.deselect()
	field.text = edit[0]
	field.caret_column = edit[1]

## A key pressed for a text field: it takes the place of what is highlighted,
## or goes in at the caret. Returns [text, caret]; unchanged when the result
## would be longer than max_length.
static func typed(text: String, caret: int, highlighted: Array, key: String, max_length: int) -> Array:
	var from: int = clampi(caret, 0, text.length())
	var to: int = from
	if highlighted[1] > highlighted[0]:
		from = clampi(highlighted[0], 0, text.length())
		to = clampi(highlighted[1], from, text.length())
	if text.length() - (to - from) + key.length() > max_length:
		return [text, clampi(caret, 0, text.length())]
	return [text.substr(0, from) + key + text.substr(to), from + key.length()]

## DEL for a text field: removes what is highlighted, or the character
## before the caret. Returns [text, caret].
static func deleted(text: String, caret: int, highlighted: Array) -> Array:
	if highlighted[1] > highlighted[0]:
		return typed(text, caret, highlighted, "", text.length())
	var at: int = clampi(caret, 0, text.length())
	if at == 0:
		return [text, 0]
	return [text.substr(0, at - 1) + text.substr(at), at - 1]

func build_ip_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "IPScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var heading = Label.new()
	heading.text = "Enter Server IP"
	heading.add_theme_font_size_override("font_size", 48)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(heading)

	var ip_spacer = Control.new()
	ip_spacer.custom_minimum_size = Vector2(0, 40)
	ip_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(ip_spacer)

	var ip_center = HBoxContainer.new()
	ip_center.alignment = BoxContainer.ALIGNMENT_CENTER
	ip_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(ip_center)

	var ip_input = LineEdit.new()
	ip_input.name = "IPField"
	ip_input.custom_minimum_size = Vector2(600, 80)
	ip_input.add_theme_font_size_override("font_size", 36)
	ip_input.placeholder_text = "e.g. 192.168.1.100"
	ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Pressing a key below takes the focus from the field; what is highlighted
	# has to outlive that, so the key can replace it (8w).
	ip_input.deselect_on_focus_loss_enabled = false
	ip_center.add_child(ip_input)

	var numpad_spacer = Control.new()
	numpad_spacer.custom_minimum_size = Vector2(0, 30)
	numpad_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(numpad_spacer)

	var numpad_center = CenterContainer.new()
	numpad_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(numpad_center)

	var numpad = GridContainer.new()
	numpad.name = "IPNumpad"
	numpad.columns = 3
	numpad.add_theme_constant_override("h_separation", 8)
	numpad.add_theme_constant_override("v_separation", 8)
	numpad_center.add_child(numpad)

	# ":" added (2026-08-26) so an optional custom port can be typed here too
	# ("ip:port") - matches the main %IPInput numpad in ui_controller.gd, see
	# main.gd's parse_ip_port(). Max length raised 15 -> 21 to fit it. "DEL"
	# moved out of this grid (below, next to PairBtn) - with 13 items (after
	# adding ":") a 3-column grid left DEL alone on its own final row,
	# isolated from the other keys.
	var keys = ["7","8","9","4","5","6","1","2","3",".","0",":"]
	for key in keys:
		var btn = Button.new()
		btn.text = key
		btn.custom_minimum_size = Vector2(120, 80)
		btn.add_theme_font_size_override("font_size", 36)
		numpad.add_child(btn)
		btn.pressed.connect(func():
			# At the caret, so a wrong digit in the middle can be corrected
			# after pointing at it (keys used to go on the end regardless),
			# and in place of whatever is highlighted, as typing does anywhere.
			_apply_edit(ip_input, typed(ip_input.text, ip_input.caret_column, _highlighted(ip_input), key, IP_FIELD_MAX))
		)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 30)
	btn_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(btn_spacer)

	# Pair + DEL share a row (2026-08-26) - Pair on the left, DEL on the
	# right, rather than DEL sitting alone in the numpad grid above. Widths
	# sized so the row's total width (240 + 16 separation + 120 = 376)
	# matches the numpad grid's own width (3 * 120 + 2 * 8 h_separation =
	# 376), so this row visually aligns with the grid above it.
	var action_row = HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 16)
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(action_row)

	var pair_btn = Button.new()
	pair_btn.name = "PairBtn"
	pair_btn.custom_minimum_size = Vector2(240, 90)
	pair_btn.add_theme_font_size_override("font_size", 36)
	pair_btn.text = "Pair"
	action_row.add_child(pair_btn)

	var del_btn = Button.new()
	del_btn.name = "DelBtn"
	del_btn.custom_minimum_size = Vector2(120, 90)
	del_btn.add_theme_font_size_override("font_size", 36)
	del_btn.text = "DEL"
	action_row.add_child(del_btn)
	del_btn.pressed.connect(func():
		_apply_edit(ip_input, deleted(ip_input.text, ip_input.caret_column, _highlighted(ip_input)))
	)

	var bottom_spacer = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_spacer)

	var back_btn = Button.new()
	back_btn.custom_minimum_size = Vector2(300, 60)
	back_btn.add_theme_font_size_override("font_size", 28)
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(back_btn)

	var bottom_margin = Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 40)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_margin)

	pair_btn.pressed.connect(func():
		var ip = ip_input.text
		if ip.is_empty():
			return
		main._connecting_ip = ip
		main.get_node("%IPInput").text = ip
		start_pair(ip)
	)
	back_btn.pressed.connect(func(): show_welcome_screen("server"))

func build_pin_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "PINScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var heading = Label.new()
	heading.name = "PINHeading"
	heading.text = "Enter PIN on Host"
	heading.add_theme_font_size_override("font_size", 40)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(heading)

	var pin_spacer = Control.new()
	pin_spacer.custom_minimum_size = Vector2(0, 40)
	pin_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(pin_spacer)

	var pin_label = Label.new()
	pin_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pin_label.name = "PINLabel"
	pin_label.add_theme_font_size_override("font_size", 80)
	pin_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1, 1))
	pin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pin_label.text = "----"
	pin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(pin_label)

	# Steam Frame port: what to do with the PIN, on the PC. The heading alone
	# ("Enter PIN on Host") left a first-time user to find the place.
	var help_spacer = Control.new()
	help_spacer.custom_minimum_size = Vector2(0, 30)
	help_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(help_spacer)

	var help = Label.new()
	help.name = "PINHelp"
	help.text = PIN_HELP_HOST
	help.add_theme_font_size_override("font_size", PIN_HELP_FONT)
	help.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(PIN_HELP_WIDTH, 0)
	help.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(help)

	var bottom_spacer = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_spacer)

	var back_btn = Button.new()
	back_btn.custom_minimum_size = Vector2(400, 90)
	back_btn.add_theme_font_size_override("font_size", 36)
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(back_btn)

	var bottom_margin = Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 40)
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_margin)

	back_btn.pressed.connect(func():
		pairing_finished()
		var manager = main.stream_backend.get_computer_manager()
		if manager and manager.has_method("cancel_pair"): manager.cancel_pair()
		show_welcome_screen("server"))

const WELCOME_FRAME := Vector2i(1920, 1080)

func show_welcome_screen(name: String):
	if "pcvr_test" in main and main.pcvr_test.is_exclusive(): return
	main._welcome_screen = name
	# A failed connection can navigate here while the ray is still over the
	# previous screen. Clear the world-space cursor filter before changing the
	# welcome viewport/layout, otherwise the rendered pointer can retain the old
	# hit point and appear offset until the app is restarted.
	main._reset_steady_filter()
	main.was_clicking = false
	# The welcome UI is rendered on the same shared mesh/material as the stream
	# (see main.gd's comp_shader_mat main_texture reuse), and several code paths
	# can leave that mesh in a non-16:9 state that main.layout doesn't reflect:
	# a multi-monitor stream attempt that reshapes it before the connection
	# outcome is known, or load_host_state() restoring a saved per-screen
	# mesh_size/position directly onto main.screens without ever touching
	# main.layout. Checking main.layout.frame_size alone can silently miss
	# both, so force this back to a fixed 16:9 unconditionally instead of
	# trying to detect every way it could have drifted - this function is only
	# ever shown while not actively streaming, and apply_screen_layout() is
	# cheap enough to call on every navigation click.
	if not main.is_streaming:
		main.settings_controller.apply_screen_layout(ScreenLayout.single(WELCOME_FRAME))
	var root = main.welcome_viewport.get_node("WelcomeRoot/Screens")
	for child in root.get_children():
		child.visible = false
	match name:
		"welcome":
			root.get_node_or_null("WelcomeScreen").visible = true
			update_welcome_info()
		"server":
			root.get_node_or_null("ServerScreen").visible = true
			populate_server_list()
		"ip":
			root.get_node_or_null("IPScreen").visible = true
		"name":
			root.get_node_or_null("NameScreen").visible = true
			_refresh_name_screen()
		"pin":
			var pin_screen = root.get_node_or_null("PINScreen")
			if pin_screen:
				pin_screen.visible = true
			var pin_label = root.get_node_or_null("PINScreen/PINLabel")
			if pin_label:
				pin_label.text = main._pair_pin if not main._pair_pin.is_empty() else "----"

func update_welcome_info():
	var root = main.welcome_viewport.get_node_or_null("WelcomeRoot")
	if not root:
		return
	var screens = root.get_node_or_null("Screens")
	if not screens:
		return
	var ws = screens.get_node_or_null("WelcomeScreen")
	if not ws:
		return
	# These two sit inside their own box, not directly on the page.
	var host_label = ws.find_child("WelcomeHostName", true, false)
	var ip_label = ws.find_child("WelcomeHostIP", true, false)
	var connect_btn = ws.get_node_or_null("WelcomeConnect")
	var app_btn = ws.get_node_or_null("WelcomeAppBtn")
	var change_btn = ws.get_node_or_null("WelcomeChangeServer")
	var wol_btn = ws.get_node_or_null("WelcomeWol")
	var spacer1 = ws.get_node_or_null("Spacer1")
	var spacer2 = ws.get_node_or_null("Spacer2")

	var saved_ip_raw = main.get_node("%IPInput").text
	var saved_ip = main.parse_ip_port(saved_ip_raw)[0]
	var has_saved = not saved_ip_raw.is_empty()
	var _cm = main.stream_backend.get_config_manager() if main.stream_backend else null
	var _hosts = _cm.get_hosts() if _cm else []
	var has_hosts = _hosts.size() > 0

	# The saved PC that Connect will use: its name over what the name leaves out.
	var picked := SavedHosts.pick(_hosts, main.current_host_id, saved_ip)
	var host_name := main._last_hostname as String
	var host_detail: String = saved_ip
	if host_name.is_empty() and not picked.is_empty():
		host_name = SavedHosts.title(picked)
		host_detail = SavedHosts.detail(picked)

	if has_saved:
		if connect_btn and connect_btn.text != "Connecting...":
			connect_btn.text = "Connect"
			connect_btn.disabled = false
		if not host_name.is_empty():
			if host_label: host_label.text = host_name
			if ip_label: ip_label.text = host_detail
		else:
			if host_label: host_label.text = saved_ip
			if ip_label: ip_label.text = ""
		if app_btn: app_btn.visible = true
		if change_btn: change_btn.visible = true
		if spacer1: spacer1.visible = true
		if spacer2: spacer2.visible = true
		var has_mac = not _get_host_mac(saved_ip).is_empty()
		if wol_btn: wol_btn.visible = has_mac
		if main.current_host_id >= 0:
			query_app_list()
		elif not main._available_apps.is_empty():
			if app_btn: app_btn.text = Localization.t("App: %s") % main._available_apps[main._selected_app_idx].get("name", "Desktop")
	else:
		if has_hosts:
			if connect_btn: connect_btn.text = "Connect"
		else:
			if connect_btn: connect_btn.text = "Pair"
		if host_label: host_label.text = ""
		if ip_label: ip_label.text = ""
		if app_btn: app_btn.visible = false
		if change_btn: change_btn.visible = true
		if wol_btn: wol_btn.visible = false
		if spacer1: spacer1.visible = false
		if spacer2: spacer2.visible = true

func reset_connect_button():
	var root = main.welcome_viewport.get_node_or_null("WelcomeRoot")
	if not root:
		return
	var screens = root.get_node_or_null("Screens")
	if not screens:
		return
	var ws = screens.get_node_or_null("WelcomeScreen")
	if not ws:
		return
	var connect_btn = ws.get_node_or_null("WelcomeConnect")
	if connect_btn:
		connect_btn.text = "Connect"
		connect_btn.disabled = false

func save_last_ip(ip: String, server_unique_id: String = ""):
	var save = ConfigFile.new()
	save.set_value("connection", "ip", ip)
	# server_unique_id (2026-08-27) - a host reached via NAT port-forwarding
	# can share a bare IP with a completely different, already-paired host
	# (see stream_manager.gd's on_pair_completed() fix). Startup auto-connect
	# needs this same unique_id, not just the IP, to find the right saved
	# host record - see main.gd's _init_textures_and_ui()/_try_auto_connect().
	save.set_value("connection", "server_unique_id", server_unique_id)
	save.save("user://last_connection.cfg")

func browse_mdns():
	if mdns_browsing:
		return
	mdns_browsing = true
	var ss = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens/ServerScreen")
	if not ss:
		mdns_browsing = false
		return
	var discover_list = ss.get_node_or_null("DiscoverList")
	var scan_btn = ss.get_node_or_null("ScanBtn")
	if discover_list:
		for child in discover_list.get_children():
			child.queue_free()
	if scan_btn:
		scan_btn.text = "Scanning..."
		scan_btn.disabled = true
	var hosts = await main.stream_manager.browse_mdns()
	if discover_list:
		for child in discover_list.get_children():
			child.queue_free()
	if hosts.size() > 0 and discover_list:
		for host in hosts:
			var ip = host.get("ip", "")
			var friendly = host.get("friendly_name", host.get("hostname", ip))
			# The host's HTTP port, as advertised: Sunshine on a custom port
			# (50000, say) only answers pairing there.
			var address := pair_address(ip, int(host.get("port", main.DEFAULT_PAIR_PORT)))
			# The PC's name stays out of the log: it can be a person's.
			main._log("[mDNS] Discovered: ip='" + ip + "' port=" + str(host.get("port", "?")))
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(400, 60)
			btn.add_theme_font_size_override("font_size", 22)
			btn.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			btn.text = friendly + "  " + ip
			var btn_style = StyleBoxFlat.new()
			btn_style.set_bg_color(Color(0.15, 0.18, 0.25, 0.9))
			btn_style.set_border_width_all(1)
			btn_style.set_border_color(Color(0.3, 0.4, 0.6, 0.8))
			btn_style.set_corner_radius_all(8)
			btn_style.set_content_margin_all(6)
			btn.add_theme_stylebox_override("normal", btn_style)
			var hover_style = btn_style.duplicate()
			hover_style.set_bg_color(Color(0.2, 0.25, 0.35, 1.0))
			btn.add_theme_stylebox_override("hover", hover_style)
			var press_style = btn_style.duplicate()
			press_style.set_bg_color(Color(0.3, 0.35, 0.5, 1.0))
			btn.add_theme_stylebox_override("pressed", press_style)
			btn.pressed.connect(func():
				main._log("[mDNS] Selected host: address='" + address + "'")
				# An address can now belong to a different host/profile. Pairing
				# first checks identity and verifies the saved certificate over TLS,
				# and if this machine is already paired it just records the new
				# address on the existing entry instead of pairing again.
				main.get_node("%IPInput").text = address
				save_last_ip(address)
				main.state_manager.load_host_state(address)
				start_pair(address)
			)
			discover_list.add_child(btn)
	if scan_btn:
		scan_btn.text = "Scan Network"
		scan_btn.disabled = false
	mdns_browsing = false

func populate_server_list():
	var screens = main.welcome_viewport.get_node("WelcomeRoot/Screens")
	var ss = screens.get_node("ServerScreen")
	var server_list = ss.get_node("ServerList")
	for child in server_list.get_children():
		# Out of the list at once, so the new rows get the names (Host1, ...).
		server_list.remove_child(child)
		child.queue_free()

	var hosts := _saved_hosts()
	var usb_link_up: bool = not main.stream_manager._usb_link_iface().is_empty()
	for h in hosts:
		server_list.add_child(_server_row(h, usb_link_up))

func _saved_hosts() -> Array:
	var cm = main.stream_backend.get_config_manager() if main.stream_backend else null
	return cm.get_hosts() if cm else []

const SERVER_ROW_HEIGHT := 92

## One saved PC in the list: the button that picks it (its name, and under it
## whatever the name leaves out), then Rename and Remove.
func _server_row(h: Dictionary, usb_link_up: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Host%d" % int(h.id)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pick_btn := Button.new()
	pick_btn.name = "Pick"
	pick_btn.custom_minimum_size = Vector2(560, SERVER_ROW_HEIGHT)
	pick_btn.clip_contents = true
	row.add_child(pick_btn)
	var lines := VBoxContainer.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", -2)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick_btn.add_child(lines)
	var detail := SavedHosts.detail(h)
	if not str(h.get("usb_address", "")).is_empty() and usb_link_up:
		detail = (detail + "  [USB]").strip_edges()
	for line in [[SavedHosts.title(h), 34, Color.WHITE], [detail, 20, Color(0.72, 0.78, 0.9)]]:
		if String(line[0]).is_empty():
			continue
		var label := Label.new()
		label.text = line[0]
		# Names and addresses are not words to translate.
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.add_theme_font_size_override("font_size", line[1])
		label.add_theme_color_override("font_color", line[2])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(label)
	pick_btn.pressed.connect(func():
		var ip: String = h.get("localaddress", "")
		main.get_node("%IPInput").text = ip
		save_last_ip(ip, h.get("server_unique_id", ""))
		# Before its settings are loaded: they are filed under the PC that is
		# picked, and several can share this address.
		main.current_host_id = h.id
		main.state_manager.load_host_state(ip)
		main.settings_controller.detect_polaris_host(ip, main.current_host_id)
		show_welcome_screen("welcome")
	)

	var rename_btn := _server_row_button("Rename", Color(0.7, 0.85, 1.0))
	rename_btn.name = "Rename"
	rename_btn.pressed.connect(func(): rename_saved_server(h))
	row.add_child(rename_btn)

	# Two presses, so a slip of the pointer doesn't cost a pairing.
	var remove_btn := _server_row_button("Remove", Color(0.9, 0.5, 0.5))
	remove_btn.name = "Remove"
	remove_btn.pressed.connect(func():
		if remove_btn.text == "Sure?":
			remove_saved_server(h)
			return
		remove_btn.text = "Sure?"
		await main.get_tree().create_timer(REMOVE_CONFIRM_SEC).timeout
		if is_instance_valid(remove_btn):
			remove_btn.text = "Remove"
	)
	row.add_child(remove_btn)
	return row

const REMOVE_CONFIRM_SEC := 4.0

func _server_row_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, SERVER_ROW_HEIGHT)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", color)
	return btn

## Forgets one saved PC: its pairing on this headset, its name and its saved
## settings. The PC still lists the headset among its paired devices, which
## does no harm; pairing with it again replaces that entry.
func remove_saved_server(host: Dictionary) -> void:
	var cm = main.stream_backend.get_config_manager() if main.stream_backend else null
	if cm == null:
		return
	var hosts: Array = cm.get_hosts()
	var target := SavedHosts.find(hosts, host)
	if not target.is_empty():
		var current := SavedHosts.by_id(hosts, main.current_host_id)
		cm.remove_host(target.id)
		hosts = cm.get_hosts()
		main.state_manager.forget_host_state(target, hosts)
		main._log("[PAIR] Removed one saved server, %d left" % hosts.size())
		if SavedHosts.same(current, target):
			main.current_host_id = -1
			main.get_node("%IPInput").text = ""
			save_last_ip("")
		else:
			# Removing a record renumbers the ones after it.
			main.current_host_id = SavedHosts.find(hosts, current).get("id", -1)
	populate_server_list()

# --- Naming a saved PC ---

const NAME_KEY_ROWS: Array[String] = ["1234567890", "QWERTYUIOP", "ASDFGHJKL-", "ZXCVBNM_"]
var _naming: Dictionary = {}
var _name_text := ""
var _name_shift := true
var _name_keys: Array[Button] = []

func build_name_screen(parent: Node) -> void:
	var screen := VBoxContainer.new()
	screen.name = "NameScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	parent.add_child(screen)
	_name_spacer(screen, 0, true)

	var heading := Label.new()
	heading.text = "Name This PC"
	heading.add_theme_font_size_override("font_size", 48)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(heading)

	var which := Label.new()
	which.name = "NameWhich"
	which.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	which.add_theme_font_size_override("font_size", 24)
	which.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
	which.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	which.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(which)
	_name_spacer(screen, 24)

	var field := Label.new()
	field.name = "NameField"
	field.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	field.custom_minimum_size = Vector2(700, 80)
	field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	field.add_theme_font_size_override("font_size", 40)
	field.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var field_box := StyleBoxFlat.new()
	field_box.set_bg_color(Color(0.08, 0.1, 0.16, 0.9))
	field_box.set_border_width_all(1)
	field_box.set_border_color(Color(0.3, 0.4, 0.6, 0.8))
	field_box.set_corner_radius_all(8)
	field.add_theme_stylebox_override("normal", field_box)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(field)
	_name_spacer(screen, 24)

	_name_keys.clear()
	for keys in NAME_KEY_ROWS:
		var line := _name_row(screen)
		for ch in keys:
			var key := _name_key(ch, 84, func(): _name_type(ch))
			# A letter is not a word to translate.
			key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			key.set_meta("letter", ch)
			_name_keys.append(key)
			line.add_child(key)
		_name_spacer(screen, 8)
	var edit_row := _name_row(screen)
	edit_row.add_child(_name_key("Shift", 170, func():
		_name_shift = not _name_shift
		_refresh_name_screen()))
	edit_row.add_child(_name_key("Space", 300, func(): _name_type(" ")))
	edit_row.add_child(_name_key("Del", 170, func():
		_name_text = _name_text.left(maxi(0, _name_text.length() - 1))
		_refresh_name_screen()))
	edit_row.add_child(_name_key("Clear", 170, func():
		_name_text = ""
		_name_shift = true
		_refresh_name_screen()))
	_name_spacer(screen, 20)

	var hint := Label.new()
	hint.text = "Leave the name empty to show the PC's own name."
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(hint)
	_name_spacer(screen, 20)

	var action_row := _name_row(screen)
	action_row.add_theme_constant_override("separation", 16)
	var save_btn := _name_key("Save", 240, func(): _save_name())
	save_btn.name = "NameSave"
	save_btn.custom_minimum_size.y = 90
	action_row.add_child(save_btn)
	var cancel_btn := _name_key("Cancel", 240, func(): show_welcome_screen("server"))
	cancel_btn.name = "NameCancel"
	cancel_btn.custom_minimum_size.y = 90
	action_row.add_child(cancel_btn)
	_name_spacer(screen, 0, true)
	_name_spacer(screen, 40)

func _name_spacer(parent: Node, height: int, expand: bool = false) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	if expand:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)

func _name_row(parent: Node) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return line

func _name_key(text: String, width: int, action: Callable) -> Button:
	var key := Button.new()
	key.text = text
	key.focus_mode = Control.FOCUS_NONE
	key.custom_minimum_size = Vector2(width, 72)
	key.add_theme_font_size_override("font_size", 32)
	key.pressed.connect(action)
	return key

func _name_type(letter: String) -> void:
	if _name_text.length() < SavedHosts.NAME_MAX:
		_name_text += letter if _name_shift else letter.to_lower()
	# Shift holds for one letter, and comes back for the start of each word.
	_name_shift = letter == " "
	_refresh_name_screen()

func _refresh_name_screen() -> void:
	var screen = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens/NameScreen")
	if not screen:
		return
	screen.get_node("NameWhich").text = SavedHosts.described(_naming)
	screen.get_node("NameField").text = _name_text + "_"
	for key in _name_keys:
		var letter: String = key.get_meta("letter")
		key.text = letter if _name_shift else letter.to_lower()

func rename_saved_server(host: Dictionary) -> void:
	_naming = host
	_name_text = str(host.get("name", ""))
	_name_shift = _name_text.is_empty()
	show_welcome_screen("name")

func _save_name() -> void:
	var cm = main.stream_backend.get_config_manager() if main.stream_backend else null
	var target := SavedHosts.find(_saved_hosts(), _naming)
	if cm and not target.is_empty():
		cm.update_host(target.id, {"name": SavedHosts.clean_name(_name_text)})
	show_welcome_screen("server")

func start_pair(ip: String):
	main.get_node("%IPInput").text = ip
	var parsed = main.parse_ip_port(ip)
	var host_ip: String = parsed[0]
	var host_port: int = parsed[1]
	main._log("[PAIR] Starting pair with %s:%d..." % [host_ip, host_port])
	var pin = main.stream_backend.start_pair(host_ip, host_port)
	main._log("[PAIR] start_pair completed")
	if str(pin) == "" or str(pin) == "0":
		main._log("[PAIR] FAILED - no pin returned")
		return
	show_pin_when_needed(str(pin))

# Pairing first checks whether the server already knows this client (a known
# machine reached by a new address, say over USB Link); that answers
# "Already paired" within a moment. The PIN only shows if the check hasn't
# finished by then, so a known machine doesn't flash a PIN it never needs.
const PIN_DELAY_SEC := 1.0
var _pin_pending := 0

# The PIN screen's heading and the line under the PIN, for each stage:
# the PIN is to be typed on the host; Meteor has taken the request and asks
# on the PC; nobody answered within Meteor's minute.
const PIN_HEAD_HOST := "Enter PIN on Host"
const PIN_HEAD_METEOR := "Approve pairing on your PC"
const PIN_HEAD_EXPIRED := "Pairing request expired"
const PIN_HELP_HOST := "On your PC, open the streaming host's web page (Sunshine, Apollo or Vibepollo), find PIN or Clients, and type this PIN."
const PIN_HELP_METEOR := "Nightfall Meteor on your PC is asking: choose Yes in its window.\nNo window? Right-click the Meteor icon by the clock and choose Approve pairing."
const PIN_HELP_EXPIRED := "A request lasts one minute. Press Back and pair again, or type the PIN on the host's web page."
const PIN_HELP_FONT := 28
const PIN_HELP_WIDTH := 1300.0
const PIN_APPROVAL_SECONDS := 60.0

## Sets the PIN screen's heading and help line together.
func set_pin_stage(heading_text: String, help_text: String) -> void:
	if main.welcome_viewport == null:
		return
	var heading = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens/PINScreen/PINHeading")
	var help = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens/PINScreen/PINHelp")
	if heading: heading.text = heading_text
	if help: help.text = help_text

func show_pin_when_needed(pin: String) -> void:
	main._pair_pin = pin
	_pin_pending += 1
	var ticket := _pin_pending
	await main.get_tree().create_timer(PIN_DELAY_SEC).timeout
	if ticket == _pin_pending:
		show_welcome_screen("pin")
		set_pin_stage(PIN_HEAD_HOST, PIN_HELP_HOST)
		var address: Array = main.parse_ip_port(main.get_node("%IPInput").text)
		var identity: String = main.stream_backend.get_last_paired_unique_id()
		var xr_identity: String = get_xr_control().public_identity()
		var offered := await MeteorHostPairing.request(main, address[0], address[1], pin, identity, xr_identity, func(): return ticket == _pin_pending)
		if offered and ticket == _pin_pending:
			set_pin_stage(PIN_HEAD_METEOR, PIN_HELP_METEOR)
			main._log("[PAIR] Meteor is waiting for desktop approval")
			await main.get_tree().create_timer(PIN_APPROVAL_SECONDS).timeout
			if ticket == _pin_pending:
				set_pin_stage(PIN_HEAD_EXPIRED, PIN_HELP_EXPIRED)

## Text under "Select Server" ("" hides it). error = red, otherwise light blue.
func set_server_message(text: String, error: bool = false) -> void:
	var msg = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens/ServerScreen/ServerMessage") if main.welcome_viewport else null
	if msg == null:
		return
	msg.text = text
	msg.visible = not text.is_empty()
	msg.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if error else Color(0.7, 0.85, 1.0))

## Called when pairing finishes, either way: a PIN still waiting stays hidden.
func pairing_finished() -> void:
	_pin_pending += 1

func cycle_app():
	if main._available_apps.is_empty():
		return
	main._selected_app_idx = (main._selected_app_idx + 1) % main._available_apps.size()
	main._selected_app_id = main._available_apps[main._selected_app_idx].get("id", 881448767)
	var app_name = main._available_apps[main._selected_app_idx].get("name", "Desktop")
	var screens = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens")
	if not screens:
		return
	var app_btn = screens.get_node_or_null("WelcomeScreen/WelcomeAppBtn")
	if app_btn:
		app_btn.text = Localization.t("App: %s") % app_name

# The address to pair with, in the form main.parse_ip_port() reads: the bare
# address on the default port, else "ip:port", or "[v6]:port" for IPv6.
static func pair_address(ip: String, port: int) -> String:
	if port <= 0 or port > 65535 or port == 47989:
		return ip
	if ip.contains(":"):
		return "[%s]:%d" % [ip, port]
	return "%s:%d" % [ip, port]

# Hosts list apps in their own order (vibepollo also pulls in Lutris games), and
# the first entry is preselected - so pin Desktop, then Steam, ahead of the rest.
# Everything else keeps the host's order.
static func order_apps(apps: Array) -> Array:
	var rank := func(app) -> int:
		var name := String(app.get("name", "")).strip_edges().to_lower()
		if name == "desktop":
			return 0
		if name.begins_with("steam"):
			return 1
		return 2
	var indexed := []
	for i in apps.size():
		indexed.append([rank.call(apps[i]), i, apps[i]])
	indexed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var ordered := []
	for entry in indexed:
		ordered.append(entry[2])
	return ordered

func query_app_list():
	if main.current_host_id < 0:
		return
	main.stream_backend.get_app_list(main.current_host_id, func(success: bool):
		if success:
			var _cm3 = main.stream_backend.get_config_manager() if main.stream_backend else null
			main._available_apps = order_apps(_cm3.get_apps(main.current_host_id) if _cm3 else [])
			if main._available_apps.is_empty():
				main._available_apps = [{"name": "Desktop", "id": 881448767}]
			main._selected_app_idx = 0
			main._selected_app_id = main._available_apps[0].get("id", 881448767)
			var app_name = main._available_apps[0].get("name", "Desktop")
			var screens = main.welcome_viewport.get_node_or_null("WelcomeRoot/Screens")
			if screens:
				var app_btn = screens.get_node_or_null("WelcomeScreen/WelcomeAppBtn")
				if app_btn:
					app_btn.text = Localization.t("App: %s") % app_name
					app_btn.visible = true
	)

func _get_host_mac(ip: String) -> String:
	var _cm = main.stream_backend.get_config_manager() if main.stream_backend else null
	var hosts = _cm.get_hosts() if _cm else []
	for h in hosts:
		if main.host_matches_address(h, ip):
			var mac = h.get("mac", "")
			if not mac.is_empty() and mac != "00:00:00:00:00:00":
				return mac
	return ""
