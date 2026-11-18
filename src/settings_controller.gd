class_name SettingsController
extends RefCounted
const PCVRTiming = preload("res://src/pcvr_timing_policy.gd")
var pcvr_timing := PCVRTiming.new()
var _pcvr_wait_for_desktop := false
var _pcvr_previous_render_cap := 0

var main: Node3D
var _restart_pending: bool = false
var _restart_seq: int = 0
var _last_applied_virtual_count: int = 0
var _ai_3d_commit_seq: int = 0
var _last_effective_backend: int = -1
var _last_backend_status: String = ""
var _auto_depth_fallback: bool = false
var _stereo_sdr_shader: Shader = null
var _stereo_picture_shader: Shader = null
var _refresh_request_seq: int = 0
var _last_sbs_mode: int = 1

var sbs_labels: Array = ["Off", "Stretch", "Crop"]
# MiDaS-GPU (stereo_mode 5) is REMOVED, not disabled - its underlying
# fp16 model/weights, gradle deps, and Java code are gone
# (DepthEstimator.java, build.sh). The real bug (wrong quantization
# parameters on the w8a8 model, see git history 2026-08-18) is fixed now,
# so GPU isn't needed as a working comparison point anymore. Don't restore
# a mapping for stereo_mode 5 without re-adding that code.
# The original "MiDaS" mode (a single-sample parallax shift, stereo_mode 3)
# is REMOVED too (2026-08-18) - stereo_mode 3/4's shader branch in
# yuv_display.gdshader is dead code left in place (harmless, costs nothing
# unless selected) rather than deleted - see stereo_mode 4/5's own history
# for the same pattern.
#
# Collapsed (2026-08-24) from four independent controls (model/backend/
# quality/debug) down to two, per user request - "AI 3D" and "AI Model" felt
# like they should each be a single toggle, not four:
#   ai_3d_speed_labels  - is AI-3D on at all, and at which performance tier.
#                         Off/Auto/Fast/Standard - absorbs both the
#                         old on/off state (previously ai_3d_model==0) and
#                         the old ai_3d_quality_labels tier picker. Fast/
#                         Standard directly select depth_estimator.gd's
#                         warp_tier 1/0 (see MiDaS-Fast's own history in
#                         main.gd for what it trades off - Fastest/tier 2
#                         was removed 2026-08-25, on-device benchmarking
#                         showed it near-identical to Fast at every tested
#                         resolution). Auto instead picks BOTH a tier and a
#                         model from the current resolution/passthrough
#                         state, via a literal lookup table (AUTO_TABLE
#                         below) built from an on-device GPU-inference
#                         benchmark matrix, not a formula - see
#                         resolve_quality_tier()/get_auto_selection() below.
#   ai_3d_models        - WHICH model, dictionaries of {label, java_index,
#                         gpu}. Re-split back into two independent
#                         controls (2026-08-28, AI 3D tab) - Model here and
#                         Type (main.settings.host.ai_3d_backend_pref, GPU/CPU) are now
#                         orthogonal, matching Mode/Debug's own independence
#                         above; gpu records which Type exposes each entry.
#                         Linux has CPU and Vulkan entries for MiDaS and
#                         DA-V2-252, while platform flags hide unavailable
#                         variants. YOLO26-N/
#                         MiDaS/Depth Anything V2 all share the exact same
#                         downstream warp/postProcess pipeline
#                         (DepthEstimator.java's postProcess() works on a
#                         plain float[] regardless of source model, and the
#                         warp shaders read textureSize(depth_texture, 0)
#                         dynamically), so the speed-tier selection above is
#                         completely orthogonal to which model is active -
#                         only apply_stereo()'s final set_depth_model() call
#                         and depth_estimator.gd's sync_model_size() (256 vs
#                         YOLO's 768) need to know which one is picked here.
#   ai_3d_debug_labels  - debug depth-data VIEWS
#                         (DMap/-Raw/-Input/-Warp), overlaid
#                         on whichever tier is active rather than a mode of
#                         its own - see get_stereo_mode() and
#                         _schedule_ai_3d_commit(). Left untouched by this
#                         collapse (still its own hidden/disabled button).
# History prior to the collapse (model roster, retired entries, etc.) lives
# in git blame for this file rather than repeated here - see commits through
# 2026-08-20 for the YOLO26-S/MiDaS-GPU/YOLO26-N-resolution/7-way-lineup
# history that produced the roster below.
var ai_3d_speed_labels: Array = ["Off", "Auto", "Fast", "Standard"]
# Persisted values: 0 protects stream/render cadence (the product default),
# while 1 gives the inference delegate the driver's normal-priority context.
# "AI 3D" describes that user-visible tradeoff more clearly than "Default".
var ai_3d_gpu_priority_labels: Array = ["Stream", "Adaptive", "AI 3D"]
const AI3D_GPU_PRIORITY_STREAM := 0
const AI3D_GPU_PRIORITY_ADAPTIVE := 1
const AI3D_GPU_PRIORITY_AI_3D := 2
var _ai3d_pacer := Ai3dAdaptivePacer.new()
var ai_3d_gpu_api_labels: Array = ["OpenCL", "OpenGL"] # GPU delegate choice only; "CPU" (get_ai_3d_gpu_api_label()) is a third state layered on top, not index 2 here - it's not a GPU delegate backend at all.
const MODEL_ZIPDEPTH_384 := 2
const ANDROID_MODEL_AUTO := 9
# Stable persisted/UI slots repurposed for the final Android quality tiers.
# The historical entries remain in ai_3d_models below so old saves and Linux
# indices do not shift; Android cycles only Auto and the manual EdgePad slots.
const ANDROID_MODEL_STANDARD := 18
# Slot 19 uses the square EdgePad-256 model for Quest 2 and GPU fallback.
const ANDROID_MODEL_LEGACY_EDGEPAD_256 := 19
const ANDROID_MODEL_EDGEPAD_320 := 21
const ANDROID_MODEL_EDGEPAD_256_CPU := 22
const ANDROID_MODEL_EDGEPAD_384_CPU := 23
const ANDROID_MODEL_LEGACY_EDGEPAD_384 := 24
const ANDROID_DEPTH_PROCESS_FULL := 5
# Native renderer-only production mode: retain Full's occlusion/Newton warp,
# but resize the reconstructed Standard depth with one linear texture sample
# instead of running the 5x5 joint-bilateral pass.
const ANDROID_DEPTH_PROCESS_FULL_LINEAR := 6
# Native renderer-only experiment: four bilinear depth taps receive
# scale-matched colour weights only where those taps already contain a depth
# boundary. Flat-depth text and texture therefore remain ordinary linear.
const ANDROID_DEPTH_PROCESS_FULL_GUIDED_LINEAR := 7
# Back to its original 5-entry shape (2026-08-28, AI 3D tab - briefly
# deduplicated to 3 entries with an independent Type control, corrected
# after clarifying the actual request: Type doesn't just gate Model, it
# FILTERS which entries Model cycles through. Linux deliberately exposes a
# compact production-oriented roster: Vulkan
# shows only ZipDepth-384, while CPU keeps MiDaS-256 and DA-V2-252 as
# compatibility/tinkering choices. Historical slots remain in this array so
# persisted indices and Android mappings never shift; `linux = false` merely
# removes them from Linux's Model cycle.
# cycle_ai_3d_model() below only cycles entries whose .gpu matches
# main.settings.host.ai_3d_backend_pref;
# cycle_ai_3d_type() snaps main.settings.host.ai_3d_model to the new Type's first entry
# whenever the current selection doesn't match. Same order/indices as the
# original list for MiDaS-256-GPU (0) and MiDaS-192-GPU (1), so AUTO_TABLE/
# QUEST2_AUTO_TABLE's stored model_idx values need no changes. ZipDepth
# entries (below) are additive on top of this same 5-entry shape.
var ai_3d_models: Array = [
	{"label": "MiDaS-256-GPU", "java_index": 3, "gpu": true, "linux": false},
	{"label": "MiDaS-192-GPU", "java_index": 10, "gpu": true, "linux": false},
	{"label": "ZipDepth-384-GPU", "java_index": 14, "gpu": true},
	{"label": "MiDaS-192", "java_index": 10, "gpu": false, "linux": false},
	{"label": "MiDaS-256", "java_index": 3, "gpu": false},
	{"label": "DA-V2-252", "java_index": 1, "gpu": false},
	{"label": "ZipDepth-512x288-GPU (Experimental)", "java_index": 15, "gpu": true, "linux": false},
	{"label": "ZipDepth-672x384-GPU (Experimental)", "java_index": 16, "gpu": true, "linux": false},
	# Keep this appended so existing persisted indices for the experimental
	# widescreen GPU models do not change. Type=CPU includes it in the model
	# cycle; it shares Java index 14 with the GPU entry above, while Type selects
	# the full-head W8A32/XNNPACK interpreter instead of the GPU delegate.
	{"label": "ZipDepth-384", "java_index": 14, "gpu": false, "linux": false},
	# Android-only entries appended to preserve existing saved model indices.
	{"label": "Auto", "java_index": 14, "gpu": true, "android": true, "linux": false},
	{"label": "Fastest", "java_index": 18, "gpu": true, "android": true, "linux": false},
	# Linux Vulkan variant; appended so every existing persisted index remains stable.
	{"label": "DA-V2-252-GPU", "java_index": 1, "gpu": true, "android": false, "linux": false},
	# Temporary exact-graph optimization comparison. Appended so every
	# existing persisted model index remains stable.
	{"label": "ZipDepth-384-Standard-v2-GPU", "java_index": 19, "gpu": true, "android": true, "linux": false},
	{"label": "ZipDepth-384-Hybrid-v2-GPU", "java_index": 20, "gpu": true, "android": true, "linux": false},
	{"label": "ZipDepth-384-Standard-v3-GPU", "java_index": 21, "gpu": true, "android": true, "linux": false},
	{"label": "Fast", "java_index": 22, "gpu": true, "android": true, "linux": false},
	{"label": "ZipDepth-384-Standard-Packed-GPU", "java_index": 23, "gpu": true, "android": true, "linux": false},
	{"label": "ZipDepth-384-Standard-Optimized-GPU", "java_index": 24, "gpu": true, "android": true, "linux": false},
	{"label": "EdgePad-512", "java_index": 25, "gpu": true, "android": true, "linux": false},
	{"label": "EdgePad-256", "java_index": 26, "gpu": true, "android": true, "linux": false},
	{"label": "Direct-128", "java_index": 27, "gpu": true, "android": true, "linux": false},
	# Retired slot: retain persisted indices; never selectable or bundled.
	{"label": "EdgePad-320 (retired)", "java_index": 28, "gpu": true, "android": false, "linux": false},
	# CPU twins (XNNPACK, no GPU delegate) - selected via the "Backend"
	# control's CPU option, not the locked Model list. _android_cpu_model_index()
	# picks between them to match whatever Model is actually selected.
	{"label": "EdgePad-256-CPU", "java_index": 29, "gpu": false, "android": true, "linux": false},
	{"label": "EdgePad-384-CPU", "java_index": 14, "gpu": false, "android": true, "linux": false},
	# Exact square v0.7.11 export. It uses a fresh Java index because index 25
	# now belongs to the current widescreen EdgePad-512 model.
	{"label": "EdgePad-384 (Reference)", "java_index": 30, "gpu": true, "android": true, "linux": false},
]
var ai_3d_debug_labels: Array = ["Off", "DMap-Final", "DMap-Raw", "DMap-Input", "DMap-Warp"]
var ai_3d_process_debug_labels: Array = ["Off", "Raw", "Spatial", "Guided", "Occlusion", "Full"]
const AI3D_BACKEND_CPU := 1
const AI3D_BACKEND_GPU := 2
const AI3D_HZ_CAP_VALUES: Array = [12, 15, 20, 30, 40, 60]
const AI3D_SEPARATION_VALUES: Array = [50, 75, 100, 125, 150, 200]
const AI3D_CONVERGENCE_VALUES: Array = [30, 40, 50, 60, 70]
const AI3D_CURSOR_POSITION_LABELS: Array = ["Left", "Default", "Right"]
# stereo_screen.gdshader's own live-path separation constant (mesh-
# projection rendering, not the composition path yuv_display.gdshader
# covers) - independently tuned to a different magnitude than
# depth_estimator.gd's _pass_parallax (0.006), matching that file's own
# comment about the two paths never having been unified. Scaled by
# main.settings.host.ai_3d_separation_pct the same way, just against its own base.
const STEREO_SCREEN_BASE_PARALLAX := 0.042

# Picture tab (2026-08-31). Brightness is additive (-20%..20%, mapped to
# -0.2..0.2 in apply_filter()); Contrast/Gamma are multiplier/exponent-style
# like AI3D_SEPARATION_VALUES above (50%..150% around a neutral 100%).
const PICTURE_BRIGHTNESS_VALUES: Array = [-20, -10, 0, 10, 20]
const PICTURE_CONTRAST_VALUES: Array = [50, 75, 100, 125, 150]
const PICTURE_GAMMA_VALUES: Array = [50, 75, 100, 125, 150]

# HorizonOS v2.7 accepts arbitrary integer display rates through 207 Hz on
# Quest 3 using the standard API. Rates above that require developer-only
# global display scaling, so they are deliberately not exposed here.
# Keep the stream choices device-independent. apply_display_refresh_rate()
# requests the unlisted standard extended rates only on known Quest 3
# hardware, then verifies them and falls back to the runtime's reported list.
const STREAM_FPS_RATES: Array = [30, 60, 72, 90, 120, 144, 165, 200, 207]
const QUEST3_REFRESH_REQUEST_MAX := 207.0
# The Quest runtime recreates display surfaces asynchronously after accepting
# a refresh-rate request. Do not allocate/resize any stream GLES resources
# until that transition has completed. A fixed post-request settling window is
# intentional: get_display_refresh_rate() can report the new value before the
# Android surface transition itself has finished.
const REFRESH_SURFACE_SETTLE_SEC := 0.35

# Auto-mode resolution classification (2026-08-25) - aspect first (ultrawide
# vs 16:9; 2560x1080's aspect is 2.37 and 3440x1440's is 2.39, both cleanly
# separated from 16:9's 1.778 by a 2.0 threshold), then bucket by pixel
# count within that aspect class at the midpoint between each pair of named
# reference resolutions - anything below the lowest or above the highest
# named bucket clamps to the nearest end rather than extrapolating. See
# _classify_auto_resolution()/get_auto_selection() below.
const AUTO_ASPECT_ULTRAWIDE_THRESHOLD := 2.0
const AUTO_CLASS_16_9 := [
	{"name": "720p", "px": 1280 * 720},
	{"name": "HD", "px": 1920 * 1080},
	{"name": "2K", "px": 2560 * 1440},
	{"name": "4K", "px": 3840 * 2160},
]
const AUTO_CLASS_ULTRAWIDE := [
	{"name": "21:9 HD", "px": 2560 * 1080},
	{"name": "21:9 2K", "px": 3440 * 1440},
]

# The Auto-mode target table (2026-08-25, on-device GPU-inference benchmark
# matrix - MiDaS-192-GPU/MiDaS-256-GPU x Fast/Fastest/Standard x six
# resolution classes x passthrough on/off, Quest 3/3s). A literal lookup,
# NOT a formula - which model wins (192 vs 256) does not follow a
# monotonic rule against resolution or passthrough alone (2K-on picks 192
# but 2K-off picks 256; 21:9-2K-on picks 256 but -off picks 192) - these
# are direct empirical judgment calls per combo. tier: 0=Standard/1=Fast
# (matches depth_estimator.gd's warp_tier - Fastest/2 was removed the same
# day). model_idx: index into ai_3d_models above (0=MiDaS-256, 1=MiDaS-192
# - Auto never picks DA-V2, and always resolves to GPU - see
# get_depth_backend_index()). cap_px: 0 = no
# cap, else the sqrt-pixel-budget resolution cap compute_requested_resolution()
# applies (replaces the old flat MIDAS_FAST_MAX_PIXELS/MIDAS_FASTEST_MAX_PIXELS
# constants, which this table's per-combo caps supersede - see main.gd).
# Keyed by class name, then main.settings.passthrough_enabled (bool).
const AUTO_TABLE := {
	"720p":    {false: {"tier": 0, "model_idx": 0, "cap_px": 0}, true: {"tier": 0, "model_idx": 0, "cap_px": 0}},
	"HD":      {false: {"tier": 0, "model_idx": 0, "cap_px": 0}, true: {"tier": 1, "model_idx": 0, "cap_px": 0}},
	"21:9 HD": {false: {"tier": 1, "model_idx": 0, "cap_px": 0}, true: {"tier": 1, "model_idx": 0, "cap_px": 0}},
	"2K":      {false: {"tier": 1, "model_idx": 0, "cap_px": 0}, true: {"tier": 1, "model_idx": 1, "cap_px": 0}},
	"21:9 2K": {false: {"tier": 1, "model_idx": 1, "cap_px": 0}, true: {"tier": 1, "model_idx": 0, "cap_px": 2560 * 1080}},
	"4K":      {false: {"tier": 1, "model_idx": 0, "cap_px": 2560 * 1440}, true: {"tier": 1, "model_idx": 1, "cap_px": 2560 * 1440}},
}

# Quest 2 Auto table (2026-08-27) - NOT benchmarked on real Quest 2 hardware
# (none available) - extrapolated from Meta's own published XR2 Gen 1 vs
# Gen 2 GPU figures (roughly 2-2.5x slower on Quest 2, worse under sustained
# thermal load) applied to the real Quest 3 benchmark data above. main.gd's
# QUEST2_MAX_RESOLUTION already hard-caps the stream to 1080p before this
# table is even consulted (Quest 2's own display is lower-res than Quest 3's
# anyway, and dividing AUTO_TABLE's 4K/cap_px=2560x1440 entry by ~2.2x lands
# almost exactly on 1080p's pixel count) - so only 720p/HD rows exist here,
# always the cheapest surviving tier+model (Fast, MiDaS-192-GPU), with an
# extra pixel-budget cap on HD+passthrough since passthrough adds real GPU
# cost this hardware has much less headroom for. Treat as a starting point
# to be corrected once real on-device Quest 2 feedback comes in, not a
# measured result like the table above.
const QUEST2_AUTO_TABLE := {
	"720p": {false: {"tier": 1, "model_idx": 1, "cap_px": 0}, true: {"tier": 1, "model_idx": 1, "cap_px": 0}},
	"HD":   {false: {"tier": 1, "model_idx": 1, "cap_px": 0}, true: {"tier": 1, "model_idx": 1, "cap_px": 1280 * 720}},
}
var idle_labels: Array = ["Off", "5m", "15m", "30m", "60m"]
var idle_values: Array = [0, 5, 15, 30, 60]

func _init(owner: Node3D):
	main = owner

func get_stereo_mode() -> int:
	if main.settings.host.sbs_mode > 0:
		return main.settings.host.sbs_mode
	if main.settings.host.ai_3d_speed == 0:
		return 0
	if main.settings.host.ai_3d_depth_view:
		return 7 # User-facing Final depth-map view.
	if main.settings.host.ai_3d_debug == 1:
		return 7 # DMap-Final: exact production upsampled depth
	elif main.settings.host.ai_3d_debug == 2:
		return 8 # MiDaS-DMap-Raw
	elif main.settings.host.ai_3d_debug == 3:
		return 9 # MiDaS-DMap-Input
	elif main.settings.host.ai_3d_debug == 4:
		return 12 # DMap-Warp: final occlusion/displacement field
	match resolve_quality_tier():
		1: return 10 # MiDaS-Fast
		_: return 6 # MiDaS-Std

# 0=Standard, 1=Fast - matches depth_estimator.gd's warp_tier numbering
# exactly, so apply_stereo() can pass this straight through. Fastest/2 was
# removed 2026-08-25 (was ai_3d_speed==3) - near-identical to Fast at every
# resolution benchmarked, not worth the extra tier. ai_3d_speed_labels =
# ["Off", "Auto", "Fast", "Standard"] - Off never reaches here
# (get_stereo_mode() short-circuits on it above).
func resolve_quality_tier() -> int:
	match main.settings.host.ai_3d_speed:
		2: return 1 # Fast
		3: return 0 # Standard
		_: return get_auto_selection().tier

# Reads the pre-AI3D-cap BASE resolution (compute_requested_resolution(false),
# NOT the live/possibly-already-capped value - reading the capped value
# would be circular, since Auto's own tier choice is what determines the
# cap in the first place), classifies it (aspect + pixel-count bucket, see
# AUTO_CLASS_16_9/AUTO_CLASS_ULTRAWIDE above), and looks up the matching
# AUTO_TABLE row. Public (unlike the old _auto_quality_tier()) - main.gd's
# compute_requested_resolution() and ui_controller.gd's AI-Model-button
# labeling both need this same combo, not just resolve_quality_tier() here.
# Deliberately NOT cached - get_stereo_mode() (which calls this via
# resolve_quality_tier()) already gets called every frame from several
# places with no caching today, and this is exactly as cheap as the
# function it replaces (one Vector2i compute + a handful of comparisons,
# no allocations) - a cache/invalidation path would be new complexity for
# no measured benefit.
func _classify_auto_resolution(w: int, h: int) -> String:
	if h <= 0:
		return "720p"
	var aspect := float(w) / float(h)
	var refs: Array = AUTO_CLASS_ULTRAWIDE if aspect >= AUTO_ASPECT_ULTRAWIDE_THRESHOLD else AUTO_CLASS_16_9
	var pixels := w * h
	for i in range(refs.size() - 1):
		var midpoint: float = (refs[i].px + refs[i + 1].px) / 2.0
		if pixels <= midpoint:
			return refs[i].name
	return refs[refs.size() - 1].name

func get_auto_selection() -> Dictionary:
	var res: Vector2i = main.compute_requested_resolution(false)
	var cls := _classify_auto_resolution(res.x, res.y)
	if main.device_is_quest2:
		# QUEST2_AUTO_TABLE only has 720p/HD rows (see its own comment) -
		# QUEST2_MAX_RESOLUTION means classification should never actually
		# produce anything above HD on Quest 2, but clamp defensively rather
		# than throw if it somehow does.
		var quest2_cls = cls if QUEST2_AUTO_TABLE.has(cls) else "HD"
		return QUEST2_AUTO_TABLE[quest2_cls][main.settings.passthrough_enabled]
	return AUTO_TABLE[cls][main.settings.passthrough_enabled]

func _save_setting(btn: Button, label: String):
	if btn:
		main.ui_controller.update_option_btn(btn, label)
	main.state_manager.save_state()

func cycle_sbs_mode():
	set_sbs_mode((main.settings.host.sbs_mode + 1) % sbs_labels.size())

func toggle_sbs_mode():
	set_sbs_mode(0 if main.settings.host.sbs_mode > 0 else _last_sbs_mode)

func set_sbs_mode(requested_mode: int):
	var previous_mode: int = main.settings.host.sbs_mode
	main.settings.host.sbs_mode = clampi(requested_mode, 0, sbs_labels.size() - 1)
	if previous_mode > 0:
		_last_sbs_mode = previous_mode
	elif main.settings.host.sbs_mode > 0:
		_last_sbs_mode = main.settings.host.sbs_mode
	_save_setting(main._ui_sbs_btn, sbs_labels[main.settings.host.sbs_mode])
	main.ui_controller.update_3d_btn_state()
	apply_stereo()
	if main.screen_shortcuts:
		main.screen_shortcuts.refresh_visuals(main.primary_screen)
	main._log("[SBS] Mode changed: %s -> %s" % [
		sbs_labels[previous_mode], sbs_labels[main.settings.host.sbs_mode]])
	if main.settings.host.sbs_mode > 0 and main.screens.size() > 1:
		main._ui_status_label.text = "SBS applies to primary screen only"

# AI-3D depth estimation is native (no JNI/JVM) on Linux as of 2026-08-20
# (see depth_bridge.cpp's NIGHTFALL_PLATFORM_LINUX branch / MidasDepthEngine) -
# Linux uses the same selectable native TFLite models as Android. A shared
# check here avoids repeating "Android or Linux" three times below.
func _ai_3d_supported() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "Linux"

