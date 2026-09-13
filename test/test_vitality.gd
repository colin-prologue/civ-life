extends GutTest
## Land vitality as the world holds it: how it is stored, how it is read, and
## what it does to what a tile is worth.

const SEED := 20260815


func _world() -> WorldMap:
	return WorldGen.generate(SEED)


func test_a_fresh_world_starts_at_full_vitality_everywhere() -> void:
	var world := _world()
	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		for value in world.vitality_data(use):
			assert_eq(value, Land.MAX_VITALITY, "an untouched world is unworn")


func test_vitality_is_stored_per_use() -> void:
	# The whole point of AgDR-014: ground worn by one use is untouched for the
	# other. If these two arrays are ever the same array, this fails.
	var world := _world()
	var graze := world.vitality_data(Land.Use.GRAZE)
	var cultivate := world.vitality_data(Land.Use.CULTIVATE)
	assert_eq(graze.size(), cultivate.size(), "one value per tile per use")
	assert_eq(graze.size(), world.grid.tile_count(), "and one per tile")


func test_forage_for_use_is_the_curve_scaled_by_vitality() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var base := world.forage_at(land)

	assert_almost_eq(world.forage_for_use(land, Land.Use.GRAZE), base, 0.0001,
			"at full vitality a use gets the whole curve")


func test_the_terrain_curve_is_still_the_ceiling() -> void:
	# AgDR-009's surviving half. Vitality scales the curve down and can never
	# scale it up, so no tile can ever be worth more than its terrain and season
	# say it is.
	var world := _world()
	for coord in world.grid.all_coords():
		for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
			assert_lte(world.forage_for_use(coord, use), world.forage_at(coord) + 0.0001,
					"no use exceeds the terrain curve at %s" % coord)


func _first_land_coord(world: WorldMap) -> Vector2i:
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) != WorldGen.Terrain.WATER:
			return coord
	fail_test("the generated world has no land at all")
	return Vector2i.ZERO


## A world with terrain and nothing living in it.
##
## `WorldGen.generate()` places fourteen herds, a farm, a granary and citizens,
## so a "deplete, stop, run forward" test built on it is not resting at all —
## the farm holds its own tile near the continuous-use equilibrium and never
## reaches the ceiling. Any test whose claim is about land left alone needs a
## world where nothing is working it.
func _bare_world(terrain := WorldGen.Terrain.GRASS) -> WorldMap:
	var grid := HexGrid.new(8, 8)
	var world := WorldMap.new(grid, 99)
	for coord in grid.all_coords():
		world.set_terrain(coord, terrain)
	return world


func test_worn_land_recovers_without_anyone_doing_anything() -> void:
	# AgDR-014: recovery is unconditional. No policy, no structure, no player
	# action. It is the world's behaviour, not a reward.
	#
	# On a bare world for the same reason as the absorbing-states test below: a
	# generated one has herds walking over the tile being watched.
	var world := _bare_world()
	var land := Vector2i.ZERO
	world.set_vitality(land, Land.Use.GRAZE, Land.MIN_VITALITY)

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	assert_gt(world.vitality_at(land, Land.Use.GRAZE), Land.MIN_VITALITY + 0.2,
			"a year of being left alone brings the ground back")


func test_recovery_stops_at_full_and_does_not_overshoot() -> void:
	# Started from half-worn ground rather than a fresh world. On a fresh world
	# every value is already 1.0, so the assertion below holds whether recovery
	# is implemented or does nothing at all — it would pass against an empty
	# function.
	var world := _bare_world()
	for coord in world.grid.all_coords():
		world.set_vitality(coord, Land.Use.GRAZE, 0.5)
	assert_almost_eq(_highest(world.vitality_data(Land.Use.GRAZE)), 0.5, 0.0001,
			"the ground really is worn before the run starts")

	for i in range(200):
		world.advance_turn()

	assert_gt(world.vitality_at(Vector2i.ZERO, Land.Use.GRAZE), 0.9,
			"and two hundred turns of rest actually recovered it")
	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		for value in world.vitality_data(use):
			assert_lte(value, Land.MAX_VITALITY + 0.0001, "nothing rises above full")


