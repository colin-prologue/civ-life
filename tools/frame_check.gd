class_name FrameCheck
extends RefCounted

## Decides whether a captured frame contains a picture or nothing.
##
## This is the reason the capture harness exists. Godot's `--headless` mode
## forces the `dummy` rendering driver, which draws no pixels but still lets
## `Image.save_png()` succeed — so the naive capture writes a perfectly valid
## file containing nothing. An empty PNG attached to a pull request is worse
## than no PNG at all: it looks like evidence, and a reviewer glancing at a
## thumbnail can sign off on a world they have never seen.
##
## Kept in its own file, taking an `Image` rather than a viewport, for one
## reason: the classifier can then be tested on a machine with no rendering
## context at all. `test/test_frame_check.gd` feeds it hand-built blank and
## non-blank images under `./test.sh`, which must stay runnable without a GPU.
## The live end-to-end proof — that the guard fires against a *real* headless
## Godot — is `./capture.sh --self-test`, which needs a display and therefore
## cannot live in the suite.

## A frame is transparent if no sampled pixel exceeds this alpha.
const MIN_ALPHA := 0.02

## A frame is black if no sampled pixel exceeds this alpha-weighted channel
## value. Not a perceptual luminance: the question is "did anything get drawn",
## and the brightest channel answers that with fewer assumptions than a
## weighted mix, which can score a saturated blue near zero.
const MIN_LUMA := 0.02

## Every Nth pixel on each axis is examined. A full scan of a 1280x720 frame is
## ~920k GDScript-level pixel reads per capture; a step of 2 is a quarter of
## that and cannot miss a difference that spans more than one pixel. Nothing
## this renderer draws is one pixel wide.
const SAMPLE_STEP := 2

## Distinct colours are counted up to here and then stop being counted. The
## number is reported for the log, not used as a threshold, so saturating it is
## harmless — and an uncapped dictionary over a photographic frame would be
## megabytes of nothing.
const DISTINCT_CAP := 256


## Inspect a captured frame. Returns a dictionary with `ok` (bool) and, when
## `ok` is false, `reason` — a sentence naming what was wrong with it.
##
## The other fields are evidence rather than verdict: they go into the capture
## log so that "this frame passed" is a claim with numbers behind it.
static func inspect(img: Image) -> Dictionary:
	var out := {
		"ok": false,
		"reason": "",
		"width": 0,
		"height": 0,
		"distinct": 0,
		"max_alpha": 0.0,
		"max_luma": 0.0,
	}

	# A rendering context that never came up returns nothing here rather than
	# returning something empty. Both are failures; only this one would
	# otherwise crash on the next line.
	if img == null:
		out["reason"] = "the viewport returned no image at all"
		return out

	var w := img.get_width()
	var h := img.get_height()
	out["width"] = w
	out["height"] = h
	if w <= 0 or h <= 0:
		out["reason"] = "the image is %dx%d — the viewport has no size" % [w, h]
		return out

	var first := img.get_pixel(0, 0)
	var uniform := true
	var max_alpha := 0.0
	var max_luma := 0.0
	var seen := {}

	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if uniform and not c.is_equal_approx(first):
				uniform = false
			if c.a > max_alpha:
				max_alpha = c.a
			var luma := maxf(c.r, maxf(c.g, c.b)) * c.a
			if luma > max_luma:
				max_luma = luma
			if seen.size() < DISTINCT_CAP:
				seen[c.to_rgba32()] = true
			x += SAMPLE_STEP
		y += SAMPLE_STEP

	out["distinct"] = seen.size()
	out["max_alpha"] = max_alpha
	out["max_luma"] = max_luma

	# Ordered most-specific-cause-first, so the message names the actual failure
	# rather than the most general description of it. A fully transparent frame
	# is also uniform and also black; "transparent" is the useful thing to say.
	if max_alpha <= MIN_ALPHA:
		out["reason"] = "every sampled pixel is transparent (max alpha %.4f)" % max_alpha
		return out
	if max_luma <= MIN_LUMA:
		out["reason"] = "every sampled pixel is black (max channel %.4f)" % max_luma
		return out
	if uniform:
		out["reason"] = "every sampled pixel is the same colour (%s)" % first.to_html()
		return out

	out["ok"] = true
	return out


## One-line summary of an `inspect()` result, for the capture log.
static func describe(report: Dictionary) -> String:
	return "%dx%d, %d distinct colours (cap %d), max alpha %.3f, max channel %.3f" % [
		report["width"],
		report["height"],
		report["distinct"],
		DISTINCT_CAP,
		report["max_alpha"],
		report["max_luma"],
	]
