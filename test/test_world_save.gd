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


## State the running game cannot produce: a fraction where a tile or a count
## goes, an amount below nothing or above what holds it, a herd below its floor.
func test_a_save_with_state_the_game_cannot_reach_is_refused() -> void:
	var good := WorldSave.encode(_populated_world())
	var damage := {
		"a node at a fractional tile": [
			func(d): d["nodes"][0]["coord"][0] = d["nodes"][0]["coord"][0] + 0.5, "whole"],
		"a herd at a fractional tile": [
			func(d): _first_of(d, "herd")["coord"][1] = _first_of(d, "herd")["coord"][1] + 0.25, "whole"],
		"a citizen at a fractional tile": [
			func(d): _first_of(d, "citizen")["coord"][0] = _first_of(d, "citizen")["coord"][0] - 0.5, "whole"],
		"a route step at a fractional tile": [
			func(d): d["routes"][0]["path"][1][0] = d["routes"][0]["path"][1][0] + 0.5, "whole"],
		"a coordinate too large to be an integer": [
			func(d): d["nodes"][0]["coord"][0] = 1e30, "whole"],
		"a store above its capacity": [
			func(d): d["nodes"][0]["store"] = WorldSave._exact(d["nodes"][0]["capacity"]["value"] + 1.0), "store"],
		"a negative store": [
			func(d): d["nodes"][0]["store"] = WorldSave._exact(-1.0), "negative"],
		"a negative last yield": [
			func(d): d["nodes"][0]["last_yield"] = WorldSave._exact(-0.5), "negative"],
		"a negative took-in": [
			func(d): d["nodes"][0]["took_in"] = WorldSave._exact(-0.5), "negative"],
		"a negative gave-out": [
			func(d): d["nodes"][0]["gave_out"] = WorldSave._exact(-0.5), "negative"],
		"a negative mouth count": [
			func(d): d["nodes"][0]["mouths"] = -1, "negative"],
		"a negative unmet": [
			func(d): d["nodes"][0]["unmet"] = WorldSave._exact(-0.5), "negative"],
		"a negative plenty run": [
			func(d): d["nodes"][0]["plentiful_turns"] = -1, "negative"],
		"a negative year length": [
			func(d): d["nodes"][0]["year_turns"] = -1, "negative"],
		"a negative year asked": [
			func(d): d["nodes"][0]["year_asked"] = WorldSave._exact(-0.5), "negative"],
		"a negative year unmet": [
			func(d): d["nodes"][0]["year_unmet"] = WorldSave._exact(-0.5), "negative"],
		"a year unmet beyond a year asked": [_overdraw_the_year, "exceeds"],
		"a citizen with a negative sack": [
			func(d): _first_of(d, "citizen")["capacity"] = WorldSave._exact(-1.0), "negative"],
		"a citizen carrying more than the sack holds": [
			func(d): _first_of(d, "citizen")["carrying"] = WorldSave._exact(_first_of(d, "citizen")["capacity"]["value"] + 1.0), "capacity"],
		"a citizen carrying less than nothing": [
			func(d): _first_of(d, "citizen")["carrying"] = WorldSave._exact(-1.0), "negative"],
		"a citizen held up a negative time": [
			func(d): _first_of(d, "citizen")["held_up"] = -1, "held up"],
		"a citizen held up past the cap": [
			func(d): _first_of(d, "citizen")["held_up"] = Citizen.MAX_HELD_UP + 1, "held up"],
		"a herd below its species' floor": [
			func(d): _first_of(d, "herd")["population"] = WorldSave._exact(Species.grazer().minimum_population - 0.5), "minimum"],
		"a herd that planned in a season that does not exist": [
			func(d): _first_of(d, "herd")["planned_in"] = 99, "season"],
		"a herd that planned in a season before the first": [
			func(d): _first_of(d, "herd")["planned_in"] = -2, "season"],
	}
	for what in damage:
		var copy: Dictionary = JSON.parse_string(JSON.stringify(good, "", false, true))
		damage[what][0].call(copy)
		var result := WorldSave.decode(copy)
		assert_null(result["world"], "%s gives no world" % what)
		assert_string_contains(result["refusal"], damage[what][1], "%s is refused for the right reason" % what)


