class_name Herd
extends Agent

## A population of animals standing on one tile, eating what that tile grows,
## and walking one step a turn toward somewhere better.
##
## The whole behaviour is two lines of arithmetic and one comparison, and that
## is deliberate — the question this ticket exists to answer is whether a world
## that moves on its own is worth watching, and answering it with a complicated
## model would leave the answer attributable to the model.
##
## **Feeding.** A tile supports `forage / consumption_per_head` heads at full
## ration. Divide that by the heads actually standing there and you get a
## *ration*: 1.0 is exactly fed, above 1.0 is surplus, below is hunger. The
## population is then scaled up or down in proportion to how far the ration sits
## from 1.0. Nothing integrates and nothing is stored per tile, so a herd cannot
## eat a meadow bare — see `AgDR-009`. Grazing pressure is expressed as heads
## sharing a tile, not as forage removed from it.
##
## That shape has one property worth stating plainly, because the acceptance
## criteria on this ticket all fall out of it: the ration is inversely
## proportional to the population, so growth is self-limiting in both
## directions. A herd that crashes finds the ration high and comes back; a herd
## that booms finds it low and thins. There is no runaway and no floor to fall
## through, and neither needed a clamp to arrange.
##
## **Moving.** The herd scores every land tile within its sensing range by the
## ration it would get standing there — its own mouths included, so a crowded
## tile scores worse than an empty one of the same forage — discounts that by
## how far away it is, picks the best, and takes one step toward it. It moves one
## tile a turn; the range decides the direction, not the speed.
##
## Choosing only between the six tiles it is touching does not work, and that is
## measured rather than argued: herds so restricted barely migrate at all, because a herd
## in the middle of a meadow sees six identical neighbours and has no reason to
## prefer any of them, all winter, however good the wood two tiles away is. See
## `.decisions/AgDR-010-herds-follow-a-sensed-gradient.md` for the numbers and
## for what it costs to have herds that can see.

## How much better a neighbour has to be before the herd bothers moving. Pure
## hysteresis: without it, float noise between two equal tiles is enough to keep
## a herd stepping back and forth forever, which is the "drifting at random"
## reading this ticket is specifically trying to avoid.
const MOVE_MARGIN := 0.02

## How much a tile's appeal is discounted per tile of walking to reach it. At
## 0.06 a tile four steps away has to feed about a quarter better than the one
## underfoot to be worth crossing to — which is roughly the difference between a
## winter meadow and a winter wood, and nothing like the difference between two
## meadows.
const DISTANCE_COST := 0.06

## Herds placed on a fresh world.
const PLACEMENT_COUNT := 14

## No two herds start within this many tiles of each other. Herds compete for
## the tile they share, so starting them stacked would make the first few turns
## a scattering rather than a world.
const PLACEMENT_SPACING := 4

## A tile has to be able to feed something in spring to be worth starting on.
const PLACEMENT_MIN_FORAGE := 0.5

## Mixed into the world seed for placement draws, so herd positions come from
## the same seed without shifting a single number the terrain generator draws.
const PLACEMENT_SALT := 0x48455244

var species: Species

## Heads in the herd. A float rather than a count: at these rates an integer
## population would round every small change to zero and the herd would sit
## still until something large happened to it. Written through
## `WorldMap.set_herd_population()`.
var population: float

## Where this herd was placed. Kept so migration can be measured against it
## without the test having to remember a starting state.
var start_coord: Vector2i

## Where the herd is currently headed, and the season it decided that in. Equal
## to `coord` when it has arrived and is grazing.
var _destination: Vector2i
var _planned_in := -1


func _init(p_id: int, p_coord: Vector2i, p_species: Species, p_population: float) -> void:
	super(p_id, p_coord)
	species = p_species
	population = p_population
	start_coord = p_coord
	_destination = p_coord


## Rounded heads, for anything showing this to a person.
func head_count() -> int:
	return roundi(population)


## Every head is a mouth, so a herd's claim on the tile it is standing on is
## simply its population. This is the one place the base type's census question
## gets a non-zero answer at present.
func forage_demand() -> float:
	return population


