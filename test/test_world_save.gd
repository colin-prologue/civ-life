extends GutTest

# A world written out and read back is the same world, and stays the same world
# as it runs on. See `sim/world_save.gd` and `AgDR-022`.
#
# The comparison here is deliberately not hand-written. `_differences()` walks
# every script variable of every object reachable from the world, so a field the
# encoder forgot shows up as a difference even if nobody remembered to add it to
# an explicit assertion — and `test_every_field_is_saved_or_excused` fails before
# that, on the field list alone, whatever value the field happens to hold.

const SEED := 20260815
const RUN_ON := 500
const SAVE_AT := 150

const MainScene := preload("res://game/main.tscn")


## A world with everything in it a save has to carry: turns elapsed, herds that
## have moved and bred, worn ground, stores, a player-placed structure and road,
## and a herd standing on a road so a carrier is held up.
func _populated_world() -> WorldMap:
	var world := WorldGen.generate(SEED)
	var granary: CityNode = null
	for node in world.nodes:
		if node.kind == CityNode.Kind.GRANARY:
			granary = node
	var built := false
	for coord in world.grid.all_coords():
		if built or HexGrid.distance(coord, granary.coord) != 2:
			continue
		if CityGen.can_place_node(world, coord):
			var farm := CityGen.place_node(world, coord, CityNode.Kind.FARM)
			if CityGen.connect_nodes(world, farm, granary) != null:
				built = true
	assert_true(built, "the fixture found room for a player-built road")
	var people := world.citizens()
	world.add_agent(Herd.new(9001, people[0].route.path[1], Species.grazer(), 40.0))
	for i in range(SAVE_AT):
		world.advance_turn()
	return world


func _round_trip(world: WorldMap) -> WorldMap:
	var text := WorldSave.to_text(world)
	assert_ne(text, "", "the world could be written")
	var loaded := WorldSave.from_text(text)
	assert_eq(loaded["refusal"], "", "the world could be read back")
	return loaded["world"]


# --- AC2: what was saved is what comes back ---------------------------------

func test_a_loaded_world_equals_the_saved_one() -> void:
	var world := _populated_world()
	assert_gt(world.held_up_count() + world.total_stored_grain(), 0.0,
		"the fixture is actually carrying state worth losing")
	var loaded := _round_trip(world)

	assert_eq(_differences(world, loaded), PackedStringArray(), "every saved field is equal")
	assert_eq(world.difference_count(loaded), 0, "terrain is identical")
	assert_eq(loaded.turn, world.turn, "turn")
	assert_eq(loaded.world_seed, world.world_seed, "seed")
	assert_eq(loaded.nodes.size(), world.nodes.size(), "nodes")
	assert_eq(loaded.routes.size(), world.routes.size(), "routes")
	assert_eq(loaded.agents.size(), world.agents.size(), "agents")
	for i in range(world.nodes.size()):
		assert_eq(loaded.nodes[i].store, world.nodes[i].store, "node %d store" % i)
	for i in range(world.routes.size()):
		assert_eq(loaded.routes[i].path, world.routes[i].path, "route %d path" % i)
		assert_eq(loaded.nodes.find(loaded.routes[i].source), world.nodes.find(world.routes[i].source),
			"route %d source" % i)
	for i in range(world.agents.size()):
		assert_eq(loaded.agents[i].coord, world.agents[i].coord, "agent %d position" % i)
		assert_eq(loaded.agents[i].forage_demand(), world.agents[i].forage_demand(), "agent %d demand" % i)
	assert_eq(loaded.held_up_count(), world.held_up_count(), "held-up counters")


func test_a_fresh_world_round_trips_too() -> void:
	var world := WorldGen.generate(SEED)
	assert_eq(_differences(world, _round_trip(world)), PackedStringArray(), "turn 0 world")


func test_the_file_path_round_trips() -> void:
	var world := _populated_world()
	var path := "user://test_world_save.json"
	assert_eq(WorldSave.write_file(world, path), "", "written")
	var loaded := WorldSave.read_file(path)
	assert_eq(loaded["refusal"], "", "read")
	assert_eq(_differences(world, loaded["world"]), PackedStringArray(), "equal after a file")
	DirAccess.remove_absolute(path)


