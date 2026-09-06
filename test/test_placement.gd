extends GutTest

# The player's first verb, checked where the verb actually lives.
#
# Everything below runs without a scene tree, a viewport or a click, which is
# the point rather than a convenience: `AgDR-001` says a rule that can only be
# exercised through the renderer is a rule that cannot be reproduced from a
# seed. If placement validity were in `game/`, none of this file could exist.
#
# Three claims, in the order they matter:
#
#   1. **The rule is in `sim/` and it is right.** Land, free, and connectable are
#      answered by `CityGen`, and the reason a refusal gives is the reason that
#      actually applied.
#
#   2. **There is one way to build a city.** The generator and the player go
#      through the same two calls. Checked by construction — a source scan for
#      anything else building a structure, a route or a carrier — because "we
#      remembered to reuse it" is exactly the claim that decays quietly.
#
#   3. **Determinism survives player input.** `AgDR-001` promises that the same
#      seed and the same ordered inputs reproduce the same world. A recorded
#      list of placements is replayed against two fresh worlds and both are
#      compared in full after two hundred turns.

## The seed the rest of the project measures things on.
const SEED_A := 20260815

## How far the replayed worlds are run before they are compared. Long enough
## that carriers have made dozens of round trips, herds have drifted across the
## map, and any divergence has had time to grow into something visible.
const REPLAY_TURNS := 200


# --- 1. the rule ------------------------------------------------------------

func test_a_free_land_tile_accepts_a_structure() -> void:
	var world := _flat_world()
	var coord := HexGrid.from_offset(3, 3)
	assert_eq(CityGen.node_refusal(world, coord), "", "clear land refuses nothing")
	assert_true(CityGen.can_place_node(world, coord), "and can therefore be built on")

	var node := CityGen.place_node(world, coord, CityNode.Kind.FARM)
	assert_not_null(node, "placement returned the structure it made")
	assert_eq(world.nodes.size(), 1, "and the world is holding it")
	assert_eq(world.node_at(coord), node, "on the tile it was asked for")


func test_water_refuses_a_structure_and_says_so() -> void:
	var world := _flat_world()
	var coord := HexGrid.from_offset(4, 4)
	world.set_terrain(coord, WorldGen.Terrain.WATER)

	assert_eq(CityGen.node_refusal(world, coord), CityGen.REFUSAL_WATER)
	assert_null(CityGen.place_node(world, coord, CityNode.Kind.FARM), "nothing was built")
	assert_eq(world.nodes.size(), 0, "and nothing was added to the world")


func test_a_taken_tile_refuses_a_second_structure() -> void:
	var world := _flat_world()
	var coord := HexGrid.from_offset(3, 3)
	CityGen.place_node(world, coord, CityNode.Kind.FARM)

	assert_eq(CityGen.node_refusal(world, coord), CityGen.REFUSAL_OCCUPIED)
	assert_null(CityGen.place_node(world, coord, CityNode.Kind.GRANARY))
	assert_eq(world.nodes.size(), 1, "the tile still holds exactly what it held")


func test_a_tile_off_the_map_refuses_a_structure() -> void:
	# The renderer's hit test answers "which tile" for points in the margin and
	# on the legend too, so this is a real input rather than a defensive one.
	var world := _flat_world()
	assert_eq(CityGen.node_refusal(world, Vector2i(-4, -4)), CityGen.REFUSAL_OFF_MAP)
	assert_null(CityGen.place_node(world, Vector2i(-4, -4), CityNode.Kind.FARM))


func test_a_route_needs_a_farm_at_one_end_and_a_granary_at_the_other() -> void:
	var world := _flat_world()
	var farm := CityGen.place_node(world, HexGrid.from_offset(2, 3), CityNode.Kind.FARM)
	var other_farm := CityGen.place_node(world, HexGrid.from_offset(5, 3), CityNode.Kind.FARM)
	var granary := CityGen.place_node(world, HexGrid.from_offset(8, 3), CityNode.Kind.GRANARY)

	assert_eq(CityGen.route_refusal(world, farm, other_farm), CityGen.REFUSAL_NOT_A_PAIR)
	assert_eq(CityGen.route_refusal(world, farm, farm), CityGen.REFUSAL_SAME_STRUCTURE)
	assert_eq(CityGen.route_refusal(world, farm, granary), "", "one of each connects")
	assert_null(CityGen.connect_nodes(world, farm, other_farm), "and the refused pair built nothing")
	assert_eq(world.routes.size(), 0)


