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

## What a granary holds.
##
## **Re-derived when people started eating (#29).** This was 5000 — "large enough
## that nothing in a normal run meets it" — because a granary that fills and
## refuses deliveries is a scarcity mechanic arriving by the back door. That
## reasoning assumed grain had nowhere to go but the store. It now does: a store
## that sits well above `GROWTH_FRACTION` of this for `GROWTH_TURNS` turns becomes
## another person, and that person eats. A granary at this size is therefore
## turned into people long before it is full, and the size is what makes "a fraction
## of capacity" a reachable bar rather than a number no city ever sees.
##
## Forty grain is about two seasons of what the starting city eats, and about a
## winter of what a grown one eats — deep enough to carry a city through the lean
## half of the year, shallow enough that a good summer visibly fills it.
const GRANARY_CAPACITY := 40.0

## The share of its capacity a granary has to hold, turn after turn, before the
## people it feeds count as having a surplus.
##
## Half. A granary at half is one that has carried the city through the turns
## since the last harvest and still has a winter's worth in hand — that is what
## plenty looks like here, as opposed to "not empty". Lower than half and an
## ordinary summer grows a city it cannot feed in winter; higher and growth waits
## on a store so full that deliveries start being refused first.
const GROWTH_FRACTION := 0.5

## Consecutive turns a granary has to hold above `GROWTH_FRACTION` before a new
## person appears. One season.
##
## A season because it is the unit the world is legible in: a single good turn is
## a delivery landing, and a season held is a surplus. It is also the cap on how
## fast a city grows — at most one person per granary per season — which is what
## stops the loop overshooting badly before the extra mouths show up in the store.
const GROWTH_TURNS := Seasons.TURNS_PER_SEASON

## How long a granary keeps its books on hunger before judging them. Two years.
##
## Two because of what `LEAN_SHARE` has to do, below: be low enough to notice a
## city eating a quarter more than its land grows, and still be out of reach of
## one empty season. Over one year no share does both — a whole empty season is a
## quarter of a year, which is the same size as the overpopulation it has to
## catch. Over two years that season is an eighth, and it stays at most an eighth
## however it straddles the boundary between two sets of books.
const LEAN_TURNS := Seasons.TURNS_PER_YEAR * 2

## The share of the books' appetite a granary has to leave unmet before one of
## the people it feeds is lost. A sixth.
##
## `world-growth-tone` rule 2: soft fail only, and only from sustained
## mismanagement — never a single bad season. A granary emptied for a whole season
## inside otherwise fed books leaves an eighth unmet and costs nobody. Losing a
## person takes a city short by more than that across two years, and then costs
## one person per two years.
##
## Measured into place rather than chosen, in two wrong steps worth recording.
## The first version counted *consecutive* hungry turns, and a city eating more
## than its land grows still gets a fed turn after each good delivery, which
## restarted the count — a city grown on a fresh field sat above what the worn
## field fed indefinitely. The second judged a year against a third, and left a
## dead band: on the standard seed a city of nine was a quarter short and stayed
## nine, a city of six could not fill its granary and stayed six, and a city
## knocked from one to the other never came back. At a sixth of two years the
## nine sheds people until it is fed, which is where the growth line already was.
const LEAN_SHARE := 1.0 / 6.0

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

## What a gathering node holds between carriers: about three turns of its best
## harvest, the sizing rule the farm's barn states and for the same reason — a
## store that could absorb a whole quiet season would make the carriers
## decorative, and here it would also hide the thing this kind exists to show,
## that the flow stops when the animals leave.
##
## Its own number rather than `FARM_CAPACITY`, which it was until the farm's
## barn was re-derived for worn fields (`AgDR-014`). That reason does not reach a
## camp: what it gathers is set by the mouths in range and nothing it draws on
## wears out, so three turns of its best harvest is still 3.0. Sharing the
## constant had shrunk the camp's barn as a side effect of a farm change. Found
## by codex review on PR #51.
const GATHERING_CAPACITY := 3.0

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

## Mouths that asked this node for food this turn, and how much of what they
## asked for it could not give. Cleared with the flows at the top of the turn.
##
## Counted by the node rather than by walking the agents, for `AgDR-013`'s reason
## seen from the store's side: whoever eats reports a quantity to the thing they
## eat from, and nothing here can find out what they are. A node nobody ate from
## this turn has `mouths == 0`, and that — not its kind — is why a farm never
## grows a population.
var mouths: int
var unmet: float

## Consecutive turns this node has fed somebody while holding above
## `GROWTH_FRACTION` of its capacity — what growth reads.
##
## And the hunger books for the year in progress: turns into it, appetite asked,
## appetite unmet — what loss reads, once `year_turns` reaches `LEAN_TURNS`.
##
## State carried between turns, which the other fields here are not — the reason
## `AgDR-019` gave for keeping one class holds anyway: every kind carries these,
## they mean the same thing on every kind, and they stay at zero on any node
## nobody eats from.
var plentiful_turns: int
var year_turns: int
var year_asked: float
var year_unmet: float