func test_no_absorbing_states_a_flattened_region_comes_all_the_way_back() -> void:
	# FR-8b. Deplete as hard as the rules allow, stop, and assert full recovery.
	# This is the assertion that separates this design from Manor Lords' deer.
	var world := _bare_world()
	assert_eq(world.agents.size(), 0, "nothing is working this land")
	assert_eq(world.nodes.size(), 0, "nothing is farming it either")
	for coord in world.grid.all_coords():
		world.set_vitality(coord, Land.Use.GRAZE, Land.MIN_VITALITY)
		world.set_vitality(coord, Land.Use.CULTIVATE, Land.MIN_VITALITY)

	# Assert the setup landed before trusting the conclusion. Without this the
	# test passes when the flattening silently fails: vitality stays at 1.0, the
	# world runs forward, and every value is comfortably above 0.9 for exactly
	# the wrong reason.
	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		assert_almost_eq(_highest(world.vitality_data(use)), Land.MIN_VITALITY, 0.0001,
				"every tile really is at the floor for use %d before the run" % use)

	for i in range(Seasons.TURNS_PER_YEAR * 10):
		world.advance_turn()

	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		for value in world.vitality_data(use):
			assert_gt(value, 0.9, "ten years of rest restores every tile toward full")


func test_a_grazing_herd_wears_the_ground_it_stands_on() -> void:
	var world := _world()
	var herds := world.herds()
	assert_gt(herds.size(), 0, "the world placed herds — otherwise this asserts nothing")
	var watched: Herd = herds[0]
	var where := watched.coord

	for i in range(Seasons.TURNS_PER_SEASON):
		world.advance_turn()

	assert_lt(world.vitality_at(where, Land.Use.GRAZE), Land.MAX_VITALITY,
			"a season of grazing shows on the tile")

	# And it shows by an amount worth reading, somewhere. `< MAX_VITALITY` alone
	# is satisfied by a float that moved in its last decimal place; the lowest
	# value on the map says the herds are actually eating. Measured at 0.928
	# after a year, 0.927 after the one season this waits.
	var lowest := Land.MAX_VITALITY
	for value in world.vitality_data(Land.Use.GRAZE):
		lowest = minf(lowest, value)
	assert_lt(lowest, 0.99, "and somewhere on the map the ground is visibly eaten down")


func test_standing_on_barren_ground_costs_nothing() -> void:
	# The bug this guards against: wear computed from how hungry the herd was
	# rather than from what it ate would floor every tile in the world each
	# winter, when nothing grows and every ration is bad.
	#
	# Built on an empty grid rather than a generated world, with a herd that
	# cannot move or sense. A generated world already holds fourteen herds that
	# would wander across the watched tile during the eighteen turns this waits
	# for winter, and a mobile subject would wander off it — either way the
	# assertion would be measuring something other than what it claims. The
	# species is pinned immobile so the scenario is forced rather than hoped for.
	var grid := HexGrid.new(8, 8)
	var world := WorldMap.new(grid, 99)
	var land := Vector2i.ZERO
	for coord in grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.MOUNTAIN)

	# name, consumption/head, growth, decline, move_range, sense_range, min, start
	var rooted := Species.new("rooted", 0.006, 0.070, 0.110, 0, 0, 2.0, 40.0)
	var herd := Herd.new(1, land, rooted, 40.0)
	world.add_agent(herd)

	# Winter on a mountain is the least forage the table offers.
	while world.season() != Seasons.Season.WINTER:
		world.advance_turn()
	assert_eq(herd.coord, land, "the subject stayed on the watched tile")
	var before := world.vitality_at(land, Land.Use.GRAZE)
	for i in range(Seasons.TURNS_PER_SEASON):
		world.advance_turn()

	assert_eq(herd.coord, land, "and stayed there for the measurement")
	assert_gt(world.vitality_at(land, Land.Use.GRAZE), before - 0.05,
			"a herd on ground that fed it nothing barely wore it")