func test_a_route_that_would_cross_water_is_refused_rather_than_routed_around() -> void:
	# `sim/route.gd` is explicit that there is no pathfinding and none is wanted.
	# The consequence has to be a refusal the player can see, not a road that
	# quietly takes a different line than the one they drew.
	var world := _flat_world()
	var farm := CityGen.place_node(world, HexGrid.from_offset(2, 3), CityNode.Kind.FARM)
	var granary := CityGen.place_node(world, HexGrid.from_offset(6, 3), CityNode.Kind.GRANARY)
	for coord in HexGrid.line(farm.coord, granary.coord):
		if coord != farm.coord and coord != granary.coord:
			world.set_terrain(coord, WorldGen.Terrain.WATER)

	assert_eq(CityGen.route_refusal(world, farm, granary), CityGen.REFUSAL_NO_STRAIGHT_RUN)
	assert_null(CityGen.connect_nodes(world, farm, granary))
	assert_eq(world.agents.size(), 0, "and no carriers were put on a road that is not there")


func test_the_same_pair_cannot_be_connected_twice() -> void:
	var world := _flat_world()
	var farm := CityGen.place_node(world, HexGrid.from_offset(2, 3), CityNode.Kind.FARM)
	var granary := CityGen.place_node(world, HexGrid.from_offset(5, 3), CityNode.Kind.GRANARY)
	assert_not_null(CityGen.connect_nodes(world, farm, granary))

	assert_eq(CityGen.route_refusal(world, farm, granary), CityGen.REFUSAL_ALREADY_LINKED)
	assert_eq(
		CityGen.route_refusal(world, granary, farm),
		CityGen.REFUSAL_ALREADY_LINKED,
		"and the same road read the other way round is the same road"
	)
	assert_eq(world.routes.size(), 1)


func test_a_route_runs_from_the_farm_whichever_end_was_picked_first() -> void:
	# Grain leaves a farm and arrives at a granary, so direction is a property of
	# the pair rather than of the click order. Two worlds built by opposite
	# selection orders have to be the same world.
	var forward := _flat_world()
	var farm_a := CityGen.place_node(forward, HexGrid.from_offset(2, 3), CityNode.Kind.FARM)
	var granary_a := CityGen.place_node(forward, HexGrid.from_offset(5, 3), CityNode.Kind.GRANARY)
	var route_a := CityGen.connect_nodes(forward, farm_a, granary_a)

	var backward := _flat_world()
	var farm_b := CityGen.place_node(backward, HexGrid.from_offset(2, 3), CityNode.Kind.FARM)
	var granary_b := CityGen.place_node(backward, HexGrid.from_offset(5, 3), CityNode.Kind.GRANARY)
	var route_b := CityGen.connect_nodes(backward, granary_b, farm_b)

	assert_eq(route_a.source.kind, CityNode.Kind.FARM, "grain is collected at the farm")
	assert_eq(route_a.sink.kind, CityNode.Kind.GRANARY, "and delivered to the granary")
	assert_eq(route_b.path, route_a.path, "and the road is the same road either way round")


# --- 2. one way to build a city ---------------------------------------------

func test_a_player_laid_route_gets_the_carriers_the_generator_would_give_it() -> void:
	var world := _flat_world()
	var farm := CityGen.place_node(world, HexGrid.from_offset(2, 3), CityNode.Kind.FARM)
	var granary := CityGen.place_node(world, HexGrid.from_offset(4, 3), CityNode.Kind.GRANARY)
	var route := CityGen.connect_nodes(world, farm, granary)

	assert_not_null(route, "the route was laid")
	assert_eq(
		world.citizens().size(),
		CityGen.CITIZENS_PER_ROUTE,
		"with the same number of carriers the generator puts on one"
	)
	for citizen in world.citizens():
		assert_eq(citizen.route, route, "and all of them are on it")

	# And it is a working city rather than a diagram: run it long enough for a
	# few round trips and the granary has something in it.
	for i in range(40):
		world.advance_turn()
	assert_gt(world.total_granary_store(), 0.0, "grain reached the granary the player built")