# Main-page On/Off toggle (2026-08-28) - replaces the old direct
# Off/Auto/Fast/Standard cycle on this button. Flips main.settings.host.ai_3d_speed
# between 0 and whichever mode was last active (main.settings.host.ai_3d_last_mode,
# kept current by cycle_ai_3d_mode() below) instead of always landing on
# Auto - tier selection itself now lives on the AI 3D tab.
func toggle_ai_3d_enabled():
	main._log("[AI3D] toggle requested: speed=%d last_mode=%d sbs_mode=%d screens=%d" % [
		main.settings.host.ai_3d_speed, main.settings.host.ai_3d_last_mode,
		main.settings.host.sbs_mode, main.screens.size()])
	if not _ai_3d_supported():
		return
	if main.settings.host.sbs_mode > 0:
		main._log("[AI3D] ignored: SBS mode is on (turn SBS off first)")
		return
	if main.settings.host.ai_3d_speed == 0:
		# A saved last_mode of 0 would leave 3D stuck off; fall back to Auto.
		main.settings.host.ai_3d_speed = main.settings.host.ai_3d_last_mode if main.settings.host.ai_3d_last_mode > 0 else 1
	else:
		main.settings.host.ai_3d_last_mode = main.settings.host.ai_3d_speed
		main.settings.host.ai_3d_speed = 0
	_save_setting(main._ui_3d_speed_btn, "On" if main.settings.host.ai_3d_speed != 0 else "Off")
	main.ui_controller.update_option_btn(main._ui_3d_enable_btn, "On" if main.settings.host.ai_3d_speed != 0 else "Off")
	main.ui_controller.update_3d_btn_state()
	if main.settings.host.ai_3d_speed != 0 and main.screens.size() > 1:
		main._ui_status_label.text = "AI 3D applies to the primary screen only"
	_schedule_ai_3d_commit()

# AI 3D tab's "3D Mode" control (2026-08-28) - cycles Auto/Fast/Standard
# (1-3) only; Off lives on the main page's toggle instead
# (toggle_ai_3d_enabled() above). Greyed out via update_3d_btn_state()
# whenever ai_3d_speed==0, but guarded here too since a disabled Button
# still technically has this connected.
func cycle_ai_3d_mode():
	if not _ai_3d_supported() or ai3d_options_locked():
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0:
		return
	# Only the label updates immediately - actually applying the mode
	# (apply_stereo(), which reconfigures depth_estimator and can trigger a
	# resolution-cap stream restart) is debounced below, same UX as
	# cycle_resolution()/_schedule_stream_restart(): click through to find
	# the setting you want, and it only commits once you stop, instead of
	# reconfiguring/restarting on every single click along the way.
	main.settings.host.ai_3d_speed = (main.settings.host.ai_3d_speed % 3) + 1 # 1->2->3->1 (Auto/Fast/Standard)
	main.settings.host.ai_3d_last_mode = main.settings.host.ai_3d_speed
	# Type can now change while Auto is active (2026-08-30, cycle_ai_3d_type())
	# without touching Model (frozen/table-driven under Auto) - re-sync Model
	# to Type here on the way OUT of Auto, in case they drifted apart while
	# Auto was active.
	normalize_ai_3d_model_for_type()
	_save_setting(main._ui_3d_mode_btn, ai_3d_speed_labels[main.settings.host.ai_3d_speed])
	main.ui_controller.update_3d_btn_state()
	_schedule_ai_3d_commit()

# Returns the indices into ai_3d_models whose .gpu matches want_gpu -
# shared by cycle_ai_3d_model() (cycles within the current Type's subset)
# and cycle_ai_3d_type() (snaps Model to the new Type's subset).
func _ai_3d_model_indices_for_type(want_gpu: bool) -> Array:
	var result: Array = []
	for i in range(ai_3d_models.size()):
		if OS.get_name() == "Linux" and not ai_3d_models[i].get("linux", true):
			continue
		if ai_3d_models[i].gpu == want_gpu:
			result.append(i)
	return result

# AI 3D tab's "Type" control (2026-08-28) - filters which ai_3d_models
# entries Model can cycle through (GPU: MiDaS-256-GPU/MiDaS-192-GPU; CPU:
# MiDaS-192/MiDaS-256/DA-V2-252), not just a passive preference. Snaps
# main.settings.host.ai_3d_model to the new Type's first matching entry whenever the
# current selection doesn't belong to it (e.g. switching CPU->GPU while
# DA-V2-252 was selected).
func cycle_ai_3d_type():
	if not _ai_3d_supported() or ai3d_options_locked():
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0:
		return
	main.settings.host.ai_3d_backend_pref = AI3D_BACKEND_CPU if main.settings.host.ai_3d_backend_pref == AI3D_BACKEND_GPU else AI3D_BACKEND_GPU
	# Under Auto (2026-08-30), Model stays table-driven (AUTO_TABLE/
	# get_auto_selection()) - main.settings.host.ai_3d_model itself is frozen/irrelevant,
	# so there's nothing to snap here; only Fast/Standard need Model kept in
	# sync with the new Type.
	if main.settings.host.ai_3d_speed != 1:
		var candidates = _ai_3d_model_indices_for_type(main.settings.host.ai_3d_backend_pref == AI3D_BACKEND_GPU)
		if not candidates.is_empty() and not candidates.has(main.settings.host.ai_3d_model):
			main.settings.host.ai_3d_model = candidates[0]
	main.state_manager.save_state()
	main.ui_controller.update_stereo_shader() # refreshes both Type's and Model's labels
	_schedule_ai_3d_commit()

# AI 3D tab's "Hz Cap" control (2026-08-28).
func cycle_ai_3d_hz_cap():
	if not _ai_3d_supported():
		return
	if frame_depth_available():
		# Steam Frame: the rate of the headset's own model, kept for the
		# headset rather than per PC, and changed without restarting anything.
		if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0 or meteor_depth_selected():
			return
		var rates: Array = [FRAME_DEPTH_RATE_AUTO] + AI3D_HZ_CAP_VALUES
		main.settings.frame_depth_rate = rates[(maxi(rates.find(main.settings.frame_depth_rate), 0) + 1) % rates.size()]
		_frame_depth_auto.reset()
		_save_setting(main._ui_3d_hz_cap_btn, hz_cap_label())
		main.stream_backend.set_depth_hz_cap(get_effective_hz_cap())
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0 or main.settings.host.ai_3d_speed == 1:
		return
	var idx = AI3D_HZ_CAP_VALUES.find(main.settings.host.ai_3d_hz_cap)
	main.settings.host.ai_3d_hz_cap = AI3D_HZ_CAP_VALUES[(maxi(idx, 0) + 1) % AI3D_HZ_CAP_VALUES.size()]
	_save_setting(main._ui_3d_hz_cap_btn, "%dhz" % main.settings.host.ai_3d_hz_cap)
	_schedule_ai_3d_commit()

# AI 3D tab's "Stereo Separation" control (2026-08-28) - a percentage
# multiplier on top of the warp shaders' own tuned base values (see
# STEREO_SCREEN_BASE_PARALLAX/depth_estimator.gd's _pass_parallax), not a
# replacement absolute value. Left live under Auto (unlike Type/Model/Hz
# Cap) - it's a general 3D-strength tune, not something the Auto table
# decides.
func cycle_ai_3d_separation():
	if not _ai_3d_supported():
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0:
		return
	var idx = AI3D_SEPARATION_VALUES.find(main.settings.host.ai_3d_separation_pct)
	main.settings.host.ai_3d_separation_pct = AI3D_SEPARATION_VALUES[(maxi(idx, 0) + 1) % AI3D_SEPARATION_VALUES.size()]
	_save_setting(main._ui_3d_separation_btn, get_ai_3d_separation_label())
	_schedule_ai_3d_commit()

func get_ai_3d_separation_label() -> String:
	var value: int = main.settings.host.ai_3d_separation_pct
	return "%d%%%s" % [value, " (Default)" if value == 75 else ""]

# Steam Frame: Separation and Convergence are sliders with a wider range than
# the cycle buttons' lists. Those lists were menu choices, not limits of the
# warp: the shaders take any strength and any convergence from 0 to 1. Higher
# separation costs a little more GPU (the warp searches further sideways) and
# stretches the picture more around the edges of near things.
const AI3D_SEPARATION_SLIDER_STEPS := 15 # 25% .. 400%, 25% apart (HostSettings.separation_valid)

func _ai_3d_effect_adjustable() -> bool:
	return _ai_3d_supported() and main.settings.host.sbs_mode == 0 and main.settings.host.ai_3d_speed != 0

func set_ai_3d_separation(value: int, commit: bool) -> void:
	if not _ai_3d_effect_adjustable():
		refresh_ai_3d_sliders()
		return
	main.auto_detect_enabled = false
	var step: int = clampi(int(round(value * AI3D_SEPARATION_SLIDER_STEPS / 100.0)), 0, AI3D_SEPARATION_SLIDER_STEPS)
	main.settings.host.ai_3d_separation_pct = 25 + 25 * step
	refresh_ai_3d_sliders()
	_apply_ai_3d_effect_live(commit)

func set_ai_3d_convergence(value: int, commit: bool) -> void:
	if not _ai_3d_effect_adjustable():
		refresh_ai_3d_sliders()
		return
	main.auto_detect_enabled = false
	main.settings.host.ai_3d_convergence_pct = clampi(int(round(value / 5.0)) * 5, 0, 100)
	refresh_ai_3d_sliders()
	_apply_ai_3d_effect_live(commit)

# While dragging, the picture follows at once; letting go saves and runs the
# same commit the cycle buttons use.
func _apply_ai_3d_effect_live(commit: bool) -> void:
	if main.depth_estimator:
		main.depth_estimator.set_separation_pct(main.settings.host.ai_3d_separation_pct)
	_push_ai3d_effect_uniforms()
	if commit:
		main.state_manager.save_state()
		_schedule_ai_3d_commit()

## Shows the current values on the two sliders (no-op for plain buttons).
func refresh_ai_3d_sliders() -> void:
	var sep_btn: Button = main._ui_3d_separation_btn
	if sep_btn and sep_btn.has_meta("slider"):
		var step: int = clampi(int(round((main.settings.host.ai_3d_separation_pct - 25) / 25.0)), 0, AI3D_SEPARATION_SLIDER_STEPS)
		main.ui_controller.set_slider_value(sep_btn, int(round(step * 100.0 / AI3D_SEPARATION_SLIDER_STEPS)), get_ai_3d_separation_label())
	var conv_btn: Button = main._ui_3d_convergence_btn
	if conv_btn and conv_btn.has_meta("slider"):
		main.ui_controller.set_slider_value(conv_btn, main.settings.host.ai_3d_convergence_pct, get_ai_3d_convergence_label())

# AI 3D tab's "Convergence" control (2026-08-28) - maps directly to the
# warp shaders' already-declared "convergence" uniform (0.30-0.70), which
# was never actually driven from GDScript before this - see
# _push_ai3d_effect_uniforms(). Left live under Auto, same reasoning as
# Separation above.
func cycle_ai_3d_convergence():
	if not _ai_3d_supported():
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0:
		return
	var idx = AI3D_CONVERGENCE_VALUES.find(main.settings.host.ai_3d_convergence_pct)
	main.settings.host.ai_3d_convergence_pct = AI3D_CONVERGENCE_VALUES[(maxi(idx, 0) + 1) % AI3D_CONVERGENCE_VALUES.size()]
	_save_setting(main._ui_3d_convergence_btn, get_ai_3d_convergence_label())
	_schedule_ai_3d_commit()

func get_ai_3d_convergence_label() -> String:
	var value: int = main.settings.host.ai_3d_convergence_pct
	return "%d%%%s" % [value, " (Default)" if value == 50 else ""]

# Moves the rendered cursor over the AI-warped image without changing the
# raycast or host click coordinates. This corrects visual click alignment;
# it deliberately does not alter cursor depth/binocular disparity.
func cycle_ai_3d_cursor_position():
	if not _ai_3d_supported():
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0:
		return
	main.settings.host.ai_3d_cursor_position = ((clampi(main.settings.host.ai_3d_cursor_position, -1, 1) + 1 + 1) % AI3D_CURSOR_POSITION_LABELS.size()) - 1
	_save_setting(main._ui_3d_cursor_position_btn, get_ai_3d_cursor_position_label())

func get_ai_3d_cursor_position_label() -> String:
	return AI3D_CURSOR_POSITION_LABELS[clampi(main.settings.host.ai_3d_cursor_position, -1, 1) + 1]

func toggle_ai_3d_depth_sync():
	if OS.get_name() != "Android" or main.settings.host.sbs_mode > 0 \
			or main.settings.host.ai_3d_speed == 0:
		return
	main.settings.host.ai_3d_depth_sync = not main.settings.host.ai_3d_depth_sync
	_save_setting(main._ui_3d_depth_sync_btn,
		"On" if main.settings.host.ai_3d_depth_sync else "Off")

func toggle_ai_3d_edge_alignment():
	main.settings.host.ai_3d_edge_alignment = not main.settings.host.ai_3d_edge_alignment
	_save_setting(main._ui_3d_edge_alignment_btn,
		"On" if main.settings.host.ai_3d_edge_alignment else "Off")
	main.ui_controller.update_3d_btn_state()
	if main.native_xr_renderer:
		main.native_xr_renderer.request_redraw()

func toggle_ai_3d_contour_cleanup():
	if not main.settings.host.ai_3d_edge_alignment:
		return
	main.settings.host.ai_3d_contour_cleanup = not main.settings.host.ai_3d_contour_cleanup
	_save_setting(main._ui_3d_contour_cleanup_btn,
		"On" if main.settings.host.ai_3d_contour_cleanup else "Off")
	if main.native_xr_renderer:
		main.native_xr_renderer.request_redraw()

func toggle_ai_3d_depth_view():
	if (OS.get_name() != "Android" and not main.device_is_steam_frame) or main.settings.host.sbs_mode > 0 \
			or main.settings.host.ai_3d_speed == 0:
		return
	main.settings.host.ai_3d_depth_view = not main.settings.host.ai_3d_depth_view
	# Both controls select a renderer diagnostic mode. Keep their state
	# separate, but never display both when a development build exposes the
	# full Raw/Input/Warp selector alongside this user-facing Final view.
	if main.settings.host.ai_3d_depth_view and main.settings.host.ai_3d_debug != 0:
		main.settings.host.ai_3d_debug = 0
		_save_setting(main._ui_3d_debug_btn, ai_3d_debug_labels[0])
	_save_setting(main._ui_3d_depth_view_btn,
		"On" if main.settings.host.ai_3d_depth_view else "Off")
	# This changes only the renderer's view of the depth already flowing. It
	# never changes stream resolution or model state, so apply it immediately.
	apply_stereo()

func cycle_ai_3d_process_debug():
	if OS.get_name() != "Android" or main.settings.host.sbs_mode > 0 \
			or main.settings.host.ai_3d_speed == 0:
		return
	main.settings.host.ai_3d_process_debug = \
		(main.settings.host.ai_3d_process_debug + 1) % ai_3d_process_debug_labels.size()
	_save_setting(main._ui_3d_process_debug_btn,
		ai_3d_process_debug_labels[main.settings.host.ai_3d_process_debug])
	if main.native_xr_renderer:
		main.native_xr_renderer.request_redraw()

# AI 3D tab's "Reset" button (2026-08-28) - restores only this tab's own
# settings to their defaults (today's real, previously-hardcoded values -
# see each field's own comment on main.gd). Deliberately does NOT touch
# the main-page On/Off state: if AI-3D is currently off, it stays off, just
# with ai_3d_last_mode reset to Auto for whenever it's turned back on; if
# currently on, its active mode is reset to Auto too (matching "3D Mode
# -> Auto" being one of the reset targets).
func reset_ai_3d_effect_settings():
	if not _ai_3d_supported():
		return
	main.settings.host.ai_3d_last_mode = 1
	if main.settings.host.ai_3d_speed != 0:
		main.settings.host.ai_3d_speed = 1
	main.settings.host.ai_3d_backend_pref = AI3D_BACKEND_GPU
	main.settings.host.ai_3d_model = MODEL_ZIPDEPTH_384 if OS.get_name() == "Linux" else 0
	main.settings.host.ai_3d_gpu_api = 0
	main.settings.host.ai_3d_hz_cap = 20
	main.settings.host.ai_3d_separation_pct = 75
	main.settings.host.ai_3d_convergence_pct = 50
	main.settings.host.ai_3d_cursor_position = 0
	main.settings.host.ai_3d_depth_sync = false
	main.settings.host.ai_3d_edge_alignment = true
	main.settings.host.ai_3d_contour_cleanup = true
	main.settings.host.ai_3d_process_debug = 5
	enforce_ai3d_platform_lock()
	main.state_manager.save_state()
	main.ui_controller.update_stereo_shader()
	_schedule_ai_3d_commit()

# Stands for Nightfall Meteor's host depth in the Model cycle. Not an index
# into ai_3d_models: Meteor is only offered per stream, so it never replaces
# the saved on-device model (see meteor_depth_selected()).
const MODEL_METEOR := -1

## The PC's Nightfall Meteor offered host depth for the current stream.
func meteor_depth_offered() -> bool:
	return not primary_is_browser() and main.is_streaming and main.stream_manager != null and not main.stream_manager.meteor_depth_info().is_empty()

func primary_is_browser() -> bool:
	return main.get("browser_prototype") != null and main.browser_prototype.active

func selected_depth_model_index() -> int:
	if primary_is_browser():
		var choice = main.browser_prototype.get("depth_model_override")
		return int(choice) if choice != null else ANDROID_MODEL_AUTO
	return main.settings.host.ai_3d_model

## Meteor depth is chosen automatically whenever it's offered, unless the
## user picked an on-device model while it was (per host, until they pick
## Meteor again). depth_estimator.gd falls back to on-device depth while
## Meteor's maps aren't arriving.
func meteor_depth_selected() -> bool:
	# A Steam Frame build without on-headset depth: Meteor is the only depth
	# source and can't be declined.
	if main.device_is_steam_frame and not frame_depth_available():
		return meteor_depth_offered()
	return meteor_depth_offered() and not main.settings.host.ai_3d_meteor_declined

# --- Steam Frame: on-headset depth (frame_depth_engine.h) ---
# In the order of the native engine's models: ZipDepth at 512x288, and the
# 256 pixel 8-bit one, which is several times lighter on the processor. The
# third is Meteor's own model on the headset's graphics chip (a test in 7j;
# since 7k its work is ranked below Nightfall's drawing, and it holds every
# display rate). It is only offered where the build has that engine and the
# model's files.
const FRAME_DEPTH_LABELS: Array[String] = ["Headset: Detail", "Headset: Light", "Headset: GPU"]
const FRAME_DEPTH_GPU_MODEL := 2

## Whether this build can make the depth on the headset itself. Asked every
## frame, and the answer can't change while the app runs, so it is kept.
var _frame_depth_known := false
var _frame_depth_there := false

func frame_depth_available() -> bool:
	if not _frame_depth_known and main.stream_backend != null:
		_frame_depth_known = true
		_frame_depth_there = main.device_is_steam_frame and main.stream_backend.has_decoder_depth()
		if main.device_is_steam_frame:
			main._log("[DEPTH] on-headset depth: %s" % ("in this build" if _frame_depth_there else "not in this build (Meteor only)"))
	return _frame_depth_there

## How many of FRAME_DEPTH_LABELS this headset can use: the two processor
## models, and the graphics-chip one where it is there.
var _frame_depth_models := 0

func frame_depth_model_count() -> int:
	if _frame_depth_models == 0 and frame_depth_available():
		var gpu: bool = main.stream_backend.decoder_depth_model_present(FRAME_DEPTH_GPU_MODEL)
		_frame_depth_models = FRAME_DEPTH_LABELS.size() if gpu else FRAME_DEPTH_GPU_MODEL
		main._log("[DEPTH] on-headset depth on the graphics chip: %s" % ("offered (test)" if gpu else "not in this build"))
	return maxi(_frame_depth_models, 1)

## The headset model in use: the saved one, or the first when that one isn't here.
func frame_depth_model() -> int:
	var saved: int = main.settings.frame_depth_model
	return saved if saved < frame_depth_model_count() else 0

## The Frame's Model choices in turn: Meteor first while it is offered, then
## the headset's own models. Returns MODEL_METEOR or a headset model's number.
static func next_frame_depth_choice(meteor_offered: bool, meteor_selected: bool, model: int, models: int = 2) -> int:
	var choices: Array[int] = []
	if meteor_offered:
		choices.append(MODEL_METEOR)
	for i in models:
		choices.append(i)
	var at := 0 if (meteor_offered and meteor_selected) else choices.find(model)
	return choices[(maxi(at, -1) + 1) % choices.size()]

# Cycles only within the entries matching the current Type
# (main.settings.host.ai_3d_backend_pref) - see _ai_3d_model_indices_for_type() above.
# Meteor comes first while it's offered.
func cycle_ai_3d_model():
	if not _ai_3d_supported():
		return
	if main.device_is_steam_frame:
		if not frame_depth_available():
			main.settings.host.ai_3d_meteor_declined = false
			return
		if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0:
			return
		var offered := meteor_depth_offered()
		var choice := next_frame_depth_choice(offered, meteor_depth_selected(), frame_depth_model(), frame_depth_model_count())
		if choice == MODEL_METEOR:
			main.settings.host.ai_3d_meteor_declined = false
		else:
			main.settings.frame_depth_model = choice
			# Declining Meteor is only a choice while it is on offer (and is
			# kept for this PC, as on the other devices).
			if offered:
				main.settings.host.ai_3d_meteor_declined = true
		_save_setting(main._ui_3d_btn, get_depth_model_label())
		main.ui_controller.update_3d_btn_state()
		_schedule_ai_3d_commit(0.8)
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0 or (OS.get_name() != "Android" and main.settings.host.ai_3d_speed == 1):
		return
	var candidates = [ANDROID_MODEL_AUTO, ANDROID_MODEL_STANDARD, ANDROID_MODEL_LEGACY_EDGEPAD_256, ANDROID_MODEL_LEGACY_EDGEPAD_384] if OS.get_name() == "Android" else _ai_3d_model_indices_for_type(main.settings.host.ai_3d_backend_pref == AI3D_BACKEND_GPU)
	if candidates.is_empty():
		return
	var offered := meteor_depth_offered()
	if offered:
		candidates = [MODEL_METEOR] + candidates
	var pos = 0 if meteor_depth_selected() else candidates.find(selected_depth_model_index())
	var next = candidates[(maxi(pos, -1) + 1) % candidates.size()]
	if next == MODEL_METEOR:
		main.settings.host.ai_3d_meteor_declined = false
	elif primary_is_browser():
		main.browser_prototype.depth_model_override = next
	else:
		main.settings.host.ai_3d_model = next
		if offered:
			main.settings.host.ai_3d_meteor_declined = true
	_save_setting(main._ui_3d_btn, get_depth_model_label())
	if main._ui_3d_gpu_api_btn:
		main.ui_controller.update_option_btn(main._ui_3d_gpu_api_btn, get_ai_3d_gpu_api_label())
	main.ui_controller.update_3d_btn_state()
	# Match the resolution selector's settling window: model labels update on
	# every click, but only the final choice tears down/compiles an OpenCL
	# delegate after the user stops cycling.
	_schedule_ai_3d_commit(0.8)

func get_ai_3d_gpu_api_effective() -> int:
	if is_android_ai3d_auto():
		# Quest 2 lacks the OpenCL library exposed on Quest 3. Auto starts on
		# the compatible EdgePad-256/OpenGL tier there; Quest 3 starts
		# EdgePad-512/OpenCL and uses the 256/OpenGL path only after a real
		# OpenCL failure.
		return 1 if main.device_is_quest2 or _auto_depth_fallback else 0
	return main.browser_prototype.depth_gpu_api_override if primary_is_browser() else main.settings.host.ai_3d_gpu_api

func is_android_ai3d_auto() -> bool:
	return OS.get_name() == "Android" and selected_depth_model_index() == ANDROID_MODEL_AUTO

func get_ai_3d_gpu_api_label() -> String:
	if OS.get_name() == "Android" and get_depth_backend_index() == AI3D_BACKEND_CPU:
		return "CPU"
	return ai_3d_gpu_api_labels[get_ai_3d_gpu_api_effective()]

# On Android this is the only exposed way to choose CPU inference (the "Type"
# row with GPU/CPU is hidden, see ai3d_options_locked()) - cycles OpenCL ->
# OpenGL -> CPU -> OpenCL. CPU runs the CPU twin matching whatever Model the
# locked button shows (_android_cpu_model_index()), so AI 3D can run using no
# GPU time at all; see get_depth_model_index()/_label().
func cycle_ai_3d_gpu_api() -> void:
	if OS.get_name() != "Android" or is_android_ai3d_auto() or main.settings.host.ai_3d_speed == 0 or main.settings.host.sbs_mode > 0:
		return
	if primary_is_browser():
		var browser = main.browser_prototype
		if browser.depth_backend_override == AI3D_BACKEND_CPU:
			browser.depth_backend_override = AI3D_BACKEND_GPU
			browser.depth_gpu_api_override = 0
		elif browser.depth_gpu_api_override == 0:
			browser.depth_gpu_api_override = 1
		else:
			browser.depth_backend_override = AI3D_BACKEND_CPU
	elif main.settings.host.ai_3d_backend_pref == AI3D_BACKEND_CPU:
		main.settings.host.ai_3d_backend_pref = AI3D_BACKEND_GPU
		main.settings.host.ai_3d_gpu_api = 0
	elif main.settings.host.ai_3d_gpu_api == 0:
		main.settings.host.ai_3d_gpu_api = 1
	else:
		main.settings.host.ai_3d_backend_pref = AI3D_BACKEND_CPU
	_save_setting(main._ui_3d_gpu_api_btn, get_ai_3d_gpu_api_label())
	_schedule_ai_3d_commit()