## The edges of what the game can reach are still loadable and come back exactly.
func test_state_at_its_limits_still_round_trips() -> void:
	var world := _populated_world()
	var people := world.citizens()
	var node: CityNode = world.nodes[0]
	node.store = node.capacity
	node.year_unmet = node.year_asked
	node.mouths = 0
	var walker: Citizen = people[0]
	walker.carrying = walker.capacity
	walker.held_up = Citizen.MAX_HELD_UP
	var cold: Citizen = people[1]
	cold.carrying = 0.0
	cold.held_up = 0
	var herd: Herd = null
	for agent in world.agents:
		if agent is Herd:
			herd = agent
	world.set_herd_population(herd, herd.species.minimum_population)
	herd._planned_in = -1
	var bare: CityNode = world.nodes[1]
	bare.capacity = 0.0
	bare.store = 0.0
	var loaded := _round_trip(world)
	assert_not_null(loaded, "the limits themselves are in range")
	assert_eq(_differences(world, loaded), PackedStringArray(), "and come back unchanged")


## Corruption that crosses a real conversion, allocator or bounded-history rule:
## a value that would wrap or become infinite when narrowed, an id the next
## allocation would reuse, a herd in the sea, a road below its crew, a demand row
## that is not the agents' census, a chronicle longer than its window.
func test_a_save_that_would_wrap_overflow_or_collide_is_refused() -> void:
	var good := WorldSave.encode(_populated_world())
	var tiles: int = good["terrain"].size()
	var wrapped_terrain := func(d): d["terrain"][0] = 4294967296.0 + float(d["terrain"][0])
	var damage := {
		"terrain that wraps into a real terrain": [wrapped_terrain, "32-bit"],
		"fractional terrain": [func(d): d["terrain"][0] = 1.5, "32-bit"],
		"a demand of 1e100": [func(d): d["forage_demand"][0] = 1e100, "finite"],
		"a demand that is NaN": [func(d): d["forage_demand"][0] = NAN, "finite"],
		"a demand of +infinity": [func(d): d["forage_demand"][0] = INF, "finite"],
		"a demand of -infinity": [func(d): d["forage_demand"][0] = -INF, "finite"],
		"a vitality of 1e100": [func(d): d["vitality"][0][0] = 1e100, "finite"],
		"a turn-start demand of 1e100": [func(d): d["forage_demand_at_turn_start"][0] = 1e100, "finite"],
		"a turn-start vitality of NaN": [func(d): d["grazing_vitality_at_turn_start"][0] = NAN, "finite"],
		"a chronicle reading of 1e100": [func(d): d["chronicle"][d["chronicle"].keys()[0]][0] = 1e100, "finite"],
		"a chronicle reading of -infinity": [func(d): d["chronicle"][d["chronicle"].keys()[0]][0] = -INF, "finite"],
		"a store too large for the reports": [func(d): d["nodes"][0]["capacity"] = WorldSave._exact(1e300); d["nodes"][0]["store"] = WorldSave._exact(1e300), "too large"],
		"a herd too large for the reports": [func(d): _first_of(d, "herd")["population"] = WorldSave._exact(1e300), "too large"],
		"a node tile a whole lap of 2^32 away": [func(d): d["nodes"][0]["coord"][0] = d["nodes"][0]["coord"][0] + 4294967296.0, "whole"],
		"a herd tile a lap away": [func(d): _first_of(d, "herd")["coord"][1] = _first_of(d, "herd")["coord"][1] - 4294967296.0, "whole"],
		"a citizen tile a lap away": [func(d): _first_of(d, "citizen")["coord"][0] = _first_of(d, "citizen")["coord"][0] + 4294967296.0, "whole"],
		"a route step a lap away": [func(d): d["routes"][0]["path"][0][0] = d["routes"][0]["path"][0][0] + 4294967296.0, "whole"],
		"a herd start a lap away": [func(d): _first_of(d, "herd")["start_coord"][0] = 4294967296.0, "whole"],
		"a herd destination a lap away": [func(d): _first_of(d, "herd")["destination"][1] = -4294967296.0, "whole"],
		"a structure id equal to the count": [func(d): d["nodes"][0]["id"] = d["nodes"].size(), "outside"],
		"a negative structure id": [func(d): d["nodes"][0]["id"] = -1, "outside"],
		"a road id equal to the count": [func(d): d["routes"][0]["id"] = d["routes"].size(), "outside"],
		"a negative road id": [func(d): d["routes"][0]["id"] = -1, "outside"],
		"a negative agent id": [func(d): _first_of(d, "herd")["id"] = -1, "outside"],
		"an agent id past the exact-integer birth boundary": [func(d): _first_of(d, "herd")["id"] = 9007199254740992.0, "outside"],
		"a carrier id that wraps": [func(d): d["routes"][0]["carriers"][0] = 1e30, "carrier"],
		"a herd in the sea": [_drown_a_herd, "water"],
		"a road below its crew": [_thin_a_road, "fewer"],
		"a demand row of zeros": [func(d): d["forage_demand"] = _zeros(tiles), "forage demand"],
		"a demand row for another herd": [func(d): _first_of(d, "herd")["population"] = WorldSave._exact(_first_of(d, "herd")["population"]["value"] + 5.0), "forage demand"],
		"demand left on an empty tile": [func(d): _add_demand_on_an_empty_tile(d, 3.0), "forage demand"],
		"a chronicle one reading over its window": [_overfill_the_chronicle, "window"],
	}
	for what in damage:
		var copy: Dictionary = JSON.parse_string(JSON.stringify(good, "", false, true))
		damage[what][0].call(copy)
		var result := WorldSave.decode(copy)
		assert_null(result["world"], "%s gives no world" % what)
		assert_string_contains(result["refusal"], damage[what][1], "%s is refused for the right reason" % what)