func test_a_big_seed_survives() -> void:
	# JSON numbers come back as doubles, and a double cannot hold every 64-bit
	# integer. The seed is the one integer a player can make that large.
	var world := WorldMap.new(HexGrid.new(3, 3), 9007199254740993)
	assert_eq(_round_trip(world).world_seed, 9007199254740993, "seed past 2^53")


# --- AC3: the one that catches unsaved state --------------------------------

func test_a_loaded_world_runs_on_exactly_like_the_original() -> void:
	var original := _populated_world()
	var loaded := _round_trip(original)
	for i in range(RUN_ON):
		original.advance_turn()
		loaded.advance_turn()
	assert_eq(loaded.turn, SAVE_AT + RUN_ON, "both ran")
	assert_eq(_differences(original, loaded), PackedStringArray(),
		"saved at %d and run %d turns on, the two worlds agree" % [SAVE_AT, RUN_ON])


# --- AC5: versions ----------------------------------------------------------

func test_an_unknown_version_is_refused() -> void:
	var data := WorldSave.encode(_populated_world())
	for version in [WorldSave.VERSION + 1, 0, "1", null]:
		data["version"] = version
		var loaded := WorldSave.decode(data)
		assert_null(loaded["world"], "version %s gives no world" % str(version))
		assert_string_contains(loaded["refusal"], "version")


func test_a_save_carries_its_format_and_version() -> void:
	var parsed = JSON.parse_string(WorldSave.to_text(WorldGen.generate(SEED)))
	assert_eq(parsed["format"], WorldSave.FORMAT)
	assert_eq(int(parsed["version"]), WorldSave.VERSION)


func test_damaged_saves_are_refused_rather_than_half_loaded() -> void:
	var good := WorldSave.encode(_populated_world())
	var damage := {
		"not json at all": null,
		"a missing field": func(d): d.erase("nodes"),
		"a short terrain row": func(d): d["terrain"].pop_back(),
		"a road off its structures": func(d): d["routes"][0]["source"] = 99,
		"a citizen off its road": _strand_the_citizens,
		"an unknown agent": func(d): d["agents"][0]["kind"] = "band",
		"a coordinate off the map": func(d): d["nodes"][0]["coord"] = [500, 500],
		"a number edited without its bits": func(d): d["nodes"][0]["store"]["value"] = 12345.0,
		"a herd named as a carrier": _crew_a_road_with_a_herd,
		"a carrier on someone else's road": _crew_a_road_with_a_stranger,
		"a carrier listed twice": func(d): d["routes"][0]["carriers"].append(d["routes"][0]["carriers"][0]),
		"a citizen dropped from the carrier list": func(d): d["routes"][0]["carriers"].pop_back(),
		"a herd taking a citizen's id": _give_a_herd_a_citizens_id,
		"a citizen moved off its route step": _move_a_citizen_along_its_road,
		"a million tiles along each edge": func(d): d["width"] = 1000000; d["height"] = 1000000,
		"a map one tile over the supported size": func(d): d["width"] = WorldGen.DEFAULT_WIDTH + 1,
		"a vitality above the ceiling": func(d): d["vitality"][0][5] = 1.5,
		"a vitality below the floor": func(d): d["vitality"][1][7] = 0.05,
		"a negative vitality": func(d): d["vitality"][0][0] = -1.0,
		"a road through water": _lay_a_road_through_water,
	}
	for what in damage:
		var result: Dictionary
		if typeof(damage[what]) == TYPE_NIL:
			result = WorldSave.from_text("{ this is not")
		else:
			var copy: Dictionary = JSON.parse_string(JSON.stringify(good, "", false, true))
			damage[what].call(copy)
			result = WorldSave.decode(copy)
		assert_null(result["world"], "%s gives no world" % what)
		assert_ne(result["refusal"], "", "%s says why" % what)
		if what.contains("carrier"):
			assert_string_contains(result["refusal"], "carrier", "%s is refused for the crew list" % what)
		if what.contains("id"):
			assert_string_contains(result["refusal"], "share the id", "%s is refused for the shared id" % what)
		if what.contains("route step"):
			assert_string_contains(result["refusal"], "somewhere other than", "%s is refused for the coordinate" % what)
		if what.contains("tile"):
			assert_string_contains(result["refusal"], "out of range", "%s is refused for its size" % what)
		if what.contains("vitality"):
			assert_string_contains(result["refusal"], "vitality", "%s is refused for the land" % what)
		if what.contains("water"):
			assert_string_contains(result["refusal"], "water", "%s is refused for the terrain" % what)