func test_two_herds_sharing_a_tile_do_not_overcharge_it() -> void:
	# The share each herd draws is settled against the census as it stood before
	# anything moved. Without that, a herd stepped after one that has already
	# grazed and left divides by a smaller denominator and claims a share the
	# tile was charged for a moment earlier — so a shared tile wears faster than
	# a tile carrying the same total number of animals in one herd.
	# The populations are sized so the tile CANNOT feed them, and that is the
	# whole point. Grass in spring is 0.95 forage against 0.006 consumption per
	# head, so one tile supports about 158 animals. With 40 the herds always want
	# less than their share, `minf(my_share, my_want)` always picks `my_want`,
	# the denominator never enters the calculation, and this test passes happily
	# with the sharing bug put back. 300 animals forces the proportional branch.
	var shared := _bare_world()
	var solo := _bare_world()
	var where := Vector2i.ZERO
	shared.add_agent(Herd.new(1, where, Species.grazer(), 150.0))
	shared.add_agent(Herd.new(2, where, Species.grazer(), 150.0))
	solo.add_agent(Herd.new(1, where, Species.grazer(), 300.0))

	# Assert the premise rather than trusting it: if a later change to the forage
	# table makes this tile generous enough to feed them, the comparison below
	# stops testing anything and this is what says so. Read from the season curve
	# rather than the world — a world that has never been advanced has no forage
	# computed yet, and a ration of zero would satisfy this for the wrong reason.
	var available := Seasons.forage_for(WorldGen.Terrain.GRASS, Seasons.season_for_turn(1))
	assert_lt(Species.grazer().heads_supported_by(available), 300.0,
			"the tile is forage-limited, so the proportional-share branch runs")

	for i in range(Seasons.TURNS_PER_SEASON):
		shared.advance_turn()
		solo.advance_turn()

	assert_almost_eq(
		shared.vitality_at(where, Land.Use.GRAZE),
		solo.vitality_at(where, Land.Use.GRAZE),
		0.02,
		"three hundred animals wear a tile the same whether they came as one herd or two"
	)


func test_grazing_does_not_wear_the_ground_for_cultivation() -> void:
	# The per-use split, which is the entire point of AgDR-014. Ground eaten
	# down by animals is still good ground to farm.
	#
	# On a bare world with an immobile herd, because the *magnitude* half of this
	# claim needs ground that is grazed for the whole year. Measured on a
	# generated world instead: a herd's starting tile reads 0.974 a year later
	# and the most-eaten tile anywhere on the map reads 0.928, because herds
	# rotate off worn ground — which is the mechanism working, not failing. A
	# magnitude asserted at a snapshotted coordinate would be asserting where a
	# herd happened to wander.
	#
	# Held ground settles far lower: 0.817 after one year, 0.73 after three.
	var world := _bare_world()
	var rooted := Species.new("rooted", 0.006, 0.070, 0.110, 0, 0, 2.0, 40.0)
	world.add_agent(Herd.new(1, Vector2i.ZERO, rooted, 40.0))

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	assert_lt(world.vitality_at(Vector2i.ZERO, Land.Use.GRAZE), 0.85,
			"a year of being eaten wore the grazing")
	# Every tile, not just the one underfoot: nothing in this world cultivates
	# anything, so the whole cultivation row must still be untouched.
	for value in world.vitality_data(Land.Use.CULTIVATE):
		assert_eq(value, Land.MAX_VITALITY, "and left cultivation untouched")


func test_a_farm_wears_the_ground_it_works() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var farm := CityNode.new(1, land, CityNode.Kind.FARM)
	world.add_node(farm)

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	assert_lt(world.vitality_at(land, Land.Use.CULTIVATE), 0.95,
			"a year of farming shows on the field")
	assert_almost_eq(world.vitality_at(land, Land.Use.GRAZE), Land.MAX_VITALITY, 0.0001,
			"and leaves the grazing untouched")


func test_a_worn_field_yields_less() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var fresh := CityNode.new(1, land, CityNode.Kind.FARM)
	world.add_node(fresh)
	world.advance_turn()
	var first_year := fresh.store

	world.set_vitality(land, Land.Use.CULTIVATE, Land.MIN_VITALITY)
	fresh.store = 0.0
	world.advance_turn()

	assert_lt(fresh.store, first_year, "exhausted ground gives less than fresh ground")
	assert_gt(fresh.store, 0.0, "but never nothing — the floor is above zero")


func test_the_field_a_farm_advertises_is_the_field_it_actually_works() -> void:
	# `yield_rate()` exists so a display can quote a farm's output without
	# re-deriving it, and `produce()` deposits exactly what it returns. Wear had
	# to go into the same expression rather than beside it: a `produce()` that
	# read the worn field while `yield_rate()` still read the unworn curve would
	# put a number on the map that the granary never sees.
	var world := _world()
	var land := _first_land_coord(world)
	var farm := CityNode.new(1, land, CityNode.Kind.FARM)
	world.add_node(farm)
	world.set_vitality(land, Land.Use.CULTIVATE, 0.5)

	var advertised := farm.yield_rate(world)
	assert_almost_eq(advertised, CityNode.FARM_YIELD_PER_TURN * world.forage_at(land) * 0.5,
			0.0001, "the quoted rate is the curve scaled by how worn the field is")

	farm.begin_turn()
	farm.produce(world)
	assert_almost_eq(farm.took_in, advertised, 0.0001,
			"and it is what the farm actually put in the barn")


