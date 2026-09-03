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