## Each payload breaks one rule the constructors, `CityGen` or the one species
## preset rely on; decoding must refuse it, with a refusal naming the rule.
func test_a_save_that_breaks_a_gameplay_invariant_is_refused() -> void:
	var good := WorldSave.encode(_populated_world())
	var damage := {
		"a sense range wide enough to hang the herd's search": [
			func(d): d["species"][0]["sense_range"] = 1000000000, "species"],
		"a species that eats nothing": [
			func(d): d["species"][0]["consumption_per_head"] = WorldSave._exact(0.0), "species"],
		"a species that moves further than the preset": [
			func(d): d["species"][0]["move_range"] = 50, "species"],
		"a non-finite number": [
			func(d): d["nodes"][0]["store"] = {"value": 0.0, "bits": "000000000000f87f"}, "finite"],
		"a structure standing on the sea": [_put_a_structure_in_the_sea, "water"],
		"two structures on one tile": [
			func(d): d["nodes"][1]["coord"] = d["nodes"][0]["coord"], "stand on"],
		"two structures with one number": [
			func(d): d["nodes"][1]["id"] = d["nodes"][0]["id"], "structures share"],
		"a structure with negative room": [
			func(d): d["nodes"][0]["capacity"] = WorldSave._exact(-1.0), "negative capacity"],
		"a road that ends at a farm": [_end_a_road_at_a_farm, "granary"],
		"a road that starts at a granary": [_start_a_road_at_a_granary, "granary"],
		"a road that is not the straight run": [_bend_a_road, "straight run"],
		"a second road between the same two structures": [_double_a_road, "same pair"],
		"two roads with one number": [
			func(d): d["routes"][1]["id"] = d["routes"][0]["id"], "roads share"],
	}
	for what in damage:
		var copy: Dictionary = JSON.parse_string(JSON.stringify(good, "", false, true))
		damage[what][0].call(copy)
		var result := WorldSave.decode(copy)
		assert_null(result["world"], "%s gives no world" % what)
		assert_string_contains(result["refusal"], damage[what][1], "%s is refused for the right reason" % what)


func test_a_world_with_another_species_is_refused_at_save_time() -> void:
	var world := WorldGen.generate(SEED)
	world.add_agent(Herd.new(8001, world.agents[0].coord, Species.new("odd", 0.006, 0.07, 0.11, 1, 400, 2.0, 40.0), 10.0))
	assert_string_contains(WorldSave.unsaveable(world), "species")
	assert_eq(WorldSave.to_text(world), "")


func test_land_at_its_floor_and_ceiling_still_loads() -> void:
	var world := WorldGen.generate(SEED)
	world._vitality[0][0] = Land.MIN_VITALITY
	world._vitality[0][1] = Land.MAX_VITALITY
	var loaded := _round_trip(world)
	assert_not_null(loaded, "the bounds themselves are in range")
	assert_eq(_differences(world, loaded), PackedStringArray(), "and come back unchanged")


func test_a_generated_world_is_within_the_size_a_save_allows() -> void:
	assert_eq(WorldGen.generate(SEED).grid.tile_count(), WorldGen.DEFAULT_WIDTH * WorldGen.DEFAULT_HEIGHT)


func test_an_agent_the_format_does_not_know_is_refused_at_save_time() -> void:
	var world := WorldGen.generate(SEED)
	world.add_agent(Agent.new(77, world.agents[0].coord))
	assert_ne(WorldSave.unsaveable(world), "", "a plain agent cannot be written")
	assert_eq(WorldSave.to_text(world), "", "and nothing is produced")


