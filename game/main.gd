class_name Main
extends Node2D

## The window onto the world: generate a map, draw it, and move the clock.
##
## This is a controller, not a rule-holder. It owns a `WorldMap`, forwards input
## to it, and asks the view to redraw. `advance_turn()` here does nothing but
## call `advance_turn()` on the world — deliberately, so there is exactly one
## path a turn can travel and the tests drive the same one the player does. If
## this function ever grows a rule, the rule is in the wrong layer.
##
## **Why there is a play button.** A year is 24 turns and a herd moves about a
## tile a year (`AgDR-010`), so anything this world does on its own timescale is
## hundreds of key presses away. A world that can only be advanced by hand is a
## world nobody watches long enough to find out whether it is worth watching —
## which is the question `world-growth-tone` says the whole design rests on.
## Auto-advance is therefore an observation instrument, not a convenience.
##
## It is still the same single path: the timer calls `advance_turn()` and
## nothing else, so there is no second way for the clock to move.
##
## **What placement adds here, and what it does not.** This file now holds what
## the player has selected and what they are part-way through doing — a tile, and
## optionally a structure a route is being drawn from. That is session state, not
## world state: it is not saved, not seeded, and nothing in `sim/` can see it.
##
## Every decision about whether an action is allowed is `CityGen`'s. This file
## works out which tile a click landed on, asks, and shows whichever sentence
## comes back. It does not know what water is. The refusal is displayed rather
## than dropped, because a first verb that silently does nothing is
## indistinguishable from a broken one.

## Fixed for now. A seed picker is a later concern; what matters at this point is
## that relaunching shows the same world, so a visual change is attributable to
## the change and not to a new map.
const WORLD_SEED := 20260815

## Turns per second at each speed setting. The top end is chosen so that a human
## lifetime of world time is minutes rather than an afternoon: at 16 turns per
## second a year takes a second and a half.
const TURNS_PER_SECOND := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]

## The most turns one frame may run, however long the frame took.
##
## Without this, a frame that took a second — the window was dragged, the process
## was suspended, the map was being resized — would pay back its whole backlog at
## once and the world would lurch. Dropping the time is the honest behaviour:
## wall clock the player did not see is not world time they are owed.
const MAX_TURNS_PER_FRAME := 4

var world: WorldMap

## Whether the clock is running on its own. Off at launch: a world that starts
## moving before anyone has looked at it has already shown the first thing it
## does to nobody.
var playing := false

var speed_index := 1

## The tile the player has clicked, if any. `Vector2i` has no null, so the flag
## is separate rather than encoded as a sentinel coordinate — (0, 0) is a real
## tile on this map.
var selected_coord := Vector2i.ZERO
var has_selection := false

## The structure a route is being drawn from, once `R` has been pressed on one.
## Null the rest of the time, which is most of the time.
var route_origin: CityNode = null

## What just happened, in the words `sim/` used. Cleared by nothing — it stands
## until the next action replaces it, so a refusal does not vanish before it has
## been read.
var message := ""

var _accumulator := 0.0

@onready var _view: HexMapView = $HexMapView
@onready var _status: Label = $Status
@onready var _prompt: Label = $Prompt


func _ready() -> void:
	world = WorldGen.generate(WORLD_SEED)
	_view.show_world(world, get_viewport_rect().size)
	_show_selection()
	_update_status()
	get_viewport().size_changed.connect(_on_viewport_resized)


## How many whole turns a given accumulation of fractional turns owes, and what
## is left over afterwards.
##
## Pure and static so the awkward part — the cap, and what happens to the time it
## discards — is testable without a scene tree or a clock. Reaching the cap
## resets the accumulator rather than keeping the surplus, because a backlog that
## survives the cap is a backlog that gets paid the following frame instead, and
## the lurch it was there to prevent happens one frame later.
static func drain(accumulator: float, cap: int) -> Dictionary:
	var whole := int(floor(accumulator))
	if whole >= cap:
		return {"turns": cap, "accumulator": 0.0}
	return {"turns": whole, "accumulator": accumulator - float(whole)}


func _process(delta: float) -> void:
	tick(delta)


## Give the clock `delta` seconds of wall time and run whatever turns that buys.
## Returns how many turns were run.
##
## Separated from `_process` so the timing behaviour can be driven from a test
## with an explicit delta. A test that waits for real frames measures the host's
## frame rate as much as this logic, and under `--headless` the frames arrive
## far faster than a second, so the interesting cases never fire.
func tick(delta: float) -> int:
	if not playing:
		return 0
	_accumulator += delta * float(TURNS_PER_SECOND[speed_index])
	var due := drain(_accumulator, MAX_TURNS_PER_FRAME)
	_accumulator = due["accumulator"]
	var turns := int(due["turns"])
	for i in range(turns):
		advance_turn()
	return turns


## Move the world forward one turn and show the result. The UI entry point, the
## timer's entry point and the test entry point are all this function.
func advance_turn() -> int:
	var turn := world.advance_turn()
	_view.refresh()
	_update_status()
	return turn


func set_playing(value: bool) -> void:
	playing = value
	# Whatever fraction of a turn had built up belongs to the run that was
	# stopped, not to the next one.
	_accumulator = 0.0
	_update_status()


func faster() -> void:
	speed_index = mini(speed_index + 1, TURNS_PER_SECOND.size() - 1)
	_update_status()


