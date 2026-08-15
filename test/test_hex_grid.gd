extends GutTest

# The grid is coordinate arithmetic, so these tests are mostly about the two
# places that arithmetic is easy to get subtly wrong: the offset<->axial
# conversion, and what happens at an edge.


func test_offset_and_axial_round_trip() -> void:
	var grid := HexGrid.new(40, 30)
	for row in range(grid.height):
		for col in range(grid.width):
			var axial := HexGrid.from_offset(col, row)
			var back := HexGrid.to_offset(axial)
			assert_eq(back, Vector2i(col, row), "round trip at (%d, %d)" % [col, row])


func test_iteration_visits_every_tile_exactly_once() -> void:
	var grid := HexGrid.new(40, 30)
	var coords := grid.all_coords()
	assert_eq(coords.size(), 1200, "40x30 tiles")
	var seen := {}
	for c in coords:
		seen[c] = true
	assert_eq(seen.size(), coords.size(), "no coordinate appears twice")


func test_index_matches_iteration_order() -> void:
	var grid := HexGrid.new(12, 9)
	var coords := grid.all_coords()
	for i in range(coords.size()):
		assert_eq(grid.index_of(coords[i]), i, "index of tile %d" % i)
		assert_eq(grid.coord_at(i), coords[i], "coord at index %d" % i)


func test_interior_tile_has_six_neighbors() -> void:
	var grid := HexGrid.new(40, 30)
	var centre := HexGrid.from_offset(20, 15)
	var neighbors := grid.neighbors_in_bounds(centre)
	assert_eq(neighbors.size(), 6, "an interior tile is surrounded")
	for n in neighbors:
		assert_eq(HexGrid.distance(centre, n), 1, "every neighbour is one step away")


func test_neighbors_are_distinct_and_reciprocal() -> void:
	var grid := HexGrid.new(40, 30)
	var centre := HexGrid.from_offset(7, 4)
	var neighbors := grid.neighbors_in_bounds(centre)
	var seen := {}
	for n in neighbors:
		seen[n] = true
		assert_true(grid.neighbors_in_bounds(n).has(centre), "neighbourhood is mutual")
	assert_eq(seen.size(), neighbors.size(), "no duplicate neighbours")


func test_edges_clip_neighbors_without_leaking_off_the_map() -> void:
	var grid := HexGrid.new(40, 30)
	var off_map := 0
	for coord in grid.all_coords():
		var neighbors := grid.neighbors_in_bounds(coord)
		assert_between(neighbors.size(), 2, 6, "neighbour count stays sane at %s" % coord)
		for n in neighbors:
			if not grid.has_coord(n):
				off_map += 1
	assert_eq(off_map, 0, "no in-bounds neighbour is actually off the map")


func test_corner_has_the_fewest_neighbors() -> void:
	var grid := HexGrid.new(40, 30)
	var corner := HexGrid.from_offset(0, 0)
	assert_between(grid.neighbors_in_bounds(corner).size(), 2, 3, "a corner is hemmed in")
	assert_eq(HexGrid.neighbors(corner).size(), 6, "the raw ring is always six")


func test_distance_is_zero_symmetric_and_additive() -> void:
	var a := HexGrid.from_offset(3, 3)
	var b := HexGrid.from_offset(17, 11)
	assert_eq(HexGrid.distance(a, a), 0, "a tile is zero steps from itself")
	assert_eq(HexGrid.distance(a, b), HexGrid.distance(b, a), "distance is symmetric")

	# Walking one direction n times must land exactly n steps away.
	for dir in HexGrid.DIRECTIONS:
		var walked: Vector2i = a
		for step in range(1, 5):
			walked += dir
			assert_eq(HexGrid.distance(a, walked), step, "%d steps along %s" % [step, dir])


func test_distance_obeys_the_triangle_inequality() -> void:
	var grid := HexGrid.new(10, 8)
	var coords := grid.all_coords()
	var a := coords[0]
	var b := coords[40]
	for c in coords:
		assert_true(
			HexGrid.distance(a, b) <= HexGrid.distance(a, c) + HexGrid.distance(c, b),
			"triangle inequality via %s" % c
		)


func test_has_coord_rejects_tiles_past_the_border() -> void:
	var grid := HexGrid.new(40, 30)
	assert_true(grid.has_coord(HexGrid.from_offset(39, 29)), "the far corner is on the map")
	assert_false(grid.has_coord(HexGrid.from_offset(40, 29)), "one column past the edge is not")
	assert_false(grid.has_coord(HexGrid.from_offset(0, 30)), "one row past the edge is not")
	assert_false(grid.has_coord(HexGrid.from_offset(-1, 0)), "negative columns are not")
	assert_eq(grid.index_of(HexGrid.from_offset(-1, 0)), -1, "off-map tiles have no index")