func test_a_save_is_written_whole_or_not_at_all() -> void:
	var world := _populated_world()
	var path := "user://test_durable_save.json"
	assert_eq(WorldSave.write_file(world, path), "", "the first save is written")
	assert_false(FileAccess.file_exists(path + ".tmp"), "no temporary file is left behind")
	var before := FileAccess.get_file_as_string(path)
	world.advance_turn()
	for step in ["open", "store", "flush", "close", "replace"]:
		var why := WorldSave.write_file(world, path, _FailingSteps.new(step))
		assert_ne(why, "", "a failing %s is reported" % step)
		assert_eq(FileAccess.get_file_as_string(path), before, "the earlier save survives a failing %s" % step)
		assert_eq(WorldSave.read_file(path)["refusal"], "", "and still loads after a failing %s" % step)
		assert_false(FileAccess.file_exists(path + ".tmp"), "no temporary file after a failing %s" % step)
	assert_eq(WorldSave.write_file(world, path), "", "a later save replaces it")
	assert_ne(FileAccess.get_file_as_string(path), before, "with the newer world")
	DirAccess.remove_absolute(path)


class _FailingSteps extends WorldSave.FileSteps:
	var _step: String

	func _init(step: String) -> void:
		_step = step

	func open(path: String) -> FileAccess:
		return null if _step == "open" else super.open(path)

	func store(file: FileAccess, text: String) -> bool:
		return false if _step == "store" else super.store(file, text)

	func flush(file: FileAccess) -> Error:
		return FAILED if _step == "flush" else super.flush(file)

	func close(file: FileAccess) -> Error:
		var result := super.close(file)
		return FAILED if _step == "close" else result

	func replace(from: String, to: String) -> Error:
		return FAILED if _step == "replace" else super.replace(from, to)


# --- AC6: a new field that is not saved turns this red -----------------------

func test_every_field_is_saved_or_excused() -> void:
	var seen := {}
	_collect_classes(_populated_world(), seen)
	for expected in WorldSave.SAVED:
		assert_true(seen.has(expected), "the fixture world contains a %s" % expected)
	for name in seen:
		assert_true(WorldSave.SAVED.has(name),
			"%s is part of a world and sim/world_save.gd has no field list for it" % name)
		if WorldSave.SAVED.has(name):
			assert_eq(_unlisted_fields(seen[name], name), PackedStringArray(),
				"%s has fields sim/world_save.gd neither saves nor excuses" % name)
	for name in WorldSave.NOT_SAVED:
		for field in WorldSave.NOT_SAVED[name]:
			assert_false(WorldSave.SAVED[name].has(field), "%s.%s is not both saved and excused" % [name, field])


class _GrownWorld extends WorldMap:
	var a_new_kind_of_state := 3


func test_the_field_check_would_notice_a_new_field() -> void:
	var grown := _GrownWorld.new(HexGrid.new(2, 2), 1)
	assert_eq(_unlisted_fields(grown, "WorldMap"), PackedStringArray(["a_new_kind_of_state"]),
		"a field added to WorldMap and not listed is reported")


func test_the_comparison_would_notice_a_difference() -> void:
	var world := _populated_world()
	var loaded := _round_trip(world)
	loaded.citizens()[0].held_up += 1
	loaded.routes[0].sink.store += 0.001
	# Counted by field rather than by path: the granary is reachable from every
	# road and carrier that refers to it, so one changed store is several paths.
	var fields := {}
	for found in _differences(world, loaded):
		var at := found.get_slice(":", 0).get_slice(" ", 0)
		fields[at.substr(at.rfind(".") + 1)] = true
	var names := fields.keys()
	names.sort()
	assert_eq(names, ["held_up", "store"], "both changes are found, and nothing else")


# --- AC7: forage is not stored ----------------------------------------------

func test_forage_is_recomputed_not_stored() -> void:
	var world := _populated_world()
	var parsed: Dictionary = JSON.parse_string(WorldSave.to_text(world))
	assert_false(parsed.has("forage"), "no forage in the file")
	var loaded := _round_trip(world)
	assert_eq(loaded.forage_data(), world.forage_data(), "and it comes back identical anyway")


# --- AC1 and the game side --------------------------------------------------