func test_the_boundaries_of_the_new_checks_still_load() -> void:
	var good := WorldSave.encode(_populated_world())
	var fresh := WorldSave.encode(WorldGen.generate(SEED))
	var tolerated := {
		"an agent id at the exact-integer limit": func(d): _first_of(d, "herd")["id"] = float(WorldSave.MAX_AGENT_ID),
		"a small negative residue on an empty tile": func(d): _add_demand_on_an_empty_tile(d, -1e-5),
		"a chronicle series of exactly the window": func(d): _fill_the_chronicle(d, Chronicle.WINDOW),
		"an unknown chronicle series": func(d): d["chronicle"]["not_a_series"] = [1.0, 2.0],
		"a chronicle series left empty": func(d): _fill_the_chronicle(d, 0),
	}
	for what in tolerated:
		var copy: Dictionary = JSON.parse_string(JSON.stringify(good, "", false, true))
		tolerated[what].call(copy)
		var result := WorldSave.decode(copy)
		assert_eq(result["refusal"], "", "%s still loads" % what)
		assert_not_null(result["world"], "%s gives a world" % what)
	assert_eq(WorldSave.decode(fresh)["refusal"], "", "a fresh world, with empty chronicle rows, loads")


func _granary_of(world: WorldMap) -> CityNode:
	for node in world.nodes:
		if node.kind == CityNode.Kind.GRANARY:
			return node
	return null


