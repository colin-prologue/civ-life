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

var _accumulator := 0.0

@onready var _view: HexMapView = $HexMapView
@onready var _status: Label = $Status


func _ready() -> void:
	world = WorldGen.generate(WORLD_SEED)
	_view.show_world(world, get_viewport_rect().size)
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


func _unhandled_input(event: InputEvent) -> void:
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
		_:
			return
	get_viewport().set_input_as_handled()


func _on_viewport_resized() -> void:
	_view.resize_to(get_viewport_rect().size)


## What the status area says when the turn crossed no threshold at all.
##
## Said out loud rather than left blank. An empty report is a real answer — the
## world ran a turn and nothing in it was worth pointing at — and a blank space
## is indistinguishable from an instrument that has stopped working.
const QUIET_TURN := "nothing crossed a threshold this turn"


func _update_status() -> void:
	# The herd total is here because the thing this world is trying to show is
	# change over time, and a number that moves every turn is the cheapest way to
	# tell whether what is on screen is going anywhere.
	#
	# Underneath it, the same turn said as events rather than as totals. A total
	# that moves tells you something happened somewhere; the lines below say what
	# and where, and the number on each one is the number ringed on the map.
	_status.text = _totals_line() + "\n" + _report_text()


## The report in words, or the quiet-turn line. Rebuilt from `world.report` every
## time, holding nothing between calls — the view keeps no memory of a turn the
## world has finished with.
func _report_text() -> String:
	var report := world.report
	if report == null or report.is_empty():
		return QUIET_TURN
	return "\n".join(report.lines())


func _totals_line() -> String:
	return "Turn %d — %s, year %d — %d animals in %d herds — %d grain in store — seed %d — %s  [space] step  [P] play/pause  [ ] speed %0.1f/s" % [
		world.turn,
		Seasons.season_name(world.season()),
		world.year(),
		roundi(world.total_herd_population()),
		world.herds().size(),
		roundi(world.total_granary_store()),
		world.world_seed,
		"playing" if playing else "paused",
		float(TURNS_PER_SECOND[speed_index]),
	]
