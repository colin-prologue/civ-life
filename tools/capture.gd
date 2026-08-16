extends SceneTree

## In-engine capture harness: runs the real game scene against a real rendering
## driver and reads pixels back out of the viewport.
##
## Driven by `capture.sh`, never by hand — the shell script owns argument
## validation, the byte cap, and the watchdog. This file owns the two things
## that can only be done from inside the engine: getting the frame, and
## refusing to write one that has nothing in it.
##
## Why in-engine and not a screenshot tool: macOS screen recording is gated
## behind a TCC permission grant that an unattended agent cannot satisfy, and a
## denied grant produces a black rectangle rather than an error. Reading the
## viewport texture has no such failure mode — either the rendering context
## came up or it did not, and `FrameCheck` can tell the difference.
##
## Why this drives `game/main.tscn` rather than building its own view: the
## thing worth reviewing is what the game actually shows. A capture path with
## its own scene setup would be a second renderer that can drift from the first,
## and the drift would be invisible precisely in the frames meant to prove
## nothing had drifted.
##
## Contract with `capture.sh`, which greps for these:
##   CAPTURE-FRAME <path>     one per verified frame written
##   CAPTURE-OK <count>       the run finished and every frame passed
##   CAPTURE-FAIL <reason>    the run stopped; nothing further was written
## Anything else on stdout is commentary.

const MAIN_SCENE := "res://game/main.tscn"

## Frames to let pass after a change before reading the viewport. The view
## rebuilds on `queue_redraw()`, which lands on the next drawn frame; a couple
## of spare frames covers the window resize settling on the way in.
const SETTLE_FRAMES := 4

## Frames between turn advances in movie mode, at whatever `--fixed-fps`
## `--write-movie` is running. Overridable with `--hold=`.
const DEFAULT_HOLD_FRAMES := 12

## How many main-loop iterations to wait for `RenderingServer.frame_post_draw`
## before giving up on it and reading the viewport anyway.
##
## Under the `dummy` rendering driver that signal never arrives at all, so an
## unbounded `await` on it hangs until the shell's watchdog kills the process —
## which is the one outcome this harness must not have, because it means the
## blank frame never reaches the guard and the guard is never seen to fire.
## Counted in frames rather than seconds so the wait is the same on every host.
const POST_DRAW_WAIT_FRAMES := 120

var _mode := "stills"
var _seed := 20260815
var _turns: Array[int] = [0]
var _from_turn := 0
var _to_turn := 8
var _hold := DEFAULT_HOLD_FRAMES
var _out_dir := ""
var _width := 1280
var _height := 720

var _main: Node = null
var _view: Node = null
var _written := 0
var _drew := false


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	var args := _parse_args(OS.get_cmdline_user_args())

	_mode = str(args.get("mode", _mode))
	_seed = int(args.get("seed", _seed))
	_out_dir = str(args.get("out", ""))
	_width = int(args.get("width", _width))
	_height = int(args.get("height", _height))
	_hold = int(args.get("hold", _hold))
	_from_turn = int(args.get("from", _from_turn))
	_to_turn = int(args.get("to", _to_turn))
	if args.has("turns"):
		_turns = _parse_turns(str(args["turns"]))

	if _out_dir == "":
		_fail("no --out= directory was given")
		return
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("could not create the output directory %s" % _out_dir)
		return

	print("[capture] driver=%s display=%s target=%dx%d seed=%d mode=%s" % [
		RenderingServer.get_video_adapter_name(),
		DisplayServer.get_name(),
		_width,
		_height,
		_seed,
		_mode,
	])

	# Deliberately NOT an early exit on `DisplayServer.get_name() == "headless"`.
	# A name check would only catch the failure mode we already know about, and
	# would report it in a place that never proves the pixel guard works. Let
	# the run proceed and let `FrameCheck` reject the blank frames — that way
	# the guard this ticket exists for is the thing on the failure path, and
	# `capture.sh --self-test` exercises it for real rather than exercising a
	# string comparison standing in front of it. `_wait_for_draw()` is what makes
	# that possible: without a bounded wait the headless run hangs before the
	# guard is ever consulted, which looks the same from outside as no guard.

	root.size = Vector2i(_width, _height)
	await process_frame
	await process_frame

	_main = load(MAIN_SCENE).instantiate()
	root.add_child(_main)
	_view = _main.get_node_or_null("HexMapView")
	if _view == null:
		_fail("game/main.tscn has no HexMapView node — the capture path is stale")
		return

	_apply_seed()

	for i in range(SETTLE_FRAMES):
		await process_frame

	if _mode == "movie":
		await _run_movie()
	else:
		await _run_stills()


