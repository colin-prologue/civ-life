extends SceneTree
## Frame grab for the diorama spike scene — the same in-engine capture idea as
## tools/capture.gd, scoped to the spike. Needs a real rendering context
## (never --headless; see capture.sh's notes):
##
##   xvfb-run godot --path . --resolution 1280x720 \
##       -s tools/spike_shot.gd -- out.png [key=value ...]
##
## Any exported art-direction parameter on the scene can be overridden by
## trailing key=value pairs, which is what makes the ticket's parameter sweeps
## (AC12) one command per frame instead of one edit per frame:
##
##   -- low.png  elevation_exaggeration=0.6
##   -- wide.png fov_horizontal_deg=30 camera_pitch_deg=28
##
## Prints, in capture.sh's greppable contract style:
##   SPIKE-SHOT <path>            frame written and verified non-blank
##   SPIKE-BUILD-MS <total> <phase=ms ...>   scene build cost (AC10)
##   SPIKE-FAIL <reason>          nothing usable was produced

const SCENE := "res://game/diorama/spike.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("SPIKE-FAIL no output path given")
		quit(1)
		return
	var out: String = args[0]

	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("SPIKE-FAIL scene did not load")
		quit(1)
		return
	var spike: Node3D = packed.instantiate()

	# Overrides are applied BEFORE the node enters the tree, so _ready()'s
	# build already sees them and nothing is built twice.
	for i in range(1, args.size()):
		if not _apply_override(spike, args[i]):
			spike.free()
			quit(1)
			return

	root.add_child(spike)
	# add_child during _initialize() is deferred, so _ready() — and with it the
	# build we are about to time — has not run yet. Let one frame pass.
	await process_frame
	_report_build_cost(spike)
	_grab(out)


## key=value onto an exported property. Refuses unknown keys rather than
## silently rendering the default — a sweep that quietly ignores its own
## parameter produces frames that all look the same for no visible reason.
func _apply_override(spike: Node3D, pair: String) -> bool:
	var bits := pair.split("=", true, 1)
	if bits.size() != 2:
		print("SPIKE-FAIL malformed override '%s' (want key=value)" % pair)
		return false
	var key: String = bits[0].strip_edges()
	var raw: String = bits[1].strip_edges()
	if key == "rebuild":
		print("SPIKE-FAIL 'rebuild' is a trigger, not a parameter")
		return false
	var current: Variant = spike.get(key)
	if current == null:
		print("SPIKE-FAIL unknown parameter '%s'" % key)
		return false
	match typeof(current):
		TYPE_FLOAT:
			if not raw.is_valid_float():
				print("SPIKE-FAIL '%s' wants a number, got '%s'" % [key, raw])
				return false
			spike.set(key, raw.to_float())
		TYPE_INT:
			if not raw.is_valid_int():
				print("SPIKE-FAIL '%s' wants an integer, got '%s'" % [key, raw])
				return false
			spike.set(key, raw.to_int())
		TYPE_BOOL:
			spike.set(key, raw == "true" or raw == "1")
		_:
			print("SPIKE-FAIL '%s' is not an overridable scalar" % key)
			return false
	return true


func _report_build_cost(spike: Node3D) -> void:
	var total: float = spike.get("last_build_ms")
	var phases: Dictionary = spike.get("last_phase_ms")
	var parts: Array[String] = []
	for name: String in phases:
		parts.append("%s=%.1f" % [name, phases[name]])
	parts.sort()
	print("SPIKE-BUILD-MS %.1f %s" % [total, " ".join(parts)])


func _grab(out: String) -> void:
	# Without this the loop below measures the vsync wait and reports a tidy
	# 16.67 ms on any scene at all — a number that looks like a measurement and
	# is really just the refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Warm up first: the first frames include pipeline compilation and shadow
	# map allocation, and timing those would flatter nothing and mislead a lot.
	for _i in range(30):
		await process_frame
	var samples: Array[float] = []
	for _i in range(60):
		var t0 := Time.get_ticks_usec()
		await process_frame
		samples.append((Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	print("SPIKE-FRAME-MS median=%.2f p95=%.2f  (%d samples, steady state)"
			% [samples[samples.size() / 2],
			samples[int(samples.size() * 0.95)], samples.size()])
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
