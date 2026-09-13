extends GutTest

# People eat, and a fed surplus becomes more people (#29).
#
# The claim under test is not that a city grows. It is that it grows *and
# settles*, from something already in the world rather than from a cap: more
# walkers eat more, the land sets what comes in, and the count finds the level
# the land feeds. Every test past the first two is one of `world-growth-tone`'s
# rules stated as an assertion — rule 3 (perturb, run, observe return), and
# rules 1 and 2 (hunger costs growth, never a road, never a structure, never the
# city).

const SEED_A := 20260815
const SEED_B := 987654321

## AC3's horizon, and AC7's.
const LONG_RUN := 1000

## Turns a world runs before its population is read as "the level it settled
## at". Half the long run: the starting crew of four needs a few years to build
## the first surplus and a few more to climb.
const SETTLE_TURNS := 500

## A count above this after a thousand turns is a loop that did not settle. Not
## a cap in the simulation — nothing there knows this number — but a statement
## of what "bounded" means for one farm and one camp.
const RUNAWAY_BOUND := 40

## Turns of enforced hunger in the restoring-force and deprivation tests.
## Two years: long enough that `CityNode.LEAN_TURNS` fires, so the city actually
## loses people and "returns" has something to return from.
const DEPRIVATION_TURNS := Seasons.TURNS_PER_YEAR * 2

## Turns the city is left alone afterwards to find its level again.
const RECOVERY_TURNS := Seasons.TURNS_PER_YEAR * 20


# --- 1. eating and growing ---------------------------------------------------

func test_citizens_eat_from_the_granary_at_the_end_of_their_road() -> void:
	# AC1. Every person on a road asks its granary for `Citizen.APPETITE` once a
	# turn, whether or not they are standing at it.
	var world := _flat_world()
	var route := _built_city(world)
	var granary := route.sink
	granary.deposit(10.0)

	world.advance_turn()
	assert_eq(granary.mouths, route.carriers.size(), "every carrier ate from the granary")
	assert_almost_eq(
		granary.gave_out,
		Citizen.APPETITE * route.carriers.size(),
		0.0001,
		"and each took one turn's appetite"
	)
	assert_eq(route.source.mouths, 0, "nobody eats at the farm")


func test_a_granary_held_above_the_line_for_a_season_gains_a_person() -> void:
	# AC2. The stated fraction for the stated duration, and not a turn sooner.
	var world := _flat_world()
	var route := _built_city(world)
	var granary := route.sink
	var before := world.citizen_count()

	for i in range(CityNode.GROWTH_TURNS):
		assert_eq(world.citizen_count(), before, "no growth on turn %d of the season" % i)
		granary.store = granary.capacity
		world.advance_turn()

	assert_eq(world.citizen_count(), before + 1, "a season of plenty added one person")
	assert_eq(route.carriers.size(), before + 1, "who joined the road the granary serves")
	assert_eq(route.carriers[-1].coord, granary.coord, "and set out from the granary's door")


func test_a_new_person_joins_the_thinnest_road_into_the_granary() -> void:
	var world := WorldGen.generate(SEED_A)
	var granary := _granary(world)
	for i in range(CityNode.GROWTH_TURNS):
		granary.store = granary.capacity
		world.advance_turn()
	for i in range(CityNode.GROWTH_TURNS):
		granary.store = granary.capacity
		world.advance_turn()
	var sizes: Array[int] = []
	for route in world.routes:
		sizes.append(route.carriers.size())
	assert_eq(
		sizes,
		[CityGen.CITIZENS_PER_ROUTE + 1, CityGen.CITIZENS_PER_ROUTE + 1] as Array[int],
		"two seasons of plenty put one person on each road, not two on the first"
	)


# --- 2. the loop settles -----------------------------------------------------

