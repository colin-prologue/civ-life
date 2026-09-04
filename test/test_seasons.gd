extends GutTest

# The failure this suite exists to prevent is a season that is only a caption:
# the label changes, the world does not, and the herds ticket built on top of it
# inherits a map that is secretly static. So the checks are on summed forage and
# on tiles, never on the name of the season.
#
# The other half is time. Determinism after one turn is nearly free and proves
# almost nothing; anything that accumulates — a float nudged per turn, a value
# fed back into itself — only shows up after a hundred. Every check here that
# could be run for one turn is run for many.

const SEED_A := 20260815
const SEED_B := 987654321

## Long enough that anything accumulating per turn has had room to accumulate,
## and not a whole number of years, so the worlds are compared mid-season.
const LONG_RUN := 137

## The no-drift horizon. Also the performance budget below, because a project
## that cannot afford to run this far cannot afford the test that proves it does
## not drift.
const HORIZON := 500

## Advancing `HORIZON` turns must fit in this. Stated as a budget for later
## tickets: a long-horizon ecology test is only writable if a long horizon is
## cheap.
const HORIZON_BUDGET_MSEC := 2000.0

## How much more the best season must feed than the worst. A seasonal cycle that
## moves the total less than this is decoration.
const MIN_SEASONAL_SWING := 1.5


func test_a_fresh_world_starts_in_spring_of_year_one() -> void:
	var world := WorldGen.generate(SEED_A)
	assert_eq(world.turn, 0, "a fresh world has not been advanced")
	assert_eq(world.season(), Seasons.Season.SPRING, "and it starts in spring")
	assert_eq(world.year(), 1, "counted from year one, not year zero")


func test_seasons_cycle_in_order_and_wrap() -> void:
	# Expectations are derived from the constant rather than written out, so
	# retuning the year length retunes this test with it. A hard-coded turn
	# number here would make the constant a lie the first time it moved.
	var world := WorldGen.generate(SEED_A)
	var seen: Array[int] = [world.season()]
	for turn in range(1, Seasons.TURNS_PER_YEAR * 2 + 1):
		world.advance_turn()
		var expected: int = Seasons.SEASON_ORDER[
			(turn / Seasons.TURNS_PER_SEASON) % Seasons.SEASON_ORDER.size()
		]
		assert_eq(world.season(), expected, "turn %d falls in the right season" % turn)
		if seen.is_empty() or seen[-1] != world.season():
			seen.append(world.season())

	# Two full years of it: the order is the order, and the second year is not a
	# different order that happens to start the same way.
	var order := Seasons.SEASON_ORDER
	assert_eq(seen.size(), 9, "the starting season plus eight changes: %s" % [seen])
	for i in range(seen.size()):
		assert_eq(seen[i], order[i % order.size()], "season %d of the run is in cycle order" % i)

	assert_eq(world.turn, Seasons.TURNS_PER_YEAR * 2, "two years elapsed")
	assert_eq(world.year(), 3, "and the world is into the third")


func test_a_year_is_four_seasons_of_the_named_length() -> void:
	assert_eq(
		Seasons.TURNS_PER_YEAR,
		Seasons.TURNS_PER_SEASON * Seasons.SEASON_ORDER.size(),
		"the year is derived from the season length, not written down twice"
	)
	assert_eq(Seasons.SEASON_ORDER.size(), 4, "four seasons")


func test_every_tile_carries_forage_inside_its_bounds() -> void:
	for world_seed in [SEED_A, SEED_B]:
		var world := WorldGen.generate(world_seed)
		assert_eq(
			world.forage_data().size(),
			world.grid.tile_count(),
			"seed %d: every tile carries a forage value" % world_seed
		)
		for coord in world.grid.all_coords():
			assert_between(
				world.forage_at(coord),
				Seasons.MIN_FORAGE,
				Seasons.MAX_FORAGE,
				"seed %d: tile %s is in bounds" % [world_seed, coord]
			)


func test_land_feeds_something_and_water_never_does() -> void:
	# Without this, "forage is in bounds" is satisfied by a map of zeroes.
	var world := WorldGen.generate(SEED_A)
	for turn in range(Seasons.TURNS_PER_YEAR):
		var fed_land := 0
		for coord in world.grid.all_coords():
			var is_water := world.terrain_at(coord) == WorldGen.Terrain.WATER
			if is_water:
				assert_eq(world.forage_at(coord), 0.0, "water feeds nothing at %s" % coord)
			elif world.forage_at(coord) > 0.0:
				fed_land += 1
		assert_gt(fed_land, 0, "turn %d has land that feeds something" % world.turn)
		world.advance_turn()


func test_the_peak_season_feeds_at_least_half_again_the_trough() -> void:
	# The load-bearing test in this file. Summed over the actual map, so a season
	# that changes a label without changing what the world can support fails here
	# rather than being discovered by whatever is built on top of it.
	var world := WorldGen.generate(SEED_A)
	var totals := {}
	for turn in range(Seasons.TURNS_PER_YEAR):
		totals[world.season()] = world.total_forage()
		world.advance_turn()

	assert_eq(totals.size(), Seasons.SEASON_ORDER.size(), "one total per season")

	var peak := 0.0
	var trough := INF
	var report: Array[String] = []
	for season in Seasons.SEASON_ORDER:
		var total: float = totals[season]
		report.append("%s %.0f" % [Seasons.season_name(season), total])
		peak = maxf(peak, total)
		trough = minf(trough, total)
	gut.p("map forage by season: %s" % ", ".join(report))

	assert_gt(trough, 0.0, "the trough is not zero — a divide by nothing proves nothing")
	assert_gte(
		peak / trough,
		MIN_SEASONAL_SWING,
		"peak %.0f vs trough %.0f is a %.2fx swing" % [peak, trough, peak / trough]
	)


