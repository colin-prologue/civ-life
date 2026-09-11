extends GutTest

# The first piece of a city, and the first real test of the claim `AgDR-002`
# rests on: that citizens and herds are one kind of thing rather than two
# systems sharing a coordinate space.
#
# The suite is in two halves and the first one matters more.
#
#   1. **Is the unification real?** `test_the_base_agent_type_has_no_kind_checks`
#      reads `sim/agent.gd` and fails if the base type asks what kind of agent it
#      is holding, and `test_the_base_agent_type_has_only_the_methods_it_claims`
#      enumerates its methods so "no method branches" is checked by listing the
#      methods rather than by trusting a grep. `AgDR-002` names this as its own
#      refutation signal: a shared class with no shared behaviour would be worse
#      than two honest systems, and the finding would be worth more than the
#      feature.
#
#   2. **Does grain move, and does the world reach it?** Production, delivery,
#      seasonality, and what happens when something is standing in the road.
#
# Most of the second half runs on a flat, herd-free world built by hand rather
# than on a generated one. That is not avoidance of the real thing — the
# generated world is exercised by the criteria that are about it (placement,
# end-to-end flow, determinism). It is because "delivery falls when a herd is in
# the way" is a claim about a difference between two runs, and a generated world
# has fourteen herds wandering through the measurement.

## The seed the rest of the project measures things on.
const SEED_A := 20260815

## Determinism horizon, matching `test_herds.gd`.
const DETERMINISM_TURNS := 500

## Years the seasonal-delivery measurement runs for, and how many it discards
## first. The opening year is skipped because a route starts empty: the first
## carrier reaches the granary part-way through spring, so year one is short by
## one delivery through nothing but the world having just begun.
const SEASONAL_YEARS := 8
const SEASONAL_WARMUP_YEARS := 1

## Stated margins for AC6. Two of them, because they say different things.
##
## `MIN_SPRING_OVER_WINTER` compares the peak *forage* season against the trough
## one. `MIN_PEAK_OVER_TROUGH` compares the best delivery season against the
## worst, whichever they turn out to be — which is the wider claim and the one
## with room in it, because deliveries lag production by the time it takes to
## walk the road. See the note on that test.
const MIN_SPRING_OVER_WINTER := 1.30
const MIN_PEAK_OVER_TROUGH := 2.00

## The values the stated margins must not fall below, and the ceiling the
## obstruction share must not rise above.
##
## These exist because lowering a margin is the cheapest way to make a real
## regression look like a passing suite, and a plan that says "re-derive the
## expectation, never weaken the assertion" is prose — it competes with a
## delivery incentive and prose loses. This is the same claim at the altitude
## the implementer actually works at: a second failing test.
##
## It is a tripwire, not a lock. Someone determined can edit these too. What it
## buys is that doing so is deliberate, appears in the diff as its own change,
## and cannot happen as a quiet one-line adjustment while chasing a red suite.
## Raising a margin is always fine and these do not object to it.
##
## If a change genuinely warrants moving one of these, move it in its own commit
## and say why in the message.
const SPRING_OVER_WINTER_FLOOR := 1.30
const PEAK_OVER_TROUGH_FLOOR := 2.00
const OBSTRUCTED_SHARE_CEILING := 0.60

## How much of the control run's throughput a route with a herd parked on it is
## allowed to still manage. Interference has to be visible to be worth having;
## this is what "visible" means numerically.
const MAX_OBSTRUCTED_SHARE := 0.60

## Turns the obstruction test runs for. Long enough that the difference between
## the two runs is a trend rather than a phase of the walking cycle.
const OBSTRUCTION_TURNS := 120


# --- 1. the unification ------------------------------------------------------

