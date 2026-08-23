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
## Why this drives `game/main.tscn` by default rather than building its own
## view: the thing worth reviewing is what the game actually shows. A capture
## path with its own scene setup would be a second renderer that can drift from
## the first, and the drift would be invisible precisely in the frames meant to
## prove nothing had drifted.
##
## `--scene=` overrides that default so a standalone lab scene can be
## photographed by the same harness — the procedural-art intent judges lab
## output through this script, and a spike whose evidence cannot be captured
## cannot be reviewed. The override does not weaken the argument above: the
## default is unchanged, and the "no HexMapView" guard still fires for the game
## scene, where a missing view means the capture path went stale. For any other
## scene a missing view is simply a scene that is not the hex game, so the
## world/turn plumbing is skipped rather than fatal.
##
## What an overridden scene gets: a real rendering context, the settle frames,
## and the same `FrameCheck` blank-frame guard — which is the part that matters,
## because it is what distinguishes a captured diorama from a grey rectangle.
## What it does not get: seeding and turn advance, which are calls on the hex
## game's own API. A scene that wants those must expose `world` and
## `advance_turn()`.
##
## Contract with `capture.sh`, which greps for these:
##   CAPTURE-FRAME <path>     one per verified frame written
##   CAPTURE-OK <count>       the run finished and every frame passed
##   CAPTURE-FAIL <reason>    the run stopped; nothing further was written
## Anything else on stdout is commentary.
##
## Scene selection:
##   --scene=res://path.tscn  what to photograph (default: the game scene)
##   --label=name             stem for stills from a non-turn-driven scene,
##                            which has no turn number to name them by

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
var _scene := MAIN_SCENE
var _label := ""

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
	_scene = str(args.get("scene", _scene))
	_label = str(args.get("label", ""))
	if args.has("turns"):
		_turns = _parse_turns(str(args["turns"]))

	# Verification of already-written frames needs no rendering context and no
	# scene, so it short-circuits everything below.
	if _mode == "verify":
		_run_verify(str(args.get("frames", "")))
		return

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

	if not ResourceLoader.exists(_scene):
		_fail("no scene at %s" % _scene)
		return
	_main = load(_scene).instantiate()
	root.add_child(_main)
	_view = _main.get_node_or_null("HexMapView")
	# Only fatal for the game scene. There, a missing view means this harness
	# has drifted from the thing it photographs and every later frame would be
	# of the wrong scene; anywhere else it just means "not the hex game".
	if _view == null and _scene == MAIN_SCENE:
		_fail("game/main.tscn has no HexMapView node — the capture path is stale")
		return

	if _is_turn_driven():
		_apply_seed()

	for i in range(SETTLE_FRAMES):
		await process_frame

	if _mode == "movie":
		await _run_movie()
	else:
		await _run_stills()


## Whether the loaded scene exposes the hex game's clock and world.
##
## Checked by capability rather than by comparing against MAIN_SCENE: a future
## scene that genuinely drives the same API should get seeding and turn advance,
## and a copy of main.tscn that has diverged should not get them just because of
## where it lives.
func _is_turn_driven() -> bool:
	return _view != null and _main.has_method("advance_turn") and "world" in _main


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
	if not _is_turn_driven():
		await _run_static_still()
		return
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


## One verified frame from a scene that has no clock to advance.
##
## Named from `--label=` or the scene's own filename, because the turn-numbered
## convention the hex game uses has nothing to put in the number. Everything
## else — settle frames, the viewport read, the blank-frame guard — is the same
## path the game scene takes, which is the point: the evidence a spike attaches
## is verified the same way the game's is.
func _run_static_still() -> void:
	var stem := _label
	if stem == "":
		stem = _scene.get_file().get_basename()
	var wrote := await _capture_to("%s/%s.png" % [_out_dir, stem])
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
	if not _is_turn_driven():
		# Refused rather than approximated. Movie mode means "advance the clock
		# and record", and a scene with no clock would silently produce N copies
		# of one frame — a GIF that looks like a successful capture of a world
		# that never moved, which is the single most misleading thing this
		# harness could hand a reviewer.
		_fail("movie mode needs a scene with advance_turn(); %s has none" % _scene)
		return
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


## Run the blank-frame guard over PNGs somebody else already wrote.
##
## `--write-movie` is the engine writing files, not this harness, so the guard
## cannot stand in front of those the way it does for a still. It can stand
## behind them: load each one back and run the same `FrameCheck`. The earlier
## stand-in — a floor on file size, on the theory that a uniform PNG compresses
## to almost nothing — was too weak to notice that the recording opens with the
## engine's clear colour before the scene has been added, which is a 1280x720
## grey rectangle and several kilobytes of it.
##
## Prints one line per frame, oldest first, and leaves the deciding to
## `capture.sh`: leading blanks are engine start-up and get trimmed, a blank
## after the recording has begun properly is a hole and is fatal.
func _run_verify(dir: String) -> void:
	if dir == "":
		_fail("verify mode needs --frames=<directory>")
		return
	var names := DirAccess.get_files_at(dir)
	if names.is_empty():
		_fail("no files to verify in %s" % dir)
		return
	names.sort()
	var checked := 0
	for name in names:
		if not name.ends_with(".png"):
			continue
		var img := Image.load_from_file("%s/%s" % [dir, name])
		var report := FrameCheck.inspect(img)
		print("FRAME-%s %s" % ["OK" if report["ok"] else "BLANK", name])
		checked += 1
	if checked == 0:
		_fail("no PNG frames to verify in %s" % dir)
		return
	print("CAPTURE-OK %d" % checked)
	quit(0)


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