func _init(p_id: int, p_coord: Vector2i, p_kind: int, p_capacity := -1.0) -> void:
	id = p_id
	coord = p_coord
	kind = p_kind
	store = 0.0
	last_yield = 0.0
	capacity = p_capacity if p_capacity >= 0.0 else default_capacity(p_kind)
	took_in = 0.0
	gave_out = 0.0
	mouths = 0
	unmet = 0.0
	plentiful_turns = 0
	end_year()


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
	if kind != Kind.FARM:
		return
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
	# `last_yield` is charged rather than what `deposit()` accepted. A full barn
	# is a harvest with nowhere to go, not a harvest that never happened, and the
	# ground was turned either way.
	#
	# Charged here rather than inside `yield_of()` because that expression is also
	# what a display quotes: wear belongs to the turn being taken, not to the act
	# of asking what the field is worth.
	world.draw_vitality(coord, Land.Use.CULTIVATE, last_yield / FARM_YIELD_PER_TURN)


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
##
## The farm branch reads the *cultivation* share of its tile rather than the bare
## seasonal curve (`AgDR-014`): a field that has been worked hard gives less, and
## a field a herd has eaten down gives exactly as much as it always did. Reading
## the worn field here rather than beside the `deposit()` in `produce()` is what
## keeps the number a display quotes and the number the granary receives the same
## number — the drift this single expression exists to prevent.
func yield_of(world: WorldMap) -> float:
	match kind:
		Kind.FARM:
			return FARM_YIELD_PER_TURN * world.forage_for_use(coord, Land.Use.CULTIVATE)
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


## What this farm actually took off its field on the last turn it produced.
##
## The remembered twin of `yield_rate()`, and farm-only for the same reason: the
## chronicle's `FARM_YIELD` series quotes the fields, while a camp's flow is told
## through `yield_share()`. `last_yield` itself is set for every producing kind,
## so summing it across `nodes` would quietly fold a camp's gathering into the
## fields' harvest.
##
## The kind test lives here rather than in `WorldMap.farm_harvest()` because a
## node knows what it is and the world does not ask (`AgDR-013`) — the same split
## `yield_rate()` above already makes.
func harvest() -> float:
	if kind != Kind.FARM:
		return 0.0
	return last_yield


## Start a turn with both flow counters at zero. Called by the world before
## anything produces or carries.
func begin_turn() -> void:
	took_in = 0.0
	gave_out = 0.0
	mouths = 0
	unmet = 0.0


## Give one mouth what it asks for, or as much of it as is here. Returns what was
## eaten.
##
## A withdrawal that also counts who asked and what went unmet — the only
## difference between a carrier filling a sack and a person eating, and the reason
## both go through `withdraw()` so the outflow a display quotes includes both.
func feed(appetite: float) -> float:
	mouths += 1
	var asked := maxf(appetite, 0.0)
	var eaten := withdraw(asked)
	unmet += asked - eaten
	year_asked += asked
	year_unmet += asked - eaten
	return eaten


## Close the turn's books: extend or reset the plenty run, and move the hunger
## year on. Called by the world after every agent has stepped, so what it reads is
## the store as the turn left it and every mouth that ate during it.
##
## A node nobody ate from resets everything. That is a farm on every turn, and a
## granary whose last road was somehow never walked — neither has people to grow
## or lose.
func end_turn() -> void:
	if mouths == 0:
		plentiful_turns = 0
		end_year()
		return
	plentiful_turns = plentiful_turns + 1 if store > GROWTH_FRACTION * capacity else 0
	year_turns += 1


## Whether the people this node feeds have had a surplus long enough to be joined
## by another. Asked after `end_turn()`.
func has_surplus() -> bool:
	return plentiful_turns >= GROWTH_TURNS


## Whether the year just finished left more than `LEAN_SHARE` of its appetite
## unmet. Only ever true on the turn a year's books close.
func has_shortage() -> bool:
	return year_turns >= LEAN_TURNS and year_unmet > LEAN_SHARE * year_asked


## Whether this turn finished a year of hunger books, lean or not.
func year_is_over() -> bool:
	return year_turns >= LEAN_TURNS


## Start the plenty run again. Called when a person was added, so a granary grows
## by at most one person per `GROWTH_TURNS` rather than once a turn for as long as
## the store stays high.
func reset_plenty() -> void:
	plentiful_turns = 0


## Open a fresh year of hunger books.
func end_year() -> void:
	year_turns = 0
	year_asked = 0.0
	year_unmet = 0.0


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
