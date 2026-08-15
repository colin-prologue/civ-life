extends GutTest

# The point of this suite is the first two tests. Terrain being pleasant is a
# preference; terrain being reproducible is the thing the rest of the project
# will be debugged with.

const SEED_A := 20260815
const SEED_B := 987654321

## Seeds every "is this map plausible" check runs over. A property that only
## holds for one seed is not a property of the generator.
const SEEDS := [SEED_A, SEED_B, 1, 42, 7, 555]


func test_map_is_at_least_forty_by_thirty() -> void:
	var map := WorldGen.generate(SEED_A)
	assert_gte(map.grid.width, 40, "map is wide enough")
	assert_gte(map.grid.height, 30, "map is tall enough")
	assert_eq(map.terrain_data().size(), map.grid.tile_count(), "every tile carries terrain")


func test_every_tile_has_a_terrain_from_the_enumeration() -> void:
	var map := WorldGen.generate(SEED_A)
	var valid := WorldGen.Terrain.values()
	for coord in map.grid.all_coords():
		assert_true(valid.has(map.terrain_at(coord)), "tile %s has a known terrain" % coord)


func test_the_same_seed_produces_an_identical_map_tile_for_tile() -> void:
	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)

	# Compared tile by tile rather than by sampling or by a digest, so a failure
	# points at where the two runs diverged.
	var mismatches: Array[String] = []
	for coord in first.grid.all_coords():
		if first.terrain_at(coord) != second.terrain_at(coord):
			mismatches.append("%s: %d vs %d" % [coord, first.terrain_at(coord), second.terrain_at(coord)])
	assert_eq(mismatches.size(), 0, "tiles differing between two runs: %s" % [mismatches.slice(0, 5)])
	assert_eq(first.difference_count(second), 0, "no tile differs")


func test_generation_is_unaffected_by_what_ran_before_it() -> void:
	# Catches a generator that leans on any shared or global random state: if
	# something else draws numbers in between, the map must not move.
	var first := WorldGen.generate(SEED_A)
	var _noise := WorldGen.generate(SEED_B)
	var third := WorldGen.generate(SEED_A)
	assert_eq(first.difference_count(third), 0, "an unrelated generation in between changes nothing")


func test_different_seeds_produce_substantially_different_maps() -> void:
	var a := WorldGen.generate(SEED_A)
	var b := WorldGen.generate(SEED_B)
	var differing := a.difference_count(b)
	var ratio := float(differing) / float(a.grid.tile_count())
	assert_gt(ratio, 0.10, "seeds drive generation (differing tiles: %.1f%%)" % [ratio * 100.0])


func test_the_map_contains_both_land_and_water() -> void:
	# Checked across seeds rather than one: the first version of this generator
	# put 66-86% of the map under water depending on the seed, and a single-seed
	# check is a coin toss about whether that gets noticed.
	for world_seed in SEEDS:
		var map := WorldGen.generate(world_seed)
		var counts := _terrain_counts(map)
		var water: int = counts.get(WorldGen.Terrain.WATER, 0)
		assert_gt(water, 0, "seed %d has water" % world_seed)
		var land := map.grid.tile_count() - water
		assert_gt(land, 0, "seed %d has land" % world_seed)
		# Neither extreme is playable: an ocean or a pancake would both pass a
		# "has land and water" check on its own.
		var water_ratio := float(water) / float(map.grid.tile_count())
		assert_between(
			water_ratio,
			0.05,
			0.80,
			"seed %d: water covers %.1f%% of the map" % [world_seed, water_ratio * 100.0]
		)


func test_the_largest_landmass_holds_most_of_the_land() -> void:
	for world_seed in SEEDS:
		var map := WorldGen.generate(world_seed)
		var land := _land_tiles(map)
		assert_gt(land.size(), 0, "seed %d produced land" % world_seed)
		var largest := _largest_land_region(map, land)
		var share := float(largest) / float(land.size())
		assert_gte(
			share,
			0.40,
			"seed %d: largest landmass holds %.1f%% of land, not confetti" % [world_seed, share * 100.0]
		)


func test_land_is_varied_rather_than_one_terrain() -> void:
	# Also across seeds. This passed on SEED_A alone while the generator was
	# producing near-zero mountains on most other seeds.
	for world_seed in SEEDS:
		var map := WorldGen.generate(world_seed)
		var counts := _terrain_counts(map)
		for terrain in WorldGen.Terrain.values():
			assert_gt(
				counts.get(terrain, 0),
				0,
				"seed %d: terrain %d appears somewhere" % [world_seed, terrain]
			)


# --- helpers -----------------------------------------------------------------


func _terrain_counts(map: WorldMap) -> Dictionary:
	var counts := {}
	for coord in map.grid.all_coords():
		var t := map.terrain_at(coord)
		counts[t] = counts.get(t, 0) + 1
	return counts


func _land_tiles(map: WorldMap) -> Dictionary:
	var land := {}
	for coord in map.grid.all_coords():
		if map.terrain_at(coord) != WorldGen.Terrain.WATER:
			land[coord] = true
	return land


## Size of the biggest connected run of non-water tiles. Flood fill, iterative
## so a big map cannot blow the stack.
func _largest_land_region(map: WorldMap, land: Dictionary) -> int:
	var visited := {}
	var largest := 0
	for start in land.keys():
		if visited.has(start):
			continue
		var size := 0
		var frontier: Array[Vector2i] = [start]
		visited[start] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_back()
			size += 1
			for n in map.grid.neighbors_in_bounds(current):
				if land.has(n) and not visited.has(n):
					visited[n] = true
					frontier.append(n)
		largest = maxi(largest, size)
	return largest
