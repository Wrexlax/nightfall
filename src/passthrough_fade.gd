class_name PassthroughFade
extends RefCounted

# Darkens passthrough so the screen and menus stand out against a bright room
# (Rush_iam: white wall). Godot's passthrough has no opacity control, so a
# compositor sphere of translucent black sits between the room and every
# other layer. Composition layers reach the compositor whether or not Godot
# submits its projection layer, so this works in projectionless mode too.

const FADE_VALUES: Array = [0, 25, 50, 75, 90]
# The Meta vendors plugin submits passthrough itself as a layer at -100, so
# the fade must sit above it, yet below the projection and ambient layers (0).
const SORT_ORDER := -50
# The C++ setter stores a float but checks against double PI/2. Exactly
# 90 degrees rounds above that bound and can leave the default 45-degree cap.
const VERTICAL_HALF_ANGLE := PI * 0.5 - 0.000001

var layer: Node3D = null
var _viewport: SubViewport = null
var _fill: ColorRect = null
var _layer_unsupported := false

static func next_fade(current: int) -> int:
	var idx := FADE_VALUES.find(current)
	return FADE_VALUES[(idx + 1) % FADE_VALUES.size()]

## What a saved fade may be: the cycle button's values, or any 5% step (the
## Steam Frame's slider).
static func valid(fade_pct: int) -> bool:
	return FADE_VALUES.has(fade_pct) or (fade_pct >= 0 and fade_pct <= 100 and fade_pct % 5 == 0)

static func label(fade_pct: int) -> String:
	return "Off" if fade_pct <= 0 else "%d%%" % fade_pct

## What is doing the fading, for the log: "equirect layer", "background
## colour" or "nothing".
var method := "nothing"

## Creates the layer; false when the runtime lacks equirect layers (then see
## setup_background()).
func setup(scene_root: Node, xr_origin: Node3D) -> bool:
	if layer:
		return true
	if _layer_unsupported:
		return false
	if _setup_equirect(scene_root, xr_origin):
		method = "equirect layer"
		return true
	_layer_unsupported = true
	return false

func _make_fill_viewport(scene_root: Node) -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PassthroughFadeViewport"
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(16, 16)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	scene_root.add_child(_viewport)
	_fill = ColorRect.new()
	_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill.color = Color(0, 0, 0, 0)
	_viewport.add_child(_fill)
	layer.set_layer_viewport(_viewport)

func _setup_equirect(scene_root: Node, xr_origin: Node3D) -> bool:
	layer = OpenXRCompositionLayerEquirect.new()
	layer.name = "PassthroughFadeLayer"
	layer.set_sort_order(SORT_ORDER)
	layer.set_radius(40.0)
	layer.set_central_horizontal_angle(TAU)
	layer.set_upper_vertical_angle(VERTICAL_HALF_ANGLE)
	layer.set_lower_vertical_angle(VERTICAL_HALF_ANGLE)
	layer.set_enable_hole_punch(false)
	layer.set_alpha_blend(true)
	layer.visible = false
	xr_origin.add_child(layer)
	if not layer.is_natively_supported():
		layer.queue_free()
		layer = null
		return false
	_make_fill_viewport(scene_root)
	return true

## Steam Frame (SteamVR has no equirect layers): the room shows through
## wherever the 3D scene's picture is transparent, and Nightfall's own engine
## build lets the scene's background colour say how transparent
## (steam-frame/engine/, patch 0003; FrameEngine.BACKGROUND_OPACITY). A black
## background at 40% opacity is a 40% fade: nothing extra is drawn, every
## opacity is available, and the screen, glow, controllers and pointer are
## untouched because they are drawn over the background as always.
##
## Stock Godot drops the background's opacity, so on an engine without the
## patch there is no fade on the Frame. Builds 5d to 6k drew one instead: a
## far dark quad layer behind a flat screen, and a dithered dark shell in the
## scene for curved screens (SteamVR draws every quad layer in front of the
## scene, and the Mobile renderer's 3D buffer has only 2 bits of alpha). Both
## went in 6m; they are in the history before it.
var _environment: Environment = null

func setup_background(environment: Environment) -> bool:
	if environment == null:
		return false
	_environment = environment
	method = "background colour"
	return true

## Shows the fade at `fade_pct` percent while passthrough is on.
func apply(passthrough_on: bool, fade_pct: int) -> void:
	var show := passthrough_on and fade_pct > 0
	if layer:
		if show:
			_fill.color = Color(0, 0, 0, fade_pct / 100.0)
		# A uniform 16x16 texture: rendering it continuously costs nothing, and
		# UPDATE_ONCE churns the GLES render target on Quest.
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show else SubViewport.UPDATE_DISABLED
		layer.visible = show
	elif _environment and passthrough_on:
		# With passthrough off the background belongs to the Background
		# setting (apply_background()), and its opacity isn't looked at.
		_environment.background_color = Color(0, 0, 0, fade_pct / 100.0)