## A quantity can be finite as a 32-bit float and still break what reads it: the
## report's `floori(value / step)` and a herd's `roundi` are undefined past a
## 64-bit integer, and two finite float32 readings can sum to infinity in the
## chronicle. Each case is made on the world itself (so the demand census stays
## coherent), written, and must be refused on the way back.
func test_quantities_the_reports_cannot_digest_are_refused() -> void:
	assert_true(is_finite(PackedFloat32Array([1e30])[0]), "1e30 is a finite float32, so narrowing alone lets it through")
	assert_true(is_finite(PackedFloat32Array([3e38])[0]), "so is 3e38, near the float32 ceiling, though two of them sum past it")
	var damage := {
		"a store and capacity of 1e30": func(w: WorldMap):
			var granary := _granary_of(w)
			granary.capacity = 1e30
			granary.store = 1e30,
		"a capacity of 1e30": func(w: WorldMap): _granary_of(w).capacity = 1e30,
		"a herd of 1e30 with its census to match": func(w: WorldMap):
			var herd: Herd = w.herds()[0]
			w.set_herd_population(herd, 1e30),
		"two herds of 3e38 whose total overflows float32": func(w: WorldMap):
			w.set_herd_population(w.herds()[0], 3e38)
			w.set_herd_population(w.herds()[1], 3e38),
		"two stores of 3e38 whose total overflows float32": func(w: WorldMap):
			var granaries: Array[CityNode] = []
			for node in w.nodes:
				if node.kind == CityNode.Kind.GRANARY:
					granaries.append(node)
			for granary in granaries.slice(0, 2):
				granary.capacity = 3e38
				granary.store = 3e38,
		"a carrier holding 1e30": func(w: WorldMap):
			var walker: Citizen = w.citizens()[0]
			walker.capacity = 1e30
			walker.carrying = 1e30,
	}
	for what in damage:
		var world := _populated_world()
		assert_gt(world.herds().size(), 1, "the fixture has two herds")
		damage[what].call(world)
		var result := WorldSave.decode(WorldSave.encode(world))
		assert_null(result["world"], "%s gives no world" % what)
		assert_string_contains(result["refusal"], "too large", "%s is refused for the right reason" % what)


func test_the_largest_accepted_quantities_still_load_and_run() -> void:
	var world := _populated_world()
	var granary := _granary_of(world)
	granary.capacity = WorldSave.MAX_MAGNITUDE
	granary.store = WorldSave.MAX_MAGNITUDE
	world.set_herd_population(world.herds()[0], WorldSave.MAX_MAGNITUDE / 2.0)
	var loaded := _round_trip(world)
	assert_not_null(loaded, "the limit itself is accepted for stores, half of it for what the agents ask in all")
	assert_eq(_differences(world, loaded), PackedStringArray(), "and comes back unchanged")
	for i in range(3):
		loaded.advance_turn()
	for key in loaded.chronicle._series:
		for value in loaded.chronicle._series[key]:
			assert_true(is_finite(value), "the chronicle stays finite beside a limit-sized quantity")
	assert_gt(loaded.herds()[0].head_count(), 0, "a limit-sized herd can be counted")


## The clock is written as a decimal string so it is exact over the whole int64
## range, not only to 2^53 where a JSON number stops being exact.
func _with_turn(good: Dictionary, turn) -> Dictionary:
	var copy: Dictionary = JSON.parse_string(JSON.stringify(good, "", false, true))
	copy["turn"] = turn
	return copy


func test_turns_around_two_to_the_fifty_three_save_and_load_exactly() -> void:
	var world := _populated_world()
	for turn in [9007199254740991, 9007199254740992, 9007199254740993, WorldMap.LAST_TURN]:
		world.turn = turn
		var data := WorldSave.encode(world)
		assert_eq(data["turn"], str(turn), "written as text")
		var loaded := _round_trip(world)
		assert_eq(loaded.turn, turn, "turn %d comes back exactly" % turn)
		assert_eq(_differences(world, loaded), PackedStringArray(), "and nothing else moved")


func test_a_legacy_numeric_turn_still_loads() -> void:
	var good := WorldSave.encode(_populated_world())
	for turn in [0.0, 150.0, 9007199254740991.0]:
		var loaded = WorldSave.decode(_with_turn(good, turn))["world"]
		assert_not_null(loaded, "numeric turn %d loads" % int(turn))
		assert_eq(loaded.turn, int(turn))