func test_the_seed_comes_from_the_command_line_or_the_default() -> void:
	assert_eq(Main.seed_from_args(PackedStringArray(), 5), 5, "no argument: default")
	assert_eq(Main.seed_from_args(PackedStringArray(["--seed=42"]), 5), 42, "--seed=N")
	assert_eq(Main.seed_from_args(PackedStringArray(["--x", "--seed", "-7"]), 5), -7, "--seed N")
	assert_eq(Main.seed_from_args(PackedStringArray(["--seed=abc"]), 5), 5, "nonsense: default")
	assert_eq(Main.DEFAULT_SEED, 20260815, "the shipped default is the seed captures were taken on")


func test_choosing_a_seed_in_game_replaces_the_world_and_names_it() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	assert_eq(main.world.world_seed, Main.DEFAULT_SEED, "launches on the default")
	main.choose_seed(42)
	assert_eq(main.world.world_seed, 42, "the world is the chosen seed's")
	assert_eq(main.world.turn, 0, "and fresh")
	assert_string_contains(main.get_node("Status").text, "seed 42")


func test_the_game_saves_and_loads_through_one_path() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var path := "user://test_main_save.json"
	for i in range(30):
		main.advance_turn()
	main.save_world(path)
	var saved := main.world
	main.choose_seed(7)
	main.load_world(path)
	assert_eq(main.world.turn, 30, "the saved turn is back")
	assert_eq(_differences(saved, main.world), PackedStringArray(), "and so is the world")
	assert_string_contains(main.get_node("Status").text, "seed %d" % Main.DEFAULT_SEED)
	DirAccess.remove_absolute(path)
	main.load_world(path)
	assert_eq(main.world.turn, 30, "a missing file leaves the world alone")
	assert_string_contains(main.message, "no save")


# --- helpers ----------------------------------------------------------------

static func _crew_a_road_with_a_herd(data: Dictionary) -> void:
	for agent in data["agents"]:
		if agent["kind"] == "herd":
			data["routes"][0]["carriers"][0] = agent["id"]
			return


static func _crew_a_road_with_a_stranger(data: Dictionary) -> void:
	data["routes"][0]["carriers"][0] = data["routes"][1]["carriers"][0]


static func _give_a_herd_a_citizens_id(data: Dictionary) -> void:
	for agent in data["agents"]:
		if agent["kind"] == "herd":
			agent["id"] = data["routes"][0]["carriers"][0]
			return


# Another coordinate off the same road's path: in bounds, but not where the
# citizen's route index says it stands.
static func _move_a_citizen_along_its_road(data: Dictionary) -> void:
	for agent in data["agents"]:
		if agent["kind"] == "citizen":
			for step in data["routes"][int(agent["route"])]["path"]:
				if step != agent["coord"]:
					agent["coord"] = step
					return


static func _lay_a_road_through_water(data: Dictionary) -> void:
	var grid := HexGrid.new(int(data["width"]), int(data["height"]))
	var step: Array = data["routes"][0]["path"][1]
	data["terrain"][grid.index_of(Vector2i(int(step[0]), int(step[1])))] = WorldGen.Terrain.WATER


static func _tile_of(data: Dictionary, at: Array) -> int:
	return HexGrid.new(int(data["width"]), int(data["height"])).index_of(Vector2i(int(at[0]), int(at[1])))


static func _put_a_structure_in_the_sea(data: Dictionary) -> void:
	data["terrain"][_tile_of(data, data["nodes"][0]["coord"])] = WorldGen.Terrain.WATER


static func _end_a_road_at_a_farm(data: Dictionary) -> void:
	data["nodes"][int(data["routes"][0]["sink"])]["kind"] = CityNode.Kind.FARM


static func _start_a_road_at_a_granary(data: Dictionary) -> void:
	data["nodes"][int(data["routes"][0]["source"])]["kind"] = CityNode.Kind.GRANARY


# A contiguous four-tile detour over land between the same two structures, so
# only "not the straight run" is wrong with it.
static func _bend_a_road(data: Dictionary) -> void:
	for route in data["routes"]:
		var path: Array = route["path"]
		var a := Vector2i(int(path[0][0]), int(path[0][1]))
		var b := Vector2i(int(path[-1][0]), int(path[-1][1]))
		for x in HexGrid.neighbors(a):
			for y in HexGrid.neighbors(x):
				var detour: Array[Vector2i] = [a, x, y, b]
				if y == a or HexGrid.distance(y, b) != 1 or not Route.is_contiguous(detour) \
						or not _all_land(data, detour):
					continue
				var out := []
				for coord in detour:
					out.append([coord.x, coord.y])
				route["path"] = out
				return