## One turn: eat where you are, then decide where to be next. In that order, so
## a herd's numbers are the consequence of the tile it actually spent the turn
## on rather than of the one it is about to walk to.
func step(world: WorldMap) -> void:
	_graze(world)
	_migrate(world)


## Grow or thin according to the ration on this tile.
##
## The response is capped at one whole ration either side: a herd that finds
## itself on ten times the food it needs still only grows at `growth_rate`, so
## an accidentally rich tile cannot produce a spike that the rest of the model
## then has to absorb.
func _graze(world: WorldMap) -> void:
	var ration := ration_at(world, coord)
	var scaled := population
	if ration >= 1.0:
		scaled = population * (1.0 + species.growth_rate * minf(ration - 1.0, 1.0))
	else:
		scaled = population * (1.0 - species.decline_rate * minf(1.0 - ration, 1.0))
	world.set_herd_population(self, maxf(scaled, species.minimum_population))

	# Wear is what THIS herd actually ate. Three mistakes are easy here and all
	# three were made in earlier drafts of this plan.
	#
	# First: wear is not how hungry the herd was. The tempting `1.0 / ration`
	# saturates on a tile supporting nothing, so a herd on dead winter grass
	# would wear the ground as hard as one on a spring meadow and every tile
	# would floor itself each winter.
	#
	# Second: `forage_demand_at()` is the tile's TOTAL demand, every agent
	# standing there. Every co-located herd runs this same code, so charging the
	# tile the total once per herd bills it N times over for N herds — flooring
	# exactly the popular tiles the periodicity experiment is measuring. Charge
	# this herd for its own share: what it wanted, or its proportional cut of
	# what was there when that is less.
	#
	# Third: the denominator has to be the census as it stood before anything
	# moved. `step()` grazes and then migrates, so a herd stepped later sees
	# earlier herds already gone from the live census, divides by a smaller
	# number, and claims a share the tile was charged for a moment ago. Shares
	# must sum to at most one, so they are settled against a frozen census.
	var available := world.forage_for_use(coord, Land.Use.GRAZE)
	var mouths := maxf(world.forage_demand_at_turn_start(coord), species.minimum_population)
	var my_share := available * (forage_demand() / mouths)
	var my_want := population * species.consumption_per_head
	world.draw_vitality(coord, Land.Use.GRAZE, minf(my_share, my_want) / Seasons.MAX_FORAGE)


## Walk toward the best ground the herd can sense, one tile per step, up to
## `move_range` steps.
##
## The herd picks a destination and keeps it until it arrives or the season
## turns, rather than reconsidering every turn. Two reasons, and the second is
## the one that mattered: looking around is by far the most expensive thing a
## herd does, and a world that re-plans every agent every turn was measured at
## seven times the cost of one that does not. But it also reads better — an
## animal crossing three tiles to a wood is going somewhere, where one
## re-deciding at every step is milling about.
func _migrate(world: WorldMap) -> void:
	var season := world.season()
	if _destination == coord or season != _planned_in:
		_destination = _best_ground(world)
		_planned_in = season

	for _step in range(species.move_range):
		if _destination == coord:
			return
		var next := _step_toward(world, _destination)
		if next == coord:
			# Nothing adjacent gets closer — the way is blocked by water or by
			# the edge of the map. Give the destination up rather than spend
			# every turn until the season changes failing to reach it.
			_destination = coord
			return
		world.move_agent(self, next)


## The tile within sensing range the herd would most like to be standing on.
##
## Distance is charged for rather than ignored: a tile twice as far has to be
## meaningfully better to be worth walking to, which is what keeps a herd
## grazing where it is instead of crossing the map every time a season turns.
## The current tile is charged nothing and additionally gets the move margin, so
## ties resolve to staying put.
func _best_ground(world: WorldMap) -> Vector2i:
	var best := coord
	var best_score := ration_at(world, coord) * (1.0 + MOVE_MARGIN)
	var range_ := species.sense_range
	# Axial disc, enumerated in a fixed order so two runs consider candidates in
	# the same sequence and a tie always resolves the same way.
	for dq in range(-range_, range_ + 1):
		for dr in range(maxi(-range_, -dq - range_), mini(range_, -dq + range_) + 1):
			if dq == 0 and dr == 0:
				continue
			var candidate := coord + Vector2i(dq, dr)
			var i := world.grid.index_of(candidate)
			if i < 0 or world.terrain_by_index(i) == WorldGen.Terrain.WATER:
				continue
			# Through the grazing share, not the raw curve. Scoring destinations
			# on unworn forage while the tile underfoot knows better would leave
			# herds walking onto ground they have already eaten down, and the
			# rotation `AgDR-014` is about would have no effect on where anything
			# goes.
			var supported := species.heads_supported_by(
					world.forage_for_use_by_index(i, Land.Use.GRAZE))
			var mouths := world.forage_demand_by_index(i) + population
			var steps := (absi(dq) + absi(dq + dr) + absi(dr)) >> 1
			var score := supported / mouths / (1.0 + DISTANCE_COST * float(steps))
			if score > best_score:
				best_score = score
				best = candidate
	return best


