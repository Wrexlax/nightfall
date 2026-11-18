class_name FrameDepthAutoRate
extends RefCounted

## Steam Frame: Hz Cap "Auto" for the headset's own depth model.
##
## How often the model should run depends on two things nobody should have to
## work out: whether the headset is keeping its frame rate, and how fast the
## chosen model is on this processor.
##
## Frame rate: Nightfall's own pacer (Ai3dAdaptivePacer, written for the
## Quest's graphics-chip models) does the stepping. A second in which the app
## falls short of the display's rate cuts the model's rate by a quarter; three
## good seconds in a row give 2 a second back. Moonlight XR for Frame does a
## cruder version of the same (it halves the rate when frames are late).
##
## The pacer's second test, the video keeping its rate, is left out here. A
## PC desktop only sends a new picture when something on it changes: in the
## 7h log the video arrived at a median 73 a second on a 90 fps stream and 60
## on a 144 fps one, under the pacer's 95% in nine seconds out of ten, with
## the headset doing nothing wrong. Auto sat at its floor for the whole
## session because of it.
##
## The model's speed: asking for more maps than the model can make only runs
## it back to back. Headset: Detail takes 54 to 72 ms a map on the Frame (6y to
## 7a logs), so about 15 a second is all there is, and at that it never rests.
## Auto asks for at most MODEL_DUTY of what the model could do, which leaves
## the processor a breather for everything else (voice typing took half as
## long again while Detail ran flat out).
##
## The numbers are a first setting, to be judged from the logs.

## Auto never asks for more than this (the rate Nightfall and Moonlight XR
## both start their processor models at).
const CEILING_HZ := 20
## Nor for less: below this the depth visibly trails what moves.
const FLOOR_HZ := 12
const MODEL_DUTY := 0.8

var _pacer := Ai3dAdaptivePacer.new()
var _rate := CEILING_HZ

## The most Auto asks of a model that takes `model_ms` a map (not yet known:
## the ceiling).
static func model_ceiling(model_ms: float) -> int:
	if model_ms <= 0.0:
		return CEILING_HZ
	return clampi(int(floor(1000.0 / model_ms * MODEL_DUTY)), FLOOR_HZ, CEILING_HZ)

## The rate in force.
func rate() -> int:
	return _rate

func reset() -> void:
	_pacer.reset(CEILING_HZ)
	_rate = CEILING_HZ

## One second's figures in; the rate to apply out, or -1 when it stays.
func on_sample(app_fps: float, display_hz: float, model_ms: float) -> int:
	var ceiling := model_ceiling(model_ms)
	# No stream rate given: the pacer then takes the video as keeping up.
	_pacer.on_sample(app_fps, 0.0, display_hz, 0.0, ceiling)
	var next := clampi(int(_pacer.current_hz), FLOOR_HZ, ceiling)
	if next == _rate:
		return -1
	_rate = next
	return next
