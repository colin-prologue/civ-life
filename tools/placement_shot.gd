extends SceneTree

## Frames of the player's verb: select a tile, place a farm, place a granary,
## draw the route, and let it run. Needs a real rendering context (never
## `--headless`; see capture.sh's notes on why a blank PNG is worse than none):
##
##   godot --path . --resolution 1280x720 \
##       -s tools/placement_shot.gd -- docs/shots/placement
##
## **Why a bespoke tool rather than `capture.sh --turns`.** That harness
## photographs a world at a list of turn numbers, and three of the four frames
## this ticket needs happen at the *same* turn — before placement, after a farm,
## after a route. The distinguishing axis is player actions, not the clock,
## which is not something a turn list can express. `tools/spike_shot.gd` set the
## precedent: when the general harness cannot state the shot, the shot gets its
## own script rather than a general harness bent into a shape nobody else wants.
##
## What is deliberately shared with `capture.sh` anyway: `FrameCheck`, run
## before anything reaches disk, so these frames clear the same blank-frame
## guard `--self-test` watches fire; and `--links`, which works on any directory
## of PNGs and is how AgDR-011's commit-pinned URLs get emitted.
##
## **Every frame is produced by driving `main.gd`'s public verbs** — the same
## `click_at()`, `place()` and `arm_route()` a keypress reaches. Calling `CityGen`
## directly would have been shorter and would have photographed a world the
## player cannot actually build: the hit test, the selection state and the
## refusal path would all be untested by the evidence. The clicks are given in
## pixels, so the round trip through `coord_at_point()` is in every frame.
##
## Prints, in capture.sh's greppable contract style:
##   SHOT-FRAME <path>     one per verified frame written
##   SHOT-OK <count>       the run finished and every frame passed
##   SHOT-FAIL <reason>    the run stopped; nothing further was written

const MAIN_SCENE := "res://game/main.tscn"

## Frames to let pass before reading the viewport. The view redraws on
## `queue_redraw()`, which lands on the next drawn frame.
const SETTLE_FRAMES := 4

## Turns the finished route is left running before the last frame. Twenty is
## AC10's number and it is not arbitrary: a carrier covers the two-tile road and
## comes back in roughly eight turns, so twenty is enough for a couple of round
## trips to have landed grain in the granary and for the status line to show it.
const RUN_TURNS := 20

var _width := 1280
var _height := 720

var _main: Node = null
var _view: Node = null
var _out_dir := ""
var _written := 0
var _drew := false


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	var args := OS.get_cmdline_user_args()
	# `--width=`/`--height=` mirror tools/capture.gd. Godot's own --resolution
	# flag does not survive into a SceneTree script's viewport, so the wrapper
	# says the size twice — once for the window, once here — and this is the
	# copy the PNGs actually get.
	for arg in args:
		if arg.begins_with("--width="):
			_width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_height = int(arg.trim_prefix("--height="))
		elif not arg.begins_with("--"):
			_out_dir = arg
	if _out_dir.is_empty():
		_fail("no output directory given")
		return
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("could not create the output directory %s" % _out_dir)
		return

	print("[shot] driver=%s display=%s target=%dx%d" % [
		RenderingServer.get_video_adapter_name(),
		DisplayServer.get_name(),
		_width,
		_height,
	])

	root.size = Vector2i(_width, _height)
	await process_frame
	await process_frame

	_main = load(MAIN_SCENE).instantiate()
	root.add_child(_main)
	_view = _main.get_node_or_null("HexMapView")
	if _view == null:
		_fail("game/main.tscn has no HexMapView — this capture path is stale")
		return
	for i in range(SETTLE_FRAMES):
		await process_frame

	await _run()


