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
##
## **Re-derived when fields started wearing out (`AgDR-014`).** The rule above did
## not change; the harvest it is stated in terms of did. A farm now holds its own
## field at about two thirds of the seasonal curve — measured at 0.66 after ten
## years — so a good harvest fell from 0.95 to roughly 0.63 a turn and three turns
## of one fell with it. Left at 3.0 the barn had become six turns deep instead of
## three, and a held-up carrier no longer cost the city anything much: the
## obstruction test's share of throughput went from 54% to 71% against a 60%
## ceiling. This is that ratio put back where its own sizing rule says it belongs,
## not a number chosen to clear a red suite.
const FARM_CAPACITY := 2.0

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

## Grain that arrived here this turn, and grain that left it. Cleared by the
## world at the top of every turn, so between turns these are the two flows that
## produced the change in `store`.
##
## Counted rather than inferred from the difference. A store that took eight in
## and gave eight out looks identical to one that did nothing, and the whole
## point of showing a flow is that those are not the same event. This costs two
## additions per transfer and decides nothing — no rule reads them.
var took_in: float
var gave_out: float


func _init(p_id: int, p_coord: Vector2i, p_kind: int, p_capacity := -1.0) -> void:
	id = p_id
	coord = p_coord
	kind = p_kind
	store = 0.0
	capacity = p_capacity if p_capacity >= 0.0 else default_capacity(p_kind)
	took_in = 0.0
	gave_out = 0.0


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
	var grown := yield_rate(world)
	deposit(grown)
	# Working the field wears it, for cultivation and for nothing else
	# (`AgDR-014`). A herd can eat this same tile down to the floor and the farm
	# will not notice, which is the whole content of that record.
	#
	# Charged against what the field actually grew rather than against the fact
	# that a farm stands here — the same correction `Herd._graze()` carries. Wear
	# proportional to how badly a farm wanted a harvest would floor every field
	# in the world each winter, when the ground gives least and the want is
	# largest. A field that grew nothing was barely worked.
	#
	# `grown` is charged rather than what `deposit()` accepted. A full barn is a
	# harvest with nowhere to go, not a harvest that never happened, and the
	# ground was turned either way.
	world.draw_vitality(coord, Land.Use.CULTIVATE, grown / FARM_YIELD_PER_TURN)


## What this node would grow this turn, before anything is done with it.
##
## The same expression `produce()` uses, pulled out so a display can show the
## field's current yield without either re-deriving it or waiting for a turn to
## pass. A number quoted from somewhere other than the place it is computed is a
## number that can be wrong, and this is the one the ticket asks to be visible.
##
## Which is why wear went in *here* rather than beside the `deposit()` in
## `produce()`. Reading the worn field in one place and the bare seasonal curve
## in the other would leave the map advertising a yield the granary never sees —
## exactly the drift this method exists to prevent.
func yield_rate(world: WorldMap) -> float:
	if kind != Kind.FARM:
		return 0.0
	return FARM_YIELD_PER_TURN * world.forage_for_use(coord, Land.Use.CULTIVATE)


## Start a turn with both flow counters at zero. Called by the world before
## anything produces or carries.
func begin_turn() -> void:
	took_in = 0.0
	gave_out = 0.0


## Put grain in. Returns how much was actually accepted, which is less than was
## offered only when the node is full.
func deposit(amount: float) -> float:
	var accepted := minf(maxf(amount, 0.0), capacity - store)
	store += accepted
	took_in += accepted
	return accepted


## Take grain out. Returns how much was actually given, which is less than was
## asked for only when the node is nearly empty.
func withdraw(amount: float) -> float:
	var given := minf(maxf(amount, 0.0), store)
	store -= given
	gave_out += given
	return given