func _android_depth_class() -> Object:
	var wrapper: Object = Engine.get_singleton("JavaClassWrapper") if OS.get_name() == "Android" else null
	return wrapper.wrap("com.godot.game.GodotApp") if wrapper else null

func cycle_ai_3d_gpu_priority():
	if not depth_gpu_priority_available():
		return
	var was_stream: bool = main.settings.ai_3d_gpu_priority == AI3D_GPU_PRIORITY_STREAM
	main.settings.ai_3d_gpu_priority = (main.settings.ai_3d_gpu_priority + 1) % ai_3d_gpu_priority_labels.size()
	_save_setting(main._ui_3d_priority_btn, ai_3d_gpu_priority_labels[main.settings.ai_3d_gpu_priority])
	# Only crossing to or from Stream changes the OpenCL context priority, which
	# reloads the inference delegate; Adaptive <-> AI 3D just changes pacing.
	var reloads: bool = was_stream != (main.settings.ai_3d_gpu_priority == AI3D_GPU_PRIORITY_STREAM)
	apply_depth_gpu_priority(true, reloads)

func apply_depth_gpu_priority(notify: bool = false, reloads: bool = true):
	if not depth_gpu_priority_available() or not main.stream_backend:
		return
	if not main.stream_backend.has_method("set_depth_gpu_priority"):
		return
	# The OpenCL context only has two levels: LOW (Stream) and default. Adaptive
	# uses default and paces inference instead (see Ai3dAdaptivePacer).
	var opencl_default_priority: bool = main.settings.ai_3d_gpu_priority != AI3D_GPU_PRIORITY_STREAM
	main.stream_backend.set_depth_gpu_priority(1 if opencl_default_priority else 0)
	_ai3d_pacer.reset(_base_hz_cap())
	main.stream_backend.set_depth_hz_cap(get_effective_hz_cap())
	var label: String = ai_3d_gpu_priority_labels[main.settings.ai_3d_gpu_priority]
	main._log("[DEPTH] GPU priority selected: %s" % label)
	if notify and main.ui_controller:
		main.ui_controller.set_status("Depth GPU priority: %s%s" % [label, " (reloading inference)" if reloads else ""])

# Safety net for main.settings.host.ai_3d_model/ai_3d_backend_pref disagreeing (e.g. a
# save file edited/corrupted outside the normal cycle_ai_3d_model()/
# cycle_ai_3d_type() paths, which otherwise always keep them in sync) -
# called after loading persisted state. Snaps Model to Type's first entry
# if the current selection doesn't belong to it; a no-op otherwise.
func normalize_ai_3d_model_for_type():
	var candidates = _ai_3d_model_indices_for_type(main.settings.host.ai_3d_backend_pref == AI3D_BACKEND_GPU)
	if not candidates.is_empty() and not candidates.has(main.settings.host.ai_3d_model):
		main.settings.host.ai_3d_model = candidates[0]

# Android keeps Type and the legacy 3D Mode hidden, but exposes one concise
# model selector: Auto, EdgePad-512, EdgePad-256 and EdgePad-384 reference. See
# docs/guides/zipdepth-quest-tiers.md for the model and reconstruction
# decisions behind those names. Linux retains its independent model library.
func ai3d_options_locked() -> bool:
	return SettingsPlatformPolicy.ai3d_options_locked()

func depth_gpu_priority_available() -> bool:
	return SettingsPlatformPolicy.depth_gpu_priority_available()

func _locked_ai3d_model_index() -> int:
	return ANDROID_MODEL_AUTO

# Called after loading persisted state (any format/migration branch - see
# load_host_state()'s own comment) and by reset_ai_3d_effect_settings(), so
# a save file from before this lock existed (or Reset's own MiDaS/Auto
# defaults) can never leave Android pointed at a model that isn't actually
# bundled. No-op on Linux.
func enforce_ai3d_platform_lock(prefer_auto: bool = false):
	if not ai3d_options_locked():
		return
	# CPU is a real, persisted choice here (the "Backend" control's third
	# state, EdgePad-256-CPU) - only an unrecognized value falls back to GPU.
	if main.settings.host.ai_3d_backend_pref != AI3D_BACKEND_CPU:
		main.settings.host.ai_3d_backend_pref = AI3D_BACKEND_GPU
	# Preserve manual intent for saves that selected the retired 320 tier.
	if main.settings.host.ai_3d_model == ANDROID_MODEL_EDGEPAD_320:
		main.settings.host.ai_3d_model = ANDROID_MODEL_LEGACY_EDGEPAD_256
	if prefer_auto or not [ANDROID_MODEL_AUTO, ANDROID_MODEL_STANDARD, ANDROID_MODEL_LEGACY_EDGEPAD_384, ANDROID_MODEL_LEGACY_EDGEPAD_256].has(main.settings.host.ai_3d_model):
		main.settings.host.ai_3d_model = ANDROID_MODEL_AUTO
	main.settings.host.ai_3d_gpu_api = clampi(main.settings.host.ai_3d_gpu_api, 0, 1)
	main.settings.host.ai_3d_last_mode = 3
	# Diagnostic selectors start in the normal picture. The permanent Final
	# view is deliberately session-only so a forgotten diagnostic cannot make
	# the next launch appear broken.
	main.settings.host.ai_3d_depth_view = false
	main.settings.host.ai_3d_debug = 0
	main.settings.host.ai_3d_process_debug = 5
	if main.settings.host.ai_3d_speed != 0:
		main.settings.host.ai_3d_speed = 3

# Maps main.settings.host.ai_3d_model (the persisted UI selection, an index into
# ai_3d_models) to DepthEstimator's real Java-side model index. Under Auto
# (ai_3d_speed==1), main.settings.host.ai_3d_model is frozen/irrelevant - the table picks
# the model instead (see get_auto_selection()/AUTO_TABLE above).
func get_depth_model_index() -> int:
	if main.settings.host.ai_3d_speed == 0:
		return 0
	if main.device_is_steam_frame:
		# The Frame's engine numbers its own models (FRAME_DEPTH_LABELS).
		return frame_depth_model()
	if OS.get_name() == "Android" and get_depth_backend_index() == AI3D_BACKEND_CPU:
		return ai_3d_models[_android_cpu_model_index()].java_index
	if is_android_ai3d_auto():
		return 26 if main.device_is_quest2 or _auto_depth_fallback else 25
	# Linux Auto is intentionally simple: ZipDepth-384 on Vulkan by default,
	# or MiDaS-256 when the user explicitly changes Type to CPU. The old Auto
	# table was calibrated for the retired MiDaS GPU roster and must not make
	# Linux silently select a slower model.
	if OS.get_name() == "Linux" and main.settings.host.ai_3d_speed == 1:
		return 14 if main.settings.host.ai_3d_backend_pref == AI3D_BACKEND_GPU else 3
	if main.settings.host.ai_3d_speed == 1:
		return ai_3d_models[get_auto_selection().model_idx].java_index
	return ai_3d_models[selected_depth_model_index()].java_index

# The model actually running on Android, for the stats overlay. Under Auto
# the menu shows "Auto"; this names what Auto chose. Looked up in
# ai_3d_models rather than a separate list: a hand-kept copy went stale when
# Java index 25 became EdgePad-512 and kept calling it EdgePad-384.
func active_android_depth_model_name() -> String:
	if get_depth_backend_index() == AI3D_BACKEND_CPU:
		return ai_3d_models[_android_cpu_model_index()].label
	var java_index := get_depth_model_index()
	for model in ai_3d_models:
		if model.java_index == java_index and model.gpu and model.get("android", false) and model.label != "Auto":
			return model.label
	return "ZipDepth (model %d)" % java_index

func get_depth_model_label() -> String:
	if meteor_depth_selected():
		return "Meteor"
	if main.device_is_steam_frame:
		return FRAME_DEPTH_LABELS[frame_depth_model()] if frame_depth_available() else "Needs Meteor"
	if OS.get_name() == "Android" and get_depth_backend_index() == AI3D_BACKEND_CPU:
		return ai_3d_models[_android_cpu_model_index()].label
	if OS.get_name() == "Linux" and main.settings.host.ai_3d_speed == 1:
		return "ZipDepth-384-GPU" if main.settings.host.ai_3d_backend_pref == AI3D_BACKEND_GPU else "MiDaS-256"
	return ai_3d_models[selected_depth_model_index()].label

# Which CPU model twin to run while Backend==CPU. Matches whatever Model the
# locked button is actually showing, so switching Model while on CPU picks the
# equivalent CPU tier instead of silently always running one fixed size.
func _android_cpu_model_index() -> int:
	if selected_depth_model_index() in [ANDROID_MODEL_STANDARD, ANDROID_MODEL_LEGACY_EDGEPAD_384]:
		return ANDROID_MODEL_EDGEPAD_384_CPU
	return ANDROID_MODEL_EDGEPAD_256_CPU

# Android production reconstruction is part of the tier definition rather
# than a hidden debug preference. Both EdgePad models retain ZipDepth's full
# learned reconstruction head. Hardware-linear produced the best practical
# quality/cost result; the 5x5 and conservative 2x2 colour-guided experiments
# remain available in the native renderer and comparison tools for reference.
func get_depth_process_stage() -> int:
	if OS.get_name() == "Android":
		var model_index := get_depth_model_index()
		if model_index in [25, 26, 30]:
			return ANDROID_DEPTH_PROCESS_FULL_LINEAR
	return ANDROID_DEPTH_PROCESS_FULL if OS.get_name() == "Android" \
		else main.settings.host.ai_3d_process_debug

# The backend to actually request from configure_depth() (2026-08-28 -
# now driven by main.settings.host.ai_3d_backend_pref, the "Type" control). Model is
# always kept filtered to match Type by cycle_ai_3d_model()/
# cycle_ai_3d_type(), so main.settings.host.ai_3d_backend_pref and
# ai_3d_models[main.settings.host.ai_3d_model].gpu can never disagree - no need to
# fall back based on the model's own .gpu flag here.
func get_depth_backend_index() -> int:
	# Preserve the selected backend while AI 3D is off. Returning a CPU sentinel
	# here mislabeled fresh Auto/OpenCL installs as EdgePad-256-CPU. Inference
	# enablement remains gated separately by ai_3d_speed/get_depth_model_index().
	if primary_is_browser():
		var backend = main.browser_prototype.get("depth_backend_override")
		return AI3D_BACKEND_GPU if selected_depth_model_index() == ANDROID_MODEL_AUTO or backend == null else int(backend)
	# PyroWave's own decode already costs real GPU time every frame (it's a
	# Vulkan compute codec) - Auto pairs it with CPU-only inference on every
	# headset instead of adding GPU-delegate depth work on top.
	if OS.get_name() == "Android" and is_android_ai3d_auto() and main.settings.codec_preference == 4:
		return AI3D_BACKEND_CPU
	# 2026-08-30: Auto follows the Type control the same as Fast/Standard do -
	# it was never meant to force GPU unconditionally, just default to it
	# (main.settings.host.ai_3d_backend_pref's own default value). AUTO_TABLE's model_idx
	# entries (0/1, the "-GPU"-labeled rows) resolve to the exact same
	# java_index as their CPU-labeled counterparts (2/3) - GPU vs CPU is
	# entirely this return value's job, not which model_idx AUTO_TABLE
	# picked, so honoring Type here needs no AUTO_TABLE change.
	return main.settings.host.ai_3d_backend_pref

# AI 3D tab's Hz Cap control ignores itself under Auto (which always
# targets a fixed 20Hz) - see cycle_ai_3d_hz_cap()'s own comment. Used both
# for the button's displayed label and the actual value pushed to the
# Java inference loop, so they can never disagree.
func get_effective_hz_cap() -> int:
	var base := _base_hz_cap()
	if voice_easing_depth():
		return mini(base, VOICE_DEPTH_RATE)
	if is_ai3d_adaptive_active() and _ai3d_pacer.current_hz > 0.0:
		return mini(base, int(_ai3d_pacer.current_hz))
	return base

func _base_hz_cap() -> int:
	if frame_depth_available():
		return _frame_depth_auto.rate() if frame_depth_auto() else main.settings.frame_depth_rate
	return 20 if main.settings.host.ai_3d_speed == 1 else main.settings.host.ai_3d_hz_cap

## Steam Frame: Hz Cap "Auto" for the headset's own model (FrameDepthAutoRate).
const FRAME_DEPTH_RATE_AUTO := 0
var _frame_depth_auto := FrameDepthAutoRate.new()

func frame_depth_auto() -> bool:
	return frame_depth_available() and main.settings.frame_depth_rate == FRAME_DEPTH_RATE_AUTO

## What the Hz Cap button shows.
func hz_cap_label() -> String:
	return "Auto" if frame_depth_auto() else "%dhz" % get_effective_hz_cap()

## Whether the headset's own model is the one making the depth just now.
func _frame_depth_running() -> bool:
	return main.is_streaming and main.depth_estimator != null and main.depth_estimator.decoder_depth_on()

## The rate last sent to the model by Auto; -1 while the model isn't running,
## so the first second it runs again sends the rate afresh.
var _frame_depth_rate_sent := -1

func _pace_frame_depth(sample: Dictionary) -> void:
	if not _frame_depth_running():
		_frame_depth_auto.reset()
		_frame_depth_rate_sent = -1
		return
	if voice_easing_depth():
		return   # the rate is voice typing's for the moment; nothing to judge by
	var app_fps := float(sample.get("app_fps", 0.0))
	var model_ms: float = main.stream_backend.get_depth_last_inference_ms() if main.stream_backend else 0.0
	var before := _frame_depth_auto.rate()
	_frame_depth_auto.on_sample(app_fps, float(main.display_refresh_rate), model_ms)
	var rate := _frame_depth_auto.rate()
	if rate == _frame_depth_rate_sent or not main.stream_backend:
		return
	_frame_depth_rate_sent = rate
	main.stream_backend.set_depth_hz_cap(rate)
	main._log("[DEPTH] Auto rate %d a second%s (app %.0f of %.0f fps; model %.0f ms a map, so at most %d)" % [
		rate, "" if rate == before else ", from %d" % before, app_fps, float(main.display_refresh_rate),
		model_ms, FrameDepthAutoRate.model_ceiling(model_ms)])

## Steam Frame: Advanced Settings > Faster Voice Typing. While a clip is being
## worked out, the headset's depth model runs only this often, so the speech
## model has the processor: with Headset: Detail running, the Small speech
## model took about half the clip's length to type it out (7h log: 15.8 s for
## 30 s of speech) against about a third without a depth model, and running
## the depth model a little less often (Hz Cap Auto) made no difference.
const VOICE_DEPTH_RATE := 4
## No clip takes this long (the longest is 30 s of speech, about 16 s of work):
## past it the model goes back to its rate even if voice typing never said
## it had finished.
const VOICE_WORK_MAX_MS := 45000
var _voice_working := false
var _voice_working_since_ms := 0

func voice_easing_depth() -> bool:
	return _voice_working and Time.get_ticks_msec() - _voice_working_since_ms < VOICE_WORK_MAX_MS \
		and main.settings.frame_voice_eases_depth and frame_depth_available() \
		and frame_depth_on_processor()

## The speech model runs on the processor. A depth model on the graphics chip
## is not in its way (7j: 2.0 s for a sentence with the option off, as quick
## as Detail with it on), so there is nothing to ease.
func frame_depth_on_processor() -> bool:
	return frame_depth_model() != FRAME_DEPTH_GPU_MODEL

## Voice typing says when a clip starts and stops being worked out.
func set_voice_working(working: bool) -> void:
	if working == _voice_working:
		return
	var eased := voice_easing_depth()
	_voice_working = working
	_voice_working_since_ms = Time.get_ticks_msec()
	if eased == voice_easing_depth() or not main.stream_backend:
		return
	# Down to voice typing's rate, or back to Auto's (sent afresh) or the chosen number.
	_frame_depth_rate_sent = -1
	main.stream_backend.set_depth_hz_cap(get_effective_hz_cap())

## Steam Frame: Multi-Link, Wi-Fi only or Adapter only (FrameSecondLink).
## Takes effect at once, with no restart: Meteor follows within a few seconds.
func cycle_link_mode():
	main.settings.frame_link_mode = (main.settings.frame_link_mode + 1) % FrameSecondLink.MODE_LABELS.size()
	main.settings.frame_link_untold = not main.link_choice_reaches_meteor()
	_save_setting(main._ui_second_link_btn, FrameSecondLink.MODE_LABELS[main.settings.frame_link_mode])
	main.link_mode_changed()

func toggle_voice_eases_depth():
	var eased := voice_easing_depth()
	main.settings.frame_voice_eases_depth = not main.settings.frame_voice_eases_depth
	_save_setting(main._ui_voice_ease_btn, "On" if main.settings.frame_voice_eases_depth else "Off")
	if eased != voice_easing_depth() and main.stream_backend:
		main.stream_backend.set_depth_hz_cap(get_effective_hz_cap())

func is_ai3d_adaptive_active() -> bool:
	return main.settings.ai_3d_gpu_priority == AI3D_GPU_PRIORITY_ADAPTIVE \
		and depth_gpu_priority_available() \
		and main.is_streaming \
		and main.settings.host.ai_3d_speed > 0 \
		and get_stereo_mode() >= 3 \
		and get_depth_backend_index() == AI3D_BACKEND_GPU

# Called once per second with the app/video frame-rate telemetry sample.
func on_performance_sample(sample: Dictionary) -> void:
	if frame_depth_auto():
		_pace_frame_depth(sample)
		return
	if not is_ai3d_adaptive_active():
		_ai3d_pacer.reset(_base_hz_cap())
		return
	var new_hz := _ai3d_pacer.on_sample(
		float(sample.get("app_fps", 0.0)),
		float(sample.get("video_update_fps", 0.0)),
		float(main.display_refresh_rate),
		float(main.settings.host.stream_fps),
		_base_hz_cap())
	if new_hz > 0 and main.stream_backend:
		main.stream_backend.set_depth_hz_cap(new_hz)
		main._log("[DEPTH] Adaptive: AI 3D inference rate %d Hz (app %.1f fps, video %.1f fps)" % [
			new_hz, float(sample.get("app_fps", 0.0)), float(sample.get("video_update_fps", 0.0))])

func get_ai_3d_gpu_priority_label() -> String:
	var label: String = ai_3d_gpu_priority_labels[main.settings.ai_3d_gpu_priority]
	if is_ai3d_adaptive_active():
		label += " (%d Hz)" % get_effective_hz_cap()
	return label

# 2026-08-30: only ever "GPU" or "CPU" now - no silent runtime GPU->CPU
# substitution to represent as a third hybrid state (see
# runScheduledGpuInference()/configureDepth() in DepthEstimator.java, and
# refresh_depth_backend_status() below for how a GPU failure is surfaced
# instead: a persistent status message, not a quiet backend swap).
func get_depth_backend_label() -> String:
	if get_depth_backend_index() != AI3D_BACKEND_GPU:
		return "CPU"
	return "Vulkan" if OS.get_name() == "Linux" else "GPU"

# A non-empty backend_status while GPU is requested means GPU depth failed
# and (per 2026-08-30's "fail visibly, no fallback" request) is simply not
# producing frames - not that it silently switched to CPU. Shown as a
# persistent status message for as long as the failure lasts, not just a
# one-off transition blip, so it stays visible the whole time it's true
# (matters most for Auto, which now defaults to GPU but never used to
# surface this at all).
func refresh_depth_backend_status(notify_transition: bool = false):
	if not main.stream_backend:
		return
	# Host settings are restored on the welcome screen, and SBS can override
	# a saved AI-3D selection. Neither state runs depth inference, so a GPU
	# warning from their placeholder configuration must not reach the UI.
	if not main.primary_media_active() or get_stereo_mode() < 3:
		_last_backend_status = ""
		return
	var status = main.stream_backend.get_depth_backend_status()
	if is_android_ai3d_auto() and get_depth_backend_index() == AI3D_BACKEND_GPU \
			and get_ai_3d_gpu_api_effective() == 0 and not _auto_depth_fallback \
			and not status.is_empty() and main.primary_media_active():
		_auto_depth_fallback = true
		main._log("[DEPTH] Auto: EdgePad-512/OpenCL failed (%s); switching to EdgePad-256/OpenGL for this session" % status)
		if main.ui_controller:
			main.ui_controller.update_stereo_shader()
			main.ui_controller.show_temporary_status("AI 3D fallback: EdgePad-256 / OpenGL", 3.0)
		apply_stereo()
		return
	var requested = get_depth_backend_index()
	var failed = not status.is_empty() and requested == AI3D_BACKEND_GPU
	if notify_transition and failed and status != _last_backend_status:
		main._log("[DEPTH] GPU depth failed: " + status)
		if main.ui_controller:
			main.ui_controller.set_status(status)
	elif notify_transition and not failed and not _last_backend_status.is_empty():
		main._log("[DEPTH] GPU depth recovered")
		if main.ui_controller:
			main.ui_controller.set_status("GPU depth recovered")
	_last_backend_status = status if failed else ""

func cycle_ai_3d_debug():
	if not _ai_3d_supported():
		return
	if main.settings.host.sbs_mode > 0 or main.settings.host.ai_3d_speed == 0:
		return
	main.settings.host.ai_3d_debug = (main.settings.host.ai_3d_debug + 1) % ai_3d_debug_labels.size()
	if main.settings.host.ai_3d_debug != 0 and main.settings.host.ai_3d_depth_view:
		main.settings.host.ai_3d_depth_view = false
		_save_setting(main._ui_3d_depth_view_btn, "Off")
	_save_setting(main._ui_3d_debug_btn, ai_3d_debug_labels[main.settings.host.ai_3d_debug])
	_schedule_ai_3d_commit()

func _schedule_ai_3d_commit(delay_seconds: float = 0.6):
	_ai_3d_commit_seq += 1
	var my_seq = _ai_3d_commit_seq
	# Shorter than _schedule_stream_restart()'s own 0.8s - this one's mostly
	# used for fast click-through debugging (checking DMap/DMap-Raw/-Input/-Warp
	# against whichever tier is active), where quick feedback matters more
	# than matching the restart delay exactly. Shared across all three
	# cycle_ai_3d_*() functions above (one sequence counter), so clicking
	# between model/quality/debug controls in quick succession still only
	# commits once, for whatever the final combined state ends up being.
	await main.get_tree().create_timer(delay_seconds).timeout
	if _ai_3d_commit_seq != my_seq:
		return
	# MiDaS-DMap/-Raw/-Input/-Warp are debug VIEWS of whatever depth data is
	# already flowing, not a separate mode with its own resolution needs -
	# deliberately inherit whatever resolution (including a MiDaS-Fast
	# cap) is already active instead of recomputing/restarting back
	# to the full uncapped resolution. That restart actively worked against
	# debugging: switching to a debug view to inspect what a tier was doing
	# changed the very thing being inspected (a different, uncapped
	# resolution) and interrupted the stream to do it. They never restart,
	# so apply_stereo() is always safe to call immediately here.
	if main.settings.host.ai_3d_debug != 0 or main.settings.host.ai_3d_depth_view:
		apply_stereo()
		return
	# MiDaS-Fast caps the actual requested stream resolution (see
	# AUTO_TABLE's cap_px above, applied in main.gd). Checked BEFORE apply_stereo(), not
	# after - if a restart is needed, apply_stereo() is skipped here
	# entirely and left to main.gd's _on_stream_started(), which now calls
	# it once the new session actually lands, instead of calling it here too
	# and applying the new stereo/depth mode against the OLD, about-to-be-
	# replaced video for the ~0.8-1.3s the restart takes. That was a real,
	# visible bug (2026-08-18, user diagnosed it directly): the new effect
	# would visibly apply and then get lost the moment the restart landed,
	# since depth_estimator's pre-pass/warp state got initialized against a
	# session that was seconds from being torn down, not the one that
	# actually mattered.
	var new_res = main.compute_requested_resolution()
	if new_res != main.host_resolution:
		main.host_resolution = new_res
		refresh_resolution_btn_label()
		if main.is_streaming:
			_schedule_stream_restart()
			return
	apply_stereo()

