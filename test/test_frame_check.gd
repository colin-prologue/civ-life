extends GutTest

# The blank-frame guard is the only part of the capture harness that can be
# checked without a rendering context, and it is also the part the whole ticket
# rests on: if it does not reject an empty frame, capture produces artifacts
# that look like evidence of a world nobody has actually seen.
#
# These tests build the blank cases by hand instead of capturing them, so they
# run in the same suite as everything else on a host with no GPU. They are not
# a substitute for `./capture.sh --self-test`, which runs the real capture under
# a real headless Godot and watches the guard fire end to end. This checks the
# rule; that checks the wiring.

const SIZE := 32


func _filled(color: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img


func test_a_missing_image_is_rejected() -> void:
	# What a rendering context that never came up hands back.
	var report := FrameCheck.inspect(null)
	assert_false(report["ok"], "a null image is not a frame")
	assert_string_contains(report["reason"], "no image")


func test_a_zero_sized_image_is_rejected() -> void:
	var report := FrameCheck.inspect(Image.new())
	assert_false(report["ok"], "an empty image is not a frame")
	assert_string_contains(report["reason"], "no size")


func test_a_fully_transparent_frame_is_rejected() -> void:
	var report := FrameCheck.inspect(_filled(Color(0.0, 0.0, 0.0, 0.0)))
	assert_false(report["ok"], "nothing was drawn")
	assert_string_contains(report["reason"], "transparent")


func test_a_transparent_frame_is_rejected_even_when_its_colour_is_bright() -> void:
	# Alpha is checked before colour on purpose: a frame that is transparent
	# white would otherwise pass a luminance test while showing nothing.
	var report := FrameCheck.inspect(_filled(Color(1.0, 1.0, 1.0, 0.0)))
	assert_false(report["ok"], "invisible white is still invisible")
	assert_string_contains(report["reason"], "transparent")


func test_a_fully_black_frame_is_rejected() -> void:
	var report := FrameCheck.inspect(_filled(Color(0.0, 0.0, 0.0, 1.0)))
	assert_false(report["ok"], "an opaque black frame is a blank frame")
	assert_string_contains(report["reason"], "black")


func test_a_uniform_coloured_frame_is_rejected() -> void:
	# The renderer clears to a dark background before drawing anything. A frame
	# containing only that clear colour means the draw never happened, and it is
	# neither black nor transparent — this is the case a naive guard misses.
	var report := FrameCheck.inspect(_filled(Color(0.07, 0.08, 0.10, 1.0)))
	assert_false(report["ok"], "background only is not a picture")
	assert_string_contains(report["reason"], "same colour")


func test_a_frame_with_two_colours_is_accepted() -> void:
	var img := _filled(Color(0.13, 0.30, 0.52, 1.0))
	for y in range(SIZE / 2):
		for x in range(SIZE):
			img.set_pixel(x, y, Color(0.58, 0.76, 0.40, 1.0))
	var report := FrameCheck.inspect(img)
	assert_true(report["ok"], "two terrains side by side is a picture: %s" % report["reason"])
	assert_eq(report["distinct"], 2, "both colours were counted")


func test_a_mostly_dark_frame_with_something_in_it_is_accepted() -> void:
	# The guard must not be so eager that a legitimately dark world — night, a
	# mostly-ocean map — gets thrown away. One lit region is enough.
	var img := _filled(Color(0.0, 0.0, 0.0, 1.0))
	for y in range(8, 16):
		for x in range(8, 16):
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1.0))
	var report := FrameCheck.inspect(img)
	assert_true(report["ok"], "a dark frame with content is not a blank frame")
	assert_almost_eq(report["max_luma"], 0.9, 0.05, "the lit patch was found")


func test_the_report_carries_the_frame_size() -> void:
	# The size lands in the capture log. A frame silently captured at the wrong
	# resolution is the sort of thing only a number in a log catches.
	var report := FrameCheck.inspect(_filled(Color(0.2, 0.4, 0.6, 1.0)))
	assert_eq(report["width"], SIZE)
	assert_eq(report["height"], SIZE)
	assert_string_contains(FrameCheck.describe(report), "%dx%d" % [SIZE, SIZE])
