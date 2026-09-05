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


## The largest value in a vitality row. Used to assert that a test's setup
## actually took effect — a silently failed setup leaves every tile at 1.0,
## which satisfies most of the assertions in this file for the wrong reason.
func _highest(row: PackedFloat32Array) -> float:
	var top := -1.0
	for value in row:
		top = maxf(top, value)
	return top


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
	var world := _bare_world(WorldGen.Terrain.MOUNTAIN)
	var land := Vector2i.ZERO

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
	#
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
	# stops testing anything and this is what says so.
	assert_lt(shared.herds()[0].ration_at(shared, where), 1.0,
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
	# On a bare world with a rooted herd, for the third time in this file and for
	# the same reason each time: a herd from a generated world migrates, so a
	# tile watched across a year is grazed for part of it and recovering for the
	# rest. Measured, that lands at 0.974 — the wear is real but the tile spends
	# most of the year empty, and an assertion written as though the herd stayed
	# is measuring migration rather than the per-use split it claims to test.
	var world := _bare_world()
	var where := Vector2i.ZERO
	var rooted := Species.new("rooted", 0.006, 0.070, 0.110, 0, 0, 2.0, 40.0)
	world.add_agent(Herd.new(1, where, rooted, 200.0))

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	assert_eq(world.herds()[0].coord, where, "the subject stayed put, so this measures grazing")
	assert_lt(world.vitality_at(where, Land.Use.GRAZE), 0.95, "grazing wore the grazing")
	assert_almost_eq(world.vitality_at(where, Land.Use.CULTIVATE), Land.MAX_VITALITY, 0.0001,
			"and left cultivation untouched")


func test_a_herd_on_worn_ground_gets_less_from_it() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var full := world.forage_for_use(land, Land.Use.GRAZE)
	world.set_vitality(land, Land.Use.GRAZE, 0.5)
	assert_almost_eq(world.forage_for_use(land, Land.Use.GRAZE), full * 0.5, 0.0001,
			"half-worn ground is worth half as much to a grazer")


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


## Ground worth standing on. Deliberately a low bar: the claim being tested is
## that options never vanish, not that they stay good.
const VIABLE := 0.10


func test_a_herd_always_has_somewhere_worth_going() -> void:
	# FR-8a, first half, and the one that is not negotiable. Depletion may move
	# the answer; it may never remove the question. If this fails, the constants
	# are wrong — do not lower VIABLE to make it pass.
	var world := _world()

	for turn in range(Seasons.TURNS_PER_YEAR * 40):
		world.advance_turn()
		if turn % Seasons.TURNS_PER_SEASON != 0:
			continue
		for herd in world.herds():
			var options := 0
			for coord in world.grid.all_coords():
				if HexGrid.distance(herd.coord, coord) > herd.species.sense_range:
					continue
				if world.forage_for_use(coord, Land.Use.GRAZE) >= VIABLE:
					options += 1
			assert_gt(options, 0,
					"herd %d had nowhere to go on turn %d" % [herd.id, world.turn])


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

	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		assert_eq(a.vitality_data(use), b.vitality_data(use),
				"twenty years of wear reproduced exactly for use %d" % use)