const DEPTH_MODEL_LOAD_SEC := 2.5
# The (model, backend) last sent to configure_depth().
var _configured_depth := Vector2i.ZERO

static func depth_model_switch_loads(previous: Vector2i, next: Vector2i) -> bool:
	return next.x != 0 and next.y == AI3D_BACKEND_GPU and next != previous

func apply_stereo():
	if "pcvr_test" in main and main.pcvr_test.is_exclusive(): return
	var mode = get_stereo_mode()
	var media_active: bool = main.primary_media_active()
	var depth_active: bool = mode >= 3 and media_active
	var display_mode = mode if media_active else 0
	# native_xr_renderer.gd's refresh() re-activates on its own the moment the
	# decoder reports the new stream's video size (normally within a frame or
	# two of _on_stream_started(), which calls this), calling
	# _disable_legacy_video() to turn comp_viewport's update mode back off.
	# Unconditionally switching to the legacy composition layer here first -
	# on every single connect/restart, not just ones legacy actually ends up
	# serving - re-acquires that OpenXRCompositionLayerQuad's own OpenXR
	# swapchain for the brief window in between, racing whatever teardown/
	# recreate it was left in by the *previous* native-active session. That
	# race, not anything resolution-specific, is what was producing the
	# repeatable fault-addr-0xe0 GLThread SIGSEGV on resolution/refresh-rate
	# changes (confirmed via on-device logging: comp_viewport's own size
	# never lined up with crash/no-crash, but this activation window is
	# common to every case that crashed). Skip it here when native rendering
	# is eligible for the new config - can_render_current_config() is the
	# same static check native_xr_renderer.gd's own _eligible() uses, so this
	# stays in sync with whatever it decides moments later. If native
	# rendering then fails to actually start, deactivate(true)'s own
	# switch_to_comp_layer()/switch_to_stereo_comp_layer() fallback still
	# covers activating legacy properly.
	main.video_presentation.apply_mode(display_mode, media_active)
	if main.screen_mesh.material_override is ShaderMaterial:
		main.screen_mesh.material_override.set_shader_parameter("stereo_mode", display_mode)
	if main.depth_estimator:
		# mode 7 (MiDaS-DMap) visualizes upsampled_depth_texture (the real
		# post-upsample data the actual warp uses), so it needs the warp
		# passes running too. mode 8 (MiDaS-DMap-Raw) visualizes the raw
		# pre-upsample depth_texture directly - no warp passes needed. mode 9
		# (MiDaS-DMap-Input) visualizes the literal color capture fed to the
		# model - also no warp passes needed. mode 10 (MiDaS-Fast) is the
		# same warp passes as mode 6, just throttled/shrunk - see
		# warp_update_interval's comment in depth_estimator.gd. warp_tier
		# (0=Standard, 1=Fast - Fastest/2 removed 2026-08-25) comes from
		# resolve_quality_tier() - the SAME tier drives the pre-pass config
		# whether you're looking at the real warp (mode 6/10) or a debug
		# view of it (mode 7/8/9), since debug views are just a lens on
		# whichever tier is actually active, not a tier of their own. mode
		# 11 (MiDaS-Fastest) below is unreachable dead code, left in place
		# same as this file's other retired-stereo_mode conventions.
		var warp_tier = resolve_quality_tier() if main.settings.host.ai_3d_speed > 0 else 0
		main.depth_estimator.set_enabled(depth_active, mode == 6 or mode == 7 or mode == 10 or mode == 11 or mode == 12, warp_tier)
		# Direct decoder textures feed the small depth-input viewport without a
		# third full-resolution mono render. refresh_stream_source() keeps the
		# old mono path available only when a backend cannot expose those textures.
		main.depth_estimator.refresh_stream_source()
	# Which Java-side model/interpreter to run is entirely orthogonal to mode
	# (stereo_mode only encodes speed tier / debug view, see ai_3d_models'
	# comment above) - it comes straight from main.settings.host.ai_3d_model. Modes
	# 6/7/8/9/10/12 (Std, DMap, DMap-Raw, DMap-Input,
	# Fast) are pure visualizations/warp-pass variants of whatever
	# model's depth data is already flowing, not a separate source - mode 9
	# doesn't even read the model's output (just the color capture), but
	# MUST still resolve to the same model index here: leaving it out
	# previously silently swapped the active model down to a different one
	# every time mode 9 was selected, which then poisoned the other modes
	# with stale/wrong-quality data the next time they ran, since all modes
	# share one depth_texture/ImageTexture.
	var model_idx = get_depth_model_index() if depth_active else 0
	if OS.get_name() == "Android":
		var java_class := _android_depth_class()
		if java_class:
			java_class.setDepthGpuApi(get_ai_3d_gpu_api_effective())
	var backend = get_depth_backend_index() if depth_active else AI3D_BACKEND_CPU
	main.stream_backend.configure_depth(model_idx, backend)
	# A GPU model switch pauses depth for ~2.5 s while the previous model's
	# GPU context retires and the new one compiles (DepthEstimator.java's
	# switch cooldown); the 3D effect stands still meanwhile. Say so instead
	# of looking frozen.
	if depth_model_switch_loads(_configured_depth, Vector2i(model_idx, backend)) and main.ui_controller:
		main.ui_controller.show_temporary_status("Loading depth model…", DEPTH_MODEL_LOAD_SEC)
	_configured_depth = Vector2i(model_idx, backend)
	main.stream_backend.set_depth_hz_cap(get_effective_hz_cap())
	refresh_depth_backend_status(true)
	# sync_model_size() (2026-08-27 - moved BEFORE the texture-capture block
	# below, was after) resizes depth_viewport in place, which recreates
	# its underlying render-target texture - reading/pushing
	# de.depth_viewport.get_texture() etc. into the comp shader materials
	# before this ran meant every model switch that actually changed size
	# (e.g. 256<->192) pushed a texture reference that was about to go
	# stale, confirmed via on-device logcat showing "Condition
	# 't->is_render_target' is true" / "Parameter 'from_tex' is null"
	# errors at the exact moment of a model switch, and reported as
	# "sometimes stops loading the depth map" after switching models.
	# configure_depth() above must still run first - sync_model_size()
	# reads get_depth_model_width()/get_depth_model_height(), which only
	# reflect the new model once the Java side has been reconfigured.
	if depth_active and main.depth_estimator:
		main.depth_estimator.sync_model_size()
		main.depth_estimator.set_separation_pct(main.settings.host.ai_3d_separation_pct)
		if main.depth_estimator.depth_texture:
			var de = main.depth_estimator
			var upsampled_tex = de.upsample_viewport.get_texture() if de.upsample_viewport else null
			var offset_tex = de.offset_viewport.get_texture() if de.offset_viewport else null
			var guide_tex = de.depth_viewport.get_texture() if de.depth_viewport else null
			if main.comp_shader_mat_left:
				main.comp_shader_mat_left.set_shader_parameter("depth_texture", de.depth_texture)
				main.comp_shader_mat_left.set_shader_parameter("upsampled_depth_texture", upsampled_tex)
				main.comp_shader_mat_left.set_shader_parameter("offset_texture", offset_tex)
				main.comp_shader_mat_left.set_shader_parameter("depth_guide_texture", guide_tex)
			if main.comp_shader_mat_right:
				main.comp_shader_mat_right.set_shader_parameter("depth_texture", de.depth_texture)
				main.comp_shader_mat_right.set_shader_parameter("upsampled_depth_texture", upsampled_tex)
				main.comp_shader_mat_right.set_shader_parameter("offset_texture", offset_tex)
				main.comp_shader_mat_right.set_shader_parameter("depth_guide_texture", guide_tex)
	_push_ai3d_effect_uniforms()

# Pushes Stereo Separation/Convergence to every material that reads them -
# unconditional (not gated on mode >= 3) so a value change while AI-3D is
# off is already correct the instant it's turned back on. mode5_parallax on
# comp_shader_mat_left/right is handled separately by depth_estimator.gd's
# set_separation_pct() above (it needs _pass_size, which only depth_
# estimator.gd tracks) - this covers stereo_screen.gdshader's own
# independently-tuned copy plus convergence everywhere, including
# depth_offset.gdshader's offset_mat, which nothing pushed to before this.
func _push_ai3d_effect_uniforms():
	var convergence = main.settings.host.ai_3d_convergence_pct / 100.0
	if main.screen_mesh.material_override is ShaderMaterial:
		main.screen_mesh.material_override.set_shader_parameter("mode5_parallax", STEREO_SCREEN_BASE_PARALLAX * (main.settings.host.ai_3d_separation_pct / 100.0))
		main.screen_mesh.material_override.set_shader_parameter("convergence", convergence)
	for mat in [main.comp_shader_mat_left, main.comp_shader_mat_right]:
		if mat:
			mat.set_shader_parameter("convergence", convergence)
	if main.depth_estimator and main.depth_estimator.offset_mat:
		main.depth_estimator.offset_mat.set_shader_parameter("convergence", convergence)

func toggle_passthrough():
	if not main.is_xr_active or not main.passthrough_supported:
		main._log("[PASSTHROUGH] toggle ignored: is_xr_active=%s passthrough_supported=%s" % [str(main.is_xr_active), str(main.passthrough_supported)])
		return
	var fps_before := effective_stream_fps()
	main.settings.passthrough_enabled = not main.settings.passthrough_enabled
	main._log("[PASSTHROUGH] Begin enable=%s streaming=%s native=%s background=%d pcvr=%d" % [main.settings.passthrough_enabled, main.is_streaming, main.video_presentation.is_native_active(), main.settings.background_mode, main.pcvr_handover.state])
	main._flush_log()
	apply_passthrough(main.settings.passthrough_enabled)
	_save_setting(main._ui_pt_btn, "On" if main.settings.passthrough_enabled else "Off")
	main._log("[PASSTHROUGH] toggled to %s and saved" % str(main.settings.passthrough_enabled))
	main._flush_log()
	_follow_camera_limit(fps_before)
	# AUTO_TABLE's tier/model/cap picks all key off passthrough_enabled (see
	# get_auto_selection()) - and manual Fast's resolution cap does too, same
	# table. Refresh the AI Model button immediately (was showing a stale
	# label otherwise - Auto's resolved model can silently change here, e.g.
	# 2K flips between MiDaS-192-GPU and MiDaS-256-GPU) and re-commit the
	# actual depth config/resolution cap the same debounced way any other
	# AI-3D-affecting change does - nothing else calls apply_stereo() on a
	# passthrough toggle otherwise, so the server-side model/cap would
	# silently stay stale too, not just the label.
	if main.settings.host.ai_3d_speed != 0 and main.ui_controller:
		main.ui_controller.update_stereo_shader()
		_schedule_ai_3d_commit()

# Steam Frame: is the screen a mesh in the 3D scene (curved, or Flat Screen:
# 3D Scene) rather than a layer? For the [FRAME-COST] log line.
func _screen_drawn_in_scene() -> bool:
	if not main.device_is_steam_frame:
		return false
	return main.comp == null or not main.comp.in_use or main.comp.get("_frame_curve_active") == true

func apply_passthrough(enable: bool):
	if "pcvr_handover" in main and main.pcvr_handover.owns_workspace(): return
	if "pcvr_test" in main and main.pcvr_test.is_exclusive(): return
	if not main.is_xr_active:
		return
	_hide_all_backgrounds()
	main._sync_comp_background()
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return
	# Steam Frame: SteamVR has no equirect layers. With Nightfall's own
	# engine build the fade is the opacity of the scene's background colour
	# (see PassthroughFade.setup_background()).
	var fade: PassthroughFade = main.passthrough_fade
	var fade_ready: bool = fade.setup(main, main.xr_origin)
	if not fade_ready and main.device_is_steam_frame and FrameEngine.patch_level() >= FrameEngine.BACKGROUND_OPACITY:
		fade_ready = fade.setup_background(main.world_env.environment)
	if enable:
		main.get_viewport().transparent_bg = true
		main.world_env.environment.background_mode = Environment.BG_COLOR
		# With none of those, ask through the background colour anyway; it
		# reaches the compositor only where the renderer keeps its opacity.
		var fade_alpha: float = 0.0 if fade_ready else main.settings.passthrough_fade_pct / 100.0
		main.world_env.environment.background_color = Color(0, 0, 0, fade_alpha)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	else:
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		main.get_viewport().transparent_bg = false
		apply_background(main.settings.background_mode)
	fade.apply(enable, main.settings.passthrough_fade_pct)
	main._log("[PASSTHROUGH] fade %d%% via %s" % [main.settings.passthrough_fade_pct, fade.method])

func cycle_background():
	main.settings.background_mode = (main.settings.background_mode + 1) % main.background_labels.size()
	apply_background(main.settings.background_mode)
	_save_setting(main._ui_bg_btn, main.background_labels[main.settings.background_mode])

func apply_background(bg_mode: int):
	if "pcvr_test" in main and main.pcvr_test.is_exclusive(): return
	if not main.is_xr_active or main.settings.passthrough_enabled:
		return
	_hide_all_backgrounds()
	main.world_env.environment.background_color = Color(0, 0, 0, 1 if bg_mode == 0 else 0)
	if bg_mode > 0:
		var bg_idx = bg_mode - 1
		if bg_idx >= 0 and bg_idx < main.bg_names.size():
			var bg = main.get_node_or_null(main.bg_names[bg_idx])
			if bg:
				bg.visible = true
				bg.emitting = true
	main._sync_comp_background()

func _hide_all_backgrounds():
	for name in main.bg_names:
		var bg = main.get_node_or_null(name)
		if bg:
			bg.visible = false
			bg.emitting = false

func cycle_cursor_mode():
	main.settings.cursor_mode = (main.settings.cursor_mode + 1) % main.cursor_labels.size()
	_save_setting(main._ui_cursor_btn, main.cursor_labels[main.settings.cursor_mode])

func cycle_steady():
	var order: Array[int] = main.POINTER_STEADY_ORDER
	main.settings.pointer_steady = order[(order.find(main.settings.pointer_steady) + 1) % order.size()]
	main._reset_steady_filter()
	_save_setting(main._ui_steady_btn, main.pointer_steady_labels[main.settings.pointer_steady])

func cycle_double_click_mode():
	main.settings.double_click_mode = (main.settings.double_click_mode + 1) % main.double_click_mode_labels.size()
	_save_setting(main._ui_double_click_btn, main.double_click_mode_labels[main.settings.double_click_mode])

func is_codec_available(idx: int) -> bool:
	var client_ok = false
	var server_ok = false
	match idx:
		0:
			client_ok = main._client_codec_support.get("h264", true)
			server_ok = main._server_codec_support.get("h264", true)
		1:
			client_ok = main._client_codec_support.get("hevc", true)
			server_ok = main._server_codec_support.get("hevc", true)
		2:
			client_ok = main._client_codec_support.get("av1", true)
			server_ok = main._server_codec_support.get("av1", true)
		3:
			client_ok = main._client_codec_support.get("raw", true)
			server_ok = main._server_codec_support.get("raw", true)
		4:
			client_ok = main._client_codec_support.get("pyrowave", false)
			server_ok = main._server_codec_support.get("pyrowave", false)
	if main._server_codec_support.is_empty():
		return client_ok
	return client_ok and server_ok

func _get_available_codecs() -> PackedInt32Array:
	var result = PackedInt32Array()
	for i in range(main.codec_labels.size()):
		if is_codec_available(i):
			result.append(i)
	return result

func cycle_codec():
	var available = _get_available_codecs()
	if available.is_empty():
		return
	var cur_pos = available.find(main.settings.codec_preference)
	if cur_pos >= 0:
		main.settings.codec_preference = available[(cur_pos + 1) % available.size()]
	else:
		main.settings.codec_preference = available[0]
	main.ui_controller.update_codec_btn()
	# H.264's hardware-decoder dimension cap in compute_requested_resolution() is keyed
	# off codec_preference - recompute host_resolution now that it just changed, or a
	# switch to H.264 while already at (e.g.) 100% would restart still requesting the
	# uncapped resolution left over from whatever codec was active before.
	main.host_resolution = main.compute_requested_resolution()
	refresh_resolution_btn_label()
	main.state_manager.save_state()
	if main.is_streaming:
		_schedule_stream_restart()
	if main.settings.codec_preference == 4 and main.ui_controller:
		# PyroWave decode is GPU compute work; next to passthrough and AI 3D it
		# leaves AI 3D only a few updates a second.
		main.ui_controller.set_status("PyroWave: lowest latency for fast-paced 2D streaming. GPU-heavy - not recommended with AI 3D.")

func fallback_codec():
	if is_codec_available(1):
		main.settings.codec_preference = 1
	else:
		var available = _get_available_codecs()
		main.settings.codec_preference = available[0] if not available.is_empty() else 0

func cycle_sharpen_mode():
	var choices := get_sharpen_choices()
	var current_idx := choices.find(main.settings.sharpen_mode)
	main.settings.sharpen_mode = choices[(maxi(current_idx, -1) + 1) % choices.size()]
	_save_setting(main._ui_sharpen_btn, get_sharpen_label(main.settings.sharpen_mode))
	apply_filter()

func get_sharpen_choices() -> Array:
	return SettingsPlatformPolicy.sharpen_choices(
		OS.get_name(),
		main.SHARPEN_RUNTIME_NORMAL,
		main.SHARPEN_RUNTIME_QUALITY,
		main.sharpen_labels.size())

func get_sharpen_label(mode: int) -> String:
	return SettingsPlatformPolicy.sharpen_label(
		OS.get_name(),
		mode,
		main.SHARPEN_RUNTIME_NORMAL,
		main.SHARPEN_RUNTIME_QUALITY,
		main.sharpen_labels)

func cycle_brightness():
	var idx = PICTURE_BRIGHTNESS_VALUES.find(main.settings.brightness_pct)
	main.settings.brightness_pct = PICTURE_BRIGHTNESS_VALUES[(maxi(idx, 0) + 1) % PICTURE_BRIGHTNESS_VALUES.size()]
	_save_setting(main._ui_brightness_btn, "%+d%%" % main.settings.brightness_pct)
	apply_filter()

func cycle_contrast():
	var idx = PICTURE_CONTRAST_VALUES.find(main.settings.contrast_pct)
	main.settings.contrast_pct = PICTURE_CONTRAST_VALUES[(maxi(idx, 0) + 1) % PICTURE_CONTRAST_VALUES.size()]
	_save_setting(main._ui_contrast_btn, "%d%%" % main.settings.contrast_pct)
	apply_filter()

func cycle_gamma():
	var idx = PICTURE_GAMMA_VALUES.find(main.settings.gamma_pct)
	main.settings.gamma_pct = PICTURE_GAMMA_VALUES[(maxi(idx, 0) + 1) % PICTURE_GAMMA_VALUES.size()]
	_save_setting(main._ui_gamma_btn, "%d%%" % main.settings.gamma_pct)
	apply_filter()

func cycle_ambient_mode():
	main.settings.ambient_mode = (main.settings.ambient_mode + 1) % main.ambient_mode_labels.size()
	_save_setting(main._ui_ambient_btn, main.ambient_mode_labels[main.settings.ambient_mode])
	main.comp.apply_ambient_settings()
	main.ui_controller.update_ambient_btn_state()

func cycle_ambient_color():
	main.settings.ambient_color = (main.settings.ambient_color + 1) % main.ambient_color_labels.size()
	_save_setting(main._ui_ambient_color_btn, main.ambient_color_labels[main.settings.ambient_color])
	main.comp.apply_ambient_settings()
	main.ui_controller.update_ambient_btn_state()

func toggle_mouse_follows_pointer():
	main.settings.mouse_follows_pointer = not main.settings.mouse_follows_pointer
	_save_setting(main._ui_mouse_follows_btn, "On" if main.settings.mouse_follows_pointer else "Off")

func cycle_auto_reconnect():
	main.settings.auto_reconnect_enabled = not main.settings.auto_reconnect_enabled
	if main.stream_backend and main.stream_backend._v2:
		main.stream_backend._v2.set_auto_reconnect(main.settings.auto_reconnect_enabled)
	_save_setting(main._ui_reconnect_btn, "On" if main.settings.auto_reconnect_enabled else "Off")

func set_language(code: String):
	main.settings.language = code
	apply_language()
	main.state_manager.save_state()
	# Steam Frame: voice typing listens in the menu's language.
	if main.get("voice_typing") != null and main.voice_typing.has_method("language_changed"):
		main.voice_typing.language_changed()

# Applies the saved language (or the OS language when none was chosen) and
# refreshes text that was composed before the change.
func apply_language():
	Localization.apply(Localization.resolve_language(main.settings.language))
	if main.ui_controller:
		main.ui_controller.retranslate()
	if main.welcome_screen:
		main.welcome_screen.retranslate()

func cycle_quick_start():
	main.settings.quick_start_enabled = not main.settings.quick_start_enabled
	_save_setting(main._ui_quick_start_btn, "On" if main.settings.quick_start_enabled else "Off")

# HDR is negotiated at launch (10-bit codec + hdrMode), so a live stream
# restarts to pick it up, the same as a codec change.
func reconnect_audio():
	main._log("[AUDIO] Reconnect Stream pressed")
	if main.settings.play_audio_on_pc:
		main.settings.play_audio_on_pc = false
		main.state_manager.save_state()
	if main.is_streaming:
		_schedule_stream_restart()

func toggle_audio_on_pc():
	main.settings.play_audio_on_pc = not main.settings.play_audio_on_pc
	_save_setting(main._ui_audio_on_pc_btn, "On" if main.settings.play_audio_on_pc else "Off")
	if main.is_streaming:
		_schedule_stream_restart()

func toggle_hdr():
	main.settings.hdr_enabled = not main.settings.hdr_enabled
	_save_setting(main._ui_hdr_btn, "On" if main.settings.hdr_enabled else "Off")
	if main.is_streaming:
		_schedule_stream_restart()

# Meteor's keys are remembered per host (MeteorClient.check_key()); this
# lets a reinstalled Meteor be trusted again.
func forget_meteor_keys():
	MeteorClient.forget_keys()
	main._log("[METEOR] Forgot the remembered Meteor keys")
	main.ui_controller.show_temporary_status("Meteor keys forgotten", 2.0)

# The headset microphone to Nightfall Meteor (MeteorMicrophone). Turning it on
# asks for the microphone permission the first time.
func toggle_microphone():
	if main.settings.microphone_enabled:
		_set_microphone(false)
		return
	if not MeteorMicrophone.is_supported():
		main.ui_controller.show_temporary_status("Microphone unavailable", 2.0)
		return
	main.meteor_microphone.request_permission(func(granted: bool) -> void:
		if granted:
			_set_microphone(true)
		else:
			main._log("[METEOR-MIC] Microphone permission denied")
			main.ui_controller.show_temporary_status("Microphone permission denied", 2.0))

func _set_microphone(enabled: bool) -> void:
	main.settings.microphone_enabled = enabled
	_save_setting(main._ui_microphone_btn, "On" if enabled else "Off")

const FRAME_VOLUME_STEPS: Array = [-60, -18, -12, -6, 0, 3, 6, 9, 12]

## Steam Frame: Stream > Volume is a slider. Its first position is Mute; the
## other twenty are 3 dB apart from -45 dB to +12 dB (Normal, 0 dB, at 80%),
## the same steps the volume buttons and voice commands use.
func set_volume(value: int, commit: bool) -> void:
	var step: int = clampi(int(round(value / 5.0)), 0, 20)
	main.settings.audio_boost_db = -60 if step == 0 else -48 + 3 * step
	refresh_volume_btn()
	apply_audio_boost()
	if commit:
		main.state_manager.save_state()

## Shows the current volume on Stream > Volume, slider or plain button.
func refresh_volume_btn() -> void:
	if main.ui_controller:
		main.ui_controller.refresh_mute_indicator()
	var btn: Button = main._ui_audio_boost_btn
	if btn == null:
		return
	if not btn.has_meta("slider"):
		main.ui_controller.update_option_btn(btn, get_audio_boost_label())
		return
	var db: int = main.settings.audio_boost_db
	var muted: bool = db <= -60
	var step: int = 0 if muted else clampi(int(round((db + 48) / 3.0)), 1, 20)
	main.ui_controller.set_slider_value(btn, step * 5, get_audio_boost_label(), muted)

func cycle_audio_boost():
	var values: Array = FRAME_VOLUME_STEPS if main.device_is_steam_frame else SettingsPersistence.AUDIO_BOOST_VALUES
	var idx = values.find(main.settings.audio_boost_db)
	main.settings.audio_boost_db = values[(maxi(idx, 0) + 1) % values.size()]
	_save_setting(main._ui_audio_boost_btn, get_audio_boost_label())
	refresh_volume_btn()
	apply_audio_boost()