func test_only_the_one_builder_constructs_a_city() -> void:
	# The mechanical form of "the player and the generator both go through the
	# same code path". Prose cannot hold this — the next ticket that wants a
	# structure will write `CityNode.new` wherever it happens to be standing, and
	# the two paths drift apart from there. Tests build worlds by hand and are
	# excluded on purpose; `sim/` and `game/` are not.
	var constructors := ["CityNode.new(", "Route.new(", "Citizen.new("]
	var offenders: Array[String] = []
	for path in _gd_files("res://sim") + _gd_files("res://game"):
		if path == "res://sim/city_gen.gd":
			continue
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "could read %s" % path)
		for constructor in constructors:
			if text.contains(constructor):
				offenders.append("%s builds a city with %s" % [path, constructor])
	assert_eq(
		offenders.size(),
		0,
		"only sim/city_gen.gd builds a city: %s" % [offenders]
	)


func test_the_generator_still_puts_a_city_on_a_fresh_world() -> void:
	# AC7. Placement adds to a world that already has a city in it; this ticket
	# does not make the starting world empty, and the check is here so that
	# routing the generator through the player's calls cannot have quietly
	# stopped it working.
	var world := WorldGen.generate(SEED_A)
	assert_eq(world.nodes.size(), 2, "a farm and a granary at worldgen")
	assert_eq(world.routes.size(), 1, "with a road between them")
	assert_eq(world.citizens().size(), CityGen.CITIZENS_PER_ROUTE, "and people on it")


# --- 3. determinism under player input --------------------------------------

func test_the_same_seed_and_the_same_ordered_inputs_reproduce_the_same_world() -> void:
	# AC6, and the reason `AgDR-001` is worded as *ordered inputs* rather than as
	# a seed alone. Placement is now a second source of world state, and a
	# prototype whose state cannot be reproduced cannot be debugged.
	#
	# The plan is derived once, from its own throwaway world, and then treated as
	# a recording: two fresh worlds get the identical list in the identical
	# order. Deriving it beats hard-coding coordinates that a worldgen tweak
	# would silently turn into water — the scan is itself deterministic, so the
	# recording is the same list on every run.
	var plan := _a_plan_for(WorldGen.generate(SEED_A))
	assert_gt(plan.size(), 0, "there was somewhere to build on this seed")

	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)
	_replay(first, plan)
	_replay(second, plan)

	assert_gt(first.nodes.size(), 2, "the plan actually added to the starting city")
	assert_gt(first.routes.size(), 1, "including a road the player drew")
	assert_eq(first.turn, REPLAY_TURNS, "and both worlds ran the full span")
	assert_eq(
		_fingerprint(first),
		_fingerprint(second),
		"two worlds given the same seed and the same ordered inputs are the same world"
	)


func test_the_comparison_would_notice_a_difference() -> void:
	# A fingerprint that compares nothing passes every time. Prove it fires on
	# the smallest divergence the test above is meant to catch: one extra
	# structure, placed by the player, on an otherwise identical world.
	var plain := WorldGen.generate(SEED_A)
	var built := WorldGen.generate(SEED_A)
	var plan := _a_plan_for(WorldGen.generate(SEED_A))
	_replay(built, [plan[0]])

	assert_ne(_fingerprint(plain), _fingerprint(built), "one placement changes the world")


# --- helpers ----------------------------------------------------------------

## A small map of grass with nothing on it. Placement rules are about land,
## occupancy and geometry, and a generated world would bring fourteen herds and
## a city through the middle of the measurement.
func _flat_world() -> WorldMap:
	var world := WorldMap.new(HexGrid.new(12, 8), 1)
	for coord in world.grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.GRASS)
	return world


