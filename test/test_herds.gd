extends GutTest

# This is the suite the project exists to write. Everything before it establishes
# that a world can be generated and drawn; this asks whether the world *does*
# anything worth watching once it is left alone, and it is meant to fail loudly
# if the answer is no.
#
# Three failures it is built to catch, in order of how quietly they would
# otherwise arrive:
#
#   1. A world that settles. A population that finds a level and holds it passes
#      every test you would write about correctness while being a screensaver.
#      `test_the_world_does_not_settle_into_a_flat_line` is the check, and if it
#      ever needs noise injected to go green, the finding is that the dynamics
#      are not there — not that the test is too strict.
#   2. A world that dies. The intent file's third rule says systems have
#      restoring forces; a herd knocked down comes back. That is asserted here by
#      perturbing and running forward, not argued for in a comment.
#   3. A world that runs away. The same rule inverted, and the more likely
#      failure of the two given that nothing eats the herds.
#
# The thresholds below were read off the observed run and then pinned with
# headroom — every one of them prints what it measured, so a future retune can
# see the margin it has rather than guessing at it.

const SEED_A := 20260815
const SEED_B := 987654321

## The long horizon for the does-not-die / does-not-explode / does-not-flatten
## trio. Long enough that a slow drift in either direction has arrived.
const HORIZON := 1000

## Determinism horizon. Shorter, because it is run twice and compared tile for
## tile and herd for herd.
const DETERMINISM_TURNS := 500

## Total heads across the map must stay inside this band for the whole horizon.
## Observed: see the printed line in the run — these carry roughly 3x headroom
## below and above, so they catch extinction and runaway without freezing the
## tuning.
const POPULATION_FLOOR := 200.0
const POPULATION_CEILING := 6000.0

## High-to-low ratio of total population over the horizon. A world whose
## population varies by less than this is not visibly changing.
const MIN_POPULATION_SWING := 1.20

## Fraction of a herd removed by the resilience test, and how close to its
## pre-disturbance level it has to return.
const CULL_FRACTION := 0.80
const RECOVERY_TOLERANCE := 0.75
const RECOVERY_YEARS := 3


func test_a_generated_world_comes_with_herds_on_land() -> void:
	for world_seed in [SEED_A, SEED_B]:
		var world := WorldGen.generate(world_seed)
		var herds := world.herds()
		assert_gt(herds.size(), 0, "seed %d: the world is populated" % world_seed)
		for herd in herds:
			assert_true(
				world.grid.has_coord(herd.coord),
				"seed %d: herd %d is on the map" % [world_seed, herd.id]
			)
			assert_ne(
				world.terrain_at(herd.coord),
				WorldGen.Terrain.WATER,
				"seed %d: herd %d is not standing in the sea" % [world_seed, herd.id]
			)
			assert_gt(herd.population, 0.0, "seed %d: herd %d has animals in it" % [
				world_seed, herd.id,
			])


func test_a_herd_is_an_agent_and_the_base_type_knows_nothing_about_herds() -> void:
	# The base type is load-bearing for what comes next — citizens are the second
	# implementation — so this checks the boundary rather than the behaviour.
	var plain := Agent.new(7, Vector2i(2, 3))
	assert_eq(plain.coord, Vector2i(2, 3), "an agent has a position")
	assert_eq(plain.id, 7, "and a stable identity")

	var world := WorldGen.generate(SEED_A)
	var before := plain.coord
	plain.step(world)
	assert_eq(plain.coord, before, "a bare agent's turn does nothing at all")

	var herd: Agent = world.herds()[0]
	assert_true(herd is Agent, "a herd is an agent")
	assert_true(herd is Herd, "and the herd behaviour is the subclass's")


func test_a_fed_herd_grows_and_a_starved_one_thins() -> void:
	# The two halves of the feeding rule, isolated from the map by putting a herd
	# on a tile with a known forage and giving it a population far from the level
	# that tile supports.
	var world := WorldGen.generate(SEED_A)
	var species := Species.grazer()
	var meadow := _first_tile_of(world, WorldGen.Terrain.GRASS)
	var supported := species.heads_supported_by(world.forage_at(meadow))

	var small := Herd.new(900, meadow, species, supported * 0.25)
	world.add_agent(small)
	var crowded := Herd.new(901, _far_tile_of(world, WorldGen.Terrain.GRASS), species, supported * 4.0)
	world.add_agent(crowded)

	var small_before := small.population
	var crowded_before := crowded.population
	world.advance_turn()

	assert_gt(small.population, small_before, "a herd on more food than it needs grows")
	assert_lt(crowded.population, crowded_before, "a herd on less food than it needs thins")
	gut.p("tile supports %.0f heads: %.1f -> %.1f and %.1f -> %.1f" % [
		supported, small_before, small.population, crowded_before, crowded.population,
	])