func test_a_thousand_turns_reach_a_bounded_population() -> void:
	# AC3. Grows from the starting crew, then stops growing — and the bound is the
	# land's, since nothing in `sim/` knows `RUNAWAY_BOUND`.
	for world_seed in [SEED_A, SEED_B]:
		var world := WorldGen.generate(world_seed)
		var start := world.citizen_count()
		var counts := PackedInt32Array()
		for t in range(LONG_RUN):
			world.advance_turn()
			counts.append(world.citizen_count())

		var early := _band(counts, SETTLE_TURNS, SETTLE_TURNS + 250)
		var late := _band(counts, SETTLE_TURNS + 250, LONG_RUN)
		gut.p("seed %d: %d people at the start; turns 500-750 held %d..%d, turns 750-1000 held %d..%d; %s" % [
			world_seed, start, early[0], early[1], late[0], late[1], _every(counts, 100),
		])
		assert_gt(late[1], start, "seed %d: a fed city grew" % world_seed)
		assert_lte(late[1], RUNAWAY_BOUND, "seed %d: and did not run away" % world_seed)
		assert_lte(
			late[1], early[1] + 1,
			"seed %d: the last quarter is no higher than the third — it settled rather than climbing"
				% world_seed
		)
		assert_gte(
			late[0], start,
			"seed %d: and never fell below the crew it was founded with" % world_seed
		)


# --- 3. restoring force ------------------------------------------------------

func test_a_hungry_city_returns_toward_the_level_it_was_at() -> void:
	# AC4, rule 3: perturb, run forward, observe return. The perturbation is the
	# store taken away every turn for two years — long enough that people are
	# actually lost, so the return has somewhere to return from.
	var world := WorldGen.generate(SEED_A)
	for i in range(SETTLE_TURNS):
		world.advance_turn()
	var level := world.citizen_count()

	_deprive(world, DEPRIVATION_TURNS)
	var knocked := world.citizen_count()

	var counts := PackedInt32Array()
	for i in range(RECOVERY_TURNS):
		world.advance_turn()
		counts.append(world.citizen_count())
	var recovered := _band(counts, RECOVERY_TURNS - Seasons.TURNS_PER_YEAR * 5, RECOVERY_TURNS)

	gut.p("settled at %d, knocked down to %d, back to %d..%d over the last five years of twenty" % [
		level, knocked, recovered[0], recovered[1],
	])
	assert_lt(knocked, level, "two years of hunger did cost people — the perturbation was real")
	assert_gte(
		recovered[1], level - 1,
		"and fed again, the city climbed back to within one person of where it was"
	)


# --- 4. hunger never removes what was built ----------------------------------

func test_sustained_hunger_costs_people_and_never_a_road_or_the_city() -> void:
	# AC5, rules 1 and 2. Ten years with the granary emptied every turn.
	var world := WorldGen.generate(SEED_A)
	for i in range(SETTLE_TURNS):
		world.advance_turn()
	var nodes := world.nodes.size()
	var routes := world.routes.size()
	var floor_count := CityGen.CITIZENS_PER_ROUTE * routes

	var lowest := world.citizen_count()
	for i in range(Seasons.TURNS_PER_YEAR * 10):
		_deprive(world, 1)
		lowest = mini(lowest, world.citizen_count())

	assert_eq(world.nodes.size(), nodes, "every structure still stands")
	assert_eq(world.routes.size(), routes, "every road still exists")
	for route in world.routes:
		assert_gte(
			route.carriers.size(), CityGen.CITIZENS_PER_ROUTE,
			"road %d kept its founding crew" % route.id
		)
	assert_eq(lowest, floor_count, "ten hungry years bottom out at the founding crew, not at zero")

	for i in range(RECOVERY_TURNS):
		world.advance_turn()
	gut.p("ten hungry years: down to %d; twenty fed years later: %d" % [
		lowest, world.citizen_count(),
	])
	assert_gt(world.citizen_count(), floor_count, "and fed again, the city grows")


func test_one_bad_season_costs_nobody() -> void:
	# Rule 2's "never a single unlucky season", for the sharpest season there is:
	# the store emptied every turn for a whole season, inside a year that was
	# otherwise fed. Run across several years so the season lands at every point
	# in the hunger books, and a year's judgement is always included.
	var world := _flat_world()
	var route := _built_city(world)
	var granary := route.sink
	var lowest := world.citizen_count()
	var highest := lowest
	for t in range(Seasons.TURNS_PER_YEAR * 4):
		# One bad season in every year, and a different one each year.
		var year := t / Seasons.TURNS_PER_YEAR
		var bad := (t % Seasons.TURNS_PER_YEAR) / Seasons.TURNS_PER_SEASON == year % 4
		granary.store = 0.0 if bad else granary.capacity * 0.5
		world.advance_turn()
		assert_gte(world.citizen_count(), highest, "turn %d: nobody was lost" % t)
		highest = maxi(highest, world.citizen_count())
	gut.p("four years with one empty season each: %d people throughout" % highest)


