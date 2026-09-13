extends RefCounted

## Where to put a camp, and what one there gathers — shared by
## `test/test_gathering.gd` and `tools/camp_attention_check.gd`.
##
## Shared rather than copied because the camp-attention gate's bar was derived
## from measurements taken on the test's own site selection. A second
## implementation that picked "typical" slightly differently would be comparing
## against a table it was never measured on, and nothing would say so.
##
## Lives outside res://test because GUT treats any script there that does not
## extend GutTest as a broken test. Loaded by `preload` rather than `class_name`
## so neither caller depends on the global class cache.


## Where the herds of `world_seed` actually spend `turns`, as one accumulated
## total of mouths per tile.
##
## Run rather than reasoned about: which ground is busy is a property of the
## terrain, the seasons and fourteen independent migrations, and any site picked
## by hand would be a guess that could quietly stop being true.
static func presence(world_seed: int, turns: int) -> PackedFloat32Array:
	var world := WorldGen.generate(world_seed)
	var total := PackedFloat32Array()
	total.resize(world.grid.tile_count())
	for _turn in range(turns):
		world.advance_turn()
		for i in range(total.size()):
			total[i] += world.forage_demand_by_index(i)
	return total


## The busiest, the quietest and the median land tile of one terrain, scored by
## how many mouths passed within a camp's reach of each over the run.
##
## Restricted to a single terrain — whichever the busiest tile turns out to be —
## so that the three camps in the measurement are separated by where the animals
## went and by nothing else. A farm on each of them makes the identical amount,
## which is what makes that claim checkable rather than asserted.
static func sites(world: WorldMap, presence_total: PackedFloat32Array) -> Dictionary:
	var busy := Vector2i.ZERO
	var busiest := -1.0
	var scores := {}
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			continue
		var score := 0.0
		for i in disc_indices(world.grid, coord, CityNode.GATHERING_RADIUS):
			score += presence_total[i]
		scores[coord] = score
		if score > busiest:
			busiest = score
			busy = coord

	var terrain := world.terrain_at(busy)
	# Insertion-ordered, and the insertion order is `all_coords()` — so the list
	# this sorts is the same list on every run and on every host.
	var same_terrain: Array[Vector2i] = []
	for coord in scores:
		if world.terrain_at(coord) == terrain:
			same_terrain.append(coord)
	same_terrain.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if scores[a] == scores[b]:
				# Ties broken on grid order, so "the quietest tile" is one tile
				# rather than whichever of four hundred equally empty ones the
				# sort happened to leave in front.
				return world.grid.index_of(a) < world.grid.index_of(b)
			return scores[a] < scores[b]
	)
	return {
		"busy": busy,
		"quiet": same_terrain[0],
		"typical": same_terrain[same_terrain.size() / 2],
		"terrain": terrain,
	}


## The measurement itself: a camp and a farm on each of the three sites, run for
## `years`, totalling what each one *grew* rather than what reached its store.
##
## Grown, not stored, because a barn holds three turns of a good harvest and a
## camp on good ground fills it — a store would measure the barn.
static func measure_placement(world_seed: int, years: int) -> Dictionary:
	var turns := years * Seasons.TURNS_PER_YEAR
	var world := WorldGen.generate(world_seed)
	var chosen := sites(world, presence(world_seed, turns))

	# Nodes are not agents: they have no forage demand, they do not move and
	# nothing consults them. Adding these cannot shift a herd, which is what lets
	# the sites chosen from one run be measured on another.
	var camps := {}
	var farms := {}
	for key in ["busy", "typical", "quiet"]:
		camps[key] = CityNode.new(world.nodes.size(), chosen[key], CityNode.Kind.GATHERING)
		world.add_node(camps[key])
		farms[key] = CityNode.new(world.nodes.size(), chosen[key], CityNode.Kind.FARM)
		world.add_node(farms[key])

	var totals := {"busy": 0.0, "typical": 0.0, "quiet": 0.0}
	var farm_totals := {"busy": 0.0, "typical": 0.0, "quiet": 0.0}
	# Per-year camp totals as well as the run's, because the claim this carries is
	# about *which* site wins a given year, not only which wins overall.
	var per_year := {"busy": [], "typical": [], "quiet": []}
	var this_year := {"busy": 0.0, "typical": 0.0, "quiet": 0.0}
	for turn in range(turns):
		world.advance_turn()
		for key in totals:
			totals[key] += camps[key].last_yield
			farm_totals[key] += farms[key].last_yield
			this_year[key] += camps[key].last_yield
		if (turn + 1) % Seasons.TURNS_PER_YEAR == 0:
			for key in this_year:
				per_year[key].append(this_year[key])
				this_year[key] = 0.0

	return {
		"busy": totals["busy"],
		"typical": totals["typical"],
		"quiet": totals["quiet"],
		"farm": farm_totals["busy"],
		"farm_busy": farm_totals["busy"],
		"farm_quiet": farm_totals["quiet"],
		"busy_years": per_year["busy"],
		"typical_years": per_year["typical"],
	}


## Years in which the camp on the typical tile out-gathered the one on the
## busiest ground.
static func flip_years(measured: Dictionary) -> int:
	var busy_years: Array = measured["busy_years"]
	var typical_years: Array = measured["typical_years"]
	var flips := 0
	for y in range(busy_years.size()):
		if typical_years[y] > busy_years[y]:
			flips += 1
	return flips


## Every grid index within `radius` of `coord` that is on the map, in the same
## fixed order `WorldMap.forage_demand_within()` walks.
static func disc_indices(grid: HexGrid, coord: Vector2i, radius: int) -> Array:
	var out: Array = []
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			var i := grid.index_of(coord + Vector2i(dq, dr))
			if i >= 0:
				out.append(i)
	return out
