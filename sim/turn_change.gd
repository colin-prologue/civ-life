class_name TurnChange
extends RefCounted

## One thing that happened in the world during a turn, big enough to be worth
## saying out loud.
##
## Three fields and nothing else: **where** it happened, **what kind** of thing
## it was, and **how much** of it there was. That is the whole shape, and it is
## deliberately narrow — a change that needs a fourth field to be understood is a
## change the world is not yet holding enough state to describe, and the answer
## to that is a variable in the simulation rather than a richer report (see
## `sim/turn_report.gd` for the rest of that argument).
##
## Nothing here holds a reference to the herd, node or citizen it came from. A
## report is a statement about a turn that has already finished; a reference
## would make it a live view of something that has since moved on, and the two
## read identically until they disagree.

## The kinds of change the world can report.
##
## **Declaration order is priority order.** When more changes happen in one turn
## than the report can carry, the ones nearest the top of this list survive (see
## `TurnReport.MAX_ENTRIES`). Reading down: a season turning is the whole map at
## once; the road being blocked is the one place the built city and the living
## world actually collide; the granary is what the city is for; and a herd is one
## animal population among fourteen. `DROPPED` is last because it is not a change
## at all — it is the report saying what it could not fit.
enum Kind {
	SEASON_TURNED,
	ROUTE_BLOCKED,
	GRANARY_STORE,
	HERD_POPULATION,
	HERD_CROSSED,
	DROPPED,
}

## The coordinate of a change that did not happen anywhere in particular.
##
## A season turns over the whole map and a dropped-entry count is a fact about
## the report rather than about the world, so both need a place that is not a
## place. Off-map by construction — `HexGrid.index_of()` answers -1 for it — so
## it can never collide with a tile, and `has_place()` is the check anything
## drawing a mark has to pass.
const NOWHERE := Vector2i(-1, -1)

const KIND_NAMES := {
	Kind.SEASON_TURNED: "season",
	Kind.ROUTE_BLOCKED: "road",
	Kind.GRANARY_STORE: "granary",
	Kind.HERD_POPULATION: "herd",
	Kind.HERD_CROSSED: "herd",
	Kind.DROPPED: "dropped",
}

## Where it happened, in axial coordinates, or `NOWHERE`.
var coord: Vector2i

## Which `Kind` of change this is.
var kind: int

## How much of it there was, in the units that kind is denominated in — and
## signed where the direction matters:
##
## - `SEASON_TURNED` — forage gained or lost across the whole map
## - `ROUTE_BLOCKED` — mouths standing on the tile the carrier cannot leave
## - `GRANARY_STORE` — the store mark crossed, negative if the store fell to it
## - `HERD_POPULATION` — the head-count mark crossed, negative if the herd fell
##   to it
## - `HERD_CROSSED` — heads in the herd that crossed, so the biggest movements
##   are the ones that survive a crowded turn
## - `DROPPED` — how many changes did not fit
##
## The two mark-crossing kinds report **the bar they crossed rather than the step
## that took them over it**, which is the opposite of what this field held at
## first and is the more useful half of the pair — see `TurnReport._crossing()`
## for the two sentences that argument was settled by.
var magnitude: float

## This entry's number in the report, counting only entries that have a place,
## or 0 for the ones that do not.
##
## The one thing that ties the words to the map: the status line says "3. a herd
## crossed onto new ground" and the tile it happened on is ringed and labelled
## "3". Assigned here rather than in the renderer so the list and the map cannot
## disagree about which change is which — both read the same number off the same
## report.
var mark: int = 0

## Row-major grid index of `coord`, or -1 for a placeless change. Resolved once
## when the report is built so ordering does not need the grid back.
var order_index: int = -1

## The order this change was found in during the turn's comparison. Not reported
## and not meaningful on its own — it exists so that every sort in `TurnReport`
## is a *total* order, because `Array.sort_custom()` makes no stability promise
## and two herds of the same size on the same tile would otherwise be free to
## swap places between runs.
var seq: int = 0


func _init(p_coord: Vector2i, p_kind: int, p_magnitude: float) -> void:
	coord = p_coord
	kind = p_kind
	magnitude = p_magnitude


## Whether this change happened somewhere a mark can be drawn.
func has_place() -> bool:
	return coord != NOWHERE


func kind_name() -> String:
	return KIND_NAMES.get(kind, "unknown")


## The change in words, as the status area says it.
##
## Deliberately does not name what was standing in the road, or which kind of
## agent crossed the ground. `AgDR-013` is that nothing asks an agent what it is,
## and a report that quietly re-introduces the question in order to write a
## nicer sentence has put the branch back in a place nobody greps for.
func describe() -> String:
	var size := absi(roundi(magnitude))
	match kind:
		Kind.SEASON_TURNED:
			return "the season turned — the land feeds %d %s" % [
				size, "more" if magnitude >= 0.0 else "less"
			]
		Kind.ROUTE_BLOCKED:
			return "a carrier is held up — %d mouths in the road" % size
		Kind.GRANARY_STORE:
			return "the granary %s %d grain" % [
				"passed" if magnitude >= 0.0 else "fell back below", size
			]
		Kind.HERD_POPULATION:
			return "a herd %s %d head" % [
				"passed" if magnitude >= 0.0 else "fell back below", size
			]
		Kind.HERD_CROSSED:
			return "%d head crossed onto new ground" % size
		Kind.DROPPED:
			return "%d more change%s not shown" % [size, "" if size == 1 else "s"]
	return "something happened"