func test_advancing_across_two_to_the_fifty_three_stays_exact() -> void:
	var original := _populated_world()
	original.turn = 9007199254740990
	var loaded := _round_trip(original)
	for i in range(6):
		original.advance_turn()
		loaded.advance_turn()
	assert_eq(original.turn, 9007199254740996, "the clock crossed 2^53 without losing a turn")
	assert_eq(loaded.turn, original.turn)
	assert_eq(_differences(original, loaded), PackedStringArray(), "the loaded world kept pace")
	var again := _round_trip(loaded)
	assert_eq(again.turn, original.turn, "and saves exactly after the crossing")
	assert_eq(_differences(loaded, again), PackedStringArray())


func test_an_unrepresentable_turn_is_refused() -> void:
	var good := WorldSave.encode(_populated_world())
	var bad := ["9223372036854775808", "99999999999999999999", "18446744073709551616", "-1", "1.5", "",
			"12a", " 5", "+5", -1.0, 1.5, 1e19, 9007199254740993.0 * 4.0]
	for turn in bad:
		var result := WorldSave.decode(_with_turn(good, turn))
		assert_null(result["world"], "turn %s is refused" % str(turn))
		assert_string_contains(result["refusal"], "turn", "and the refusal names the turn")


func test_the_last_turn_is_terminal_and_a_refused_advance_changes_nothing() -> void:
	var world := _populated_world()
	world.turn = WorldMap.LAST_TURN
	var before := _round_trip(world)
	assert_ne(world.advance_refusal(), "", "the clock says why it will not advance")
	var returned := world.advance_turn()
	assert_eq(returned, WorldMap.LAST_TURN, "the turn is reported unchanged, not wrapped")
	assert_eq(world.turn, WorldMap.LAST_TURN)
	assert_eq(_differences(before, world), PackedStringArray(), "the whole world is as it was")
	world.turn = WorldMap.LAST_TURN - 1
	assert_eq(world.advance_refusal(), "", "one turn short, it advances")
	assert_eq(world.advance_turn(), WorldMap.LAST_TURN, "and lands on the last turn")


## The ceiling on agent ids is a place the game itself can reach from a loaded
## save: the next birth. It must get an id that is still in the range, unique and
## deterministic, rename nobody already in the world, and leave a world that
## saves and loads again.
func test_a_birth_after_the_top_agent_id_stays_in_range_and_saves() -> void:
	var world := _populated_world()
	var herd: Herd = world.herds()[0]
	herd.id = WorldSave.MAX_AGENT_ID
	var loaded := _round_trip(world)
	assert_not_null(loaded, "the accepted boundary id loads")
	var held_before := {}
	for agent in loaded.agents:
		held_before[agent.id] = agent
	var births_on := _plenty_only_at_the_granary(loaded)
	var before := loaded.agents.size()
	CityGen.tend_population(loaded)
	assert_eq(loaded.agents.size(), before + 1, "the birth happened")
	var born: Citizen = loaded.agents[loaded.agents.size() - 1]
	var lowest_free := 0
	while held_before.has(lowest_free):
		lowest_free += 1
	assert_eq(born.id, lowest_free, "the newcomer takes the lowest id nobody holds")
	assert_false(held_before.has(born.id), "and it collides with nobody")
	assert_lte(born.id, WorldSave.MAX_AGENT_ID, "and is inside the saveable range")
	assert_eq(born.route.carriers.back(), born.id, "it is the newest on its road, as ever")
	assert_eq(births_on, born.route.sink, "at the granary that grew")
	for id in held_before:
		assert_same(loaded.agents[loaded.agents.find(held_before[id])], held_before[id], "nobody was renumbered")
		assert_eq(held_before[id].id, id, "ids held before are unchanged")
	var again := _round_trip(loaded)
	assert_not_null(again, "the world after the birth saves and loads")
	assert_eq(_differences(loaded, again), PackedStringArray(), "unchanged")
	for i in range(50):
		loaded.advance_turn()
		again.advance_turn()
	assert_eq(_differences(loaded, again), PackedStringArray(), "and runs on identically")


