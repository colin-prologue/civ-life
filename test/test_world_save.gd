extends GutTest

# A world written out and read back is the same world, and stays the same world
# as it runs on. See `sim/world_save.gd` and `AgDR-021`.
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


func test_an_agent_the_format_does_not_know_is_refused_at_save_time() -> void:
	var world := WorldGen.generate(SEED)
	world.add_agent(Agent.new(77, world.agents[0].coord))
	assert_ne(WorldSave.unsaveable(world), "", "a plain agent cannot be written")
	assert_eq(WorldSave.to_text(world), "", "and nothing is produced")


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
		fields[found.get_slice(":", 0).get_slice(" ", 0).get_slice(".", -1)] = true
	assert_eq(fields.keys(), ["held_up", "store"], "both changes are found, and nothing else")


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