func test_herds_follow_the_food_across_a_year() -> void:
	# Migration is the claim, so it is measured two ways: how far herds get from
	# where they started, and whether the tiles they are standing on at the worst
	# time of year are better than the map average. Distance alone would be
	# satisfied by wandering.
	for world_seed in [SEED_A, SEED_B]:
		var world := WorldGen.generate(world_seed)
		var herds := world.herds()
		var winter_under := 0.0
		var winter_map := 0.0
		var winter_samples := 0

		# Two distances, because migration is a round trip. The displacement at
		# the end of the year understates it by exactly as much as the herds
		# came back — which is the behaviour, not a measurement error — so the
		# furthest they got during the year is reported alongside it.
		var furthest := 0.0
		for i in range(Seasons.TURNS_PER_YEAR):
			world.advance_turn()
			furthest = maxf(furthest, _mean_displacement(herds))
			if world.season() == Seasons.Season.WINTER:
				winter_under += _mean_forage_under_herds(world)
				winter_map += _mean_land_forage(world)
				winter_samples += 1

		var mean_distance := _mean_displacement(herds)
		var under := winter_under / float(winter_samples)
		var across := winter_map / float(winter_samples)

		gut.p("seed %d: mean distance from start — %.2f tiles at year end, %.2f at its furthest; winter forage under herds %.3f vs map %.3f" % [
			world_seed, mean_distance, furthest, under, across,
		])
		assert_gt(
			mean_distance,
			1.0,
			"seed %d: herds end the year more than one tile from where they started" % world_seed
		)
		assert_gt(
			furthest,
			1.0,
			"seed %d: and got at least that far during it" % world_seed
		)
		assert_gt(
			under,
			across,
			"seed %d: in the trough season herds are on better-than-average ground" % world_seed
		)


func test_a_culled_herd_recovers_within_three_years() -> void:
	# The primary criterion. Two years of settling first so the herd is at its own
	# level rather than at whatever it was placed with, and every measurement is
	# taken at the same point in the year — comparing a spring peak against a
	# winter low would report a recovery failure that is just the season.
	var world := WorldGen.generate(SEED_A)
	for i in range(Seasons.TURNS_PER_YEAR * 2):
		world.advance_turn()

	var herd := world.herds()[0]
	var before := herd.population
	world.set_herd_population(herd, before * (1.0 - CULL_FRACTION))
	gut.p("herd %d cut from %.0f to %.0f heads on turn %d" % [
		herd.id, before, herd.population, world.turn,
	])

	var recovered_after := -1
	for year in range(RECOVERY_YEARS):
		for i in range(Seasons.TURNS_PER_YEAR):
			world.advance_turn()
		gut.p("  +%d year: %.0f heads (%.0f%% of pre-disturbance)" % [
			year + 1, herd.population, 100.0 * herd.population / before,
		])
		if recovered_after < 0 and herd.population >= before * RECOVERY_TOLERANCE:
			recovered_after = year + 1

	assert_gt(
		recovered_after,
		-1,
		"observed recovery time: %s year(s) to reach %.0f%% of %.0f heads"
			% ["none within %d" % RECOVERY_YEARS if recovered_after < 0 else recovered_after,
				RECOVERY_TOLERANCE * 100.0, before]
	)
	gut.p("observed recovery time: %d year(s) after an %.0f%% cull" % [
		recovered_after, CULL_FRACTION * 100.0,
	])


func test_the_world_neither_dies_nor_runs_away_over_a_thousand_turns() -> void:
	var totals := _population_series(SEED_A, HORIZON)
	var low: float = totals.min()
	var high: float = totals.max()
	gut.p("%d turns: low %.0f, high %.0f, final %.0f (floor %.0f, ceiling %.0f)" % [
		HORIZON, low, high, totals[-1], POPULATION_FLOOR, POPULATION_CEILING,
	])

	assert_gt(low, 0.0, "the world never empties")
	assert_gt(low, POPULATION_FLOOR, "and never drops below the stated floor")
	assert_lt(high, POPULATION_CEILING, "nor above the stated ceiling")