func get_audio_boost_label() -> String:
	if main.settings.audio_boost_db <= -60:
		return "Mute"
	if main.settings.audio_boost_db < 0:
		return "%d dB" % main.settings.audio_boost_db
	return "Normal" if main.settings.audio_boost_db == 0 else "+%d dB" % main.settings.audio_boost_db

## Steam Frame controller buttons: step the stream volume (shared with Stream > Volume).
var _pre_mute_db := 0
func step_volume(what: String) -> void:
	var db: int = main.settings.audio_boost_db
	match what:
		"vol_up":
			db = 0 if db <= -60 and _pre_mute_db == 0 else (_pre_mute_db if db <= -60 else mini(db + 3, 12))
		"vol_down":
			db = maxi((_pre_mute_db if db <= -60 else db) - 3, -45)
		"mute":
			if db <= -60:
				db = _pre_mute_db
			else:
				_pre_mute_db = db
				db = -60
	main.settings.audio_boost_db = db
	_save_setting(main._ui_audio_boost_btn, get_audio_boost_label())
	refresh_volume_btn()
	apply_audio_boost()
	main.ui_controller.show_temporary_status("Volume: " + get_audio_boost_label(), 1.0)

func get_audio_output_label() -> String:
	return "AudioTrack" if main.settings.android_audio_output == 1 else "Native"

func cycle_audio_output():
	main.settings.android_audio_output = 1 - main.settings.android_audio_output
	_save_setting(main._ui_audio_output_btn, get_audio_output_label())
	apply_audio_boost()
	if main.is_streaming:
		_schedule_stream_restart()

# Sometimes the host starts a stream without ever sending audio, and nothing
# brings it back for that session. A restart always fixes it, so if no audio
# packet has arrived a few seconds in, restart once on the user's behalf.
var _audio_watch_seq := 0
var _audio_auto_restarts := 0

func start_audio_watchdog():
	_audio_watch_seq += 1
	var my_seq := _audio_watch_seq
	await main.get_tree().create_timer(6.0).timeout
	if my_seq != _audio_watch_seq or not main.is_streaming:
		return
	if not (main.stream_backend and main.stream_backend._v2):
		return
	var audio = main.stream_backend._v2.get_audio_renderer()
	if not audio or not audio.has_method("get_packets_received"):
		return
	var packets: int = audio.get_packets_received()
	if packets > 0:
		_audio_auto_restarts = 0
		return
	if _audio_auto_restarts >= 2:
		main._log("[AUDIO] Still no audio from the host after %d automatic restarts; giving up" % _audio_auto_restarts)
		return
	_audio_auto_restarts += 1
	main._log("[AUDIO] No audio from the host 6s into the stream; restarting the stream (attempt %d)" % _audio_auto_restarts)
	_schedule_stream_restart()

func apply_audio_boost():
	if not (main.stream_backend and main.stream_backend._v2):
		return
	var audio = main.stream_backend._v2.get_audio_renderer()
	if audio:
		audio.set_volume_boost_db(float(main.settings.audio_boost_db))
		if OS.get_name() == "Android" and audio.has_method("set_android_output"):
			audio.set_android_output(main.settings.android_audio_output)

# USB Link (docs/plans/active/usb-link-streaming.md) - requests Horizon OS
# 2.5+'s TRANSPORT_USB network so streaming can use the USB-C cable instead
# of Wi-Fi. _usb_link_bridge() returns a fresh, stateless proxy each call,
# same convention as MdnsBrowser's own ad-hoc ClassDB.instantiate() use - the
# real state lives in Java's static UsbLinkManager singleton regardless of
# how many of these wrapper instances exist.
func _usb_link_bridge() -> Object:
	if not ClassDB.class_exists("UsbLinkBridge"):
		return null
	return ClassDB.instantiate("UsbLinkBridge")

func usb_link_supported() -> bool:
	var bridge = _usb_link_bridge()
	return bridge != null and bridge.is_supported()

# Called after loading persisted state - a saved "on" has to actually
# re-request the link, not just redraw the button label as "On" (unlike a
# plain cosmetic setting, this one does something only while an underlying
# system request is live, and that request does not survive a process
# restart on its own).
func apply_usb_link():
	if not main.settings.usb_link_enabled:
		return
	var bridge = _usb_link_bridge()
	if bridge == null or not bridge.is_supported():
		main.settings.usb_link_enabled = false
		return
	var started: bool = bridge.start()
	if main._ui_usb_link_btn:
		main.ui_controller.update_option_btn(main._ui_usb_link_btn, "Requesting..." if started else "Failed")
	main._log("[USB LINK] Re-requested on load: %s" % ("ok" if started else "failed"))

func toggle_usb_link():
	main._log("[USB LINK] toggle pressed, class_exists=%s" % ClassDB.class_exists("UsbLinkBridge"))
	var bridge = _usb_link_bridge()
	if bridge == null:
		main._log("[USB LINK] bridge instantiate failed")
		return
	var supported: bool = bridge.is_supported()
	main._log("[USB LINK] bridge.is_supported()=%s" % supported)
	if not supported:
		return
	main.settings.usb_link_enabled = not main.settings.usb_link_enabled
	if main.settings.usb_link_enabled:
		var started: bool = bridge.start()
		_save_setting(main._ui_usb_link_btn, "Requesting..." if started else "Failed")
		main._log("[USB LINK] Requested: %s" % ("ok" if started else "failed"))
	else:
		bridge.stop()
		_save_setting(main._ui_usb_link_btn, "Off")
		main._log("[USB LINK] Released")

# Polled once a second (own timer, deliberately NOT main.gd's telemetry
# frame_sample - that one only ever fires while is_streaming, which would
# leave this stuck on "Requesting..." at the welcome screen forever, exactly
# the bug this replaced) while the setting is on, so the button label
# actually reflects link state - start() only means "requested", not "up"
# (the link comes up asynchronously, same reason the reference PR's own UI
# has to react to a callback rather than show success immediately).
var _usb_link_poll_elapsed: float = 0.0

func poll_usb_link_status(delta: float):
	if not main.settings.usb_link_enabled or not main._ui_usb_link_btn:
		return
	_usb_link_poll_elapsed += delta
	if _usb_link_poll_elapsed < 1.0:
		return
	_usb_link_poll_elapsed = 0.0
	var bridge = _usb_link_bridge()
	if bridge == null:
		return
	var up: bool = bridge.is_up()
	var label = "Up" if up else "Requesting..."
	if main._ui_usb_link_btn.get_meta(UIController.OPTION_VALUE_META, "") != label:
		main.ui_controller.update_option_btn(main._ui_usb_link_btn, label)
	if up and not _usb_link_was_up:
		_learn_usb_addresses()
	_usb_link_was_up = up
	if up:
		_maybe_return_to_usb_link()

var _usb_link_was_up := false

# Streams use the cable only for hosts with a saved usb_address, which used
# to be learned only by pairing over the cable: a PC paired over Wi-Fi kept
# streaming over Wi-Fi while USB Link said "Up" (Rush_iam). When the link
# comes up, find saved hosts on it by their unique ID and save the address.
func _learn_usb_addresses() -> void:
	var iface: String = main.stream_manager._usb_link_iface()
	var cm = main.stream_backend.get_computer_manager()
	var config = main.stream_backend.get_config_manager()
	if iface.is_empty() or cm == null or config == null:
		return
	var found: Array = []
	var thread := Thread.new()
	thread.start(func(): found.append_array(main.stream_backend.browse_mdns_usb(iface, 3.0)))
	while thread.is_alive():
		await main.get_tree().create_timer(0.1).timeout
	thread.wait_to_finish()
	for usb_host in found:
		var ip: String = usb_host.get("ip", "")
		if ip.is_empty():
			continue
		cm.connect_to_computer(ip, int(usb_host.get("port", main.DEFAULT_PAIR_PORT)), func(result: Dictionary):
			if result.get("status", "") != "online":
				# Seen on the cable (its mDNS reached us) but its web server
				# doesn't answer there.
				main._log("[USB] %s advertises on USB Link but doesn't answer there" % ip)
				main.ui_controller.set_status("USB Link is up, but the PC doesn't answer over it. Set address_family = both in the host's config; on Windows, allow it through the firewall on Public networks.")
				return
			var host_id := usb_host_to_update(main.stream_backend.get_hosts(), ip, str(result.get("uniqueid", "")))
			if host_id >= 0:
				config.update_host(host_id, {"usb_address": ip})
				main._log("[USB] Learned USB Link address %s for host %d" % [ip, host_id])
				main.ui_controller.show_temporary_status("USB Link: PC found on the cable", 3.0))

## The saved host that `unique_id` identifies, if its USB address isn't `ip`
## yet; -1 otherwise.
static func usb_host_to_update(hosts: Array, ip: String, unique_id: String) -> int:
	if unique_id.is_empty():
		return -1
	for host in hosts:
		if str(host.get("server_unique_id", "")) == unique_id:
			return -1 if str(host.get("usb_address", "")) == ip else int(host.get("id", -1))
	return -1

var _usb_return_probe_in_flight: bool = false
var _usb_return_last_probe_ms: int = 0

# A stream that fell back to the network when the cable was pulled moves back
# onto USB Link once the host answers over it again (the link coming up on the
# headset doesn't mean the PC side is configured yet, so probe, don't assume).
func _maybe_return_to_usb_link():
	if not main.is_streaming or _restart_pending or _usb_return_probe_in_flight:
		return
	if main.session_lifecycle.phase != SessionLifecycle.Phase.STREAMING:
		return
	if main.stream_manager.connection_label() == "USB Link":
		return
	var host: Dictionary = {}
	for h in main.stream_backend.get_hosts():
		if h.get("id") == main.current_host_id:
			host = h
			break
	var usb_address: String = host.get("usb_address", "")
	if usb_address.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _usb_return_last_probe_ms < 5000:
		return
	_usb_return_last_probe_ms = now
	var cm = main.stream_backend.get_computer_manager()
	if cm == null:
		return
	_usb_return_probe_in_flight = true
	var expected_id: String = host.get("server_unique_id", "")
	cm.connect_to_computer(usb_address, int(host.get("http_port", main.DEFAULT_PAIR_PORT)), func(result: Dictionary):
		_usb_return_probe_in_flight = false
		if result.get("status", "") != "online":
			return
		if not expected_id.is_empty() and result.get("uniqueid", "") != expected_id:
			return
		if not main.is_streaming or main.stream_manager.connection_label() == "USB Link":
			return
		main._log("[USB LINK] Host reachable over USB again - moving stream back onto it")
		_schedule_stream_restart()
	)

func cycle_idle_timeout():
	var idx = idle_values.find(main.settings.idle_timeout_min)
	idx = (idx + 1) % idle_values.size()
	main.settings.idle_timeout_min = idle_values[idx]
	_save_setting(main._ui_idle_btn, idle_labels[idx])

func toggle_host_cursor():
	if not main._host_cursor_toggle_supported or not main.is_streaming:
		return
	var target = not main.host_cursor_visible
	main.stream_backend.set_cursor_visible(main.current_host_id, target, func(response: Dictionary):
		if response.get("status", "") == "success":
			main.host_cursor_visible = response.get("visible", target)
			main.ui_controller.update_host_cursor_btn_state()
	)

func apply_filter():
	if not main.is_xr_active:
		return
	# The standalone Blur control was removed. Keep the legacy shader uniform
	# neutral; its neighbourhood taps remain available only for shader-sharpen
	# fallback on runtimes without compositor sharpening.
	var filter_val = 0
	var runtime_sharpen_requested = main.settings.sharpen_mode >= main.SHARPEN_RUNTIME_NORMAL
	var runtime_sharpen_active = main.comp.apply_compositor_sharpen(main.settings.sharpen_mode) if main.comp else false
	# Retain an application-shader fallback for desktop, stock Godot templates,
	# and runtimes that do not advertise XR_FB_composition_layer_settings.
	var sharp_val: float
	if runtime_sharpen_requested:
		sharp_val = 0.0 if runtime_sharpen_active else (0.5 if main.settings.sharpen_mode == main.SHARPEN_RUNTIME_NORMAL else 1.0)
	else:
		sharp_val = float(main.settings.sharpen_mode) * 0.5
	# Picture tab (2026-08-31) - percent state -> shader-unit conversion
	# lives here, shaders themselves stay unit-agnostic (0.0/1.0/1.0
	# neutral defaults).
	var brightness_val = main.settings.brightness_pct / 100.0
	var contrast_val = main.settings.contrast_pct / 100.0
	var gamma_val = main.settings.gamma_pct / 100.0
	var picture_adjusted = main.settings.brightness_pct != 0 or main.settings.contrast_pct != 100 or main.settings.gamma_pct != 100
	# Keep pow() and the three grading uniforms out of the default mesh and
	# composition shader programs. Shader swaps only occur when crossing the
	# neutral/adjusted boundary, not for every value within that state.
	if not _stereo_sdr_shader:
		_stereo_sdr_shader = load("res://src/shaders/stereo_screen.gdshader")
	if not _stereo_picture_shader:
		_stereo_picture_shader = load("res://src/shaders/stereo_screen_picture.gdshader")
	var mat = main.screen_mesh.material_override
	if mat and mat is ShaderMaterial:
		var desired_shader = _stereo_picture_shader if picture_adjusted else _stereo_sdr_shader
		if mat.shader != desired_shader:
			mat.shader = desired_shader
		mat.set_shader_parameter("filter_mode", filter_val)
		mat.set_shader_parameter("sharpen", sharp_val)
		mat.set_shader_parameter("blur_scale", main.get_blur_scale(main.primary_screen))
		mat.set_shader_parameter("brightness", brightness_val)
		mat.set_shader_parameter("contrast", contrast_val)
		mat.set_shader_parameter("gamma", gamma_val)
	main.comp.refresh_picture_shader_state()
	for s in main.screens:
		for cm in main.comp.get_shader_mats(s):
			if cm:
				cm.set_shader_parameter("filter_mode", filter_val)
				cm.set_shader_parameter("sharpen", sharp_val)
				cm.set_shader_parameter("blur_scale", main.get_blur_scale(s))
				cm.set_shader_parameter("brightness", brightness_val)
				cm.set_shader_parameter("contrast", contrast_val)
				cm.set_shader_parameter("gamma", gamma_val)

func effective_stream_fps() -> int:
	var fps: int = pcvr_timing.effective_fps(main.settings.host.stream_fps)
	return mini(fps, CAMERA_LIMIT_FPS) if camera_limit_active() else fps

## Steam Frame: the rate Nightfall keeps to while a camera add-on shows the
## room (see FramePassthroughCamera). At 90 Hz a frame has 11.1 ms, and
## Nightfall's frame with the cameras on takes 9.5 at 1080p and 9.7 to 12.7 at
## 1440p; at 144 Hz it has 6.9 (7a log). The user's own FPS choice stays as it
## is and comes back when the limit lets go.
const CAMERA_LIMIT_FPS := 90
## Advanced Settings > Camera FPS Limit. Auto: while the add-on's camera is
## the one running. On: whenever an add-on is fitted. Either only with
## Passthrough on.
const CAMERA_LIMIT_AUTO := 0
const CAMERA_LIMIT_ON := 1
const CAMERA_LIMIT_OFF := 2
const CAMERA_LIMIT_LABELS := ["Auto", "On", "Off"]
## Auto goes back to the chosen rate only after the add-on's camera has been
## idle this long. Each change of rate restarts the stream.
const CAMERA_RELEASE_MS := 20000
## When the cameras change over by themselves, the stream is restarted this
## long after a notice says so, to leave time to pause a game.
const CAMERA_WARNING_SECONDS := 5.0
## The stream rate apply_display_refresh_rate() last worked from: the running
## stream's, while one runs.
var applied_stream_fps := 0
var _camera_restart_seq := 0
## Which waiting restart (SettingsController's _restart_seq) the camera limit
## asked for; -1 for none.
var _camera_restart_at := -1
## The add-on sensors last seen; refreshed by refresh_addon_cameras().
var addon_cameras := PackedStringArray()
## The add-on's camera is showing the room (or was a moment ago); kept up to
## date by check_addon_in_use().
var addon_in_use := false
var _addon_idle_since_ms := -1

func camera_limit_active() -> bool:
	# addon_cameras is only ever filled on the Steam Frame.
	if addon_cameras.is_empty() or not main.settings.passthrough_enabled or pcvr_timing.active:
		return false
	match main.settings.frame_camera_limit:
		CAMERA_LIMIT_ON: return true
		CAMERA_LIMIT_AUTO: return addon_in_use
	return false

## What the FPS button shows: the chosen rate, and the rate in force when the
## camera limit holds it lower.
func fps_label() -> String:
	var chosen: int = main.settings.host.stream_fps
	var now := effective_stream_fps()
	return "%d" % chosen if now == chosen else "%d (%d now)" % [chosen, now]

## Looks for a camera add-on again (it can be fitted while Nightfall runs).
func refresh_addon_cameras() -> void:
	if not main.device_is_steam_frame:
		return
	var found := FramePassthroughCamera.addons()
	if found == addon_cameras:
		return
	var before := effective_stream_fps()
	addon_cameras = found
	addon_in_use = not found.is_empty() and FramePassthroughCamera.addon_running()
	_addon_idle_since_ms = -1
	main._log("[CAMERA] camera add-on: %s%s" % ["none" if found.is_empty() else ", ".join(found),
		"" if found.is_empty() else (", showing the room" if addon_in_use else ", not running")])
	if main._ui_camera_limit_btn:
		main._ui_camera_limit_btn.visible = not found.is_empty()
	_follow_camera_limit(before, true)

## Whether the add-on's camera or the headset's own is running, looked at
## every few seconds while an add-on is fitted.
func check_addon_in_use() -> void:
	if addon_cameras.is_empty():
		return
	var running := FramePassthroughCamera.addon_running()
	var now_ms := Time.get_ticks_msec()
	if running:
		_addon_idle_since_ms = -1
	elif _addon_idle_since_ms < 0:
		_addon_idle_since_ms = now_ms
	var in_use := FramePassthroughCamera.still_in_use(addon_in_use, running,
		0 if _addon_idle_since_ms < 0 else now_ms - _addon_idle_since_ms, CAMERA_RELEASE_MS)
	if in_use == addon_in_use:
		return
	var before := effective_stream_fps()
	addon_in_use = in_use
	main._log("[CAMERA] the add-on's camera is %s" % ("showing the room" if in_use else "no longer running"))
	_follow_camera_limit(before, true)

func cycle_camera_limit():
	var before := effective_stream_fps()
	main.settings.frame_camera_limit = (main.settings.frame_camera_limit + 1) % CAMERA_LIMIT_LABELS.size()
	_save_setting(main._ui_camera_limit_btn, CAMERA_LIMIT_LABELS[main.settings.frame_camera_limit])
	_follow_camera_limit(before)

## Why the camera limit is not holding the rate down, for the notice.
func _camera_limit_released_by() -> String:
	if not main.settings.passthrough_enabled:
		return "Passthrough off"
	if addon_cameras.is_empty():
		return "Camera add-on removed"
	if main.settings.frame_camera_limit == CAMERA_LIMIT_OFF:
		return "Camera FPS Limit off"
	return "Native passthrough detected"

## After anything the camera limit depends on has changed: says so and brings
## the stream and the display to the rate now in force. `by_itself`: the
## cameras changed over (or an add-on was fitted or taken off) with nobody
## pressing anything, so the notice comes first and the restart a few seconds
## later.
func _follow_camera_limit(fps_before: int, by_itself: bool = false) -> void:
	var now := effective_stream_fps()
	if main._ui_fps_btn and not pcvr_timing.active:
		main.ui_controller.update_option_btn(main._ui_fps_btn, fps_label())
	if now == fps_before:
		return
	main._log("[CAMERA] rate %d -> %d fps%s (FPS is set to %d; passthrough %s, limit %s, add-on %s%s)" % [fps_before, now,
		" in %.0fs" % CAMERA_WARNING_SECONDS if by_itself and main.is_streaming and now != applied_stream_fps else "",
		main.settings.host.stream_fps, "on" if main.settings.passthrough_enabled else "off",
		CAMERA_LIMIT_LABELS[main.settings.frame_camera_limit].to_lower(),
		"none" if addon_cameras.is_empty() else ", ".join(addon_cameras),
		"" if addon_cameras.is_empty() else (" showing the room" if addon_in_use else " not running")])
	if not main.is_streaming:
		_schedule_display_refresh()
		return
	if by_itself and now == applied_stream_fps:
		# The cameras changed back before the restart that was announced: the
		# stream already runs at this rate, so that restart is called off.
		_camera_restart_seq += 1
		main._log("[CAMERA] change called off: the stream is already at %d fps" % now)
		if main.comp and main.comp.has_method("show_notice"):
			main.comp.show_notice("Camera switch canceled: staying at %d fps." % now, 4.0)
		return
	var wait := CAMERA_WARNING_SECONDS if by_itself else 0.0
	if main.comp and main.comp.has_method("show_notice"):
		var when := " in %d seconds" % int(wait) if by_itself else ""
		if camera_limit_active():
			_camera_limit_told = true
			main.comp.show_notice("%s: %d fps%s.\nAdvanced Settings > Camera FPS Limit changes this." % [
				"Color camera detected" if by_itself else "Color camera passthrough", now, when], wait + 4.0)
		else:
			main.comp.show_notice("%s: back to %d fps%s." % [_camera_limit_released_by(), now, when], wait + 3.0)
	_restart_for_camera_limit(now, wait)

## Restarts the stream at `fps` after `wait` seconds, unless the limit has
## changed again by then (that change brings its own restart) or the stream
## already runs at that rate (the cameras changed over and back).
func _restart_for_camera_limit(fps: int, wait: float) -> void:
	_camera_restart_seq += 1
	var seq := _camera_restart_seq
	if wait > 0.0:
		await main.get_tree().create_timer(wait).timeout
	if seq != _camera_restart_seq or effective_stream_fps() != fps:
		return
	if main.is_streaming and applied_stream_fps != fps:
		# A press of a button waits out the usual moment, so cycling through
		# the option's choices doesn't restart the stream for each.
		_schedule_stream_restart(0.0 if wait > 0.0 else 0.8)
		_camera_restart_at = _restart_seq
	elif _restart_pending and _restart_seq == _camera_restart_at:
		# Cycled on to a choice that leaves the rate where the stream already
		# is (Auto, On, Off in a row): the restart the earlier press asked for
		# is called off (7l: such a pair of presses restarted a stream at the
		# rate it already had). Only if no other setting has asked since.
		cancel_stream_restart()
		main._log("[CAMERA] restart called off: the stream is already at %d fps" % fps)

## Says why the rate is lower than the FPS chosen. Also called when a stream
## starts with the limit already in force, once a run.
var _camera_limit_told := false

func tell_camera_limit(only_once: bool = false) -> void:
	if not camera_limit_active() or effective_stream_fps() >= main.settings.host.stream_fps:
		return
	if only_once and _camera_limit_told:
		return
	_camera_limit_told = true
	if main.comp and main.comp.has_method("show_notice"):
		main.comp.show_notice("Color camera passthrough: %d fps.\nAdvanced Settings > Camera FPS Limit changes this." % CAMERA_LIMIT_FPS, 6.0)

func pcvr_timing_active() -> bool:
	return pcvr_timing.active

func prepare_pcvr_timing(fps: int) -> bool:
	if not begin_pcvr_timing(fps): return false
	if _pcvr_wait_for_desktop:
		var deadline := Time.get_ticks_msec() + 12000
		while pcvr_timing.active and not pcvr_desktop_timing_ready():
			if Time.get_ticks_msec() >= deadline: return false
			await main.get_tree().process_frame
	else:
		if not await apply_display_refresh_rate(): return false
	if not pcvr_timing.active: return false
	var interface = XRServer.find_interface("OpenXR")
	return interface != null and absf(interface.get_display_refresh_rate() - pcvr_timing.display_hz) < 0.6

func begin_pcvr_timing(fps: int) -> bool:
	var interface = XRServer.find_interface("OpenXR")
	if not interface: return false
	if not pcvr_timing.begin(fps, interface.get_display_refresh_rate()): return false
	_refresh_request_seq += 1 # Retire any older asynchronous display request.
	_pcvr_previous_render_cap = Engine.max_fps
	Engine.max_fps = int(ceil(pcvr_timing.display_hz))
	main.display_refresh_rate = pcvr_timing.display_hz
	_pcvr_wait_for_desktop = main.is_streaming and (main.settings.host.stream_fps != fps or absf(interface.get_display_refresh_rate() - pcvr_timing.display_hz) >= 0.6)
	refresh_pcvr_timing_ui()
	main._log("[PCVR-TIMING] Override desktop video=%dfps display=%.0fHz; saved desktop=%dfps" % [fps, pcvr_timing.display_hz, main.settings.host.stream_fps])
	if _pcvr_wait_for_desktop: _schedule_stream_restart(0.0)
	return true