func test_a_herd_on_worn_ground_gets_less_from_it() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var full := world.forage_for_use(land, Land.Use.GRAZE)
	world.set_vitality(land, Land.Use.GRAZE, 0.5)
	assert_almost_eq(world.forage_for_use(land, Land.Use.GRAZE), full * 0.5, 0.0001,
			"half-worn ground is worth half as much to a grazer")


## The largest value in a vitality row. Used to assert that a test's setup
## actually took effect — a silently failed setup leaves every tile at 1.0,
## which satisfies most of the assertions in this file for the wrong reason.
func _highest(row: PackedFloat32Array) -> float:
	var top := -1.0
	for value in row:
		top = maxf(top, value)
	return top


func test_a_herd_is_charged_for_the_animals_that_actually_grazed() -> void:
	# Codex review on PR #51: `_graze()` updates the population before charging
	# wear, so the share's numerator was this turn's *new* population while its
	# denominator is the census frozen at the start of the turn. On ground that
	# cannot feed the herd it shrinks first and is then under-charged; on rich
	# ground it grows and is charged for animals that were not there to eat.
	#
	# A solo herd makes the arithmetic exact: the frozen census is its own
	# pre-turn population, so its share is the whole tile's grazing, and the wear
	# it causes can be written down before the turn is taken. The two-herd
	# sharing test cannot see this — every herd shrinks by the same fraction and
	# the error cancels.
	var grid := HexGrid.new(8, 8)
	var world := WorldMap.new(grid, 99)
	for coord in grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.GRASS)
	var where := Vector2i.ZERO
	var herd := Herd.new(1, where, Species.grazer(), 300.0)
	world.add_agent(herd)

	# Read from the season curve rather than the world: forage on a world that
	# has never been advanced may not be computed yet, and a zero here would
	# make every assertion below pass for the wrong reason.
	var available := Seasons.forage_for(WorldGen.Terrain.GRASS, Seasons.season_for_turn(1))
	var before := herd.population
	var per_head := herd.species.consumption_per_head

	# The premise the bug needs: ground too poor to feed the herd, so it shrinks
	# during the turn. If the forage table ever makes this tile generous, the
	# comparison below stops testing anything, and this is what says so.
	assert_lt(herd.species.heads_supported_by(available), before,
			"the tile cannot feed all %d animals" % int(before))

	var eaten := minf(available, before * per_head)
	var expected := Land.recovered(Land.depleted(Land.MAX_VITALITY, eaten / Seasons.MAX_FORAGE))

	world.advance_turn()

	assert_lt(herd.population, before, "and it did shrink, so a post-graze count would differ")
	assert_almost_eq(world.vitality_at(where, Land.Use.GRAZE), expected, 0.00001,
			"the tile is worn by what the herd that stood on it ate, counted before it shrank")


func test_the_chronicle_records_what_the_farm_actually_grew() -> void:
	# Codex review on PR #51: `_record_turn()` runs after `produce()` has worn the
	# field and after recovery has moved it again, so sampling
	# `farm_yield_rate()` there records next turn's hypothetical harvest rather
	# than this turn's. The chronicle is history; what was grown is `last_yield`,
	# set before the wear.
	var grid := HexGrid.new(8, 8)
	var world := WorldMap.new(grid, 99)
	for coord in grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.GRASS)
	var farm := CityNode.new(1, Vector2i.ZERO, CityNode.Kind.FARM)
	world.add_node(farm)

	world.advance_turn()

	# The premise: working the field moved its forward rate away from what it
	# grew. Without wear these are the same number and the assertion below would
	# hold whichever of them the chronicle recorded.
	assert_gt(farm.last_yield - farm.yield_rate(world), 0.01,
			"the field is worth less now than it was when it was harvested")
	assert_almost_eq(world.chronicle.latest(Chronicle.FARM_YIELD), farm.last_yield, 0.00001,
			"the chronicle records the harvest the farm actually took")