func test_the_world_does_not_settle_into_a_flat_line() -> void:
	# The one that matters. A world that finds a level and holds it is the exact
	# failure this ticket exists to detect, and it must fail here rather than be
	# discovered by someone watching it and losing interest.
	var totals := _population_series(SEED_A, HORIZON)
	var low: float = totals.min()
	var high: float = totals.max()
	var swing := high / low
	gut.p("population swing over %d turns: %.2fx (%.0f..%.0f)" % [HORIZON, swing, low, high])
	assert_gte(
		swing,
		MIN_POPULATION_SWING,
		"total population varies by at least %.0f%% between its high and its low"
			% ((MIN_POPULATION_SWING - 1.0) * 100.0)
	)

	# And not just once at the start: the second half of the run has to move too,
	# or the world settled after an interesting opening.
	var tail := totals.slice(totals.size() / 2)
	var tail_swing: float = tail.max() / tail.min()
	gut.p("second half alone: %.2fx" % tail_swing)
	assert_gte(tail_swing, MIN_POPULATION_SWING, "the late world is still moving")


func test_two_worlds_from_one_seed_stay_identical_with_populations_in_them() -> void:
	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)
	# An unrelated world advanced in between, because the failure being looked for
	# is agent state leaking between worlds through something shared.
	var noise := WorldGen.generate(SEED_B)

	for i in range(DETERMINISM_TURNS):
		first.advance_turn()
		noise.advance_turn()
		second.advance_turn()

	assert_eq(first.forage_data(), second.forage_data(), "the maps still agree")

	var a := first.herds()
	var b := second.herds()
	assert_eq(a.size(), b.size(), "the same number of herds")
	var mismatches: Array[String] = []
	for i in range(a.size()):
		if a[i].coord != b[i].coord or a[i].population != b[i].population:
			mismatches.append("herd %d: %s/%.6f vs %s/%.6f" % [
				a[i].id, a[i].coord, a[i].population, b[i].coord, b[i].population,
			])
	assert_eq(
		mismatches.size(),
		0,
		"herds differing after %d turns: %s" % [DETERMINISM_TURNS, mismatches.slice(0, 5)]
	)


func test_a_populated_thousand_turns_is_still_cheap_enough_to_test_with() -> void:
	# Every test above runs the world forward; if the loop gets expensive the
	# suite stops being able to ask long-horizon questions, which is the same as
	# not being able to ask them.
	var world := WorldGen.generate(SEED_A)
	var started := Time.get_ticks_usec()
	for i in range(HORIZON):
		world.advance_turn()
	var elapsed_msec := float(Time.get_ticks_usec() - started) / 1000.0
	gut.p("%d turns with %d herds in %.1fms" % [HORIZON, world.herds().size(), elapsed_msec])
	assert_lt(elapsed_msec, 6000.0, "%d turns took %.1fms" % [HORIZON, elapsed_msec])


func _population_series(world_seed: int, turns: int) -> Array[float]:
	var world := WorldGen.generate(world_seed)
	var out: Array[float] = []
	for i in range(turns):
		world.advance_turn()
		out.append(world.total_herd_population())
	return out


func _mean_displacement(herds: Array[Herd]) -> float:
	var moved := 0.0
	for herd in herds:
		moved += float(HexGrid.distance(herd.coord, herd.start_coord))
	return moved / float(herds.size())


func _mean_forage_under_herds(world: WorldMap) -> float:
	var total := 0.0
	for herd in world.herds():
		total += world.forage_at(herd.coord)
	return total / float(world.herds().size())


func _mean_land_forage(world: WorldMap) -> float:
	var total := 0.0
	var count := 0
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) != WorldGen.Terrain.WATER:
			total += world.forage_at(coord)
			count += 1
	return total / float(count)


func _first_tile_of(world: WorldMap, terrain: int) -> Vector2i:
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == terrain and world.forage_demand_at(coord) == 0.0:
			return coord
	fail_test("the map has no empty tile of terrain %d to check" % terrain)
	return Vector2i.ZERO


func _far_tile_of(world: WorldMap, terrain: int) -> Vector2i:
	var found := Vector2i.ZERO
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == terrain and world.forage_demand_at(coord) == 0.0:
			found = coord
	return found