func test_the_base_agent_type_has_no_kind_checks() -> void:
	# AC4, and the reason this ticket was worth doing in this order. If the base
	# type has to know what is standing on the tile, the movement layer is two
	# systems in a trench coat and `AgDR-002` is refuted rather than supported.
	#
	# Comments are stripped before scanning, on purpose: the file is allowed to
	# *talk* about herds and citizens — explaining why the base knows nothing
	# about them is exactly what its documentation is for — and forbidden to act
	# on them.
	var source := _read_source("res://sim/agent.gd")
	assert_gt(source.length(), 0, "the base agent source was actually read")
	var code := _strip_comments(source)

	var forbidden := {
		"a type test": "\\bis\\s+[A-Z]",
		"a downcast": "\\bas\\s+[A-Z]",
		"a class name lookup": "get_class\\s*\\(",
		"a script lookup": "get_script\\s*\\(",
		"a kind field": "\\.kind\\b",
		"a named-kind flag": "is_(citizen|herd|agent_kind)",
	}
	for description in forbidden:
		var regex := RegEx.new()
		regex.compile(forbidden[description])
		var found := regex.search(code)
		assert_null(
			found,
			"sim/agent.gd contains %s: %s" % [
				description, "" if found == null else found.get_string()
			]
		)


func test_the_base_agent_type_has_only_the_methods_it_claims() -> void:
	# The grep above proves no method branches on kind. This proves there are no
	# other methods for it to have missed — the two together are what make AC4 an
	# assertion rather than a hope.
	var declared: Array[String] = []
	for method in Agent.new(0, Vector2i.ZERO).get_script().get_script_method_list():
		declared.append(method["name"])
	declared.sort()
	assert_eq(
		declared,
		["_init", "forage_demand", "step"] as Array[String],
		"the base agent's whole surface: a constructor, a turn, and a quantity"
	)


func test_a_citizen_and_a_herd_are_the_same_kind_of_thing() -> void:
	# AC3. Not a parallel class, and not a class that merely inherits: both are
	# stepped by the same loop through the same mutator, and the world's agent
	# list holds them together without knowing which is which.
	var world := WorldGen.generate(SEED_A)
	assert_gt(world.citizens().size(), 0, "the generated world has people in it")
	assert_gt(world.herds().size(), 0, "and animals")

	var citizen: Agent = world.citizens()[0]
	assert_true(citizen is Agent, "a citizen is an agent")
	assert_eq(
		world.agents.size(),
		world.citizens().size() + world.herds().size(),
		"and both live in the one list the turn loop walks"
	)
	assert_eq(citizen.forage_demand(), 0.0, "a citizen does not graze the tile it stands on")
	assert_gt(world.herds()[0].forage_demand(), 0.0, "a herd does")


# --- 2. structures and roads -------------------------------------------------

func test_a_farm_produces_with_the_season_and_a_granary_only_receives() -> void:
	# AC1, isolated from everything else: the two node kinds, one turn each.
	var world := _flat_world()
	var coord := HexGrid.from_offset(3, 4)
	var farm := CityNode.new(0, coord, CityNode.Kind.FARM)
	var granary := CityNode.new(1, HexGrid.from_offset(6, 4), CityNode.Kind.GRANARY)
	world.add_node(farm)
	world.add_node(granary)

	world.advance_turn()
	var spring := farm.store
	assert_gt(spring, 0.0, "a farm grows something in spring")
	assert_eq(granary.store, 0.0, "a granary grows nothing at all")

	# Forward to the trough of the year and compare one turn against one turn.
	farm.store = 0.0
	while world.season() != Seasons.Season.WINTER:
		world.advance_turn()
		farm.store = 0.0
	world.advance_turn()
	var winter := farm.store
	gut.p("one turn of farm output: %.3f in spring, %.3f in winter" % [spring, winter])
	assert_gt(spring, winter, "and less of it in winter, because the tile grows less")


func test_a_granary_will_not_hold_more_than_its_capacity() -> void:
	var granary := CityNode.new(0, Vector2i.ZERO, CityNode.Kind.GRANARY, 10.0)
	assert_eq(granary.deposit(4.0), 4.0, "an empty granary takes what it is given")
	assert_eq(granary.deposit(99.0), 6.0, "and then only what still fits")
	assert_eq(granary.store, 10.0, "never more than its capacity")
	assert_eq(granary.withdraw(99.0), 10.0, "and gives back no more than it holds")