func pcvr_desktop_timing_ready() -> bool:
	return not _pcvr_wait_for_desktop or (not _restart_pending and main.is_streaming and main.session_lifecycle.phase == SessionLifecycle.Phase.STREAMING)

func end_pcvr_timing() -> void:
	if not pcvr_timing.active: return
	var restart: bool = main.is_streaming and effective_stream_fps() != main.settings.host.stream_fps
	pcvr_timing.end()
	_refresh_request_seq += 1
	Engine.max_fps = _pcvr_previous_render_cap
	_pcvr_wait_for_desktop = false
	refresh_pcvr_timing_ui()
	main._log("[PCVR-TIMING] Restoring desktop preference %dfps" % main.settings.host.stream_fps)
	if restart:
		_schedule_stream_restart(0.0)
	else:
		apply_display_refresh_rate()

func refresh_pcvr_timing_ui() -> void:
	if not main._ui_fps_btn: return
	main._ui_fps_btn.disabled = pcvr_timing.active
	main.ui_controller.update_option_btn(main._ui_fps_btn, "%d (PCVR)" % effective_stream_fps() if pcvr_timing.active else fps_label())
	main._ui_fps_btn.set_meta(&"nightfall_tooltip", "Controlled by PCVR while active. Your desktop preference is restored on exit." if pcvr_timing.active else MenuSchema.fps_tooltip())

## `ask_steamvr`: on the Steam Frame, have SteamVR switch the display to the
## wanted rate. Off at start-up, when the stream rate in hand is only the
## default: the PC's own rate follows when its stream starts, and each switch
## is a change of the display.
func apply_display_refresh_rate(ask_steamvr: bool = true) -> bool:
	if not main.is_xr_active:
		return false
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return false
	_refresh_request_seq += 1
	var request_seq = _refresh_request_seq
	var stream_fps := effective_stream_fps()
	applied_stream_fps = stream_fps
	var target_hz: float = float(stream_fps)
	match stream_fps:
		30: target_hz = 90.0
		# 2026-08-29: testing 120Hz again now that stereo rendering is
		# projectionless (no more per-eye mesh reprojection cost) - this was
		# 72.0 since 1132efd (2026-06-12), when 120Hz was too expensive for
		# the old mesh-projection render path and caused stutter. Revert to
		# 72.0 if that's still true here.
		60: target_hz = 120.0
	if pcvr_timing.active: target_hz = pcvr_timing.display_hz
	if main.device_is_steam_frame and not pcvr_timing.active and ask_steamvr:
		target_hz = float(FrameDisplayRate.rate_for(target_hz))
		await _frame_request_rate(interface, int(target_hz))
		if request_seq != _refresh_request_seq:
			return false
	var available = interface.get_available_display_refresh_rates()
	Engine.max_fps = int(ceil(pcvr_timing.display_hz)) if pcvr_timing.active else stream_fps
	if available.is_empty():
		main._log("[REFRESH] No available refresh rates reported")
		main.display_refresh_rate = target_hz
		return false
	available.sort()
	var current_hz: float = interface.get_display_refresh_rate()
	main._log("[REFRESH] Runtime rates=%s current=%.0fHz target=%.0fHz" % [str(available), current_hz, target_hz])

	# Preserve an exact current rate. Otherwise request every Quest 3 extended
	# target through the standard API up to the documented 207 Hz maximum;
	# verification below selects a reported fallback if the runtime rejects it.
	var target_already_active := absf(current_hz - target_hz) < 0.6
	var best: float = 0.0
	if target_already_active:
		best = current_hz
	elif main.device_is_quest3 and target_hz > 120.0 and target_hz <= QUEST3_REFRESH_REQUEST_MAX:
		# Meta deprecated the enumeration API; HorizonOS still returns only
		# legacy presets even though Quest 3 accepts arbitrary integer rates.
		# Request the unlisted rate directly, then verify it and fall back to
		# the reported list on older/currently-limited runtime versions.
		interface.set_display_refresh_rate(target_hz)
		await main.get_tree().create_timer(REFRESH_SURFACE_SETTLE_SEC).timeout
		if request_seq != _refresh_request_seq:
			return false
		var applied_hz: float = interface.get_display_refresh_rate()
		if absf(applied_hz - target_hz) < 0.6:
			best = applied_hz
		else:
			best = _reported_refresh_fallback(available, target_hz)
			interface.set_display_refresh_rate(best)
			main._log("[REFRESH] Quest 3 rejected unlisted %.0fHz (actual %.0fHz); using reported %.0fHz" % [target_hz, applied_hz, best])
			await main.get_tree().create_timer(REFRESH_SURFACE_SETTLE_SEC).timeout
			if request_seq != _refresh_request_seq:
				return false
	else:
		best = _reported_refresh_fallback(available, target_hz)
		interface.set_display_refresh_rate(best)
		await main.get_tree().create_timer(REFRESH_SURFACE_SETTLE_SEC).timeout
		if request_seq != _refresh_request_seq:
			return false
	# Always report what the runtime says it actually applied. This matters on
	# desktop OpenXR runtimes such as WiVRN, where accepting a request and
	# presenting at that rate are separate concerns.
	var applied_hz: float = interface.get_display_refresh_rate()
	if applied_hz > 0.0:
		if absf(applied_hz - best) >= 0.6:
			main._log("[REFRESH] Runtime reported %.0fHz after requesting %.0fHz" % [applied_hz, best])
		best = applied_hz
	main.display_refresh_rate = best
	# 2026-08-29: capping render fps to the stream's own fps again (was
	# uncapped since 8ffa8fe, 2026-05-05, "remove 60fps cap causing Quest ASW
	# reprojection blur") - testing whether that ASW blur was a symptom of
	# the old mesh-projection render path specifically, now that rendering
	# is projectionless. Revert to 0 (uncapped) if the blur is still there.
	if pcvr_timing.active:
		main._log("[PCVR-TIMING] Display %.0fHz; desktop video %dfps; app cap %d" % [best, stream_fps, Engine.max_fps])
	elif target_already_active:
		main._log("[REFRESH] Preserved active %.0fHz for %dfps, capped render to %dfps" % [best, main.settings.host.stream_fps, main.settings.host.stream_fps])
	elif absf(best - target_hz) < 0.6:
		main._log("[REFRESH] Set headset to %.0fHz for %dfps, capped render to %dfps" % [best, main.settings.host.stream_fps, main.settings.host.stream_fps])
	else:
		main._log("[REFRESH] %.0fHz unavailable; fell back to reported %.0fHz for %dfps stream, capped render to %dfps" % [target_hz, best, main.settings.host.stream_fps, main.settings.host.stream_fps])
	return true

## Steam Frame: has SteamVR switch this app's display rate (see
## FrameDisplayRate) and waits for the display to follow.
func _frame_request_rate(interface: XRInterface, want_hz: int) -> void:
	var before: float = interface.get_display_refresh_rate()
	if absf(before - want_hz) < 0.6:
		return
	var why := FrameDisplayRate.ask(want_hz)
	if not why.is_empty():
		main._log("[REFRESH] %d Hz not asked for: %s. Staying on %.0f Hz" % [want_hz, why, before])
		return
	var waited := 0.0
	while waited < FrameDisplayRate.WAIT_SEC:
		await main.get_tree().create_timer(0.2).timeout
		waited += 0.2
		if absf(interface.get_display_refresh_rate() - want_hz) < 0.6:
			main._log("[REFRESH] SteamVR switched Nightfall from %.0f to %d Hz in %.1fs" % [before, want_hz, waited])
			return
	main._log("[REFRESH] asked SteamVR for %d Hz; the display still reports %.0f Hz after %.0fs" % [
		want_hz, interface.get_display_refresh_rate(), FrameDisplayRate.WAIT_SEC])

func _reported_refresh_fallback(available: Array, target_hz: float) -> float:
	var best := 0.0
	for rate in available:
		if rate >= target_hz and (best == 0.0 or rate < best):
			best = rate
	if best == 0.0:
		best = available[available.size() - 1]
	# Changing the OpenXR display rate tears down/recreates runtime-owned
	# surfaces on Quest, which can race a stream restart's just-rebuilt native
	# and Godot GLES resources. That protection now lives in the caller,
	# apply_display_refresh_rate()'s target_already_active check above (computed
	# once, before either set_display_refresh_rate() call site) - this helper
	# only computes which rate to fall back to, it doesn't apply anything.
	return best

func cycle_fps():
	if pcvr_timing.active: return
	main.settings.host.stream_fps = next_fps_rate(main.settings.host.stream_fps,
		main.settings.high_refresh_rates and not main.device_is_steam_frame,
		FRAME_MAX_STREAM_FPS if main.device_is_steam_frame else 0)
	_save_setting(main._ui_fps_btn, fps_label())
	if main.is_streaming:
		_schedule_stream_restart()
	else:
		_schedule_display_refresh()

# 200 and 207 Hz glitch some headsets; they're offered only when Settings >
# High Refresh Rates is on.
const HIGH_REFRESH_MIN := 200

# The Steam Frame's display goes to 144 Hz. The rates above that in the list
# are Quest 3 display rates; streamed to the Frame they only cost bitrate and
# PC work for frames that are never shown.
const FRAME_MAX_STREAM_FPS := 144

## The rate after `current` in the list. `max_rate` above 0 leaves out the
## rates beyond it.
static func next_fps_rate(current: int, high_refresh_rates: bool, max_rate: int = 0) -> int:
	var rates := STREAM_FPS_RATES.filter(func(rate):
		return (high_refresh_rates or rate < HIGH_REFRESH_MIN) and (max_rate <= 0 or rate <= max_rate))
	var idx := rates.find(current)
	if idx < 0:
		# A hidden rate, or one no longer offered: continue from the next lower one.
		idx = rates.size() - 1
		for i in rates.size():
			if rates[i] > current:
				idx = i - 1
				break
	return rates[(idx + 1) % rates.size()]

var _display_refresh_seq := 0

# Apply the headset rate only once cycling stops, so stepping from 90 to 72 Hz
# doesn't switch the display through every rate between (Rush_iam: 207 Hz
# glitched the headset on the way past).
func _schedule_display_refresh():
	_display_refresh_seq += 1
	var my_seq := _display_refresh_seq
	await main.get_tree().create_timer(0.8).timeout
	if _display_refresh_seq == my_seq and not main.is_streaming:
		apply_display_refresh_rate()

## Steam Frame: PT Fade as a slider, 0-100% in 5% steps.
func set_passthrough_fade(value: int, commit: bool) -> void:
	main.settings.passthrough_fade_pct = clampi(int(round(value / 5.0)) * 5, 0, 100)
	refresh_passthrough_fade_btn()
	if main.settings.passthrough_enabled and main.is_xr_active:
		# While dragging only the fade itself changes; letting go runs the
		# full passthrough set-up once (and logs it).
		if commit:
			apply_passthrough(true)
		else:
			main.passthrough_fade.apply(true, main.settings.passthrough_fade_pct)
	if commit:
		main.state_manager.save_state()

func refresh_passthrough_fade_btn() -> void:
	var btn: Button = main._ui_pt_fade_btn
	if btn == null:
		return
	var pct: int = main.settings.passthrough_fade_pct
	if btn.has_meta("slider"):
		main.ui_controller.set_slider_value(btn, pct, PassthroughFade.label(pct))
	else:
		main.ui_controller.update_option_btn(btn, PassthroughFade.label(pct))

func cycle_passthrough_fade():
	main.settings.passthrough_fade_pct = PassthroughFade.next_fade(main.settings.passthrough_fade_pct)
	if main.settings.passthrough_enabled:
		apply_passthrough(true)
	_save_setting(main._ui_pt_fade_btn, PassthroughFade.label(main.settings.passthrough_fade_pct))

func toggle_high_refresh_rates():
	main.settings.high_refresh_rates = not main.settings.high_refresh_rates
	_save_setting(main._ui_high_refresh_btn, "On" if main.settings.high_refresh_rates else "Off")

func cycle_resolution():
	if main.settings.host.is_polaris_host:
		var opts = main.compute_resolution_options()
		# opts[0] is always the current max (see compute_resolution_options()) - find by
		# value for everything else, but treat "currently at-or-past the max" as being
		# at slot 0 rather than falling through to opts.find()'s -1-not-found case,
		# which used to skip straight past MAX to the second entry on the very next
		# click after a codec/monitor change made the old selection unreachable.
		var idx = 0 if main.settings.host.resolution_scale_pct >= opts[0] else opts.find(main.settings.host.resolution_scale_pct)
		main.settings.host.resolution_scale_pct = opts[(maxi(idx, 0) + 1) % opts.size()]
	else:
		main.settings.host.resolution_idx = (main.settings.host.resolution_idx + 1) % main.resolutions.size()
	main.host_resolution = main.compute_requested_resolution()
	_save_setting(main._ui_res_btn, _resolution_btn_label())
	_schedule_stream_restart()

# The MAX ceiling (compute_resolution_options()[0]) depends on codec_preference
# and native_resolution, both of which can change without the user ever
# touching the resolution button itself (codec cycling, monitors being
# added/removed, the host's real desktop turning out a different size than
# assumed) - call this after any of those to keep the button's label honest
# instead of showing a stale percentage that no longer matches what's actually
# being requested.
func refresh_resolution_btn_label():
	if main._ui_res_btn:
		main.ui_controller.update_option_btn(main._ui_res_btn, _resolution_btn_label())

func _resolution_btn_label() -> String:
	if not main.settings.host.is_polaris_host:
		return main.resolution_labels[main.settings.host.resolution_idx]
	var opts = main.compute_resolution_options()
	# Show the actual resulting pixel dimensions, not just an abstract
	# percentage - a bare "%" doesn't tell you what you're really getting once
	# any of compute_requested_resolution()'s caps are in play (which is
	# exactly the case whenever this shows "MAX"). No parens/space between
	# the two - this has to fit the same 250px/26pt budget every other
	# option button uses (2026-08-18: this used to get its own wider button
	# + smaller font instead of fitting the shared size, which looked
	# inconsistent next to the rest of the row).
	var res = main.compute_requested_resolution()
	var dims = "%dx%d" % [res.x, res.y]
	if main.settings.host.resolution_scale_pct >= opts[0]:
		return "MAX %s" % dims
	return "%d%% %s" % [main.settings.host.resolution_scale_pct, dims]

# Best-effort, cached, one-time-per-host-selection probe for whether this host
# is a Polaris server running Nightfall's multi-monitor extension (in
# development, not part of stock Polaris), which reports its real, possibly
# multi-monitor desktop size via a display manifest no other GameStream-
# compatible host implements, vs everything else, e.g. Sunshine, which is
# client-driven - the
# client picks a resolution and the host adapts to match it, so there's
# nothing for it to report and main.settings.host.is_polaris_host correctly defaults to
# false (the old fixed-list picker) for it. Deliberately decoupled from the
# connect/launch flow itself: the original pre-launch probe (removed in
# 6a5c17d) shared an HTTP/session lock with establish_stream() and was a
# plausible contributor to a real connection hang. This fires once when a
# host is selected in the welcome-screen UI, well before any stream launch,
# and never blocks or gates anything - is_polaris_host just keeps whatever
# value it already had (loaded from host_state.cfg, or the false default for
# a never-seen host) until this resolves.
func detect_polaris_host(ip: String, host_id: int):
	if ip.is_empty() or host_id < 0:
		return
	main.stream_backend.fetch_display_manifest(host_id, func(manifest: Dictionary):
		var was_polaris = main.settings.host.is_polaris_host
		main.settings.host.is_polaris_host = manifest is Dictionary and not manifest.is_empty()
		if main.settings.host.is_polaris_host != was_polaris:
			refresh_resolution_btn_label()
			main.ui_controller.update_monitor_tab()
			main.state_manager.save_host_state()
	)

func cycle_bitrate():
	main.settings.host.bitrate_idx += 1
	# bitrate_labels[0] is "Auto" (idx -1), so the last real idx is size - 2.
	if main.settings.host.bitrate_idx + 1 >= main.bitrate_labels.size():
		main.settings.host.bitrate_idx = -1
	var label = main.bitrate_labels[main.settings.host.bitrate_idx + 1] if main.settings.host.bitrate_idx >= 0 else "Auto"
	_save_setting(main._ui_bitrate_btn, label)
	_schedule_stream_restart()

func cycle_double_h():
	main.settings.host.double_h = not main.settings.host.double_h
	main.state_manager.save_state()
	_schedule_stream_restart()

## Called on every change of session phase. Back to streaming with a restart
## owed (see _restart_again): ask for it now, after the stream has settled.
## Any phase other than streaming or restarting means the stream is gone, and
## the next connection reads the settings afresh anyway.
func on_session_phase(current: int) -> void:
	if current == SessionLifecycle.Phase.RESTARTING:
		return
	var owed := _restart_again and current == SessionLifecycle.Phase.STREAMING
	var end_host_session := _restart_again_ends_host_session
	_restart_again = false
	_restart_again_ends_host_session = false
	if not owed:
		return
	await main.get_tree().create_timer(0.3).timeout
	main._log("[RESTART] A stream setting changed during the last restart; restarting once more")
	_schedule_stream_restart(0.8, 0.0, end_host_session)

## Drops a stream restart that is still waiting out its pause (below), for
## when the setting that asked for it has been put back.
func cancel_stream_restart() -> void:
	_restart_again = false
	_restart_again_ends_host_session = false
	if _restart_pending:
		_restart_seq += 1
		_restart_pending = false

## A stream setting was changed while a restart was already under way: the
## stream coming up was started with the old value, so one more restart is
## owed once it is up. Before 6o the change was dropped (the button said
## Bitrate 120 while the stream ran at 60 until something else restarted it).
var _restart_again := false
var _restart_again_ends_host_session := false

func _schedule_stream_restart(debounce_seconds: float = 0.8, reconnect_delay: float = 0.0, end_host_session: bool = false):
	if main.current_host_id >= 0 and main.session_lifecycle.is_restarting():
		_restart_again = true
		_restart_again_ends_host_session = _restart_again_ends_host_session or end_host_session
		return
	if not main.is_streaming or main.current_host_id < 0:
		return
	_restart_pending = true
	_restart_seq += 1
	var my_seq = _restart_seq
	# XR timing changes are already committed; only user-cycled settings
	# need the debounce. GPU/decoder drain waits below remain unchanged.
	await main.get_tree().create_timer(debounce_seconds).timeout
	if _restart_seq != my_seq:
		return
	_restart_pending = false
	main._log("[RESTART] Restarting stream")
	main.session_lifecycle.request_restart()
	# The native renderer owns an OpenXR swapchain and a shared EGL context.
	# Stop it before changing the display rate or destroying decoder textures;
	# otherwise the runtime can recreate its display surface while either
	# renderer still references the old one, which crashes Quest's GLThread.
	if main.video_presentation:
		main.video_presentation.deactivate_native(false)
	# Stop the composition layer shader from referencing the current session's
	# texture BEFORE tearing the connection down. stop_play_stream() triggers
	# native decoder cleanup, which frees the underlying GPU texture/uniform
	# set synchronously (on the decode/cleanup thread) - if the shader
	# material still points at it when that happens, the OpenXR compositor's
	# own render pass (independent of our own binding code) can end up
	# rebuilding a uniform set against an already-freed texture on the render
	# thread, which crashes (not just renders wrong). Clearing first and
	# yielding a frame gives the renderer a chance to actually pick up the
	# null texture before the free happens, closing that race instead of
	# just narrowing it.
	main._clear_comp_yuv_textures()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	main.stream_backend.stop_play_stream()
	# Without this the host keeps the old session and the reconnect resumes it.
	# Vibepollo only creates or removes a virtual display when a session starts,
	# so a resumed session never shows the change.
	if end_host_session:
		var ended := {"done": false}
		main.stream_backend.stop_host_session(main.current_host_id, main.stream_manager.meteor_https_port(), func(reply) -> void:
			ended["done"] = true
			ended["reply"] = str(reply).left(60))
		var waited := 0.0
		while not ended["done"] and waited < 5.0:
			await main.get_tree().create_timer(0.1).timeout
			waited += 0.1
		main._log("[RESTART] Host session %s after %.1fs (%s)" % ["answered" if ended["done"] else "did not answer", waited, str(ended.get("reply", ""))])
	await main.get_tree().create_timer(0.5 + reconnect_delay).timeout
	# start_stream() is the single owner of refresh application at a connection
	# boundary. It awaits the Quest surface transition before resizing Godot
	# viewports or creating decoder/native-renderer resources.
	await main.stream_manager.start_stream(main.current_host_id, main._selected_app_id)

func hide_pc_cursor():
	if main.xr_interaction:
		main.xr_interaction.park_host_cursor()

func set_glow_strength(value: int, commit: bool):
	main.settings.ambient_strength = clampi(value, 0, 100)
	main.ui_controller.set_slider_value(main._ui_glow_strength_btn, main.settings.ambient_strength)
	if main.settings.ambient_mode > 0:
		main.comp.apply_ambient_settings()
	if commit:
		main.state_manager.save_state()

func set_glow_size(value: int, commit: bool):
	main.settings.ambient_size = clampi(value, 0, 100)
	main.ui_controller.set_slider_value(main._ui_glow_size_btn, main.settings.ambient_size)
	if main.settings.ambient_mode > 0:
		main.comp.apply_ambient_settings()
		main.comp.refresh_frame_curve()
	if commit:
		main.state_manager.save_state()

func recenter_view():
	main.recenter_view()

const HEAD_LOCK_LABELS := ["Off", "Level", "Tilt"]
const HAPTICS_LABELS := ["Off", "Clicks", "Clicks + Hover"]

# Menu button: Off -> Level -> Tilt -> Off.
func toggle_head_lock():
	set_head_lock((main.settings.head_lock + 1) % 3)

# Button action and voice: on (last used style) / off.
func switch_head_lock():
	set_head_lock(0 if main.settings.head_lock > 0 else main.settings.head_lock_last_on)

func set_head_lock(mode: int):
	mode = clampi(mode, 0, 2)
	main.settings.head_lock = mode
	if mode > 0:
		main.settings.head_lock_last_on = mode
		main.capture_head_lock()
	_save_setting(main._ui_head_lock_btn, HEAD_LOCK_LABELS[mode])
	var msg := "Head Lock off: the screen stays where it is."
	if mode == 1:
		msg = "Head Lock on: the screen follows your view and stays upright."
	elif mode == 2:
		msg = "Head Lock on (Tilt): the screen follows your view and tilts with your head."
	main.comp.show_notice(msg, 2.5)

func show_voice_commands():
	main.ui_controller.on_voice_commands_pressed()

func toggle_voice_prefix():
	main.settings.voice_require_prefix = not main.settings.voice_require_prefix
	_save_setting(main._ui_voice_prefix_btn, "On" if main.settings.voice_require_prefix else "Off")
	if main.ui_controller.has_method("refresh_voice_commands"):
		main.ui_controller.refresh_voice_commands()

## Advanced Settings > Voice Commands > Commands. Off: voice typing only types.
func toggle_voice_commands():
	main.settings.voice_commands = not main.settings.voice_commands
	_save_setting(main._ui_voice_commands_btn, "On" if main.settings.voice_commands else "Off")
	if main.ui_controller.has_method("refresh_voice_commands"):
		main.ui_controller.refresh_voice_commands()

## Advanced Settings > Logging. The launcher reads the saved choice when Nightfall starts and
## either writes the run's log or doesn't, so a change shows next start.
const LOGGING_STARTS := "Logging starts the next time Nightfall starts. Restart Nightfall to log this session's problem."
const LOGGING_STOPS := "Logging stops the next time Nightfall starts."

## What to say when Logging is switched: nothing when the choice is what this
## run is already doing. The launcher decides at start whether a run is
## logged, so the switch can't take effect before the next start, and the
## tooltip alone didn't get that across (2026-11-18: a test run went
## unlogged).
static func logging_notice(wanted: bool, this_run_logs: bool) -> String:
	if wanted == this_run_logs:
		return ""
	return LOGGING_STARTS if wanted else LOGGING_STOPS

func toggle_logging():
	main.settings.frame_logging = not main.settings.frame_logging
	_save_setting(main._ui_logging_btn, "On" if main.settings.frame_logging else "Off")
	var notice := logging_notice(main.settings.frame_logging, main._logging)
	if not notice.is_empty() and main.comp:
		main.comp.show_notice(Localization.t(notice), 6.0)