func test_births_far_from_the_ceiling_keep_the_counter_order() -> void:
	var world := _round_trip(_populated_world())
	var highest := -1
	for agent in world.agents:
		highest = maxi(highest, agent.id)
	_plenty_only_at_the_granary(world)
	CityGen.tend_population(world)
	var born: Citizen = world.agents[world.agents.size() - 1]
	assert_eq(born.id, highest + 1, "ordinary births take one past the highest id")


## Everything quiet except one granary that has had plenty for long enough; the
## granary is returned. Only a birth can follow from `tend_population()`.
func _plenty_only_at_the_granary(world: WorldMap) -> CityNode:
	for node in world.nodes:
		node.plentiful_turns = 0
		node.year_turns = 0
	var granary := _granary_of(world)
	granary.plentiful_turns = CityNode.GROWTH_TURNS
	return granary


func test_a_world_larger_than_a_save_holds_is_refused_at_save_time() -> void:
	var big := WorldGen.generate(SEED, WorldGen.DEFAULT_WIDTH + 1, WorldGen.DEFAULT_HEIGHT)
	assert_string_contains(WorldSave.unsaveable(big), "tiles")
	assert_eq(WorldSave.to_text(big), "", "nothing is written for it")
	assert_ne(WorldSave.write_file(big, "user://test_oversize_save.json"), "", "and a file save says why")
	assert_false(FileAccess.file_exists("user://test_oversize_save.json"), "and leaves no file")
	var exact := WorldGen.generate(SEED, 30, 40)
	assert_eq(WorldSave.unsaveable(exact), "", "the same tile count in another shape is within the limit")
	assert_eq(_differences(exact, _round_trip(exact)), PackedStringArray(), "and round-trips")


## A world loaded from a save can keep growing: a placement and a road after the
## load take the next ids, and that world saves and loads again unchanged.
func test_placing_and_connecting_after_a_load_keeps_ids_clean() -> void:
	var loaded := _round_trip(_populated_world())
	var granary: CityNode = null
	for node in loaded.nodes:
		if node.kind == CityNode.Kind.GRANARY:
			granary = node
	var placed := false
	for coord in loaded.grid.all_coords():
		if not placed and HexGrid.distance(coord, granary.coord) == 3 and CityGen.can_place_node(loaded, coord):
			var farm := CityGen.place_node(loaded, coord, CityNode.Kind.FARM)
			placed = CityGen.connect_nodes(loaded, farm, granary) != null
	assert_true(placed, "there was room to build after the load")
	for i in range(30):
		loaded.advance_turn()
	assert_eq(_differences(loaded, _round_trip(loaded)), PackedStringArray(), "and it saves again unchanged")


func test_loaded_and_advanced_worlds_hold_nothing_non_finite() -> void:
	var world := _round_trip(_populated_world())
	for i in range(100):
		world.advance_turn()
	var rows := [world._forage_demand, world._forage_demand_at_turn_start,
		world._grazing_vitality_at_turn_start, world._vitality[0], world._vitality[1]]
	for key in world.chronicle._series:
		rows.append(world.chronicle._series[key])
	for row in rows:
		for value in row:
			assert_true(is_finite(value), "every row value is finite")
	for node in world.nodes:
		assert_true(is_finite(node.store) and is_finite(node.last_yield), "node numbers are finite")
	for herd in world.herds():
		assert_true(is_finite(herd.population), "herd populations are finite")


