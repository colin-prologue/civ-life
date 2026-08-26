class_name Agent
extends RefCounted

## Something that stands on a tile and does something once per turn.
##
## This is the movement layer the whole design rests on: herds are the first
## implementation, citizens will be the second, and the point of them sharing a
## base type is that a herd walking through a farm district and a farmer walking
## to a granary meet through ordinary co-location rather than through a
## special-case rule (see `AgDR-002`).
##
## So nothing herd-shaped belongs here. An agent has a place in the world and a
## turn; population, appetite and what it is looking for belong to whatever
## extends it. The base carries an `id` only so that anything needing a stable
## name for an agent — a log line, a tie-break, a future save — has one that does
## not depend on where it happens to sit in an array.
##
## Agents are stepped by `WorldMap.advance_turn()` in array order, and they
## mutate themselves through the world rather than directly (`move_agent`), so
## the world can keep its per-tile bookkeeping exact instead of rebuilding it.

var id: int

## Where the agent is, in axial coordinates. Written through
## `WorldMap.move_agent()`, never assigned from outside.
var coord: Vector2i


func _init(p_id: int, p_coord: Vector2i) -> void:
	id = p_id
	coord = p_coord


## One turn of this agent's behaviour. The base agent does nothing at all: it
## exists, it has a place, and that is the whole contract.
func step(_world: WorldMap) -> void:
	pass


## How much of the tile's forage this agent is competing for, right now.
##
## The world keeps a running per-tile total of this so that anything deciding
## where to stand can read one number instead of scanning every agent. It is a
## *quantity*, asked of the agent, precisely so that the world never has to ask
## what kind of agent it is holding: something that grazes reports its mouths,
## something that does not reports nothing, and `WorldMap` adds up whatever it
## is given.
##
## Zero here is the honest default rather than a placeholder. Standing on a
## meadow does not eat it.
func forage_demand() -> float:
	return 0.0