func test_a_route_is_an_ordered_walkable_path_between_two_nodes() -> void:
	# AC2. Placed explicitly; the only geometry involved is a straight line, and
	# it has to come out walkable one tile to the next.
	var world := _flat_world()
	var route := _lay_city(world, HexGrid.from_offset(3, 4), 4, 1)
	assert_eq(route.path[0], route.source.coord, "the road starts at the farm")
	assert_eq(route.path[-1], route.sink.coord, "and ends at the granary")
	assert_eq(route.length(), 5, "with every tile between them named")
	assert_true(Route.is_contiguous(route.path), "and each tile a step from the last")
	assert_true(route.passes_through(route.path[2]), "a tile on the road is on the road")
	assert_false(route.passes_through(HexGrid.from_offset(9, 9)), "and one off it is not")


func test_a_generated_world_comes_with_a_farm_a_granary_a_road_and_people() -> void:
	# The city is two spokes out of one granary: a farm on one and a gathering
	# camp on the other. The camp is asserted here rather than in
	# `test_gathering.gd` because what is being checked is the *city's* shape —
	# that the second kind of production arrives through the same road-and-carrier
	# arrangement as the first, with no transport of its own.
	for world_seed in [SEED_A, 987654321]:
		var world := WorldGen.generate(world_seed)
		var kinds := {}
		for node in world.nodes:
			kinds[node.kind] = true
			assert_ne(
				world.terrain_at(node.coord),
				WorldGen.Terrain.WATER,
				"seed %d: nothing is built in the sea" % world_seed
			)
		assert_true(kinds.has(CityNode.Kind.FARM), "seed %d: there is a farm" % world_seed)
		assert_true(kinds.has(CityNode.Kind.GRANARY), "seed %d: and a granary" % world_seed)
		assert_true(kinds.has(CityNode.Kind.GATHERING), "seed %d: and a camp" % world_seed)
		assert_eq(world.routes.size(), 2, "seed %d: joined by a road each" % world_seed)
		assert_eq(
			world.citizens().size(),
			CityGen.CITIZENS_PER_ROUTE * world.routes.size(),
			"seed %d: with people on both" % world_seed
		)
		for route in world.routes:
			assert_eq(
				route.sink.kind,
				CityNode.Kind.GRANARY,
				"seed %d: every road ends at the granary" % world_seed
			)
			for coord in route.path:
				assert_ne(
					world.terrain_at(coord),
					WorldGen.Terrain.WATER,
					"seed %d: the road stays out of the water" % world_seed
				)


# --- 3. grain moves ----------------------------------------------------------

func test_grain_reaches_a_connected_granary_and_not_an_unconnected_one() -> void:
	# AC5, on the standard seed and on the world the game actually generates.
	# The unconnected granary is the control: without it, "the number went up"
	# is equally consistent with granaries simply filling themselves.
	var world := WorldGen.generate(SEED_A)
	var orphan := CityNode.new(
		world.nodes.size(), _empty_land(world), CityNode.Kind.GRANARY
	)
	world.add_node(orphan)

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	var connected := _sink_of(world.routes[0])
	gut.p("after one year: connected granary %.2f, unconnected %.2f" % [
		connected.store, orphan.store,
	])
	assert_gt(connected.store, 0.0, "a granary on the end of a road has grain in it")
	assert_eq(orphan.store, 0.0, "a granary with no road to it has none")


func test_a_citizen_carries_grain_one_way_and_walks_back_empty() -> void:
	# The behaviour behind AC3, watched turn by turn rather than inferred from a
	# total. What is being checked is that direction follows the load: nothing in
	# the citizen stores which way it is going.
	var world := _flat_world()
	var route := _lay_city(world, HexGrid.from_offset(3, 4), 2, 1)
	var citizen := world.citizens()[0]

	world.advance_turn()
	assert_gt(citizen.carrying, 0.0, "picks up at the farm")
	assert_eq(citizen.coord, route.path[1], "and sets off")

	world.advance_turn()
	assert_eq(citizen.coord, route.path[2], "arrives at the granary")

	world.advance_turn()
	assert_gt(route.sink.store, 0.0, "puts the grain down")
	assert_eq(citizen.carrying, 0.0, "and is empty again")
	assert_eq(citizen.coord, route.path[1], "heading back for the next load")


