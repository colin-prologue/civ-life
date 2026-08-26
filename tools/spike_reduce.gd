extends SceneTree
## The intent's reduction test, applied to a captured frame:
##
##   godot --headless -s tools/spike_reduce.gd -- in.png out.png [value|six]
##
## "Any candidate style must survive as an unlit flat-shaded silhouette in six
## colours at gameplay distance. If identity lives in lighting, blur, or
## texture, it is not yet encoded as a rule."
##
## Two honest caveats about what this does and does not prove. It reduces an
## already-lit frame rather than re-rendering the scene unlit, so it tests
## whether the *image* survives losing hue and tonal resolution — not whether
## the geometry alone would read without any lighting. That stronger version
## needs an unlit pass and belongs with S1. And `six` quantises value into six
## bands rather than mapping to six authored palette colours; it answers "does
## this collapse into mud at low tonal resolution", which is the half of the
## test that a captured frame can actually answer.
##
## Runs headless on purpose — it reads pixels off disk and never rasterises,
## so unlike spike_shot.gd it needs no rendering context.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("REDUCE-FAIL want: in.png out.png [value|six]")
		quit(1)
		return
	var mode := args[2] if args.size() > 2 else "value"
	var img := Image.load_from_file(args[0])
	if img == null:
		print("REDUCE-FAIL could not read %s" % args[0])
		quit(1)
		return
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			# Rec.709 luma: the standard weighting for perceived lightness.
			var v := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if mode == "six":
				v = floor(clampf(v, 0.0, 0.999) * 6.0) / 5.0
			img.set_pixel(x, y, Color(v, v, v, c.a))
	var err := img.save_png(args[1])
	if err != OK:
		print("REDUCE-FAIL could not write %s (error %d)" % [args[1], err])
		quit(1)
		return
	print("REDUCE-OK %s %s" % [mode, args[1]])
	quit(0)