func slower() -> void:
	speed_index = maxi(speed_index - 1, 0)
	_update_status()


## A click at a point in viewport pixels. The whole of "what was clicked" lives
## here; everything past this line is coordinates.
##
## Public and taking a point rather than an event, so the verb can be driven from
## a test or from the capture harness without synthesising input.
func click_at(point: Vector2) -> void:
	var coord := _view.coord_at_point(point)
	if not world.grid.has_coord(coord):
		# The margin, the legend, or off the edge. Clicking away from the map
		# clears the selection, which is the other half of AC1.
		clear_selection("")
		return
	if route_origin != null:
		_finish_route(coord)
		return
	select(coord)


## Select a tile. Says what is on it, because the answer decides which of the
## verbs below will work.
func select(coord: Vector2i) -> void:
	selected_coord = coord
	has_selection = true
	var standing := world.node_at(coord)
	message = "selected %s" % ("a " + standing.kind_name() if standing != null else "an empty tile")
	_show_selection()


func clear_selection(reason: String) -> void:
	has_selection = false
	route_origin = null
	message = reason
	_show_selection()


## Put a structure on the selected tile, or say why not.
func place(kind: int) -> void:
	if not has_selection:
		message = "click a tile first"
		_show_selection()
		return
	var refusal := CityGen.node_refusal(world, selected_coord)
	if not refusal.is_empty():
		message = "no %s here: %s" % [CityNode.KIND_NAMES[kind], refusal]
		_show_selection()
		return
	# Only the world changes; the selection stays where it was, so the tile just
	# built on is also the tile a route can be started from.
	CityGen.place_node(world, selected_coord, kind)
	route_origin = null
	message = "%s placed" % CityNode.KIND_NAMES[kind]
	_view.refresh()
	_show_selection()
	_update_status()


## Start a route from the selected structure. The next click picks the other end.
func arm_route() -> void:
	if not has_selection:
		message = "click a structure first"
		_show_selection()
		return
	var from := world.node_at(selected_coord)
	if from == null:
		message = "a route starts at a structure"
		_show_selection()
		return
	route_origin = from
	message = "route from the %s — click the other end" % from.kind_name()
	_show_selection()


## The second click of a route. Lands the road or says why it cannot.
##
## A miss disarms rather than staying armed, so an errant click leaves the game
## in the state the player can see rather than in a mode they have forgotten
## they are in.
func _finish_route(coord: Vector2i) -> void:
	var from := route_origin
	route_origin = null
	var to := world.node_at(coord)
	if to == null:
		selected_coord = coord
		has_selection = true
		message = "no route: nothing there to connect to"
		_show_selection()
		return
	var refusal := CityGen.route_refusal(world, from, to)
	if not refusal.is_empty():
		select(coord)
		message = "no route: %s" % refusal
		_show_selection()
		return
	CityGen.connect_nodes(world, from, to)
	select(coord)
	message = "route laid — %d carriers on it" % CityGen.CITIZENS_PER_ROUTE
	_view.refresh()
	_show_selection()
	_update_status()


func _show_selection() -> void:
	_view.set_selection(has_selection, selected_coord, route_origin != null)
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			click_at(click.position)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel", false, true):
		clear_selection("")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept", false, true):
		# A single step still works while playing; it just adds a turn.
		advance_turn()
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_P:
			set_playing(not playing)
		KEY_BRACKETRIGHT:
			faster()
		KEY_BRACKETLEFT:
			slower()
		KEY_F:
			place(CityNode.Kind.FARM)
		KEY_G:
			place(CityNode.Kind.GRANARY)
		KEY_R:
			arm_route()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_viewport_resized() -> void:
	_view.resize_to(get_viewport_rect().size)


func _update_status() -> void:
	# The herd total is here because the thing this world is trying to show is
	# change over time, and a number that moves every turn is the cheapest way to
	# tell whether what is on screen is going anywhere.
	_status.text = "Turn %d — %s, year %d — %d animals in %d herds — %d grain in store — %d farms, %d granaries, %d routes — seed %d — %s %0.1f/s" % [
		world.turn,
		Seasons.season_name(world.season()),
		world.year(),
		roundi(world.total_herd_population()),
		world.herds().size(),
		roundi(world.total_granary_store()),
		_node_count(CityNode.Kind.FARM),
		_node_count(CityNode.Kind.GRANARY),
		world.routes.size(),
		world.world_seed,
		"playing" if playing else "paused",
		float(TURNS_PER_SECOND[speed_index]),
	]


func _node_count(kind: int) -> int:
	var total := 0
	for node in world.nodes:
		if node.kind == kind:
			total += 1
	return total


## The second line: what is selected, what just happened, and what the keys do.
##
## Split from the status line because the two answer different questions and the
## status line was already the width of the window. This one is the only channel
## a refusal has, so it comes first in the string — the keys are a reminder and
## can be truncated by a narrow window without losing anything the player needs.
func _update_prompt() -> void:
	var where := "nothing selected"
	if has_selection:
		var off := HexGrid.to_offset(selected_coord)
		where = "tile %d,%d" % [off.x, off.y]
	var said := "" if message.is_empty() else " — %s" % message
	_prompt.text = "%s%s     [click] select  [F] farm  [G] granary  [R] route  [Esc] clear  [space] step  [P] play  [ ] speed" % [
		where,
		said,
	]