## A recordable list of actions that is legal on this world: two farms, two
## granaries, two roads, and the turns between them.
##
## Sites are found by scanning in grid order and taking the first that works, so
## the list is a property of the seed rather than of when the scan ran.
func _a_plan_for(world: WorldMap) -> Array:
	var pairs := _connectable_pairs(world, 2)
	if pairs.size() < 2:
		return []
	return [
		{"place": pairs[0][0], "kind": CityNode.Kind.FARM},
		{"place": pairs[0][1], "kind": CityNode.Kind.GRANARY},
		{"route": [pairs[0][0], pairs[0][1]]},
		{"turns": 40},
		{"place": pairs[1][0], "kind": CityNode.Kind.FARM},
		{"place": pairs[1][1], "kind": CityNode.Kind.GRANARY},
		# Drawn granary-first on purpose: click order must not reach the world.
		{"route": [pairs[1][1], pairs[1][0]]},
		{"turns": REPLAY_TURNS - 40},
	]


## `count` pairs of free land tiles two steps apart with clear land between them,
## found in grid order and not reusing a tile.
func _connectable_pairs(world: WorldMap, count: int) -> Array:
	var taken := {}
	for node in world.nodes:
		taken[node.coord] = true
	var out: Array = []
	for from in world.grid.all_coords():
		if out.size() >= count:
			break
		if taken.has(from) or not CityGen.can_place_node(world, from):
			continue
		for direction in HexGrid.DIRECTIONS:
			var to: Vector2i = from + direction * CityGen.ROUTE_LENGTH
			if taken.has(to) or not CityGen.can_place_node(world, to):
				continue
			var path := HexGrid.line(from, to)
			var clear := true
			for coord in path:
				if taken.has(coord) or world.terrain_at(coord) == WorldGen.Terrain.WATER:
					clear = false
			if not clear:
				continue
			for coord in path:
				taken[coord] = true
			out.append([from, to])
			break
	return out


## Apply a recorded list of actions to a world, in order.
##
## Deliberately a dozen lines in a test rather than a command system in `sim/`.
## What AC6 needs is proof that ordered input reproduces, and a general replay
## layer would be infrastructure for a save format nobody has designed yet.
func _replay(world: WorldMap, plan: Array) -> void:
	for action in plan:
		if action.has("place"):
			CityGen.place_node(world, action["place"], action["kind"])
		elif action.has("route"):
			var ends: Array = action["route"]
			CityGen.connect_nodes(world, world.node_at(ends[0]), world.node_at(ends[1]))
		elif action.has("turns"):
			for i in range(int(action["turns"])):
				world.advance_turn()


## Everything about a world that a divergence could show up in, as text.
##
## Terrain, forage and wear come out as whole rows so a single differing tile
## changes the string. Structures, roads and everything alive are written out
## one per line in the array order the turn loop steps them in, because that
## order is itself load-bearing for determinism — two worlds holding the same
## things in a different sequence are not the same world.
func _fingerprint(world: WorldMap) -> String:
	var lines := PackedStringArray()
	lines.append("turn %d" % world.turn)
	lines.append("terrain %s" % world.terrain_data())
	lines.append("forage %s" % world.forage_data())
	for use in range(Land.USE_COUNT):
		lines.append("vitality %d %s" % [use, world.vitality_data(use)])
	for node in world.nodes:
		lines.append("node %d %s %d %.5f" % [node.id, node.coord, node.kind, node.store])
	for route in world.routes:
		lines.append("route %d %d %d %s" % [route.id, route.source.id, route.sink.id, route.path])
	for agent in world.agents:
		var carried := ""
		if agent is Herd:
			carried = "herd %.5f" % (agent as Herd).population
		elif agent is Citizen:
			carried = "citizen %.5f" % (agent as Citizen).carrying
		lines.append("agent %d %s %s" % [agent.id, agent.coord, carried])
	return "\n".join(lines)


## Every `.gd` file under a directory, in a stable order.
func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entries: Array[String] = []
	var entry_name := dir.get_next()
	while entry_name != "":
		entries.append(entry_name)
		entry_name = dir.get_next()
	dir.list_dir_end()
	entries.sort()
	for entry in entries:
		var full := "%s/%s" % [dir_path, entry]
		if DirAccess.dir_exists_absolute(full):
			out.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			out.append(full)
	return out