## Point the running scene at the requested seed.
##
## `main.gd` fixes its own seed at load time, and this ticket is not allowed to
## change the renderer, so the world is replaced through the same public calls
## the scene itself uses. `_update_status()` is private by convention only;
## missing it costs a stale caption and nothing else, so it is optional rather
## than fatal.
func _apply_seed() -> void:
	_main.world = WorldGen.generate(_seed)
	_view.show_world(_main.world, root.get_visible_rect().size)
	if _main.has_method("_update_status"):
		_main.call("_update_status")


func _run_stills() -> void:
	for target in _turns:
		while _main.world.turn < target:
			_main.advance_turn()
		for i in range(2):
			await process_frame
		var path := "%s/seed-%d-turn-%03d.png" % [_out_dir, _seed, target]
		var wrote := await _capture_to(path)
		if not wrote:
			return
	_ok()


## Drive the clock across a span of turns while `--write-movie` records every
## rendered frame.
##
## The recording itself is done by the engine, so the blank-frame guard cannot
## sit in front of it. Instead a still is captured and verified from the same
## viewport at the start and the end of the span: if those two have pixels, the
## frames the movie writer took off the same viewport in between have pixels
## too. `capture.sh` adds an independent check on the recorded frames' file
## sizes, because a uniform PNG compresses to almost nothing.
func _run_movie() -> void:
	while _main.world.turn < _from_turn:
		_main.advance_turn()
	for i in range(2):
		await process_frame
	var opened := await _capture_to(
		"%s/poster-seed-%d-turn-%03d.png" % [_out_dir, _seed, _from_turn])
	if not opened:
		return

	for turn in range(_from_turn, _to_turn):
		for i in range(_hold):
			await process_frame
		_main.advance_turn()
	for i in range(_hold):
		await process_frame

	var closed := await _capture_to(
		"%s/poster-seed-%d-turn-%03d.png" % [_out_dir, _seed, _to_turn])
	if not closed:
		return
	_ok()


func _on_frame_post_draw() -> void:
	_drew = true


## Wait for one frame to finish drawing since this call started. Returns false
## if the driver never said it drew anything.
##
## The obvious version of this is `await RenderingServer.frame_post_draw`, and
## it is a trap: under the `dummy` driver the signal is never emitted, so the
## coroutine never resumes, the process sits there until the shell kills it, and
## the blank frame it was supposed to be caught holding never reaches
## `FrameCheck`. That leaves a working guard and a broken guard looking exactly
## alike from outside, which is the single thing this harness exists to prevent.
##
## `process_frame` keeps firing with no rendering context — it is the main loop,
## not the renderer — so it is what bounds the wait. A false return is not a
## failure by itself: the caller reads the viewport regardless and lets the
## pixel check pass judgement, keeping the guard on the failure path rather than
## a driver-name or signal-arrival check standing in front of it.
func _wait_for_draw() -> bool:
	_drew = false
	for i in range(POST_DRAW_WAIT_FRAMES):
		await process_frame
		if _drew:
			return true
	return false


## Read the viewport, refuse it if it is blank, and only then write it.
##
## The order matters: nothing reaches disk that has not already passed the
## check. A harness that writes first and validates afterwards leaves the blank
## file behind on every failure, and one of those eventually gets committed.
func _capture_to(path: String) -> bool:
	if not await _wait_for_draw():
		print("[capture] no frame_post_draw in %d frames; reading the viewport anyway" % [
			POST_DRAW_WAIT_FRAMES,
		])
	var tex := root.get_texture()
	var img: Image = null if tex == null else tex.get_image()

	var report := FrameCheck.inspect(img)
	if not report["ok"]:
		_fail("%s would have been blank — %s [%s]" % [
			path.get_file(),
			report["reason"],
			FrameCheck.describe(report),
		])
		return false

	var err := img.save_png(path)
	if err != OK:
		_fail("could not write %s (error %d)" % [path, err])
		return false

	print("[capture] %s — %s" % [path.get_file(), FrameCheck.describe(report)])
	print("CAPTURE-FRAME %s" % path)
	_written += 1
	return true


## The success path is not "we reached the end" — it is "we reached the end
## having written something". An empty turn list, or a mode that falls through
## without capturing, must not exit 0.
func _ok() -> void:
	if _written == 0:
		_fail("the run finished without writing a single frame")
		return
	print("CAPTURE-OK %d" % _written)
	quit(0)


func _fail(reason: String) -> void:
	printerr("CAPTURE-FAIL %s" % reason)
	quit(1)


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in raw:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "true"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


## "0,5,20" -> [0, 5, 20], sorted and de-duplicated. Sorting is not cosmetic:
## the clock only moves forward, so an out-of-order list would silently capture
## the wrong turn.
static func _parse_turns(spec: String) -> Array[int]:
	var seen := {}
	for piece in spec.split(",", false):
		var trimmed := piece.strip_edges()
		if trimmed.is_valid_int():
			seen[maxi(0, int(trimmed))] = true
	var out: Array[int] = []
	for turn in seen.keys():
		out.append(turn)
	out.sort()
	return out