# --- 5. the rule it is held to, and determinism ------------------------------

func test_the_granary_cannot_find_out_who_is_eating() -> void:
	# AC6, `AgDR-013`. Whoever eats reports a quantity to the store; the store and
	# the growth rule never ask what kind of agent they are dealing with. The node
	# side is already grepped by `test_gathering.gd`; this is the rule's side.
	var source := FileAccess.get_file_as_string("res://sim/city_gen.gd")
	var start := source.find("static func tend_population")
	assert_gt(start, -1, "found the growth rule")
	var end := source.find("\nstatic func _lose_carrier", start)
	var body := source.substr(start, end - start)
	for pattern in ["citizens(", "herds(", ".agents", " is "]:
		assert_false(body.contains(pattern), "the growth rule does not use `%s`" % pattern)


func test_two_worlds_from_one_seed_agree_after_a_thousand_turns() -> void:
	# AC7: population, stores and every agent's position.
	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)
	for i in range(LONG_RUN):
		first.advance_turn()
		second.advance_turn()
	assert_eq(first.citizen_count(), second.citizen_count(), "the same number of people")
	assert_eq(_digest(first), _digest(second), "in the same places, with the same stores")
	gut.p("after %d turns: %d people, %.2f grain in store" % [
		LONG_RUN, first.citizen_count(), first.total_granary_store(),
	])


# --- helpers -----------------------------------------------------------------

func _flat_world() -> WorldMap:
	var world := WorldMap.new(HexGrid.new(12, 10), SEED_A)
	for coord in world.grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.GRASS)
	return world


## A farm and a granary built through the player's calls, so the road's carriers
## are registered the way every real road's are.
func _built_city(world: WorldMap) -> Route:
	var farm_coord := HexGrid.from_offset(2, 4)
	var farm := CityGen.place_node(world, farm_coord, CityNode.Kind.FARM)
	var granary := CityGen.place_node(
		world, farm_coord + HexGrid.DIRECTIONS[0] * CityGen.ROUTE_LENGTH, CityNode.Kind.GRANARY
	)
	return CityGen.connect_nodes(world, farm, granary)


func _granary(world: WorldMap) -> CityNode:
	for node in world.nodes:
		if node.kind == CityNode.Kind.GRANARY:
			return node
	return null


## Run `turns` turns with every granary emptied before each one — what a city
## eats that turn has to come from that turn's deliveries alone.
func _deprive(world: WorldMap, turns: int) -> void:
	for i in range(turns):
		for node in world.nodes:
			if node.kind == CityNode.Kind.GRANARY:
				node.store = 0.0
		world.advance_turn()


## [lowest, highest] over `counts[from..to)`.
func _band(counts: PackedInt32Array, from: int, to: int) -> Array[int]:
	var lo := 1 << 30
	var hi := -1
	for i in range(from, to):
		lo = mini(lo, counts[i])
		hi = maxi(hi, counts[i])
	return [lo, hi]


func _every(counts: PackedInt32Array, stride: int) -> String:
	var parts := PackedStringArray()
	for i in range(stride - 1, counts.size(), stride):
		parts.append("t%d=%d" % [i + 1, counts[i]])
	return " ".join(parts)


func _digest(world: WorldMap) -> String:
	var parts: Array[String] = []
	for agent in world.agents:
		parts.append("%d@%s:%.6f" % [agent.id, agent.coord, agent.forage_demand()])
	for citizen in world.citizens():
		parts.append("carry%d:%.6f" % [citizen.id, citizen.carrying])
	for node in world.nodes:
		parts.append("%s%d:%.6f/%d/%d/%.6f" % [
			node.kind_name(), node.id, node.store, node.plentiful_turns, node.year_turns,
			node.year_unmet,
		])
	return "|".join(parts)
