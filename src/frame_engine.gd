class_name FrameEngine
extends RefCounted

## Steam Frame: which of Nightfall's own engine changes the running engine has.
##
## The Frame package ships an engine built from Godot's source with a few
## patches (steam-frame/engine/). That build names itself "nightfall<N>",
## where N is the number of the last patch it carries, so the app can tell
## what it may rely on. Any other engine (Godot's official one included)
## counts as 0 and the app keeps to what stock Godot does.

## Patch 0003: a transparent viewport's background colour keeps its opacity.
const BACKGROUND_OPACITY := 3
## Patch 0004: the window's title has no " (DEBUG)" suffix. Nothing in the
## app depends on it; the number is here so the list stays whole.
const PLAIN_WINDOW_TITLE := 4

static func patch_level() -> int:
	return level_of(str(Engine.get_version_info().get("build", "")))

static func level_of(build_name: String) -> int:
	if not build_name.begins_with("nightfall"):
		return 0
	var number := build_name.trim_prefix("nightfall")
	return int(number) if number.is_valid_int() else 0
