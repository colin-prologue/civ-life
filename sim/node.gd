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
## **The third kind arrived and the split was declined.** `Kind.GATHERING` gives
## `yield_of()` a second branch, so the condition written above is met on its
## face. It was not taken, for a reason worth stating rather than skipping: both
## branches are one expression that reads a number off the world and returns it,
## neither kind carries state the others do not, and the enum is still doing real
## work as the tag the renderer and `WorldMap`'s queries sort by — a subclass
## split would delete the tag and immediately rebuild it as `is Granary` at every
## call site. The split becomes right when a kind needs *inputs* (a workshop that
## consumes one good to emit another) or per-kind fields, because that is when
## the shared shape of `produce()` stops being true. See `AgDR-019`.
##
## Note that this is *not* the unification `AgDR-002` cares about. Nodes stand
## still and are placed; agents move and act. The type that must not branch on
## what it is carrying is `Agent`, and it does not — see `sim/agent.gd` and the
## grep test in `test/test_city.gd`. A gathering node is held to the same rule
## from the other side: it reads a per-tile quantity out of the census and cannot
## find out what is producing it. `test/test_gathering.gd` greps this file for
## that.

enum Kind {
	FARM,
	GRANARY,
	GATHERING,
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

## What a gathering node produces in one turn when the ground around it is
## thick with animals. The same number as a farm at full forage, so "a good year
## here" means the same thing at both, and the difference between the two nodes
## is entirely *when* the good year happens.
const GATHERING_YIELD_PER_TURN := 1.0

## How far around itself a gathering node counts. Two tiles — the nineteen-hex
## disc centred on it.
##
## Kept at two after a sweep, and the sweep is the interesting part, because it
## found no value that satisfies both halves of what this kind is supposed to be.
## Measured over eight years on the two standard seeds, at the camp `CityGen`
## actually places and at hand-picked sites:
##
##     radius   generated camp lit   a busy site over a typical one
##       2        0 of 192 turns          unbounded (typical earns nothing)
##       3        1, 0                    1.2x, 165.9x
##       4        2, 0                    1.2x, 1.3x
##       5      192, 192                  1.1x, 1.4x
##       6      192, 192                  1.1x, 1.1x
##
## Read that table as a statement about *these two seeds*, which is the sweep's
## main limitation: on both of them the generated camp happens to land away from
## the herds, so the left column reads as a flat zero and says more about where
## two roads went than about the radius. Swept wider — twelve seeds, in
## `test_gathering.gd` — a radius-two camp placed by generation is lit at some
## point on five of them, so "below five it never wakes" is false in general and
## true of the standard pair.
##
## What survives the wider sweep is the right-hand column, and that is what fixes
## this constant. At five and above the disc swallows enough permanently-occupied
## ground that a camp is lit on every single turn and where it was put stops
## mattering — a farm with a seasonal curve, the outcome the ticket named as the
## failure. Two is kept because it is the value at which placement is
## unambiguously a decision, which is the claim this kind is built on and the one
## `AgDR-019` says not to tune away.
const GATHERING_RADIUS := 2

## Mouths within `GATHERING_RADIUS` at which the node produces half of
## `GATHERING_YIELD_PER_TURN`. One herd's worth at the size herds are placed
## (`Species.grazer().starting_population`), so a single herd wandering into
## range is a visible event rather than a rounding difference.
##
## The response saturates rather than scaling: `nearby / (nearby + this)`. That
## is what keeps this an *opportunity* rather than a reason to want herds
## concentrated — four herds in range are worth roughly a third more than one,
## not four times as much, so the interesting question stays "is anything here"
## and never becomes "how do I pile animals up".
const GATHERING_HALF_AT := 40.0

## Mouths below which a census reading counts as nobody there.
##
## The per-tile census is a `PackedFloat32Array` maintained by adding a herd's
## demand on arrival and subtracting it on departure, and a 32-bit
## add-then-subtract of a 64-bit quantity can leave a residue on the order of
## 1e-4 mouths on a tile the animals have left. Without a floor that residue is
## "demand", and a camp whose herds are long gone stays faintly lit forever —
## which also poisons every measurement that classifies a turn by
## `last_yield > 0.0`. A thousandth of a mouth is orders of magnitude above any
## residue the census can accumulate and orders of magnitude below the tens of
## mouths a real herd reports, so nothing real is ever rounded away.
const GATHERING_DEMAND_FLOOR := 0.001

## What a gathering node holds between carriers. The same barn as a farm, and
## for the same reason: a store that could absorb a whole quiet season would make
## the carriers decorative, and here it would also hide the thing this kind
## exists to show — that the flow stops when the animals leave.
const GATHERING_CAPACITY := FARM_CAPACITY

const KIND_NAMES := {
	Kind.FARM: "farm",
	Kind.GRANARY: "granary",
	Kind.GATHERING: "gathering",
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

## What this node grew on the most recent turn, before anything was put away.
##
## Recorded rather than derived because it is not derivable after the fact: what
## reached the store is the yield capped by whatever room was left in it, and a
## full barn is not the same thing as a quiet one. The renderer needs the
## difference to show a gathering node as lit or dark, and that is a reading of
## simulation state rather than a rule the view is allowed to invent
## (`AgDR-001`).
var last_yield: float

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
	last_yield = 0.0
	capacity = p_capacity if p_capacity >= 0.0 else default_capacity(p_kind)
	took_in = 0.0
	gave_out = 0.0


static func default_capacity(kind_: int) -> float:
	match kind_:
		Kind.FARM:
			return FARM_CAPACITY
		Kind.GATHERING:
			return GATHERING_CAPACITY
	return GRANARY_CAPACITY


func kind_name() -> String:
	return KIND_NAMES.get(kind, "unknown")


## One turn of production: grow whatever this kind grows, then put it away.
func produce(world: WorldMap) -> void:
	last_yield = yield_of(world)
	deposit(last_yield)


## What this node grows this turn, before storage is considered.
##
## A farm reads the tile it stands on. A gathering node reads the tiles *around*
## it — how much of their forage is spoken for, which is the same per-tile total
## a citizen consults to find out whether the road ahead is busy. Both are values
## looked up every turn rather than sampled once at placement, so a farm on grass
## and a farm in a wood have different years, and so `Seasons` stays the city's
## only calendar rather than one that can drift out of step with the world's.
##
## The gathering branch is the whole of `AgDR-019`, and its restraint is the
## point: it asks for a quantity on a set of tiles and there is no question it
## could ask that would tell it what is producing that quantity. A herd reports
## its mouths, a citizen reports nothing, and anything later that wants to be
## gatherable reports a number rather than announcing a type.
##
## A granary grows nothing and waits to be filled.
func yield_of(world: WorldMap) -> float:
	match kind:
		Kind.FARM:
			return FARM_YIELD_PER_TURN * world.forage_at(coord)
		Kind.GATHERING:
			return GATHERING_YIELD_PER_TURN * gathering_share(
				world.forage_demand_within(coord, GATHERING_RADIUS)
			)
	return 0.0


## The fraction of its best turn a gathering node gets from `nearby` mouths in
## range. Saturating, zero at zero — and at anything under
## `GATHERING_DEMAND_FLOOR`, which is where float32 census residue lives — and
## never reaching one.
##
## Static and pure so the shape can be asserted on the numbers directly, without
## a world to put it in.
static func gathering_share(nearby: float) -> float:
	if nearby < GATHERING_DEMAND_FLOOR:
		return 0.0
	return nearby / (nearby + GATHERING_HALF_AT)


## The most this kind of node can grow in one turn. Zero for a granary.
static func max_yield_per_turn(kind_: int) -> float:
	match kind_:
		Kind.FARM:
			return FARM_YIELD_PER_TURN
		Kind.GATHERING:
			return GATHERING_YIELD_PER_TURN
	return 0.0


## How good the last turn was here, as a fraction of the best this node could
## have done. Zero to one, and zero for a granary.
##
## This is what makes a gathering node's state legible without the renderer
## knowing anything about herds or about how the yield was arrived at.
func yield_share() -> float:
	var ceiling := max_yield_per_turn(kind)
	if ceiling <= 0.0:
		return 0.0
	return clampf(last_yield / ceiling, 0.0, 1.0)


## What this farm would grow this turn, before anything is done with it.
##
## Pulled out so a display can show the field's current yield without either
## re-deriving it or waiting for a turn to pass, and delegated to `yield_of()`
## so there is exactly one place the expression lives. Farm-only on purpose:
## the map's yield overlay and the chronicle's `FARM_YIELD` series are quoting
## the fields, and a camp's flow is told through `yield_share()` instead.
func yield_rate(world: WorldMap) -> float:
	if kind != Kind.FARM:
		return 0.0
	return yield_of(world)


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
