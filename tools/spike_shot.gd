extends SceneTree
## Minimal frame grab for the diorama spike scene — the same in-engine
## capture idea as tools/capture.gd, scoped to the spike. Needs a real
## rendering context (never --headless; see capture.sh's notes):
##
##   xvfb-run godot --path . --resolution 1280x720 \
##       -s tools/spike_shot.gd -- out.png
##
## Prints SPIKE-SHOT <path> on success, SPIKE-FAIL <reason> otherwise, in
## the capture.sh contract style so a wrapper can grep for it.


func _initialize() -> void:
	var out := "spike_frame.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var packed: PackedScene = load("res://game/diorama/spike.tscn")
	if packed == null:
		print("SPIKE-FAIL scene did not load")
		quit(1)
		return
	root.add_child(packed.instantiate())
	_grab(out)


func _grab(out: String) -> void:
	for _i in range(30):
		await process_frame
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("SPIKE-FAIL empty frame")
		quit(1)
		return
	# refuse a frame that has nothing in it, like capture.gd does
	var histogram := {}
	for i in range(0, img.get_width() * img.get_height(), 197):
		var px := img.get_pixel(i % img.get_width(), i / img.get_width())
		histogram[px.to_rgba32()] = true
		if histogram.size() > 8:
			break
	if histogram.size() <= 2:
		print("SPIKE-FAIL frame is blank (%d distinct colours)" % histogram.size())
		quit(1)
		return
	var err := img.save_png(out)
	if err != OK:
		print("SPIKE-FAIL could not write %s (error %d)" % [out, err])
		quit(1)
		return
	print("SPIKE-SHOT ", out)
	quit(0)