func test_the_seasons_reach_the_granary() -> void:
	# AC6. Grain delivered per season, over years, on the configuration the game
	# actually ships — flat grass so the only thing varying is the calendar.
	#
	# The measured peak is one season behind the forage peak, and that is
	# physical rather than a measurement error: grain delivered in early summer
	# was grown in late spring, because somebody had to walk it there. It is the
	# reason this test states two margins. Spring-over-winter is the literal
	# criterion and it survives the lag with less room. Peak-over-trough asks the
	# question the criterion is *for* — does the city's year have a shape — and
	# has room to spare.
	#
	# The lag is proportional to route length, and long roads smear it badly
	# enough to invert the ordering entirely. That is what fixes
	# `CityGen.ROUTE_LENGTH` at a short road for now, and it is worth knowing
	# before roads become something the player draws.
	var world := _flat_world()
	var route := _lay_city(
		world, HexGrid.from_offset(2, 4), CityGen.ROUTE_LENGTH, CityGen.CITIZENS_PER_ROUTE
	)
	var granary := route.sink

	for i in range(SEASONAL_WARMUP_YEARS * Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	var delivered := {}
	for season in Seasons.SEASON_ORDER:
		delivered[season] = 0.0
	var previous := granary.store
	for i in range(SEASONAL_YEARS * Seasons.TURNS_PER_YEAR):
		world.advance_turn()
		delivered[world.season()] += granary.store - previous
		previous = granary.store

	var report: Array[String] = []
	var peak := 0.0
	var trough := INF
	for season in Seasons.SEASON_ORDER:
		report.append("%s %.1f" % [Seasons.season_name(season), delivered[season]])
		peak = maxf(peak, delivered[season])
		trough = minf(trough, delivered[season])
	gut.p("grain delivered over %d years — %s" % [SEASONAL_YEARS, ", ".join(report)])
	gut.p("spring/winter %.2fx (margin %.2f), peak/trough %.2fx (margin %.2f)" % [
		delivered[Seasons.Season.SPRING] / delivered[Seasons.Season.WINTER],
		MIN_SPRING_OVER_WINTER,
		peak / trough,
		MIN_PEAK_OVER_TROUGH,
	])

	assert_gt(trough, 0.0, "grain arrives in every season — the city does not stop")
	assert_gt(
		delivered[Seasons.Season.SPRING],
		delivered[Seasons.Season.WINTER] * MIN_SPRING_OVER_WINTER,
		"the peak forage season delivers at least %.2fx the trough season"
			% MIN_SPRING_OVER_WINTER
	)
	assert_gt(
		peak,
		trough * MIN_PEAK_OVER_TROUGH,
		"and the year has a shape: best season is at least %.2fx the worst"
			% MIN_PEAK_OVER_TROUGH
	)


# --- 4. the wild layer touches the city --------------------------------------

func test_a_herd_standing_on_a_road_slows_it_down() -> void:
	# AC7. Two runs identical but for one animal in the way, which is the only
	# way "throughput fell" means anything.
	var control := _obstructed_run(false)
	var obstructed := _obstructed_run(true)
	var share: float = obstructed["delivered"] / control["delivered"]

	gut.p("%d turns: %.1f grain delivered with a clear road, %.1f with a herd on it (%.0f%%)" % [
		OBSTRUCTION_TURNS, control["delivered"], obstructed["delivered"], share * 100.0,
	])
	assert_gt(control["delivered"], 0.0, "the control run delivered something to compare against")
	assert_lt(
		share,
		MAX_OBSTRUCTED_SHARE,
		"a herd in the road costs the city more than %.0f%% of its deliveries"
			% ((1.0 - MAX_OBSTRUCTED_SHARE) * 100.0)
	)


func test_a_herd_in_the_road_slows_the_city_and_never_breaks_it() -> void:
	# AC8, and `world-growth-tone` rule 1 stated as an assertion. The world is
	# allowed to interrupt a flow. It is not allowed to remove anything that was
	# built, to unmake a road, or to take back grain already stored.
	var run := _obstructed_run(true)
	var world: WorldMap = run["world"]

	assert_eq(world.nodes.size(), 2, "both structures are still standing")
	assert_eq(world.routes.size(), 1, "and the road between them still exists")
	assert_eq(
		world.routes[0].length(),
		CityGen.ROUTE_LENGTH + 1,
		"unchanged, tile for tile"
	)
	assert_eq(run["decreases"], 0, "stored grain never went down at any point in the run")
	assert_gt(run["delivered"], 0.0, "and the road kept working, slowly — it was never severed")

	# The citizens are still doing their job rather than parked forever on the
	# tile they were held up on: that is what `Citizen.MAX_HELD_UP` is for.
	for citizen in world.citizens():
		assert_gt(
			world.routes[0].index_of(citizen.coord),
			-1,
			"citizen %d is still somewhere on its route" % citizen.id
		)


func test_the_road_recovers_the_moment_the_herd_moves_on() -> void:
	# The other half of rule 1: interference is temporary. A reduction the city
	# never comes back from is a broken route wearing a slowdown's clothes.
	var world := _flat_world()
	var route := _lay_city(
		world, HexGrid.from_offset(2, 4), CityGen.ROUTE_LENGTH, CityGen.CITIZENS_PER_ROUTE
	)
	var herd := Herd.new(500, route.path[1], _penned_species(), 40.0)
	world.add_agent(herd)

	var window := OBSTRUCTION_TURNS / 2
	for i in range(window):
		world.advance_turn()
	var during := route.sink.store

	# The herd wanders off the road. Nothing else changes.
	world.move_agent(herd, _off_route_tile(world, route))
	var before_after := route.sink.store
	for i in range(window):
		world.advance_turn()
	var after := route.sink.store - before_after

	gut.p("%d turns blocked delivered %.1f; the same span after it left delivered %.1f" % [
		window, during, after,
	])
	assert_gt(after, during, "throughput returns once the road is clear")


# --- 5. determinism ----------------------------------------------------------

func test_two_worlds_from_one_seed_agree_about_the_city_after_five_hundred_turns() -> void:
	# AC9. The herd suite already compares herds; this compares everything the
	# city carries forward, which is the state this ticket added.
	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)
	# An unrelated world advanced in between, because the failure being looked
	# for is state leaking between worlds through something shared.
	var noise := WorldGen.generate(987654321)

	for i in range(DETERMINISM_TURNS):
		first.advance_turn()
		noise.advance_turn()
		second.advance_turn()

	assert_eq(first.forage_data(), second.forage_data(), "the maps still agree")
	assert_eq(_state_digest(first), _state_digest(second),
		"and so does every agent and every store after %d turns" % DETERMINISM_TURNS)
	gut.p("after %d turns: %.2f grain stored, citizens at %s" % [
		DETERMINISM_TURNS,
		first.total_stored_grain(),
		_citizen_coords(first),
	])
	assert_gt(first.total_granary_store(), 0.0, "and the city got somewhere in the meantime")