static func _all_land(data: Dictionary, path: Array[Vector2i]) -> bool:
	var grid := HexGrid.new(int(data["width"]), int(data["height"]))
	for coord in path:
		if not grid.has_coord(coord) or data["terrain"][grid.index_of(coord)] == WorldGen.Terrain.WATER:
			return false
	return true


static func _double_a_road(data: Dictionary) -> void:
	var copy: Dictionary = data["routes"][0].duplicate(true)
	copy["id"] = 999
	copy["carriers"] = []
	data["routes"].append(copy)


static func _strand_the_citizens(data: Dictionary) -> void:
	for agent in data["agents"]:
		if agent["kind"] == "citizen":
			agent["index"] = 999


static func _script_fields(object: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for property in object.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(property["name"])
	return out


static func _unlisted_fields(object: Object, name: String) -> PackedStringArray:
	var excused: Dictionary = WorldSave.NOT_SAVED.get(name, {})
	var out := PackedStringArray()
	for field in _script_fields(object):
		if not WorldSave.SAVED.get(name, []).has(field) and not excused.has(field):
			out.append(field)
	return out


static func _class_of(object: Object) -> String:
	var script: Script = object.get_script()
	return "" if script == null else String(script.get_global_name())


## Every class reachable from `value`, one instance of each.
func _collect_classes(value, seen: Dictionary) -> void:
	match typeof(value):
		TYPE_OBJECT:
			if value == null:
				return
			var name := _class_of(value)
			if seen.has(name):
				return
			seen[name] = value
			for field in _script_fields(value):
				if not WorldSave.NOT_SAVED.get(name, {}).has(field):
					_collect_classes(value.get(field), seen)
		TYPE_ARRAY:
			for item in value:
				_collect_classes(item, seen)
		TYPE_DICTIONARY:
			for key in value:
				_collect_classes(value[key], seen)


## Every place two worlds differ, as readable paths. Walks every script variable
## of every object except the excused ones, so it compares what is *there* and
## not what someone remembered to list. Floats are compared exactly.
static func _differences(a, b, path := "world", out := PackedStringArray()) -> PackedStringArray:
	if typeof(a) != typeof(b):
		out.append("%s: %s vs %s" % [path, type_string(typeof(a)), type_string(typeof(b))])
		return out
	match typeof(a):
		TYPE_OBJECT:
			if a == null or b == null:
				if a != b:
					out.append("%s: null vs object" % path)
				return out
			var name := _class_of(a)
			if name != _class_of(b):
				out.append("%s: %s vs %s" % [path, name, _class_of(b)])
				return out
			for field in _script_fields(a):
				if WorldSave.NOT_SAVED.get(name, {}).has(field):
					continue
				_differences(a.get(field), b.get(field), "%s.%s" % [path, field], out)
		TYPE_ARRAY:
			if a.size() != b.size():
				out.append("%s: %d vs %d entries" % [path, a.size(), b.size()])
				return out
			for i in range(a.size()):
				_differences(a[i], b[i], "%s[%d]" % [path, i], out)
		TYPE_DICTIONARY:
			var keys_a: Array = a.keys()
			var keys_b: Array = b.keys()
			if keys_a != keys_b:
				out.append("%s: keys %s vs %s" % [path, keys_a, keys_b])
				return out
			for key in keys_a:
				_differences(a[key], b[key], "%s[%s]" % [path, key], out)
		_:
			if a != b:
				var at := ""
				if a is PackedFloat32Array or a is PackedInt32Array:
					for i in range(mini(a.size(), b.size())):
						if a[i] != b[i]:
							at = " (first at %d: %s vs %s)" % [i, a[i], b[i]]
							break
					if at.is_empty():
						at = " (%d vs %d entries)" % [a.size(), b.size()]
					out.append("%s differs%s" % [path, at])
				else:
					out.append("%s: %s vs %s" % [path, a, b])
	return out