func test_identical_herds_sharing_a_tile_fare_identically() -> void:
	# Codex review on PR #51, third round: the frozen census settled who divides
	# the forage, but the forage being divided was still read live. The herd
	# stepped first wears the tile in `_graze()`, so the next reads a smaller
	# `forage_for_use()` and gets a smaller ration and a smaller share of the
	# wear — two identical herds on one tile ending the turn different purely
	# because of where they sit in the agents array.
	#
	# Identical herds make any difference between them an ordering effect by
	# construction. The sharing test above compares against a solo herd at a
	# tolerance far looser than this effect, so it cannot see it.
	var world := _bare_world()
	var where := Vector2i.ZERO
	var first := Herd.new(1, where, Species.grazer(), 150.0)
	var second := Herd.new(2, where, Species.grazer(), 150.0)
	world.add_agent(first)
	world.add_agent(second)

	var available := Seasons.forage_for(WorldGen.Terrain.GRASS, Seasons.season_for_turn(1))
	# The premise: ground too poor to feed both, so each herd's ration and its
	# share of the wear both depend on the forage it reads.
	assert_lt(first.species.heads_supported_by(available), 300.0,
			"the tile cannot feed both herds")

	# Depletion is linear, so two half-shares wear the tile exactly as one whole
	# share does, and the expected wear is one herd of 300 eating everything.
	var eaten := minf(available, 300.0 * first.species.consumption_per_head)
	var expected := Land.recovered(Land.depleted(Land.MAX_VITALITY, eaten / Seasons.MAX_FORAGE))

	world.advance_turn()

	assert_lt(first.population, 150.0, "the herds did thin, so the ration reached their numbers")
	assert_almost_eq(second.population, first.population, 0.000001,
			"two identical herds on one tile end the turn identical, whichever stepped first")
	assert_almost_eq(world.vitality_at(where, Land.Use.GRAZE), expected, 0.00001,
			"and between them they wear the tile exactly as one herd of the same size would")


## Ground worth standing on. Deliberately a low bar: the claim being tested is
## that options never vanish, not that they stay good.
const VIABLE := 0.10

## How much of a turn's recovery a reading taken after the turn can be hiding.
##
## The moment FR-8a is about is when a herd *chooses*, inside `_migrate()`. A test
## can only read the world between turns, by which time `_recover_vitality()` has
## already lifted every tile — so a tile that was under `VIABLE` when the herd
## looked at it can read as viable a moment later.
##
## The gap is bounded rather than guessed. Recovery closes a fixed fraction of
## the distance to full each turn, at most `(1 - MIN_VITALITY)` of it, and forage
## is that vitality times a seasonal curve that never exceeds
## `Seasons.MAX_FORAGE`. Requiring this much margin above `VIABLE` therefore
## proves the tile cleared `VIABLE` before the recovery step as well.
##
## Found by codex review on PR #58, which caught that checking every turn still
## reads the state *after* grazing, movement and recovery.
##
## A function rather than a `const` because it is derived from `Land`'s own
## recovery rate rather than restated as a number that could drift from it.
func _recovery_slack() -> float:
	return (1.0 - Land.MIN_VITALITY) * Seasons.MAX_FORAGE * Land.recovery_rate()