# --- helpers -----------------------------------------------------------------

## A featureless world of one terrain, with nothing alive on it. Everything that
## measures a *difference* runs here, because a generated world has fourteen
## herds walking through the measurement.
func _flat_world(width := 12, height := 10, terrain := WorldGen.Terrain.GRASS) -> WorldMap:
	var world := WorldMap.new(HexGrid.new(width, height), SEED_A)
	for coord in world.grid.all_coords():
		world.set_terrain(coord, terrain)
	return world


## Farm, granary `steps` tiles away in a straight line, the road between them,
## and `citizens` people spread along it exactly as `CityGen` spreads them.
func _lay_city(world: WorldMap, farm_coord: Vector2i, steps: int, citizens: int) -> Route:
	var direction: Vector2i = HexGrid.DIRECTIONS[0]
	var granary_coord := farm_coord + direction * steps
	assert_true(world.grid.has_coord(granary_coord), "the test's road fits on the test's map")

	var farm := CityNode.new(0, farm_coord, CityNode.Kind.FARM)
	var granary := CityNode.new(1, granary_coord, CityNode.Kind.GRANARY)
	world.add_node(farm)
	world.add_node(granary)

	var route := Route.new(0, farm, granary, HexGrid.line(farm_coord, granary_coord))
	world.add_route(route)
	for i in range(citizens):
		var start := (i * (route.length() - 1)) / maxi(1, citizens - 1)
		world.add_agent(Citizen.new(i, route, start))
	return route