func toggle_voice_confirm():
	main.settings.voice_confirm = not main.settings.voice_confirm
	_save_setting(main._ui_voice_confirm_btn, "On" if main.settings.voice_confirm else "Off")

# Which speech model voice typing uses. Switching loads the other one, which
# takes a second or two; a model that isn't installed is skipped with a notice.
func cycle_voice_model():
	var wanted: int = (main.settings.voice_model + 1) % VoiceTyping.MODEL_FILES.size()
	if not VoiceTyping.size_installed(wanted):
		main._log("[VOICE] Speech Model %s asked for, but %s isn't there" % [VoiceTyping.MODEL_LABELS[wanted], VoiceTyping.model_path(wanted)])
		if main.comp:
			main.comp.show_notice(Localization.t("The %s speech model isn't installed. Run install.sh again to download it.") % VoiceTyping.MODEL_LABELS[wanted], 4.0)
		return
	if main.voice_typing and main.voice_typing.is_busy():
		if main.comp:
			main.comp.show_notice("Voice typing is busy. Try again in a moment.", 2.5)
		return
	main.settings.voice_model = wanted
	main._log("[VOICE] Speech Model set to %s" % VoiceTyping.MODEL_LABELS[wanted])
	_save_setting(main._ui_voice_model_btn, VoiceTyping.MODEL_LABELS[wanted])
	if main.voice_typing:
		main.voice_typing.reload_model()

func toggle_keep_room_position():
	main.settings.keep_room_position = not main.settings.keep_room_position
	_save_setting(main._ui_keep_room_btn, "Same Spot" if main.settings.keep_room_position else "In Front")

# The Start Distance slider: its 20 steps are a quarter of a metre each, from
# 1 m to 6 m.
static func start_distance_from_slider(value: int) -> float:
	return AppSettings.SCREEN_START_DISTANCE_MIN + clampi(value, 0, 100) / 5.0 * 0.25

static func start_distance_to_slider(metres: float) -> int:
	return clampi(int(round((metres - AppSettings.SCREEN_START_DISTANCE_MIN) / 0.25)) * 5, 0, 100)

func set_screen_start_distance(value: int, commit: bool) -> void:
	main.settings.screen_start_distance = start_distance_from_slider(value)
	refresh_start_distance_btn()
	if commit:
		main.move_screens_to_distance(main.settings.screen_start_distance)
		main.state_manager.save_state()

# Advanced > Screen Size (Steam Frame): the main screen's width from the
# menu, as a share of how far away it is, so the slider means the same at any
# distance. It is also the way back for a screen whose corners are out of
# reach. Slider 0 to 100 covers SCREEN_SIZE_MIN_PER_METRE to VRScreen's limit.
const SCREEN_SIZE_MIN_PER_METRE := 0.3

static func screen_width_from_slider(value: int, distance: float) -> float:
	return distance * lerpf(SCREEN_SIZE_MIN_PER_METRE, VRScreen.MAX_WIDTH_PER_METRE, clampi(value, 0, 100) / 100.0)

static func screen_width_to_slider(width: float, distance: float) -> int:
	var share: float = inverse_lerp(SCREEN_SIZE_MIN_PER_METRE, VRScreen.MAX_WIDTH_PER_METRE, width / maxf(distance, 0.01))
	return clampi(roundi(share * 20.0) * 5, 0, 100)

func _screen_view_distance() -> float:
	if main.primary_screen == null or main.xr_camera == null:
		return AppSettings.SCREEN_START_DISTANCE_DEFAULT
	return maxf(main.primary_screen.global_position.distance_to(main.xr_camera.global_position), 0.5)

func set_screen_size(value: int, commit: bool) -> void:
	var s = main.primary_screen
	if s == null or s.mesh_size.y <= 0.0:
		return
	s.set_width(screen_width_from_slider(value, _screen_view_distance()), s.mesh_size.x / s.mesh_size.y)
	if main.comp and main.comp.available:
		main.comp.update_layer_size()
	refresh_screen_size_btn()
	if commit:
		reflow_grid_screens()
		main.state_manager.save_state()
		main._log("[SCREEN] size set from the menu: %.1f m wide" % s.mesh_size.x)

func refresh_screen_size_btn() -> void:
	var s = main.primary_screen
	if s == null or main._ui_screen_size_btn == null:
		return
	main.ui_controller.set_slider_value(main._ui_screen_size_btn, screen_width_to_slider(s.mesh_size.x, _screen_view_distance()), "%.1f m" % s.mesh_size.x)

func refresh_start_distance_btn() -> void:
	var metres: float = main.settings.screen_start_distance
	main.ui_controller.set_slider_value(main._ui_start_distance_btn, start_distance_to_slider(metres), "%.2f m" % metres)

func toggle_keyboard_follows_screen():
	main.settings.keyboard_follows_screen = not main.settings.keyboard_follows_screen
	_save_setting(main._ui_kb_follow_btn, "On" if main.settings.keyboard_follows_screen else "Off")

func toggle_haptics():
	main.settings.haptics = (main.settings.haptics + 1) % 3
	_save_setting(main._ui_haptics_btn, HAPTICS_LABELS[main.settings.haptics])
	if main.settings.haptics > 0:
		main.buzz(main.xr_interaction._active_hand, 0.5, 0.05)

func cycle_mic_key_mode():
	main.settings.mic_key_mode = 1 - main.settings.mic_key_mode
	_save_setting(main._ui_mic_key_btn, "Windows" if main.settings.mic_key_mode == 1 else "Nightfall")

## Advanced Settings > Reset Settings: a way back to the
## defaults for someone who has changed too much to find it. Two presses within RESET_CONFIRM_SEC; then
## the defaults are written and Nightfall restarts, because the sure way to
## put every setting into force is the way a start does it.
const RESET_CONFIRM_SEC := 6.0
const RESET_ASK := "Press Reset Settings again to put everything in the menu back to Nightfall's defaults.\nYour paired PCs, button mappings and profiles stay. Nightfall will restart."
const RESET_DONE := "Settings are back to Nightfall's defaults. Nightfall is restarting."
var _reset_armed_until_msec := 0

func reset_settings():
	var now := Time.get_ticks_msec()
	if now >= _reset_armed_until_msec:
		_reset_armed_until_msec = now + int(RESET_CONFIRM_SEC * 1000.0)
		main.ui_controller.update_option_btn(main._ui_reset_settings_btn, "Press again")
		main._log("[STATE] Reset Settings pressed once: waiting for the second press")
		if main.comp and main.comp.has_method("show_notice"):
			main.comp.show_notice(RESET_ASK, RESET_CONFIRM_SEC)
		await main.get_tree().create_timer(RESET_CONFIRM_SEC).timeout
		if not main.state_manager.reset_done and Time.get_ticks_msec() >= _reset_armed_until_msec:
			main.ui_controller.update_option_btn(main._ui_reset_settings_btn, "")
		return
	_reset_armed_until_msec = 0
	main.state_manager.reset_to_defaults()
	main.ui_controller.update_option_btn(main._ui_reset_settings_btn, "Done")
	main._log("[STATE] Reset Settings: defaults written, per-PC settings removed; restarting")
	if main.comp and main.comp.has_method("show_notice"):
		main.comp.show_notice(RESET_DONE, 5.0)
	await main.get_tree().create_timer(3.0).timeout
	main.restart_app()

func save_panel_spots():
	main.settings.menu_spot = main.spot_from_node(main.ui_panel_3d)
	var kb = main.virtual_keyboard
	var saved_kb := false
	if kb and (kb.visible or kb._has_saved_offset):
		if not kb.visible:
			# Hidden: it sits where it was last shown relative to the screen.
			kb.anchor_to_saved_offset()
		main.settings.keyboard_spot = main.spot_from_node(kb)
		saved_kb = true
	main.state_manager.save_state()
	main.ui_controller.update_option_btn(main._ui_save_spots_btn, "Saved")
	main._log("[SPOTS] Saved default menu%s spot. %s" % [" and keyboard" if saved_kb else "", spots_text()])

## The saved default spots as they are kept: x, y, z in metres from the
## viewer and yaw, pitch in radians. Written at start-up and on saving, so a
## log shows where someone likes their menu and keyboard (how Nightfall's own
## default spots were read out, 2026-11-17).
func spots_text() -> String:
	return "menu %s, keyboard %s" % [spot_text(main.settings.menu_spot), spot_text(main.settings.keyboard_spot)]

static func spot_text(spot: Array) -> String:
	if spot.size() != 5:
		return "Nightfall's own"
	return "[%.3f, %.3f, %.3f, %.3f, %.3f]" % [float(spot[0]), float(spot[1]), float(spot[2]), float(spot[3]), float(spot[4])]

func reset_panel_spots():
	main.settings.menu_spot = []
	main.settings.keyboard_spot = []
	main.state_manager.save_state()
	main.ui_controller.update_option_btn(main._ui_reset_spots_btn, "Done")
	main.ui_controller.update_option_btn(main._ui_save_spots_btn, "")
	main._log("[SPOTS] Back to Nightfall's default spots")

func toggle_curved_filter():
	main.settings.frame_fast_filter = not main.settings.frame_fast_filter
	_save_setting(main._ui_curved_filter_btn, "Fast" if main.settings.frame_fast_filter else "Full")

# Steam Frame, experimental. Foveated rendering draws the part of each eye's
# picture away from where you look at lower resolution. SteamVR offers it to
# native apps (XR_FB_foveation with a Vulkan fragment density map, following
# the eyes through XR_META_foveation_eye_tracked), and the engine applies it
# when the viewport's shading rate follows the XR runtime. What it takes on
# the Frame, found in 5v to 6f and in Godot's issue tracker:
#  - An engine with Godot PR 124811 (issue 124141): stock 4.7 draws the scene
#    in subpasses that keep the Frame's driver out of its tiled mode, and
#    outside it the density map does nothing. The package's engine is built
#    with that fix (steam-frame/engine/).
#  - Tiled mode costs twice as much as direct drawing for this scene when
#    nothing is foveated (13 ms against 6 ms), so with Foveation Off the
#    launcher asks the driver for direct drawing (nightfall.sh).
#  - "Subsampled images" off (package/override.cfg): SteamVR can't show them
#    yet, the picture comes out warped.
#  - Changing the level on a live eye picture (swapchain) stops foveation
#    until restart (6f), with no error from SteamVR. The engine decides when
#    it creates the eye pictures whether to ask for the runtime's foveation
#    (only if the level is above 0 at that moment), and it creates them anew
#    whenever their size changes. So a change of level here also changes the
#    render size by a hair, which rebuilds the eye pictures with the new
#    level: the same thing that happens at start. Tried first in 6k.
# Measured on a 7.6 m curved screen with fade and glow: Low 7.4, Medium 7.2,
# High 7.2 ms; direct drawing without foveation 6.2 ms.
const FOVEATION_LABELS := ["Off", "Low", "Medium", "High"]
## Two render sizes a hair apart; switching between them rebuilds the eye pictures.
const FOVEATION_REBUILD_SCALES := [1.0, 0.999]
## The level in force now.
var foveation_active := 0
var _foveation_rebuilds := 0
var _foveation_logged := false

func cycle_foveation():
	main.settings.frame_foveation = (main.settings.frame_foveation + 1) % FOVEATION_LABELS.size()
	_save_setting(main._ui_foveation_btn, FOVEATION_LABELS[main.settings.frame_foveation])
	apply_foveation()

## Steam Frame, experimental: Picture > Flat Screen Detail. Full draws the
## flat screen's layer pictures at 4K; Stream Size at the stream's own size.
func flat_screen_detail_label() -> String:
	return "Stream Size" if main.settings.frame_layer_match_stream else "Full"

func toggle_flat_screen_detail():
	main.settings.frame_layer_match_stream = not main.settings.frame_layer_match_stream
	_save_setting(main._ui_flat_detail_btn, flat_screen_detail_label())
	apply_flat_screen_detail()

## Puts the saved choice in force: at start (before any layer exists), and
## whenever the option changes. Each screen is asked again for the size it
## last wanted, which the setter pins to 4K or lets through; update_bezel()
## then resizes the layer pictures, and the engine replaces their swapchains.
func apply_flat_screen_detail() -> void:
	if not main.device_is_steam_frame:
		return
	VRScreen.sf_match_stream = main.settings.frame_layer_match_stream
	for s in main.screens:
		s.comp_base_size = s.comp_base_requested
	if main.comp and main.comp.available:
		main.comp.update_bezel()
	var primary: VRScreen = main.primary_screen
	main._log("[PICTURE] flat screen detail %s (layer pictures %s)" % [flat_screen_detail_label().to_lower(),
		str(primary.comp_viewport.size) if primary and primary.comp_viewport else "not made yet"])

## Puts the saved level in force: at start, and whenever the option changes.
func apply_foveation() -> void:
	if not (main.device_is_steam_frame and main.is_xr_active):
		return
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr == null:
		return
	var level: int = main.settings.frame_foveation
	if level > 0 and not xr.is_foveation_supported():
		main._log("[PICTURE] foveation %s asked for, but the runtime doesn't offer it" % FOVEATION_LABELS[level].to_lower())
		level = 0
	if level == foveation_active:
		if level == 0 and not _foveation_logged:
			main._log("[PICTURE] foveation off")
		_foveation_logged = true
		return
	_foveation_logged = true
	foveation_active = level
	set_driver_draw_mode(level > 0)
	xr.foveation_dynamic = false
	xr.foveation_level = level
	main.get_viewport().vrs_mode = Viewport.VRS_XR if level > 0 else Viewport.VRS_DISABLED
	# Rebuild the eye pictures so they are created for this level.
	_foveation_rebuilds += 1
	xr.render_target_size_multiplier = FOVEATION_REBUILD_SCALES[_foveation_rebuilds % FOVEATION_REBUILD_SCALES.size()]
	main._log("[PICTURE] foveation %s (subsampled images %s, eye pictures rebuilt %d times, render scale %.3f)" % [
		FOVEATION_LABELS[level].to_lower(), xr.foveation_with_subsampled_images, _foveation_rebuilds, xr.render_target_size_multiplier])

## The graphics driver (Mesa Turnip) draws tiled or direct. Foveation needs
## tiled; without foveation, tiled costs this scene twice the time. The
## launcher points the driver at a file it re-reads while running
## (TU_DEBUG_FILE, docs.mesa3d.org/drivers/freedreno.html) and writes it once
## from the saved setting; this rewrites it when the setting changes.
func set_driver_draw_mode(tiled: bool) -> void:
	var path := OS.get_environment("NIGHTFALL_TU_DEBUG_FILE")
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		main._log("[DRIVER] couldn't write %s" % path)
		return
	file.store_string("" if tiled else "sysmem")
	file.close()
	main._log("[DRIVER] %s" % ("left to choose (tiled, for foveation)" if tiled else "asked for direct drawing (sysmem)"))

func toggle_flat_screen_mode():
	main.settings.frame_flat_3d = not main.settings.frame_flat_3d
	_save_setting(main._ui_flat_mode_btn, "3D Scene" if main.settings.frame_flat_3d else "Layer")
	if main.comp and main.comp.in_use:
		main.comp.switch_to_comp_layer()

func toggle_icon_backdrop():
	main.settings.icon_backdrop = not main.settings.icon_backdrop
	_save_setting(main._ui_icon_backdrop_btn, "On" if main.settings.icon_backdrop else "Off")
	for screen in main.screens:
		main.screen_shortcuts.refresh_visuals(screen)

func toggle_pointer_ray():
	main.settings.show_pointer_ray = not main.settings.show_pointer_ray
	_save_setting(main._ui_pointer_ray_btn, "On" if main.settings.show_pointer_ray else "Off")

# Cursor Follow has three choices on the Steam Frame. "Capacitive Touch" is
# following plus sleep_when_put_down: a controller no finger is on lets go of
# the PC's cursor (ControllerTouch). Off and Standard never use the sensors.
func cursor_follow_label() -> String:
	if not main.settings.cursor_follow:
		return "Off"
	return "Capacitive Touch" if main.settings.sleep_when_put_down else "Standard"

# The menu button: Off -> Standard -> Capacitive Touch -> Off.
func cycle_cursor_follow():
	if not main.settings.cursor_follow:
		main.settings.cursor_follow = true
		main.settings.sleep_when_put_down = false
	elif not main.settings.sleep_when_put_down:
		main.settings.sleep_when_put_down = true
	else:
		main.settings.cursor_follow = false
	_cursor_follow_changed()

# The Buttons tab action: on and off, keeping the kind of following.
func toggle_cursor_follow():
	main.settings.cursor_follow = not main.settings.cursor_follow
	_cursor_follow_changed()

func _cursor_follow_changed() -> void:
	_save_setting(main._ui_cursor_follow_btn, cursor_follow_label())
	main._log("[CURSOR] follow %s (let go when put down: %s)" % [cursor_follow_label().to_lower(),
		"on" if main.settings.sleep_when_put_down else "off"])

const GAMEPAD_LAYOUT_LABELS := ["Standard", "Swapped", "Custom"]

func toggle_face_swap():
	main.settings.gamepad_layout = (main.settings.gamepad_layout + 1) % 3
	main.settings.gamepad_face_swap = main.settings.gamepad_layout == 1
	_save_setting(main._ui_face_swap_btn, GAMEPAD_LAYOUT_LABELS[main.settings.gamepad_layout])

func toggle_controller_models():
	main.settings.show_controller_models = not main.settings.show_controller_models
	_save_setting(main._ui_ctrl_models_btn, "On" if main.settings.show_controller_models else "Off")
	main.update_frame_controller_models()

func toggle_hand_tracking():
	# Steam Frame: no "UI Only" (hands for menus only) - it made the menu hard to click.
	var modes := [0, 1] if main.device_is_steam_frame else [0, 3, 1]
	var current: int = main.effective_tracking_mode()
	main.startup_hand_fallback.explicit_choice()
	main.settings.tracking_mode = modes[(modes.find(current) + 1) % modes.size()]
	main.state_manager.save_state()
	main.state_manager.sync_ui_to_settings()

func apply_screen_layout(new_layout: ScreenLayout):
	if main.get("browser_prototype") != null and main.browser_prototype.active and not main.is_streaming:
		main._log("[LAYOUT] Close browser screens before applying a PC monitor layout")
		return
	var err = new_layout.validate(new_layout.frame_size)
	if err != "":
		main._log("[LAYOUT] Refusing invalid layout: %s" % err)
		return
	var wanted_ids: Array = []
	for m in new_layout.enabled_monitors():
		wanted_ids.append(m.id)
	# The screen about to be replaced as primary (e.g. the welcome screen's
	# placeholder on the very first real connect) - used below to hand its exact
	# position off to whatever takes over as primary, instead of add_screen()
	# positioning the new one "next to" a screen that's about to disappear.
	var old_primary_being_replaced: VRScreen = main.primary_screen if (main.primary_screen and not wanted_ids.has(main.primary_screen.monitor_id)) else null
	var new_primary: VRScreen = null
	# add_screen() positions each new VRScreen relative to whichever screens
	# already exist, purely by insertion order (grows left/right of primary).
	# The manifest's monitor array order is the host's own RandR enumeration
	# order, not spatial order (confirmed: a 4-monitor grid capture came back
	# as [HDMI-0, DP-0, DP-2, DP-4], not left-to-right) - inserting in that
	# raw order scattered screens in VR space in an order that didn't match
	# their real desktop_rect positions, looking "scrambled". Sort by real
	# x-position first so insertion order matches physical left-to-right order.
	var ordered_monitors := new_layout.enabled_monitors()
	ordered_monitors.sort_custom(func(a, b): return a.desktop_rect.position.x < b.desktop_rect.position.x)
	# Free the slots of screens this layout drops before adding any, so a layout with as many
	# screens as MAX_SCREENS allows fits (e.g. one physical + three virtual to four virtual).
	for s in main.screens.duplicate():
		if s != main.primary_screen and not wanted_ids.has(s.monitor_id) and not main.screen_sources.is_browser_screen(s):
			main.remove_screen(s.monitor_id)
	# The outgoing primary can only go once another screen is primary. When the new primary
	# already has a screen, hand over now so the old one's slot is free for the screens added below.
	if old_primary_being_replaced and not main.screen_sources.is_browser_screen(old_primary_being_replaced):
		var primary_spec = new_layout.get_primary()
		for s in main.screens:
			if primary_spec and s != old_primary_being_replaced and s.monitor_id == primary_spec.id:
				s.global_transform = old_primary_being_replaced.global_transform
				main.set_primary_screen(s)
				if main.get("screen_tab_strip") != null and s.comp_corner_viewport:
					main.screen_tab_strip.attach(s, s.comp_corner_viewport)
				apply_stereo()
				main.remove_screen(old_primary_being_replaced.monitor_id)
				old_primary_being_replaced = null
				break
	for m in ordered_monitors:
		var existing: VRScreen = null
		for s in main.screens:
			if s.monitor_id == m.id:
				existing = s
				break
		# A browser workspace already owns the other physical slots. Reuse
		# the primary welcome surface rather than allocating a fifth screen
		# temporarily or shifting every browser when the host manifest arrives.
		if existing == null and m.is_primary and main.primary_screen != null \
				and not wanted_ids.has(main.primary_screen.monitor_id):
			for candidate in main.screens:
				if main.screen_sources.is_browser_screen(candidate):
					existing = main.primary_screen
					existing.monitor_id = m.id
					break
		var s = existing if existing else main.add_screen(m.id, m.desktop_rect.position.x, m.is_primary)
		if s == null:
			continue
		s.apply_monitor(m, new_layout.frame_size)
		if m.is_primary:
			new_primary = s
	if old_primary_being_replaced and new_primary and new_primary != old_primary_being_replaced:
		new_primary.global_transform = old_primary_being_replaced.global_transform
	main.layout = new_layout
	# Reassign primary BEFORE removing unwanted screens below - remove_screen()
	# refuses to remove whatever is currently primary_screen (a real safety net
	# for normal add/remove-monitor flows), but on the very first real connect
	# the welcome screen's placeholder VRScreen *is* primary_screen, with a
	# monitor_id that's essentially never going to match the real manifest's
	# primary id. Removing in the old order left that placeholder permanently
	# stuck (un-removable, since it was still primary_screen at removal time)
	# with its own grab bar, while the real primary got added next to it
	# instead of replacing it - "screen appears in the wrong position, two
	# grab bars" was this, not a positioning bug in add_screen() itself.
	if new_primary and new_primary != main.primary_screen:
		main.set_primary_screen(new_primary)
		# Host layout changes retire the old primary and its controls atlas.
		# Carry the primary toolbar to the replacement before removing it.
		if main.get("screen_tab_strip") != null and new_primary.comp_corner_viewport:
			main.screen_tab_strip.attach(new_primary, new_primary.comp_corner_viewport)
		# Stereo/AI-3D (switch_to_stereo_comp_layer()) only ever activates
		# whatever was primary AT THE TIME it was called - it sets up that
		# screen's own comp_cylinder_left/right visibility, viewport update
		# mode, and stereo_mode shader param, none of which set_primary_screen()
		# above carries over to the new primary. On the very first real
		# connect (this branch always runs then: the welcome screen's
		# placeholder VRScreen is primary with a monitor_id that can't match
		# any real manifest id), that left the real primary silently stuck in
		# flat/non-stereo comp-layer mode even with SBS/AI-3D still toggled
		# on - looked correct on the welcome screen (where it WAS applied)
		# and broken the moment the stream's real manifest swapped primary in.
		apply_stereo()
	for s in main.screens.duplicate():
		if not wanted_ids.has(s.monitor_id) and not main.screen_sources.is_browser_screen(s):
			main.remove_screen(s.monitor_id)
	# resize_screen_to_aspect() now calls update_cylinder_params() itself
	# (2026-08-20) - no need to pair it here anymore.
	main.screen_manager.resize_screen_to_aspect(new_layout.frame_size.x, new_layout.frame_size.y)
	if main.comp and main.comp.in_use and main.is_streaming:
		main.comp.invalidate_yuv_cache()
		main.comp.bind_yuv_textures()
	main.ui_controller.update_monitor_tab()

# ---------------------------------------------------------------------------
# Monitors tab (grid-mode redesign): staged Monitors/Virtual counts + preset
# picker, committed together by Apply. Nothing below auto-restarts the stream
# or touches main.layout/screens until apply_staged_monitor_config() runs -
# per spec this needed "a lot more to consider" than the old per-toggle
# auto-restart behavior above. Grid/free screen placement here is purely
# client-side VR presentation (MonitorGrid) and never touches ScreenLayout/
# MonitorSpec beyond enabled/is_primary, which apply_screen_layout() (above,
# unmodified) already owns.
# ---------------------------------------------------------------------------