## The census check has to hold for worlds the game really produced: several
## seeds, a thousand turns, saved and loaded at the end. The worst per-tile gap
## between the row the world maintains and a fresh sum is printed so the tolerance
## in `WorldSave` can be checked against it.
func test_the_saved_demand_row_stays_within_tolerance_over_long_runs() -> void:
	var worst := 0.0
	for seed_value in [SEED, 1, 2, 3]:
		var world := WorldGen.generate(seed_value)
		for i in range(1000):
			world.advance_turn()
			if i % 250 != 249:
				continue
			var census := PackedFloat64Array()
			census.resize(world.grid.tile_count())
			for agent in world.agents:
				census[world.grid.index_of(agent.coord)] += agent.forage_demand()
			for t in range(census.size()):
				worst = maxf(worst, absf(world._forage_demand[t] - census[t]) / maxf(1.0, census[t]))
			assert_eq(WorldSave.from_text(WorldSave.to_text(world))["refusal"], "",
				"seed %d at turn %d loads" % [seed_value, world.turn])
	gut.p("worst relative demand drift over the long runs: %s (tolerance %s)" % [worst, WorldSave._Reader.DEMAND_TOLERANCE])
	assert_lt(worst, WorldSave._Reader.DEMAND_TOLERANCE / 10.0, "the tolerance has ten times the observed drift")


static func _zeros(count: int) -> Array:
	var out := []
	out.resize(count)
	out.fill(0.0)
	return out


static func _drown_a_herd(data: Dictionary) -> void:
	var grid := HexGrid.new(int(data["width"]), int(data["height"]))
	for i in range(data["terrain"].size()):
		if int(data["terrain"][i]) == WorldGen.Terrain.WATER:
			var coord := grid.coord_at(i)
			_first_of(data, "herd")["coord"] = [coord.x, coord.y]
			return


# Drops the newest carrier from road 0 and the citizen with it, leaving a crew
# one short of `CITIZENS_PER_ROUTE`; everything else stays consistent.
static func _thin_a_road(data: Dictionary) -> void:
	var carriers: Array = data["routes"][0]["carriers"]
	while carriers.size() >= CityGen.CITIZENS_PER_ROUTE:
		var gone = carriers.pop_back()
		for i in range(data["agents"].size()):
			if data["agents"][i]["id"] == gone:
				data["agents"].remove_at(i)
				break


static func _an_empty_tile(data: Dictionary) -> int:
	var occupied := {}
	var grid := HexGrid.new(int(data["width"]), int(data["height"]))
	for agent in data["agents"]:
		occupied[grid.index_of(Vector2i(int(agent["coord"][0]), int(agent["coord"][1])))] = true
	for i in range(data["terrain"].size()):
		if not occupied.has(i):
			return i
	return -1


static func _add_demand_on_an_empty_tile(data: Dictionary, amount: float) -> void:
	data["forage_demand"][_an_empty_tile(data)] = amount


static func _fill_the_chronicle(data: Dictionary, count: int) -> void:
	for key in data["chronicle"]:
		var row := []
		for i in range(count):
			row.append(float(i))
		data["chronicle"][key] = row


static func _overfill_the_chronicle(data: Dictionary) -> void:
	_fill_the_chronicle(data, Chronicle.WINDOW + 1)


func _overdraw_the_year(data: Dictionary) -> void:
	data["nodes"][0]["year_asked"] = WorldSave._exact(1.0)
	data["nodes"][0]["year_unmet"] = WorldSave._exact(2.0)


static func _first_of(data: Dictionary, kind: String) -> Dictionary:
	for entry in data["agents"]:
		if entry["kind"] == kind:
			return entry
	return {}


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


func test_advancing_a_terminal_world_shows_the_reason_and_stops_play() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	main.world.turn = WorldMap.LAST_TURN
	main.set_playing(true)
	assert_true(main.playing, "play was on")

	var returned := main.advance_turn()

	assert_eq(returned, WorldMap.LAST_TURN, "the clock did not move")
	assert_eq(main.world.turn, WorldMap.LAST_TURN, "the world did not move")
	assert_false(main.playing, "play stops")
	assert_string_contains(main.get_node("Prompt").text, main.world.advance_refusal())
	assert_string_contains(main.get_node("Prompt").text, "last turn")


func test_a_normal_advance_leaves_the_prompt_free_of_a_refusal() -> void:
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	main.advance_turn()
	assert_eq(main.world.turn, 1, "it advanced")
	assert_string_does_not_contain(main.get_node("Prompt").text, "last turn")


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
	copy["id"] = data["routes"].size()
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