## One run of the obstruction experiment. Identical either way but for the animal
## standing on the middle of the road.
##
## The herd is of a species that does not move rather than a real herd nudged
## back into place every turn: pinning it by hand each turn would be the test
## reaching into the simulation between steps, and this way the run is exactly
## `advance_turn()` repeated.
func _obstructed_run(with_herd: bool) -> Dictionary:
	var world := _flat_world()
	var route := _lay_city(
		world, HexGrid.from_offset(2, 4), CityGen.ROUTE_LENGTH, CityGen.CITIZENS_PER_ROUTE
	)
	if with_herd:
		world.add_agent(Herd.new(500, route.path[1], _penned_species(), 40.0))

	var decreases := 0
	var previous := route.sink.store
	for i in range(OBSTRUCTION_TURNS):
		world.advance_turn()
		if route.sink.store < previous:
			decreases += 1
		previous = route.sink.store

	return {
		"world": world,
		"delivered": route.sink.store,
		"decreases": decreases,
	}


## A herd that stays where it is put: same appetite as the real one, no range to
## move or sense with, so `Herd._migrate` has nowhere to go.
func _penned_species() -> Species:
	return Species.new("penned herd", 0.006, 0.070, 0.110, 0, 0, 2.0, 40.0)


func _off_route_tile(world: WorldMap, route: Route) -> Vector2i:
	for coord in world.grid.all_coords():
		if not route.passes_through(coord):
			return coord
	fail_test("the test map is entirely road")
	return Vector2i.ZERO


func _empty_land(world: WorldMap) -> Vector2i:
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			continue
		var taken := false
		for node in world.nodes:
			if node.coord == coord:
				taken = true
		if not taken:
			return coord
	fail_test("the map has nowhere to put another structure")
	return Vector2i.ZERO


func _sink_of(route: Route) -> CityNode:
	return route.sink


## Everything about a world that survives a turn, as one comparable string.
func _state_digest(world: WorldMap) -> String:
	var parts: Array[String] = []
	for agent in world.agents:
		parts.append("%s@%s:%.6f" % [agent.id, agent.coord, agent.forage_demand()])
	for citizen in world.citizens():
		parts.append("carry%d:%.6f" % [citizen.id, citizen.carrying])
	for node in world.nodes:
		parts.append("%s%d:%.6f" % [node.kind_name(), node.id, node.store])
	return "|".join(parts)


func _citizen_coords(world: WorldMap) -> String:
	var parts: Array[String] = []
	for citizen in world.citizens():
		parts.append(str(citizen.coord))
	return ", ".join(parts)


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "could not open %s" % path)
	if file == null:
		return ""
	return file.get_as_text()


## Everything from a `#` to the end of its line. Crude — it would eat a `#` in a
## string literal — and correct enough for a file that contains no string
## literals, which the grep test's own assertion about the method list keeps
## true.
func _strip_comments(source: String) -> String:
	var out: Array[String] = []
	for line in source.split("\n"):
		var hash_at := line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)


func test_the_stated_margins_have_not_been_quietly_weakened() -> void:
	# See the note on the floor constants above. This asserts the claims this
	# suite makes about the world are still as strong as they were stated to be.
	assert_gte(
		MIN_SPRING_OVER_WINTER, SPRING_OVER_WINTER_FLOOR,
		"the spring-over-winter margin was lowered from %.2f to %.2f"
			% [SPRING_OVER_WINTER_FLOOR, MIN_SPRING_OVER_WINTER]
	)
	assert_gte(
		MIN_PEAK_OVER_TROUGH, PEAK_OVER_TROUGH_FLOOR,
		"the peak-over-trough margin was lowered from %.2f to %.2f"
			% [PEAK_OVER_TROUGH_FLOOR, MIN_PEAK_OVER_TROUGH]
	)
	assert_lte(
		MAX_OBSTRUCTED_SHARE, OBSTRUCTED_SHARE_CEILING,
		"the obstruction margin was loosened from %.2f to %.2f"
			% [OBSTRUCTED_SHARE_CEILING, MAX_OBSTRUCTED_SHARE]
	)