## The four frames, in the order the player would produce them.
func _run() -> void:
	var site := _a_site_for(_main.world)
	if site.is_empty():
		_fail("seed %d has nowhere to build a two-tile road" % _main.world.world_seed)
		return
	var farm_coord: Vector2i = site[0]
	var granary_coord: Vector2i = site[1]

	# 1. Before placement — the tile is selected and empty. Selecting is not
	#    placing, so this is still the untouched world, with the selection ring
	#    on it saying which tile the next two frames are about.
	_click(farm_coord)
	if not await _shot("01-tile-selected"):
		return

	# 2. A farm, put there by a person.
	_main.place(CityNode.Kind.FARM)
	if not await _shot("02-farm-placed"):
		return

	# 3. The granary, then the road between them. The second click of the route
	#    is a click, which is what arms-then-clicks looks like from the outside.
	_click(granary_coord)
	_main.place(CityNode.Kind.GRANARY)
	_click(farm_coord)
	_main.arm_route()
	_click(granary_coord)
	if _main.world.routes.size() < 2:
		_fail("the route was refused: %s" % _main.message)
		return
	if not await _shot("03-route-drawn"):
		return

	# 4. Twenty turns of it running. Nothing is selected by then, so the frame is
	#    of the world rather than of the interface.
	_main.clear_selection("")
	for i in range(RUN_TURNS):
		_main.advance_turn()
	if not await _shot("04-after-%d-turns" % RUN_TURNS):
		return

	_ok()


## Click the centre of a tile, in viewport pixels, through the same entry point
## a mouse press reaches. Pixels rather than coordinates on purpose — see the
## note at the top of the file.
func _click(coord: Vector2i) -> void:
	_main.click_at(_view.center_of(coord))


## A farm site and a granary site for this world: a legal pair, chosen for being
## near the middle of the map so the frames have the action in them rather than
## against an edge.
##
## Candidates are gathered in grid order and the winner is the one closest to the
## map's centre, ties broken by grid order — so this returns the same pair on
## every run and on every host, and the frames stay comparable across captures.
func _a_site_for(world: WorldMap) -> Array:
	var centre := Vector2(float(world.grid.width - 1) * 0.5, float(world.grid.height - 1) * 0.5)
	var best: Array = []
	var best_distance := INF
	for from in world.grid.all_coords():
		if not CityGen.can_place_node(world, from):
			continue
		for direction in HexGrid.DIRECTIONS:
			var to: Vector2i = from + direction * CityGen.ROUTE_LENGTH
			if not CityGen.can_place_node(world, to):
				continue
			var blocked := false
			for coord in HexGrid.line(from, to):
				if world.node_at(coord) != null:
					blocked = true
				elif world.terrain_at(coord) == WorldGen.Terrain.WATER:
					blocked = true
			if blocked:
				continue
			var off := HexGrid.to_offset(from)
			var distance := Vector2(float(off.x), float(off.y)).distance_to(centre)
			if distance < best_distance:
				best_distance = distance
				best = [from, to]
			break
	return best


func _on_frame_post_draw() -> void:
	_drew = true


## Wait for one frame to finish drawing since this call started, bounded.
##
## Unbounded `await RenderingServer.frame_post_draw` never resumes under the
## `dummy` driver, and a hang means the blank frame never reaches the guard —
## which looks identical from outside to having no guard. `tools/capture.gd`
## carries the long form of this argument.
func _wait_for_draw() -> bool:
	_drew = false
	for i in range(120):
		await process_frame
		if _drew:
			return true
	return false


## Read the viewport, refuse it if it is blank, and only then write it. Nothing
## reaches disk that has not already passed the check.
func _shot(stem: String) -> bool:
	for i in range(2):
		await process_frame
	if not await _wait_for_draw():
		print("[shot] no frame_post_draw in 120 frames; reading the viewport anyway")
	var tex := root.get_texture()
	var img: Image = null if tex == null else tex.get_image()

	var report := FrameCheck.inspect(img)
	if not report["ok"]:
		_fail("%s.png would have been blank — %s [%s]" % [
			stem,
			report["reason"],
			FrameCheck.describe(report),
		])
		return false

	var path := "%s/%s.png" % [_out_dir, stem]
	var err := img.save_png(path)
	if err != OK:
		_fail("could not write %s (error %d)" % [path, err])
		return false

	print("[shot] %s — %s" % [path.get_file(), FrameCheck.describe(report)])
	print("SHOT-FRAME %s" % path)
	_written += 1
	return true


func _ok() -> void:
	if _written == 0:
		_fail("the run finished without writing a single frame")
		return
	print("SHOT-OK %d" % _written)
	quit(0)


func _fail(reason: String) -> void:
	printerr("SHOT-FAIL %s" % reason)
	quit(1)