## One tile closer to `target`: whichever land neighbour shortens the distance
## most, breaking ties on which of them feeds better. Returns the current tile
## when nothing adjacent makes progress — a herd on a headland with the target
## across the water stays where it is rather than pacing the shore.
func _step_toward(world: WorldMap, target: Vector2i) -> Vector2i:
	var here := HexGrid.distance(coord, target)
	var best := coord
	var best_ration := 0.0
	for candidate in world.grid.neighbors_in_bounds(coord):
		if world.terrain_at(candidate) == WorldGen.Terrain.WATER:
			continue
		if HexGrid.distance(candidate, target) >= here:
			continue
		var score := ration_at(world, candidate)
		if best == coord or score > best_ration:
			best = candidate
			best_ration = score
	return best


## Food per head this herd would get on `candidate`, counting every other head
## already standing there — and its own, which is what makes an empty tile of
## the same forage preferable to a crowded one.
func ration_at(world: WorldMap, candidate: Vector2i) -> float:
	var supported := species.heads_supported_by(
			world.forage_for_use(candidate, Land.Use.GRAZE))
	var mouths: float
	if candidate == coord:
		# The tile underfoot is shared with whoever was standing on it when the
		# turn began, whether or not they have since moved on. Reading live
		# demand here lets a herd stepped later grow on forage an earlier herd
		# already ate — one herd thriving and its neighbour declining purely
		# because of the order they sit in the agents array. The wear charged in
		# `_graze()` is settled against the same frozen census, so growth and
		# wear agree about how many mouths were at the table.
		mouths = world.forage_demand_at_turn_start(candidate)
	else:
		# A destination is hypothetical and live demand is the right read: it
		# lets a herd see arrivals that have already moved there this turn.
		mouths = world.forage_demand_at(candidate) + population
	# The herd's own population is always in `mouths` and is never below the
	# species minimum, so this cannot divide by zero.
	return supported / maxf(mouths, species.minimum_population)


## Scatter herds across a freshly generated world.
##
## Draws from its own generator, seeded from the world seed with a fixed salt.
## Sharing the terrain generator's `RandomNumberGenerator` would work equally
## well for determinism and would mean that changing how many herds are placed
## silently changes the shape of every map — this way the two are independent.
static func populate(world: WorldMap, count := PLACEMENT_COUNT) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world.world_seed ^ PLACEMENT_SALT
	var species := Species.grazer()

	# Candidates in grid order, so the list a draw indexes into is the same on
	# every run and on every host.
	var candidates: Array[Vector2i] = []
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			continue
		if world.forage_at(coord) >= PLACEMENT_MIN_FORAGE:
			candidates.append(coord)
	if candidates.is_empty():
		return

	var placed: Array[Vector2i] = []
	# Bounded rather than looping until it succeeds: on a map with little land
	# the spacing rule can be unsatisfiable, and a generator that hangs on an
	# unlucky seed is worse than one that places eleven herds instead of
	# fourteen.
	var attempts := count * 40
	while placed.size() < count and attempts > 0:
		attempts -= 1
		var pick: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		var too_close := false
		for other in placed:
			if HexGrid.distance(pick, other) < PLACEMENT_SPACING:
				too_close = true
				break
		if too_close:
			continue
		placed.append(pick)
		world.add_agent(Herd.new(placed.size() - 1, pick, species, species.starting_population))