func _real_monitor_count() -> int:
	var count = 0
	for m in main.layout.monitors:
		if not m.hint.get("virtual", false) and m.capturable:
			count += 1
	return count

func browser_screen_count() -> int:
	var sources = main.get("screen_sources")
	if sources == null: return 0
	var count := 0
	for screen in main.screens:
		if sources.is_browser_screen(screen): count += 1
	return count

func monitor_screen_capacity() -> int:
	return maxi(0, main.MAX_SCREENS - browser_screen_count())

func staged_total() -> int:
	return main._staged_physical_count + main._staged_virtual_count + browser_screen_count()

func _clear_staged_preset_if_mismatched():
	if main._staged_preset_id == &"":
		return
	var p = MonitorPresets.find_preset(String(main._staged_preset_id))
	if p.is_empty() or p.get("screen_count", -1) != staged_total():
		main._staged_preset_id = &""

# Call whenever the Monitors tab is opened, so its dropdowns reflect what's
# actually live rather than whatever was last staged in a previous visit.
# (Nothing called this until Steam Frame build 7z, in upstream 0.9.0 either:
# the counts began at 0 in every app run, so with a virtual screen saved for
# the host, setting Virtual to 0 and pressing Apply looked like no change. The
# screen went from the headset, the host was never told, and the next stream
# asked for it again: a second screen at every reconnect, 2026-11-16.)
func sync_staged_from_current_layout():
	# An Apply is waiting for its new stream: the layout is still the old one,
	# and what is staged is what that stream was asked for.
	if main._pending_monitor_apply:
		return
	if not main.is_streaming:
		# Nothing is live. What counts is what the next stream will ask the
		# host for, which is what was saved.
		var saved: int = main.settings.host.virtual_display_count if main.settings.host.virtual_display_installed else 0
		main._staged_virtual_count = saved
		_last_applied_virtual_count = saved
		if main.settings.host.virtual_only and saved > 0:
			main._staged_physical_count = 0
		return
	var real_enabled = 0
	var virtual_enabled = 0
	for m in main.layout.monitors:
		if not m.enabled:
			continue
		if m.hint.get("virtual", false):
			virtual_enabled += 1
		else:
			real_enabled += 1
	# No physical monitor in the stream is a real state when virtual ones are.
	main._staged_physical_count = maxi(real_enabled, 1 if virtual_enabled == 0 else 0)
	main._staged_virtual_count = virtual_enabled
	# Left alone while the layout is empty, e.g. between a relaunch and its manifest.
	if real_enabled > 0:
		main.settings.host.virtual_only = false
	elif virtual_enabled > 0:
		main.settings.host.virtual_only = true
	# What the host reports is what exists, whatever this app run last applied.
	_last_applied_virtual_count = virtual_enabled
	main._staged_preset_id = &""

# Fewest physical monitors the stream may have: none when the host can make virtual ones
# (the stream then runs on virtual screens alone), else one.
func min_physical_count() -> int:
	var settings = main.get("settings")
	if settings == null:
		return 1
	return 0 if settings.host.virtual_display_installed and settings.host.virtual_display_max_count > 0 else 1

func stage_monitor_count(n: int):
	main._staged_physical_count = clampi(n, min_physical_count(), maxi(1, mini(_real_monitor_count(), monitor_screen_capacity())))
	# At least one screen has to remain.
	if main._staged_physical_count == 0 and main._staged_virtual_count == 0:
		main._staged_virtual_count = 1
	var low := 1 if main._staged_physical_count == 0 else 0
	main._staged_virtual_count = clampi(main._staged_virtual_count, low, maxi(low, monitor_screen_capacity() - main._staged_physical_count))
	_clear_staged_preset_if_mismatched()
	main._log("[LAYOUT] stage_monitor_count(%d): real_monitor_count=%d -> staged_physical=%d" % [n, _real_monitor_count(), main._staged_physical_count])

func stage_virtual_count(n: int):
	var low := 1 if main._staged_physical_count == 0 else 0
	main._staged_virtual_count = clampi(n, low, maxi(low, monitor_screen_capacity() - main._staged_physical_count))
	_clear_staged_preset_if_mismatched()

func select_monitor_preset(id: StringName):
	if MonitorPresets.find_preset(String(id)).is_empty():
		return
	main._staged_preset_id = id

# Builds the ScreenLayout implied by the current staged counts: the N
# leftmost real (non-virtual) monitors from the live manifest, plus M
# client-side-only virtual placeholders (hint.virtual=true, see
# stream_manager.gd::_compute_capture_outputs() for why those are excluded
# from the real outputs= request). Real monitors' frame_rect/desktop_rect are
# carried over untouched; only enabled/is_primary and the synthetic virtual
# entries are new.
func _build_staged_layout() -> ScreenLayout:
	var real_monitors: Array = []
	for m in main.layout.monitors:
		# Excludes capturable=false (connected-but-disabled host outputs) too, not just
		# virtual placeholders - otherwise the N-leftmost-by-x pick below can select a
		# monitor the host will always refuse, silently wasting a slot (the host drops it
		# from capture but this client still thinks it asked for N real monitors).
		if not m.hint.get("virtual", false) and m.capturable:
			real_monitors.append(m)
	main._log("[LAYOUT] _build_staged_layout: main.layout.monitors=%d real=%d staged_physical=%d staged_virtual=%d source=%s" % [main.layout.monitors.size(), real_monitors.size(), main._staged_physical_count, main._staged_virtual_count, str(main.layout.source)])
	if real_monitors.is_empty():
		return null
	real_monitors.sort_custom(func(a, b): return a.desktop_rect.position.x < b.desktop_rect.position.x)
	var phys_floor := 0 if main._staged_virtual_count > 0 and min_physical_count() == 0 else 1
	var phys_count = clampi(main._staged_physical_count, phys_floor, maxi(1, mini(real_monitors.size(), monitor_screen_capacity())))
	var picked: Array = real_monitors.slice(0, phys_count)

	var new_layout := ScreenLayout.new()
	new_layout.version = main.layout.version
	new_layout.source = main.layout.source
	new_layout.frame_size = main.layout.frame_size
	new_layout.desktop_bounds = main.layout.desktop_bounds
	new_layout.any_selection = main.layout.any_selection

	for m in real_monitors:
		var nm := ScreenLayout.MonitorSpec.new()
		nm.id = m.id
		nm.label = m.label
		nm.frame_rect = m.frame_rect
		nm.desktop_rect = m.desktop_rect
		nm.hint = {}
		nm.enabled = picked.has(m)
		nm.is_primary = false
		new_layout.monitors.append(nm)

	var vcount = clampi(main._staged_virtual_count, 0, maxi(0, monitor_screen_capacity() - phys_count))
	_append_virtual_placeholders(new_layout, vcount)

	var enabled := new_layout.enabled_monitors()
	if enabled.is_empty():
		return null
	enabled[0].is_primary = true
	return new_layout

# Client-side-only synthetic monitors (no real RandR output behind them - see
# stream_manager.gd::_compute_capture_outputs(), which skips hint.virtual
# entries when building the real outputs= request). Placed just past the real
# desktop's right edge so they don't overlap any real monitor's desktop_rect.
func _append_virtual_placeholders(layout: ScreenLayout, vcount: int):
	var max_x = layout.desktop_bounds.position.x + layout.desktop_bounds.size.x
	for i in range(vcount):
		var vm := ScreenLayout.MonitorSpec.new()
		vm.id = StringName("virtual_%d" % i)
		vm.label = ""
		vm.enabled = true
		vm.is_primary = false
		vm.frame_rect = Rect2i(0, 0, layout.frame_size.x, layout.frame_size.y)
		vm.desktop_rect = Rect2i(max_x + i * layout.frame_size.x, layout.desktop_bounds.position.y, layout.frame_size.x, layout.frame_size.y)
		vm.hint = {"virtual": true}
		layout.monitors.append(vm)

# Primary first (never repositioned by preset apply - it's the free-mode
# anchor everything else is placed relative to), then the rest sorted by real
# desktop x position - deterministic and matches apply_screen_layout()'s own
# insertion order in the common case.
func _screens_in_ordinal_order() -> Array:
	if not main.primary_screen:
		return []
	var rest: Array = []
	for s in main.screens:
		if s != main.primary_screen:
			rest.append(s)
	rest.sort_custom(func(a, b):
		var ax = a.monitor.desktop_rect.position.x if a.monitor else a.global_position.x
		var bx = b.monitor.desktop_rect.position.x if b.monitor else b.global_position.x
		return ax < bx
	)
	var ordered: Array = [main.primary_screen]
	ordered.append_array(rest)
	return ordered

func _place_secondaries_default(secondaries: Array):
	var primary: VRScreen = main.primary_screen
	if primary.grid_pos == Vector2i(-1, -1):
		primary.grid_pos = Vector2i(3, 1)
	primary.grid_mode = true
	var occupied: Array = [primary.grid_pos]
	for s in secondaries:
		var cand = main.nearest_free_grid_cell(s.global_position, occupied, primary.grid_pos.x, primary.grid_pos.y)
		if cand.x < 0:
			continue
		occupied.append(cand)
		s.grid_mode = true
		s.grid_pos = cand
		s.global_transform = main.grid_cell_transform(cand.x, cand.y, primary.grid_pos.x, primary.grid_pos.y)

# Applies the selected preset's per-screen grid/free position onto the
# VRScreens apply_screen_layout() just created/kept, in ordinal order. Falls
# back to a sane grid default (primary keeps its grid_pos or [3,1], others
# auto-placed via nearest_free_cell) when no preset is staged or its
# screen_count no longer matches what's actually enabled.
func _apply_preset_positions_to_screens():
	var ordered: Array = _screens_in_ordinal_order()
	if ordered.is_empty():
		return
	var primary: VRScreen = ordered[0]
	var preset := {}
	if main._staged_preset_id != &"":
		var p = MonitorPresets.find_preset(String(main._staged_preset_id))
		if not p.is_empty() and p.get("screen_count", -1) == ordered.size():
			preset = p
	if preset.is_empty():
		_place_secondaries_default(ordered.slice(1))
	else:
		var screens_data: Array = preset.get("screens", [])
		for i in range(ordered.size()):
			var s: VRScreen = ordered[i]
			var data: Dictionary = screens_data[i]
			var is_grid: bool = data.get("grid_mode", true)
			s.grid_mode = is_grid
			if is_grid:
				var gp: Array = data.get("grid_pos", [3, 1])
				s.grid_pos = Vector2i(gp[0], gp[1])
			if s == primary:
				continue
			if is_grid:
				s.global_transform = main.grid_cell_transform(s.grid_pos.x, s.grid_pos.y, primary.grid_pos.x, primary.grid_pos.y)
			else:
				var fp: Array = data.get("free_pos", [s.position.x, s.position.y, s.position.z])
				var fr: Array = data.get("free_rot", [s.rotation.x, s.rotation.y, s.rotation.z])
				s.position = Vector3(fp[0], fp[1], fp[2])
				s.rotation = Vector3(fr[0], fr[1], fr[2])
	# Primary itself is deliberately never repositioned above (it's the free-
	# mode anchor everything else is placed relative to) - but Godot's
	# CollisionObject3D only pushes a node's transform to PhysicsServer3D on
	# NOTIFICATION_TRANSFORM_CHANGED, which a node that never actually moves
	# never receives. Confirmed live: right after adding a second monitor,
	# primary's own pointer/raycast interaction went laggy/unusable (its
	# Area3D's physics-side transform was stale relative to whatever the new
	# secondary's Area3D just did to the broadphase) until manually grabbing
	# and moving primary even slightly, which fixed it - because a real grab
	# always writes global_position, firing the notification this never
	# otherwise gets. Reassigning to its own current transform is a no-op
	# geometrically but still fires that notification, without needing an
	# actual (visible) move.
	primary.global_transform = primary.global_transform
	if main.comp.available:
		main.comp.update_cylinder_params()

# Re-derives world transform for every grid-mode secondary from its existing
# grid_pos. Needed whenever curvature changes: a grid cell's world position
# depends on curvature/radius (_grid_screen_transforms() measures gaps against
# the curved edge, see main.gd), but grid_pos itself is just coordinates and
# doesn't change with curvature - so without this, a screen placed under the
# old curvature keeps its old (now wrong) position/rotation until something
# else, like a drag, happens to recompute it.
func reflow_grid_screens():
	var primary: VRScreen = main.primary_screen
	if not primary or primary.grid_pos == Vector2i(-1, -1):
		return
	for s in main.screens:
		if s == primary or not s.grid_mode or s.grid_pos == Vector2i(-1, -1):
			continue
		s.global_transform = main.grid_cell_transform(s.grid_pos.x, s.grid_pos.y, primary.grid_pos.x, primary.grid_pos.y)

# The only place that actually calls apply_screen_layout() from the new
# Monitors tab. Cycling the Monitors/Virtual dropdowns or picking a preset
# (Row 1/Row 2) never restarts anything on their own - clarification #9 asked
# for that ("a lot more to consider") - but Apply is the explicit commit
# point, and if the real (server-facing) monitor selection actually changed,
# the host needs a fresh outputs= request to capture the new set.
#
# A monitor's frame_rect (its position within the CAPTURED/composited video
# frame) is only meaningful once it's actually part of a live capture - one
# we haven't asked the host to capture yet reports frame_rect (0,0) in the
# manifest (there's no video content for it at all), which
# apply_screen_layout()'s validate() correctly refuses. So when the real
# selection changes, this does NOT try to build/position VR screens against
# that stale/invalid geometry up front - it only updates which real monitors
# are enabled/primary (what the next launch's outputs= will request) and
# restarts; the restart's own fresh manifest response
# (stream_manager.gd::_on_v2_launch_response) re-derives and applies a fully
# valid ScreenLayout once the host actually replies with real geometry for the
# new set, and finish_pending_monitor_apply() (called from there) finishes the
# job - adding virtual placeholders (never reported by any real manifest) and
# positioning every screen per the staged preset.
## The layout to show when an Apply restarts nothing and the host can make
## real virtual displays: `target` without the client's stand-ins for virtual
## monitors (a real one arrives with the next session's manifest; a stand-in
## would show a copy of the whole frame meanwhile).
##
## `keep_live_virtual`: the number of virtual monitors is unchanged, so the
## host's own virtual displays already in the stream (`live`) stay. This Apply
## then only changes where the screens sit (a layout picture). Before 6q they
## were stripped as well: picking a layout made every virtual screen vanish,
## and only changing their number brought them back (seen on the Frame, 6p).
static func layout_without_placeholders(target: ScreenLayout, live: ScreenLayout, keep_live_virtual: bool) -> ScreenLayout:
	var result := ScreenLayout.new()
	result.version = target.version
	result.source = target.source
	result.frame_size = target.frame_size
	result.desktop_bounds = target.desktop_bounds
	result.any_selection = target.any_selection
	for m in target.monitors:
		if not m.hint.get("virtual", false):
			result.monitors.append(m)
	if keep_live_virtual and live != null:
		for m in live.monitors:
			if m.hint.get("virtual", false) and m.enabled:
				result.monitors.append(m)
	return result

## Whether Apply has a change of virtual screens to tell the host about:
## the staged count differs from the one last applied, or from the one saved
## for the next stream (which is what that stream asks the host for, whatever
## this app run has applied or the host has made).
static func virtual_count_changed(staged: int, last_applied: int, saved: int, vdd_available: bool) -> bool:
	return staged != last_applied or (vdd_available and staged != saved)

func apply_staged_monitor_config():
	var target = _build_staged_layout()
	if target == null:
		main._log("[LAYOUT] apply_staged_monitor_config: _build_staged_layout() returned null (no real monitors known yet)")
		return
	var old_real_ids: Array = []
	for m in main.layout.enabled_monitors():
		if not m.hint.get("virtual", false):
			old_real_ids.append(m.id)
	var new_real_ids: Array = []
	for m in target.enabled_monitors():
		if not m.hint.get("virtual", false):
			new_real_ids.append(m.id)
	var real_changed = old_real_ids != new_real_ids
	main._log("[LAYOUT] apply_staged_monitor_config: staged=%d+%dvirtual old_real=%s new_real=%s real_changed=%s streaming=%s" % [main._staged_physical_count, main._staged_virtual_count, str(old_real_ids), str(new_real_ids), str(real_changed), str(main.is_streaming)])

	var vdd_available = main.settings.host.virtual_display_installed and main.stream_manager != null
	var virtual_changed = virtual_count_changed(main._staged_virtual_count, _last_applied_virtual_count,
		main.settings.host.virtual_display_count, vdd_available)
	main.settings.host.virtual_only = main._staged_physical_count == 0 and main._staged_virtual_count > 0
	# A virtual-display change restarts the stream itself (see the Meteor reply below): the host
	# session has to end before a new virtual display can appear, and a plain restart resumes it.
	var restart_via_meteor = virtual_changed and vdd_available and main.is_streaming

	if real_changed and main.is_streaming:
		var new_primary = target.get_primary()
		var new_primary_id = new_primary.id if new_primary else &""
		for m in main.layout.monitors:
			if m.hint.get("virtual", false):
				continue
			m.enabled = new_real_ids.has(m.id)
			m.is_primary = (m.id == new_primary_id)
		# Narrowing to exactly one real monitor makes the resulting capture
		# size exactly knowable right now, client-side: that monitor's own
		# frame_rect (already reported in the last manifest) doesn't change
		# size when captured alone - only its position within the composite
		# does (ScreenLayout always repositions a lone monitor to the
		# origin). Update native_resolution before scheduling the restart so
		# the very first launch of the new session already requests the
		# right size, instead of restarting at the OLD (still-cached)
		# composite size and relying on _process()'s "doesn't match cached
		# size" mismatch-retry to correct it via a SECOND restart -
		# confirmed via logcat to cost a real ~10s stall decoding an
		# oversized stream before self-correcting. General N>1 targets are
		# deliberately left to that same mismatch-retry (see its comment in
		# main.gd) - an arbitrary multi-monitor composite's exact frame_size
		# depends on host-side gap-filling this client can't predict.
		# With virtual screens in the stream the frame holds more than this monitor, so only a
		# lone physical monitor makes the size knowable here.
		if new_real_ids.size() == 1 and main._staged_virtual_count == 0:
			for m in main.layout.monitors:
				if m.id == new_real_ids[0]:
					# A monitor that was switched off has an empty frame_rect (that once asked the
					# host for a 320x180 stream); its desktop_rect still holds its real size.
					var lone_size: Vector2i = m.frame_rect.size if m.frame_rect.size.x > 0 and m.frame_rect.size.y > 0 else m.desktop_rect.size
					if lone_size.x > 0 and lone_size.y > 0:
						main.settings.host.native_resolution = lone_size
					break
		main._pending_monitor_apply = true
		if not restart_via_meteor:
			_schedule_stream_restart()

	# A change that restarts through Meteor leaves the screens alone until the
	# new session's manifest arrives. Removing virtual screens now would leave a
	# lone primary on the old multi-screen frame until then.
	if not (real_changed and main.is_streaming) and not restart_via_meteor:
		if vdd_available and main._staged_virtual_count > 0:
			# Don't render placeholder — real virtual monitor arrives after stream restart.
			# Strip synthetic virtual entries before applying so the user doesn't see a
			# duplicate-frame screen in the interim.
			apply_screen_layout(layout_without_placeholders(target, main.layout, not virtual_changed))
		else:
			apply_screen_layout(target)
		_apply_preset_positions_to_screens()
	if virtual_changed and vdd_available:
		var vcount = main._staged_virtual_count
		var previous_count = _last_applied_virtual_count
		_last_applied_virtual_count = vcount
		main.settings.host.virtual_display_count = vcount
		main.settings.host.virtual_only = main._staged_physical_count == 0 and vcount > 0
		var need_restart = main.is_streaming
		main.stream_manager.post_meteor_virtual(vcount, func(ok: bool, reply: Dictionary) -> void:
			if not ok:
				main._log("[METEOR] POST /meteor/virtual failed")
				# Not applied: the same Apply has to try again rather than look like no change.
				if _last_applied_virtual_count == vcount:
					_last_applied_virtual_count = previous_count
				# The restart held back above still has to happen for the monitors that changed.
				if real_changed and need_restart:
					_schedule_stream_restart()
			elif need_restart:
				# The host session has to end for Vibepollo to apply the change on the
				# next launch; the delay covers its teardown (or a full host restart
				# when Meteor fell back to that).
				var restarting: bool = reply.get("host_restarting", false)
				var delay := 15.0 if restarting else 4.0
				main._log("[METEOR] Virtual display applied (host_restarting=%s), relaunching in %.1fs" % [str(restarting), delay])
				main._pending_monitor_apply = true
				_schedule_stream_restart(0.8, delay, true)
		)

	main.host_resolution = main.compute_requested_resolution()
	main.state_manager.save_host_state()
	if main._ui_status_label:
		if (real_changed or (virtual_changed and vdd_available)) and main.is_streaming:
			main.ui_controller.set_status("Applying - restarting stream for new monitor selection...")
		elif main._staged_virtual_count > 0 and vdd_available:
			main.ui_controller.set_status("Virtual monitor(s) will appear on next stream connect")
		else:
			main.ui_controller.set_status("Monitor layout applied")

# Called once by stream_manager.gd's launch-response handler right after it
# applies the fresh post-restart manifest (real frame_rect data now valid for
# the newly-requested set). Re-adds any staged virtual placeholders (the
# server-sourced manifest only ever describes real outputs, so
# apply_screen_layout() would otherwise have just dropped them) and applies
# the staged preset's grid/free positions now that every screen actually exists.
func finish_pending_monitor_apply():
	if main._staged_virtual_count > 0 and not main.settings.host.virtual_display_installed:
		# VDD not available: Vibepollo won't create a real virtual monitor, so
		# add a placeholder so the layout doesn't look empty.
		var with_virtual := ScreenLayout.new()
		with_virtual.version = main.layout.version
		with_virtual.source = main.layout.source
		with_virtual.frame_size = main.layout.frame_size
		with_virtual.desktop_bounds = main.layout.desktop_bounds
		with_virtual.any_selection = main.layout.any_selection
		with_virtual.monitors = main.layout.monitors.duplicate()
		_append_virtual_placeholders(with_virtual, main._staged_virtual_count)
		apply_screen_layout(with_virtual)
	# When VDD is available, Vibepollo creates a real virtual display that
	# appears in the manifest as an ordinary monitor — no placeholder needed.
	_apply_preset_positions_to_screens()

func save_current_as_preset():
	var ordered = _screens_in_ordinal_order()
	if ordered.is_empty():
		return
	var screens_data: Array = []
	for s in ordered:
		var gp = s.grid_pos if s.grid_pos != Vector2i(-1, -1) else Vector2i(3, 1)
		screens_data.append({
			"is_primary": s == main.primary_screen,
			"grid_mode": s.grid_mode,
			"grid_pos": [gp.x, gp.y],
			"free_pos": [s.position.x, s.position.y, s.position.z],
			"free_rot": [s.rotation.x, s.rotation.y, s.rotation.z],
		})
	# A grid arrangement that is already among the pictures is selected rather
	# than saved again (Save with the screens side by side used to add a
	# second, identical picture).
	var existing := MonitorPresets.find_same_grid_layout(screens_data)
	if existing != "":
		main._staged_preset_id = StringName(existing)
		if main._ui_status_label:
			main.ui_controller.set_status("This layout is already saved")
		main.ui_controller.update_monitor_tab()
		return
	var customs = MonitorPresets.load_custom_presets()
	var id = MonitorPresets.next_custom_id(customs)
	customs.append({
		"version": 1,
		"id": id,
		"built_in": false,
		"screen_count": screens_data.size(),
		"screens": screens_data,
	})
	MonitorPresets.save_custom_presets(customs)
	main._staged_preset_id = StringName(id)
	if main._ui_status_label:
		main.ui_controller.set_status("Preset saved")

func remove_selected_preset():
	if main._staged_preset_id == &"":
		return
	var p = MonitorPresets.find_preset(String(main._staged_preset_id))
	if p.is_empty() or p.get("built_in", false):
		return
	MonitorPresets.remove_custom_preset(String(main._staged_preset_id))
	main._staged_preset_id = &""
	if main._ui_status_label:
		main.ui_controller.set_status("Preset removed")

func toggle_grid_mode():
	main.settings.grid_mode_enabled = not main.settings.grid_mode_enabled
	main.state_manager.save_state()
	if main._ui_grid_mode_btn:
		main.ui_controller.update_option_btn(main._ui_grid_mode_btn, "On" if main.settings.grid_mode_enabled else "Off")
