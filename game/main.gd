extends Node2D

## The window onto the world: generate a map, draw it, and let a key move the
## clock forward.
##
## This is a controller, not a rule-holder. It owns a `WorldMap`, forwards input
## to it, and asks the view to redraw. `advance_turn()` here does nothing but
## call `advance_turn()` on the world — deliberately, so there is exactly one
## path a turn can travel and the tests drive the same one the player does. If
## this function ever grows a rule, the rule is in the wrong layer.

## Fixed for now. A seed picker is a later concern; what matters at this point is
## that relaunching shows the same world, so a visual change is attributable to
## the change and not to a new map.
const WORLD_SEED := 20260815

var world: WorldMap

@onready var _view: HexMapView = $HexMapView
@onready var _status: Label = $Status


func _ready() -> void:
	world = WorldGen.generate(WORLD_SEED)
	_view.show_world(world, get_viewport_rect().size)
	_update_status()
	get_viewport().size_changed.connect(_on_viewport_resized)


## Move the world forward one turn and show the result. The UI entry point and
## the test entry point are the same function on purpose.
func advance_turn() -> int:
	var turn := world.advance_turn()
	_view.refresh()
	_update_status()
	return turn


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept", false, true):
		advance_turn()
		get_viewport().set_input_as_handled()


func _on_viewport_resized() -> void:
	_view.resize_to(get_viewport_rect().size)


func _update_status() -> void:
	_status.text = "Turn %d — seed %d — press Space to advance" % [world.turn, world.world_seed]