func test_an_individual_tile_moves_with_the_season() -> void:
	# The aggregate above could in principle be produced by a handful of tiles
	# swinging wildly while the rest sat still. Check a tile.
	var world := WorldGen.generate(SEED_A)
	var grass := _first_tile_of(world, WorldGen.Terrain.GRASS)
	var forest := _first_tile_of(world, WorldGen.Terrain.FOREST)

	var grass_values: Array[float] = []
	var forest_values: Array[float] = []
	for turn in range(Seasons.TURNS_PER_YEAR):
		if turn % Seasons.TURNS_PER_SEASON == 0:
			grass_values.append(world.forage_at(grass))
			forest_values.append(world.forage_at(forest))
		world.advance_turn()

	assert_gt(
		grass_values.max() - grass_values.min(),
		0.25,
		"a meadow is a different place in winter than in spring: %s" % [grass_values]
	)
	# Not the same curve as grass, either. Terrain that all rises and falls
	# together is one global multiplier wearing a table's clothes, and it would
	# make where a herd stands irrelevant.
	assert_ne(
		grass_values.find(grass_values.max()),
		forest_values.find(forest_values.max()),
		"grass and forest do not peak in the same season: %s vs %s"
			% [grass_values, forest_values]
	)


func test_the_same_seed_advanced_the_same_way_stays_identical() -> void:
	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)
	# An unrelated world advanced in between, because the failure this is looking
	# for is per-turn state leaking out of one world into another.
	var noise := WorldGen.generate(SEED_B)

	for i in range(LONG_RUN):
		first.advance_turn()
		noise.advance_turn()
		second.advance_turn()

	assert_eq(first.turn, LONG_RUN, "both worlds ran the full distance")
	assert_eq(second.turn, LONG_RUN)
	assert_eq(first.season(), second.season(), "and landed in the same season")

	var terrain_a := first.terrain_data()
	var terrain_b := second.terrain_data()
	var forage_a := first.forage_data()
	var forage_b := second.forage_data()
	var mismatches: Array[String] = []
	for i in range(terrain_a.size()):
		if terrain_a[i] != terrain_b[i] or forage_a[i] != forage_b[i]:
			mismatches.append("%d: %d/%.4f vs %d/%.4f" % [
				i, terrain_a[i], forage_a[i], terrain_b[i], forage_b[i],
			])
	assert_eq(
		mismatches.size(),
		0,
		"tiles differing after %d turns: %s" % [LONG_RUN, mismatches.slice(0, 5)]
	)


func test_forage_has_not_drifted_after_five_hundred_turns() -> void:
	# Bounds are checked every turn rather than at the end: a value that leaves
	# the range and comes back would pass an end-state check, and the thing this
	# is looking for is precisely a quantity that is not being recomputed cleanly.
	var world := WorldGen.generate(SEED_A)
	var offenders: Array[String] = []
	for i in range(HORIZON):
		world.advance_turn()
		for value in world.forage_data():
			if value < Seasons.MIN_FORAGE or value > Seasons.MAX_FORAGE:
				offenders.append("turn %d: %.6f" % [world.turn, value])
				break
	assert_eq(
		offenders.size(),
		0,
		"forage left its bounds during %d turns: %s" % [HORIZON, offenders.slice(0, 5)]
	)

	# And the world is not merely in bounds but in the *right* place: a world run
	# to turn 500 must equal a world that has always been on turn 500.
	var reference := WorldGen.generate(SEED_A)
	for i in range(HORIZON):
		reference.advance_turn()
	assert_eq(world.forage_data(), reference.forage_data(), "turn %d is turn %d" % [
		world.turn, reference.turn,
	])


## How many times the horizon run is timed before the best is taken.
##
## A single timing was flaky once the turn loop grew: measured 1080 ms, 2072 ms
## and 2314 ms on identical code against a 2000 ms ceiling, while the same run
## standalone was a steady 1077 ms. A timing that flips on whatever else the
## machine is doing is measuring the host, not the turn loop.
##
## Best-of-N rather than mean or median on purpose: the question this asserts is
## "can 500 turns run inside the budget", and the fastest observed run is the
## honest answer to that. Noise only ever makes a run slower, so the minimum is
## the least contaminated sample. The budget itself is untouched.
const HORIZON_ATTEMPTS := 3


func test_five_hundred_turns_is_cheap_enough_to_test_with() -> void:
	var elapsed_msec := INF
	var tile_count := 0
	for attempt in range(HORIZON_ATTEMPTS):
		var world := WorldGen.generate(SEED_A)
		tile_count = world.grid.tile_count()
		var started := Time.get_ticks_usec()
		for i in range(HORIZON):
			world.advance_turn()
		elapsed_msec = minf(elapsed_msec, float(Time.get_ticks_usec() - started) / 1000.0)

	gut.p("%d turns over %d tiles in %.1fms, best of %d (budget %.0fms)" % [
		HORIZON, tile_count, elapsed_msec, HORIZON_ATTEMPTS, HORIZON_BUDGET_MSEC,
	])
	assert_lt(
		elapsed_msec,
		HORIZON_BUDGET_MSEC,
		"%d turns took %.1fms" % [HORIZON, elapsed_msec]
	)


func _first_tile_of(world: WorldMap, terrain: int) -> Vector2i:
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == terrain:
			return coord
	fail_test("the map has no tile of terrain %d to check" % terrain)
	return Vector2i.ZERO
