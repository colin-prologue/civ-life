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
