class_name CityNode
extends RefCounted

## A structure the player has placed on a tile: where it is, what it is, and
## what it is holding.
##
## This is the first half of the decentralised city (`AgDR-002`). A city here is
## not a tile with numbers on it — it is a handful of these on separate hexes
## with routes between them, and the grain in a granary got there because
## somebody carried it.
##
## **Why a `kind` field rather than a `Farm` and a `Granary` subclass.** The
## ticket asks for "a placed structure with a position, a type, and a store",
## and `AgDR-002`'s tuning constraint asks for few chunky nodes rather than many
## small buildings. One class with an enum is the smaller thing while there are
## two kinds and one line of behaviour between them. If a third kind arrives
## with real behaviour of its own — a workshop that consumes one good and emits
## another — that is the point to split, and the split will be obvious because
## `produce()` will have grown a second branch.
##
## Note that this is *not* the unification `AgDR-002` cares about. Nodes stand
## still and are placed; agents move and act. The type that must not branch on
## what it is carrying is `Agent`, and it does not — see `sim/agent.gd` and the
## grep test in `test/test_city.gd`.

enum Kind {
	FARM,
	GRANARY,
}

## Grain a farm produces in one turn on a tile at full forage. Everything below
## that is the same number scaled by what the tile can actually grow this
## season, which is how the world's calendar reaches the city's stores without a
## second clock (see `Seasons`).
const FARM_YIELD_PER_TURN := 1.0

## What a farm can hold before the next harvest has nowhere to go. Deliberately
## small: it is a barn beside a field, not a granary, and it is what makes a
## delayed carrier cost the city something. A farm that could stockpile
## indefinitely would make the walkers decorative — every interruption would be
## made up later and throughput would depend only on the total.
##
## About three turns of a good harvest. Sized against the round trip rather than
## chosen: a carrier on a clear road comes back every couple of turns and never
## finds the barn full, and a carrier held up finds it full within three or four
## and everything after that is harvest with nowhere to go. That gap is the
## entire mechanism by which something standing in the road costs the city
## anything, and widening this number closes it — measured, at twelve the same
## obstruction cost eight percent of deliveries instead of most of them, because
## the barn simply absorbed the delay.
const FARM_CAPACITY := 3.0

## What a granary holds. Large enough that nothing in a normal run meets it —
## `world-growth-tone` is abundance-baseline, and a granary that fills up and
## starts refusing deliveries is a scarcity mechanic arriving by the back door.
## It exists so "with a capacity" is a real property rather than an unbounded
## float.
const GRANARY_CAPACITY := 5000.0

const KIND_NAMES := {
	Kind.FARM: "farm",
	Kind.GRANARY: "granary",
}

var id: int

## Where the structure stands, in axial coordinates. Nodes do not move; there is
## no setter and nothing calls one.
var coord: Vector2i

var kind: int

## Grain currently here, in the units `FARM_YIELD_PER_TURN` is denominated in.
var store: float

## The most this node will hold. Grain offered above it is not stored — it is
## the harvest that had nowhere to go, which is an absence of growth rather than
## a loss of what was built (`world-growth-tone` rule 1).
var capacity: float


func _init(p_id: int, p_coord: Vector2i, p_kind: int, p_capacity := -1.0) -> void:
	id = p_id
	coord = p_coord
	kind = p_kind
	store = 0.0
	capacity = p_capacity if p_capacity >= 0.0 else default_capacity(p_kind)


static func default_capacity(kind_: int) -> float:
	return FARM_CAPACITY if kind_ == Kind.FARM else GRANARY_CAPACITY


func kind_name() -> String:
	return KIND_NAMES.get(kind, "unknown")


## One turn of production. A farm grows grain in proportion to what its tile can
## grow this season; a granary grows nothing and waits to be filled.
##
## Read off the tile every turn rather than sampled once at placement, so a farm
## on grass and a farm in a wood have different years — and so the seasonal
## curve in `Seasons` is the city's calendar too rather than a separate one that
## can drift out of step with it.
func produce(world: WorldMap) -> void:
	if kind != Kind.FARM:
		return
	# The field is worth the seasonal curve scaled by how worn it is for growing
	# things — and working it wears it further. `AgDR-014`.
	var available := world.forage_for_use(coord, Land.Use.CULTIVATE)
	deposit(FARM_YIELD_PER_TURN * available)
	world.draw_vitality(coord, Land.Use.CULTIVATE, available)


## Put grain in. Returns how much was actually accepted, which is less than was
## offered only when the node is full.
func deposit(amount: float) -> float:
	var accepted := minf(maxf(amount, 0.0), capacity - store)
	store += accepted
	return accepted


## Take grain out. Returns how much was actually given, which is less than was
## asked for only when the node is nearly empty.
func withdraw(amount: float) -> float:
	var given := minf(maxf(amount, 0.0), store)
	store -= given
	return given