func test_a_herd_always_has_somewhere_worth_going() -> void:
	# FR-8a, first half, and the one that is not negotiable. Depletion may move
	# the answer; it may never remove the question. If this fails, the constants
	# are wrong — do not lower VIABLE to make it pass.
	var world := _world()

	# Every turn, not every season. An earlier version sampled one turn in six and
	# still said "never": a herd could have been stranded on any of the five
	# skipped turns — grazing wears ground and herds move on all of them — and this
	# would have stayed green. Found by codex review on PR #58.
	#
	# Checking six times as often is *cheaper* than before, because the scan is now
	# the herd's own reachable disc rather than all twelve hundred tiles: about
	# sixty tiles at a sense range of four, against a full-map sweep that threw
	# away 95% of what it touched.
	#
	# Two things stand between a reading taken between turns and the moment the
	# claim is about, and codex review on PR #58 caught both:
	#
	# The herd has *moved* by the time this reads it, so the disc around where it
	# ended up is not the disc it chose from. Positions are recorded before the
	# turn, and the scan is around those.
	#
	# The world has *recovered* by then, so a tile under the bar when the herd
	# looked can read as viable afterwards. `_recovery_slack()` is how much one
	# recovery step can add, so clearing `VIABLE` plus that margin here proves the
	# tile cleared `VIABLE` before it.
	var slack := _recovery_slack()
	var stood_at := {}
	for turn in range(Seasons.TURNS_PER_YEAR * 40):
		stood_at.clear()
		for herd in world.herds():
			stood_at[herd.id] = herd.coord
		world.advance_turn()
		for herd in world.herds():
			var options := 0
			var reach := herd.species.sense_range
			var from: Vector2i = stood_at[herd.id]
			for dq in range(-reach, reach + 1):
				for dr in range(maxi(-reach, -dq - reach), mini(reach, -dq + reach) + 1):
					var coord := from + Vector2i(dq, dr)
					if not world.grid.has_coord(coord):
						continue
					if world.forage_for_use(coord, Land.Use.GRAZE) >= VIABLE + slack:
						options += 1
			if options == 0:
				assert_gt(options, 0,
						"herd %d had nowhere to go on turn %d" % [herd.id, world.turn])
	# One passing assertion for the whole run rather than one per herd per season,
	# which would bury the report under several thousand identical lines.
	assert_true(world.herds().size() > 0, "there were herds to ask")


func test_the_best_ground_within_reach_keeps_changing_for_every_herd() -> void:
	# FR-8a, second half. This is the periodicity fix stated locally: if the best
	# tile at a place never changes, nothing downstream ever has a reason to.
	#
	# Tracked per herd, because FR-8a and the done bar say *every* herd — and one
	# lively region can rack up plenty of changes at an arbitrary watched tile
	# while some other herd's local choice has settled permanently. Watching one
	# tile nobody stands on would report a healthy number and prove nothing.
	var world := _world()
	var previous := {}
	var changes := {}
	var seen := {}
	for herd in world.herds():
		previous[herd.id] = Vector2i(-999, -999)
		changes[herd.id] = 0
		seen[herd.id] = {}

	for year in range(40):
		for i in range(Seasons.TURNS_PER_YEAR):
			world.advance_turn()
		for herd in world.herds():
			var best := _best_within(world, herd.coord, herd.species.sense_range)
			var places: Dictionary = seen[herd.id]
			places[best] = true
			if best != previous[herd.id]:
				changes[herd.id] = int(changes[herd.id]) + 1
			previous[herd.id] = best

	# Printed whether it passes or fails: these counts are the evidence for whether
	# the mechanism works at all. The first year always counts as a change, from
	# the sentinel, so a herd whose best tile never moved reads 1 here.
	var report: Array[String] = []
	for herd in world.herds():
		var places: Dictionary = seen[herd.id]
		report.append("%d:%d/%d" % [herd.id, int(changes[herd.id]), places.size()])
	gut.p("best-tile changes/distinct tiles per herd over forty years: %s" % ", ".join(report))

	for herd in world.herds():
		assert_gt(int(changes[herd.id]), 3,
				"herd %d's best reachable ground kept changing over forty years" % herd.id)
		var places: Dictionary = seen[herd.id]
		assert_gt(places.size(), 2,
				"herd %d saw more than two distinct best tiles" % herd.id)


func _best_within(world: WorldMap, origin: Vector2i, radius: int) -> Vector2i:
	var best := origin
	var best_value := -1.0
	for coord in world.grid.all_coords():
		if HexGrid.distance(origin, coord) > radius:
			continue
		var value := world.forage_for_use(coord, Land.Use.GRAZE)
		if value > best_value:
			best_value = value
			best = coord
	return best


func test_two_worlds_from_one_seed_wear_identically() -> void:
	var a := _world()
	var b := _world()

	for i in range(Seasons.TURNS_PER_YEAR * 20):
		a.advance_turn()
		b.advance_turn()

	# The premise: twenty years of a generated world actually wore something, or
	# two untouched rows of 1.0 would agree for the wrong reason.
	var lowest := Land.MAX_VITALITY
	for value in a.vitality_data(Land.Use.GRAZE):
		lowest = minf(lowest, value)
	assert_lt(lowest, Land.MAX_VITALITY, "the herds wore the ground being compared")

	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		assert_eq(a.vitality_data(use), b.vitality_data(use),
				"twenty years of wear reproduced exactly for use %d" % use)
