extends SceneTree

# Steam Frame 7b and 7c: the display rate that goes with a stream rate, the
# command that asks SteamVR for it, and telling a camera add-on apart.

func _init() -> void:
	_rates()
	_command()
	_addons()
	_in_use()
	_auto_rate()
	print("All frame_7b tests passed")
	quit()

func _rates() -> void:
	# A rate SteamVR has: that rate.
	for rate in [72, 90, 120, 144]:
		assert(FrameDisplayRate.rate_for(float(rate)) == rate)
	# Nightfall shows a 60 fps stream at 120 Hz and a 30 fps one at 90.
	assert(FrameDisplayRate.rate_for(120.0) == 120)
	assert(FrameDisplayRate.rate_for(90.0) == 90)
	# Anything else: the next rate up, never above the highest.
	assert(FrameDisplayRate.rate_for(60.0) == 72)
	assert(FrameDisplayRate.rate_for(100.0) == 120)
	assert(FrameDisplayRate.rate_for(89.7) == 90)   # a rate reported a hair low
	assert(FrameDisplayRate.rate_for(200.0) == 144)

func _command() -> void:
	var args := FrameDisplayRate.arguments("1234567890", 90)
	assert(args[args.size() - 3] == "--set-settings-int")
	assert(args[args.size() - 2] == "steam.app.1234567890.preferredRefreshRate")
	assert(args[args.size() - 1] == "90")
	assert(args.has(FrameDisplayRate.VRCMD))
	# SteamVR's tool must not inherit Nightfall's library path, and must not hang the app.
	assert(args.find("LD_LIBRARY_PATH") < args.find(FrameDisplayRate.VRCMD))
	assert(args.find("timeout") < args.find(FrameDisplayRate.VRCMD))
	# Not started from the Steam shortcut: nothing is run.
	if not OS.get_environment("SteamAppId").is_valid_int():
		assert(FrameDisplayRate.ask(90) != "")

# 7c: telling a camera add-on from the headset's own cameras, by the sensor
# names the system lists (taken from the 7b log).
func _addons() -> void:
	assert(FramePassthroughCamera.sensor_chip("arcimx616 0-0010") == "arcimx616")
	assert(FramePassthroughCamera.sensor_chip("og01a1b 4-0060") == "og01a1b")
	# Pipeline stages and the video decoder are not sensors.
	for other in ["msm_csiphy0", "msm_vfe0_rdi0", "qcom-iris-decoder", "msm_metadata0_metadataout0", "", "two words", "a b c"]:
		assert(FramePassthroughCamera.sensor_chip(other) == "", other)
	var frame := PackedStringArray(["msm_csiphy0", "og01a1b 4-0060", "og01a1b 4-0036", "og0ve10 5-0060", "og0ve10 5-003e", "qcom-iris-decoder"])
	assert(FramePassthroughCamera.addons_among(frame).is_empty())
	frame.append_array(PackedStringArray(["arcimx616 0-0010", "arcimx616 0-001a"]))
	assert(FramePassthroughCamera.addons_among(frame) == PackedStringArray(["arcimx616"]))   # each chip once
	# A camera nobody has made yet counts as an add-on too.
	assert(FramePassthroughCamera.addons_among(PackedStringArray(["newcam9 2-0030"])) == PackedStringArray(["newcam9"]))

# 7e: which camera is running, and Camera FPS Limit Auto's patience.
func _in_use() -> void:
	var own := [["og01a1b 4-0060", "active"], ["og01a1b 4-0036", "active"], ["og0ve10 5-0060", "active"], ["og0ve10 5-003e", "active"]]
	# The headset's own sensors read "active" either way; only the add-on's count.
	assert(not FramePassthroughCamera.addon_running_among(own))
	assert(FramePassthroughCamera.addon_running_among(own + [["arcimx616 0-0010", "active"], ["arcimx616 0-001a", "active"]]))
	assert(not FramePassthroughCamera.addon_running_among(own + [["arcimx616 0-0010", "suspended"], ["arcimx616 0-001a", "suspended"]]))
	assert(not FramePassthroughCamera.addon_running_among([]))
	# In use at once when it runs; let go only after the wait, and not before.
	assert(FramePassthroughCamera.still_in_use(false, true, 0, 20000))
	assert(FramePassthroughCamera.still_in_use(true, false, 19000, 20000))
	assert(not FramePassthroughCamera.still_in_use(true, false, 20000, 20000))
	assert(not FramePassthroughCamera.still_in_use(false, false, 0, 20000))
	assert(SettingsController.CAMERA_LIMIT_LABELS == ["Auto", "On", "Off"])
	assert(AppSettings.new().frame_camera_limit == SettingsController.CAMERA_LIMIT_AUTO)

# 7h: Hz Cap Auto for the headset's depth model.
func _auto_rate() -> void:
	# What a model's speed allows: Light (about 20 ms) the full 20, Detail
	# (54 to 72 ms) 13 down to the floor, an unknown time the ceiling.
	assert(FrameDepthAutoRate.model_ceiling(20.0) == 20)
	assert(FrameDepthAutoRate.model_ceiling(61.0) == 13)
	assert(FrameDepthAutoRate.model_ceiling(72.0) == 12)
	assert(FrameDepthAutoRate.model_ceiling(0.0) == 20)
	assert(FrameDepthAutoRate.model_ceiling(400.0) == FrameDepthAutoRate.FLOOR_HZ)
	var auto := FrameDepthAutoRate.new()
	auto.reset()
	assert(auto.rate() == 20)
	# Holding 90 of 90 with a fast model: nothing changes.
	for i in 5:
		assert(auto.on_sample(90.0, 90.0, 20.0) == -1)
	# A second short of the rate: a quarter off. Another: down to the floor, and no further.
	assert(auto.on_sample(70.0, 90.0, 20.0) == 15)
	assert(auto.on_sample(70.0, 90.0, 20.0) == 12)
	assert(auto.on_sample(70.0, 90.0, 20.0) == -1)
	assert(auto.rate() == 12)
	# Good seconds bring it back, slowly, and never past the ceiling.
	var seen := 12
	for i in 40:
		var next := auto.on_sample(90.0, 90.0, 20.0)
		if next > 0:
			assert(next > seen)
			seen = next
	assert(seen == 20 and auto.rate() == 20)
	# The slow model caps it whatever the frame rate does.
	assert(auto.on_sample(90.0, 90.0, 61.0) == 13)
	assert(auto.rate() == 13)
	# How many pictures the PC sends plays no part (7i): a still desktop sends
	# few, and Auto took that for the headset falling behind.
	auto.reset()
	for i in 10:
		assert(auto.on_sample(144.0, 144.0, 20.0) == -1)
	assert(auto.rate() == 20)
