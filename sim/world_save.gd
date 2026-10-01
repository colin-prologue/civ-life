class_name WorldSave
extends RefCounted

## A world written to text and read back.
##
## **What a world's state is.** `AgDR-009` once said a save was two numbers, seed
## and turn. That stopped being true the moment a herd's position carried from
## one turn to the next, and `AgDR-022` states what replaced it: the `WorldMap`
## and everything hanging off it, minus the handful of things that are provably
## a function of the rest. `SAVED` below is that answer written as a list, one
## entry per class, and `NOT_SAVED` is the short list of exceptions with the
## reason each one is allowed to be one.
##
## **The lists are checked, not trusted.** `test/test_world_save.gd` reads every
## script variable off every object reachable from a populated world and fails if
## one is on neither list. A future ticket that adds state to `WorldMap` — or to
## a herd, a node, a route — and does not come here turns the suite red. That is
## the whole reason the lists exist rather than the encoder simply being written
## out: the encoder below is plain hand-written code, and the lists are what make
## forgetting to extend it loud.
##
## **Plain JSON, written by hand.** Godot's variant text format would carry
## `Vector2i` and packed arrays for free, but it would also parse objects out of
## a file, and the file stops being something a person or another tool can read
## without knowing Godot. Every value here is a number, a string, an array or a
## dictionary.
##
## **Floats, and the one place the plain encoding was not enough.** The large
## per-tile rows are 32-bit and are written as ordinary numbers: text at full
## precision parses back within a hair of the double, which always rounds to the
## same 32-bit value. The 64-bit scalars — a herd's population, a store, what a
## carrier holds — did not survive that. Measured: Godot's JSON came back one
## unit in the last place on six herds of fourteen, and a world loaded that way
## diverged from the original within 500 turns. So each of those is written as
## `{"value": <readable number>, "bits": "<the 8 bytes in hex>"}`. The bits are
## what load; the number is there to be read, and a file whose number was edited
## without its bits is refused rather than half-believed.
##
## Integers survive JSON only up to 2^53, because a JSON number is read back as a
## double. Every integer here is far below that except the seed, which a player
## may type as anything, so the seed is written as a string.
##
## **Refusals are prose.** A save that cannot be read comes back as a sentence
## and no world, never as a world that is subtly wrong (`AgDR-018`'s shape for
## refusals). A version this code does not know is refused outright: there is no
## migration, and guessing is exactly the failure a version number is for.

const FORMAT := "civ-life-world"

## Bump this when the shape of the file changes. Loading any other number is
## refused, including older ones — there is no migration path yet.
const VERSION := 1

## The most tiles a save holds: the size world generation produces, since no
## player-facing control makes a map any other size. `WorldGen.generate()` will
## build a larger world when asked, but that world is outside what a save can
## carry, so `encode()` refuses it as `decode()` would rather than writing a file
## this build then cannot read back.
const MAX_TILES := WorldGen.DEFAULT_WIDTH * WorldGen.DEFAULT_HEIGHT

## The largest agent id a save accepts, and the largest the game hands out
## (`CityGen.MAX_AGENT_ID`): a JSON number holds integers exactly up to 2^53, and
## `CityGen._next_agent_id()` falls back to the lowest free id rather than pass it,
## so every birth after a load is still written and read back exactly.
const MAX_AGENT_ID := CityGen.MAX_AGENT_ID

## The largest absolute value a stored quantity (a store, a capacity, what a
## carrier holds, a herd's population, a yield or a flow) may have. Not a balance
## limit: the reports turn a quantity into a whole number with `floori(value /
## step)` and `roundi`, which are undefined past a 64-bit integer, and the
## per-turn totals are summed into 32-bit chronicle rows. 2^62 is the largest
## power of two a 64-bit integer holds with room, and it keeps any sum short of
## float32's ceiling unless the world holds some 10^20 agents.
const MAX_MAGNITUDE := 4611686018427387904.0

## The turn is written as a decimal string, as the seed is: a JSON number is a
## double, exact only to 2^53, and the clock is a 64-bit integer. Any turn up to
## `WorldMap.LAST_TURN` saves and loads exactly. A plain whole JSON number (older
## saves) is still read, within the range a double holds exactly.

## Every script variable of every class in a world's object graph that is written
## to the file. Base-class variables are listed under each subclass, because an
## instance reports them as its own.
const SAVED := {
	"WorldMap": [
		"grid", "world_seed", "turn", "agents", "nodes", "routes", "chronicle",
		"_terrain", "_vitality", "_forage_demand",
		"_forage_demand_at_turn_start", "_grazing_vitality_at_turn_start",
	],
	"HexGrid": ["width", "height"],
	"Chronicle": ["_series"],
	"CityNode": [
		"id", "coord", "kind", "store", "capacity", "last_yield", "took_in", "gave_out",
		# The hunger books (#29). `mouths` and `unmet` clear with the flows each
		# turn, exactly as `took_in` and `gave_out` do, and are saved for the same
		# reason: a loaded world should be the world that was saved, down to what
		# its panels were showing. The other four carry between turns and decide
		# whether a road gains or loses a walker, so a world that lost them would
		# reload and then grow differently — measured, before they were saved, as
		# 30 people against 36 five hundred turns after the same save.
		"mouths", "unmet", "plentiful_turns", "year_turns", "year_asked", "year_unmet",
	],
	# `carriers` is the road's own list of who walks it (#29), kept as ids. It is
	# not derived: `CityGen` maintains it as the one place carriers are made and
	# lost, and the growth rule reads it inside the turn loop. Rebuilding it on
	# load by scanning agents would also mean rebuilding its order, which is the
	# order growth and loss pick from.
	"Route": ["id", "source", "sink", "path", "carriers"],
	"Herd": ["id", "coord", "species", "population", "start_coord", "_destination", "_planned_in"],
	"Citizen": ["id", "coord", "route", "carrying", "capacity", "_index", "held_up"],
	"Species": [
		"name", "consumption_per_head", "growth_rate", "decline_rate",
		"move_range", "sense_range", "minimum_population", "starting_population",
	],
}

## Script variables deliberately left out of the file, and why each is allowed to
## be. The bar is that the value is a pure function of what *is* saved, or is
## read by nothing before the next turn rewrites it.
##
## `_forage_demand` is conspicuously absent from this list. It is documented as a
## cache of the agents' demand, but it is maintained by float addition and
## subtraction and drifts from the exact sum; decisions read the drifted value
## (a citizen's `<= 0.0` hold-up test among them), so recomputing it on load
## produced a world that diverged from the original within a few hundred turns.
## It is state, and it is saved verbatim.
const NOT_SAVED := {
	"WorldMap": {
		"_forage": "a pure function of terrain and season, recomputed on load (AgDR-009)",
		"report": "a comparison against the turn just run; rebuilt by the next advance_turn()",
	},
}


## The world as a dictionary of plain values, or an empty dictionary if it holds
## something this format cannot write — see `unsaveable()`.
static func encode(world: WorldMap) -> Dictionary:
	if not unsaveable(world).is_empty():
		return {}

	var species: Array[Species] = []
	var agents := []
	for agent in world.agents:
		if agent is Herd:
			var herd := agent as Herd
			if not species.has(herd.species):
				species.append(herd.species)
			agents.append({
				"kind": "herd",
				"id": herd.id,
				"coord": _coord_out(herd.coord),
				"species": species.find(herd.species),
				"population": _exact(herd.population),
				"start_coord": _coord_out(herd.start_coord),
				"destination": _coord_out(herd._destination),
				"planned_in": herd._planned_in,
			})
		else:
			var citizen := agent as Citizen
			agents.append({
				"kind": "citizen",
				"id": citizen.id,
				"coord": _coord_out(citizen.coord),
				"route": world.routes.find(citizen.route),
				"carrying": _exact(citizen.carrying),
				"capacity": _exact(citizen.capacity),
				"index": citizen._index,
				"held_up": citizen.held_up,
			})

	var species_out := []
	for kind in species:
		species_out.append({
			"name": kind.name,
			"consumption_per_head": _exact(kind.consumption_per_head),
			"growth_rate": _exact(kind.growth_rate),
			"decline_rate": _exact(kind.decline_rate),
			"move_range": kind.move_range,
			"sense_range": kind.sense_range,
			"minimum_population": _exact(kind.minimum_population),
			"starting_population": _exact(kind.starting_population),
		})

	var nodes := []
	for node in world.nodes:
		nodes.append({
			"id": node.id,
			"coord": _coord_out(node.coord),
			"kind": node.kind,
			"store": _exact(node.store),
			"capacity": _exact(node.capacity),
			"last_yield": _exact(node.last_yield),
			"took_in": _exact(node.took_in),
			"gave_out": _exact(node.gave_out),
			"mouths": node.mouths,
			"unmet": _exact(node.unmet),
			"plentiful_turns": node.plentiful_turns,
			"year_turns": node.year_turns,
			"year_asked": _exact(node.year_asked),
			"year_unmet": _exact(node.year_unmet),
		})

	var routes := []
	for route in world.routes:
		var path := []
		for coord in route.path:
			path.append(_coord_out(coord))
		var carriers := []
		for who in route.carriers:
			carriers.append(who)
		routes.append({
			"id": route.id,
			"source": world.nodes.find(route.source),
			"sink": world.nodes.find(route.sink),
			"path": path,
			"carriers": carriers,
		})

	var vitality := []
	for use in range(Land.USE_COUNT):
		vitality.append(Array(world._vitality[use]))

	var chronicle := {}
	for key in world.chronicle._series:
		chronicle[key] = Array(world.chronicle._series[key])

	return {
		"format": FORMAT,
		"version": VERSION,
		"seed": str(world.world_seed),
		"turn": str(world.turn),
		"width": world.grid.width,
		"height": world.grid.height,
		"terrain": Array(world._terrain),
		"vitality": vitality,
		"forage_demand": Array(world._forage_demand),
		"forage_demand_at_turn_start": Array(world._forage_demand_at_turn_start),
		"grazing_vitality_at_turn_start": Array(world._grazing_vitality_at_turn_start),
		"species": species_out,
		"nodes": nodes,
		"routes": routes,
		"agents": agents,
		"chronicle": chronicle,
	}


## Why this world cannot be written, or an empty string if it can.
##
## An agent of a kind the format does not know is refused at save time rather
## than written as something the loader will choke on. The day a third kind of
## agent exists, this is the line that says so.
static func unsaveable(world: WorldMap) -> String:
	if world.grid.tile_count() > MAX_TILES:
		return "this world has %d tiles and a save holds at most %d" % [world.grid.tile_count(), MAX_TILES]
	for agent in world.agents:
		if not (agent is Herd or agent is Citizen):
			return "agent %d is a kind this save format does not know how to write" % agent.id
		if agent is Herd and not is_supported_species((agent as Herd).species):
			return "herd %d is a species this build cannot load back" % agent.id
		if agent is Citizen and not world.routes.has((agent as Citizen).route):
			return "citizen %d walks a route that is not in the world" % agent.id
	for route in world.routes:
		if not (world.nodes.has(route.source) and world.nodes.has(route.sink)):
			return "route %d joins a structure that is not in the world" % route.id
	return ""


## The one species this build plays with is `Species.grazer()`, and a save is only
## loadable if its herds are of it: the numbers drive `Herd._best_ground()`'s
## search radius and every herd's feeding, so a decoded species is held to the
## preset rather than to an invented range. A second preset is the day this changes.
static func is_supported_species(kind: Species) -> bool:
	var preset := Species.grazer()
	return kind.name == preset.name \
			and kind.consumption_per_head == preset.consumption_per_head \
			and kind.growth_rate == preset.growth_rate \
			and kind.decline_rate == preset.decline_rate \
			and kind.move_range == preset.move_range \
			and kind.sense_range == preset.sense_range \
			and kind.minimum_population == preset.minimum_population \
			and kind.starting_population == preset.starting_population


## The world as inspectable JSON text, or an empty string if it cannot be written.
static func to_text(world: WorldMap) -> String:
	var data := encode(world)
	if data.is_empty():
		return ""
	return JSON.stringify(data, "\t", false, true)


## Read a world back from JSON text. Returns `{"world": WorldMap, "refusal": ""}`
## on success and `{"world": null, "refusal": "<why>"}` on anything else.
static func from_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _refused("this is not a readable save (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _refused("this is not a readable save")
	return decode(json.data)


## Rebuild a world from the dictionary `encode()` produced.
##
## Format and version are checked before anything else is looked at, so a file
## from a future version is refused for being from a future version and not for
## whichever of its fields happened to be read first.
static func decode(data: Dictionary) -> Dictionary:
	if data.get("format") != FORMAT:
		return _refused("this is not a %s save" % FORMAT)
	var version = data.get("version")
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or float(version) != float(VERSION):
		return _refused("this save is format version %s and this build reads only version %d" % [str(version), VERSION])

	var reader := _Reader.new(data)
	var world := reader.build()
	if not reader.refusal.is_empty():
		return _refused(reader.refusal)
	return {"world": world, "refusal": ""}


## Write a world to a file. Returns an empty string, or why it did not happen.
##
## The text is made first, written to a sibling file, and only moved over `path`
## once every step has succeeded, so a save that fails part-way leaves the
## previous save exactly as it was. `steps` is the seam a test uses to make a
## chosen step fail; nothing else passes it.
static func write_file(world: WorldMap, path: String, steps := FileSteps.new()) -> String:
	var why := unsaveable(world)
	if not why.is_empty():
		return why
	var text := to_text(world)
	var temp := path + ".tmp"
	var file := steps.open(temp)
	if file == null:
		return "could not write %s (error %d)" % [temp, FileAccess.get_open_error()]
	if not steps.store(file, text):
		file.close()
		steps.discard(temp)
		return "could not write %s (the write failed)" % temp
	var flushed := steps.flush(file)
	if flushed != OK:
		file.close()
		steps.discard(temp)
		return "could not write %s (flush failed, error %d)" % [temp, flushed]
	var closed := steps.close(file)
	if closed != OK:
		steps.discard(temp)
		return "could not write %s (close failed, error %d)" % [temp, closed]
	var replaced := steps.replace(temp, path)
	if replaced != OK:
		steps.discard(temp)
		return "could not replace %s (error %d); the earlier save is untouched" % [path, replaced]
	return ""


## The file operations `write_file()` performs, one per step, each reporting
## failure. A test subclasses this to fail exactly one of them.
class FileSteps extends RefCounted:
	func open(path: String) -> FileAccess:
		return FileAccess.open(path, FileAccess.WRITE)

	func store(file: FileAccess, text: String) -> bool:
		return file.store_string(text)

	func flush(file: FileAccess) -> Error:
		file.flush()
		return file.get_error()

	func close(file: FileAccess) -> Error:
		var failed := file.get_error()
		file.close()
		return failed

	func replace(from: String, to: String) -> Error:
		return DirAccess.rename_absolute(from, to)

	func discard(path: String) -> void:
		DirAccess.remove_absolute(path)


## Read a world from a file. Same shape of answer as `from_text()`.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _refused("there is no save at %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _refused("could not read %s (error %d)" % [path, FileAccess.get_open_error()])
	var text := file.get_as_text()
	file.close()
	return from_text(text)


static func _refused(why: String) -> Dictionary:
	return {"world": null, "refusal": why}


static func _coord_out(coord: Vector2i) -> Array:
	return [coord.x, coord.y]


## A 64-bit float as a number a person can read beside the bytes that load.
static func _exact(value: float) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return {"value": value, "bits": bytes.hex_encode()}


## The decoding half, as an object so the first thing wrong with a file can be
## recorded once and every read after it can quietly return a harmless default.
## Nothing is constructed from a value that has not been checked: the classes
## being rebuilt assert on bad input, and an assert is a crash rather than a
## refusal.
class _Reader extends RefCounted:
	const MAX_EXACT_INT := 9007199254740992.0
	const INT32_MAX := 2147483647.0
	const SLACK := 1e-9

	## How far the saved per-tile demand may sit from a fresh sum over the loaded
	## agents, as a fraction of that sum (never less than one head). The saved row
	## is kept by float32 adds and subtracts as herds move and breed, so it drifts
	## from the exact sum by rounding: measured over long multi-seed runs in
	## `test_the_saved_demand_row_stays_within_tolerance_over_long_runs`, the worst
	## tile over four seeds and a thousand turns was about 1e-4 of its sum, and the
	## drift is a random walk that grows with the run, so this leaves two orders of
	## magnitude. It is still far below one head (a herd is never under its
	## species' minimum), so a row that is zeroed, shifted, or belongs to other
	## herds is refused.
	const DEMAND_TOLERANCE := 1e-2

	var refusal := ""
	var _data: Dictionary

	func _init(data: Dictionary) -> void:
		_data = data

	func build() -> WorldMap:
		var seed := _signed_int64(_data.get("seed"), "seed")
		if not refusal.is_empty():
			return null
		# The size is judged as the numbers the file holds, before `HexGrid` turns
		# it into arrays: a save claiming a million tiles a side must be refused,
		# not allocated. The limit is what world generation produces (there is no
		# player-facing map size), so no save this build wrote can exceed it.
		var width_n := _number(_data, "width")
		var height_n := _number(_data, "height")
		var turn := _turn()
		if not refusal.is_empty():
			return null
		if width_n != floorf(width_n) or height_n != floorf(height_n) \
				or width_n < 1.0 or height_n < 1.0 \
				or width_n * height_n > float(WorldSave.MAX_TILES):
			_fail("the map size is out of range (at most %d tiles)" % WorldSave.MAX_TILES)
			return null
		var width := int(width_n)
		var height := int(height_n)

		var world := WorldMap.new(HexGrid.new(width, height), seed)
		var tiles := world.grid.tile_count()
		world.turn = turn

		# Every row is judged as the numbers the file holds before it is narrowed
		# into a packed array: a value outside 32 bits would wrap (terrain) or turn
		# into infinity (everything else) and be read as something it never was.
		world._terrain = _int32s(_data, "terrain", tiles)
		for value in world._terrain:
			if not WorldGen.Terrain.values().has(value):
				_fail("a tile has terrain %d, which is not a terrain" % value)
				return null
		var vitality: Array = _array(_data, "vitality", Land.USE_COUNT)
		var vitality_rows: Array[PackedFloat32Array] = []
		for use in range(mini(vitality.size(), Land.USE_COUNT)):
			var row := _narrowed(_numbers_in(vitality[use], "vitality row", tiles), "vitality row")
			if not _in_vitality_range(row):
				_fail("a vitality lies outside %s..%s" % [Land.MIN_VITALITY, Land.MAX_VITALITY])
				return null
			vitality_rows.append(row)
		var demand := _narrowed(_numbers(_data, "forage_demand", tiles), "forage_demand")
		# Empty on a world that has never advanced, a whole row on any other.
		var demand_then := _narrowed(_numbers(_data, "forage_demand_at_turn_start", -1), "forage_demand_at_turn_start")
		var vitality_then := _narrowed(_numbers(_data, "grazing_vitality_at_turn_start", -1), "grazing_vitality_at_turn_start")
		if not refusal.is_empty():
			return null
		for row in [demand_then, vitality_then]:
			if row.size() != 0 and row.size() != tiles:
				_fail("a turn-start snapshot does not cover the map")
				return null
		if not _in_vitality_range(vitality_then):
			_fail("a vitality lies outside %s..%s" % [Land.MIN_VITALITY, Land.MAX_VITALITY])
			return null
		for use in range(vitality_rows.size()):
			world._vitality[use] = vitality_rows[use]
		world._forage_demand = demand
		world._forage_demand_at_turn_start = demand_then
		world._grazing_vitality_at_turn_start = vitality_then
		# Forage is not in the file: it is recomputed from terrain and season, as
		# every turn recomputes it (`AgDR-009`).
		world._recompute_forage()
		world.report = TurnReport.new(turn)

		var species: Array[Species] = []
		for entry in _array(_data, "species", -1):
			species.append(_species(entry))
			if not refusal.is_empty():
				return null

		var node_entries := _array(_data, "nodes", -1)
		for entry in node_entries:
			if not refusal.is_empty():
				return null
			var coord := _coord(entry, "coord", world)
			var kind := _int(entry, "kind")
			if not CityNode.KIND_NAMES.has(kind):
				_fail("a structure is of kind %d, which is not a kind" % kind)
				return null
			# What `CityGen.node_refusal()` would say to the same placement.
			if world.terrain_at(coord) == WorldGen.Terrain.WATER:
				_fail("a structure stands on water at %s" % coord)
				return null
			if world.node_at(coord) != null:
				_fail("two structures stand on %s" % coord)
				return null
			# `CityGen.place_node()` names a structure by how many there already are
			# and nothing is ever removed, so ids are exactly 0..count-1. An id at or
			# past the count would be handed out again by the next placement.
			var node_id := _int(entry, "id")
			if node_id < 0 or node_id >= node_entries.size():
				_fail("a structure's id %d is outside 0..%d" % [node_id, node_entries.size() - 1])
				return null
			for earlier in world.nodes:
				if earlier.id == node_id:
					_fail("two structures share the id %d" % node_id)
					return null
			var capacity := _float(entry, "capacity", true)
			if capacity < 0.0:
				_fail("a structure has a negative capacity")
				return null
			# Everything below starts at zero and is only ever added to by
			# non-negative amounts, and `deposit()` never fills past `capacity`.
			var store := _held(entry, "store", capacity)
			var last_yield := _non_negative_float(entry, "last_yield", true)
			var took_in := _non_negative_float(entry, "took_in", true)
			var gave_out := _non_negative_float(entry, "gave_out", true)
			var mouths := _non_negative_int(entry, "mouths")
			var unmet := _non_negative_float(entry, "unmet")
			var plentiful_turns := _non_negative_int(entry, "plentiful_turns")
			var year_turns := _non_negative_int(entry, "year_turns")
			var year_asked := _non_negative_float(entry, "year_asked")
			var year_unmet := _non_negative_float(entry, "year_unmet")
			if not refusal.is_empty():
				return null
			# `feed()` adds `asked - eaten` to `year_unmet` beside `asked` to
			# `year_asked`, and `eaten` is never negative.
			if year_unmet > year_asked + SLACK * maxf(1.0, year_asked):
				_fail("a structure's unmet hunger for the year exceeds what was asked")
				return null
			var node := CityNode.new(node_id, coord, kind, capacity)
			node.store = store
			node.last_yield = last_yield
			node.took_in = took_in
			node.gave_out = gave_out
			node.mouths = mouths
			node.unmet = unmet
			node.plentiful_turns = plentiful_turns
			node.year_turns = year_turns
			node.year_asked = year_asked
			node.year_unmet = year_unmet
			world.nodes.append(node)

		var route_entries := _array(_data, "routes", -1)
		for entry in route_entries:
			if not refusal.is_empty():
				return null
			var source := _index(entry, "source", world.nodes.size())
			var sink := _index(entry, "sink", world.nodes.size())
			var path: Array[Vector2i] = []
			for step in _array(entry, "path", -1):
				path.append(_coord_of(step, world))
			if not refusal.is_empty():
				return null
			for step in path:
				if world.terrain_at(step) == WorldGen.Terrain.WATER:
					_fail("a route's path crosses water at %s" % step)
					return null
			if path.size() < 2 or not Route.is_contiguous(path) \
					or path[0] != world.nodes[source].coord or path[-1] != world.nodes[sink].coord:
				_fail("a route's path does not run between its two structures")
				return null
			# The orientation `CityGen.connect_nodes()` gives every road: a farm or
			# a camp feeding a granary, along the straight run between them, one
			# road to a pair.
			var from_node := world.nodes[source]
			var to_node := world.nodes[sink]
			if not (from_node.kind in [CityNode.Kind.FARM, CityNode.Kind.GATHERING] \
					and to_node.kind == CityNode.Kind.GRANARY):
				_fail("a road does not run from a farm or camp to a granary")
				return null
			if path != HexGrid.line(from_node.coord, to_node.coord):
				_fail("a road does not follow the straight run between its structures")
				return null
			# Named by how many roads there are already, as structures are.
			var route_id := _int(entry, "id")
			if route_id < 0 or route_id >= route_entries.size():
				_fail("a road's id %d is outside 0..%d" % [route_id, route_entries.size() - 1])
				return null
			for earlier in world.routes:
				if earlier.id == route_id:
					_fail("two roads share the id %d" % route_id)
					return null
				if earlier.source == from_node and earlier.sink == to_node:
					_fail("two roads join the same pair of structures")
					return null
			var route := Route.new(route_id, from_node, to_node, path)
			# Checked rather than trusted, like every other value here: a carrier
			# id is a whole number, and a file saying otherwise is refused instead
			# of producing a road whose crew list is nonsense.
			for who in _numbers(entry, "carriers", -1):
				route.carriers.append(_whole(float(who), "a road's carrier id"))
			if not refusal.is_empty():
				return null
			world.routes.append(route)

		for entry in _array(_data, "agents", -1):
			if not refusal.is_empty():
				return null
			match entry.get("kind") if typeof(entry) == TYPE_DICTIONARY else null:
				"herd":
					var which := _index(entry, "species", species.size())
					var coord := _coord(entry, "coord", world)
					if not refusal.is_empty():
						return null
					# `Herd._best_ground()` and the scatter that places herds both
					# refuse water.
					if world.terrain_at(coord) == WorldGen.Terrain.WATER:
						_fail("a herd stands on water at %s" % coord)
						return null
					var herd_id := _agent_id(entry)
					var population := _float(entry, "population", true)
					var start_coord := _coord(entry, "start_coord", world)
					var destination := _coord(entry, "destination", world)
					var planned_in := _int(entry, "planned_in")
					if not refusal.is_empty():
						return null
					# `Herd.step()` writes `maxf(scaled, minimum_population)`, so no
					# herd the game has run is ever smaller than its species' floor.
					if population < species[which].minimum_population:
						_fail("a herd is smaller than its species' minimum population")
						return null
					# -1 until the herd first plans, then the season it planned in.
					if planned_in != -1 and not Seasons.Season.values().has(planned_in):
						_fail("a herd planned in season %d, which is not a season" % planned_in)
						return null
					var herd := Herd.new(herd_id, coord, species[which], population)
					herd.start_coord = start_coord
					herd._destination = destination
					herd._planned_in = planned_in
					world.agents.append(herd)
				"citizen":
					var route_at := _index(entry, "route", world.routes.size())
					var index := _int(entry, "index")
					if not refusal.is_empty():
						return null
					var route := world.routes[route_at]
					if index < 0 or index >= route.path.size():
						_fail("a citizen stands off the end of its route")
						return null
					var citizen_id := _agent_id(entry)
					var capacity := _non_negative_float(entry, "capacity", true)
					var stands_at := _coord(entry, "coord", world)
					var carrying := _held(entry, "carrying", capacity)
					var held_up := _int(entry, "held_up")
					if not refusal.is_empty():
						return null
					if stands_at != route.path[index]:
						_fail("a citizen stands somewhere other than its route's step %d" % index)
						return null
					# `_held_up_by_traffic()` counts up and drops to zero past the cap.
					if held_up < 0 or held_up > Citizen.MAX_HELD_UP:
						_fail("a citizen has been held up %d turns, outside 0..%d" % [held_up, Citizen.MAX_HELD_UP])
						return null
					var citizen := Citizen.new(citizen_id, route, index, capacity)
					citizen.coord = stands_at
					citizen.carrying = carrying
					citizen.held_up = held_up
					world.agents.append(citizen)
				_:
					_fail("an agent is of a kind this build does not know")
					return null

		# A road's crew list is ids, and `CityGen._lose_carrier` finds whoever has
		# the id first and casts them to a `Citizen`. So ids are unique across all
		# agents, every listed id names a citizen on that same road (once), and
		# every citizen is on their road's list. Checked here, after agents exist,
		# because that is the first moment there is anything to check against.
		var by_id := {}
		for agent in world.agents:
			if by_id.has(agent.id):
				_fail("two agents share the id %d" % agent.id)
				return null
			by_id[agent.id] = agent
		for route in world.routes:
			var seen := {}
			for who in route.carriers:
				var found = by_id.get(who)
				if not found is Citizen or found.route != route or seen.has(who):
					_fail("a road's carrier %d is not a citizen walking that road" % who)
					return null
				seen[who] = true
		for agent in world.agents:
			if agent is Citizen and not agent.route.carriers.has(agent.id):
				_fail("a road's carrier list omits citizen %d, who walks it" % agent.id)
				return null
		# `tend_population()` never takes a road below the crew it was laid with.
		for route in world.routes:
			if route.carriers.size() < CityGen.CITIZENS_PER_ROUTE:
				_fail("a road has %d carriers, fewer than the %d every road is laid with" % [route.carriers.size(), CityGen.CITIZENS_PER_ROUTE])
				return null

		# The saved demand row is kept as it was, rounding included, but it has to
		# be the census of the agents just loaded: a row that disagrees would feed
		# every herd decision from agents who are not there.
		var census := PackedFloat64Array()
		census.resize(tiles)
		for agent in world.agents:
			census[world.grid.index_of(agent.coord)] += agent.forage_demand()
		for i in range(tiles):
			if absf(world._forage_demand[i] - census[i]) > DEMAND_TOLERANCE * maxf(1.0, census[i]):
				_fail("the saved forage demand on tile %d is %s but the agents standing there ask for %s" % [i, world._forage_demand[i], census[i]])
				return null

		var chronicle = _data.get("chronicle")
		if typeof(chronicle) != TYPE_DICTIONARY:
			_fail("the chronicle is missing")
			return null
		for key in chronicle:
			var series := _numbers(chronicle, key, -1)
			# `Chronicle.record()` drops from the front past `WINDOW`.
			if series.size() > Chronicle.WINDOW:
				_fail("the chronicle series '%s' holds %d readings, more than its window of %d" % [key, series.size(), Chronicle.WINDOW])
				return null
			world.chronicle._series[str(key)] = _narrowed(series, "chronicle")
		if not refusal.is_empty():
			return null

		return world if refusal.is_empty() else null

	## Compared as 32-bit floats, the way rows are stored: the floor as a double
	## is below the floor as a float, which would refuse a legitimate worn tile.
	## Written as `not (in range)` so NaN is refused too.
	func _in_vitality_range(row: PackedFloat32Array) -> bool:
		var floor32 := PackedFloat32Array([Land.MIN_VITALITY])[0]
		var ceiling32 := PackedFloat32Array([Land.MAX_VITALITY])[0]
		for value in row:
			if not (value >= floor32 and value <= ceiling32):
				return false
		return true

	func _species(entry) -> Species:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("name")) != TYPE_STRING:
			_fail("a species is malformed")
			return null
		# Every number is read and judged before a `Species` is handed to a herd, so
		# a hostile `sense_range` is refused rather than left for `_best_ground()`.
		var kind := Species.new(
			entry["name"],
			_float(entry, "consumption_per_head"),
			_float(entry, "growth_rate"),
			_float(entry, "decline_rate"),
			_int(entry, "move_range"),
			_int(entry, "sense_range"),
			_float(entry, "minimum_population"),
			_float(entry, "starting_population")
		)
		if not refusal.is_empty():
			return null
		if not WorldSave.is_supported_species(kind):
			_fail("a species is not the one this build plays ('%s')" % Species.grazer().name)
			return null
		return kind

	func _fail(why: String) -> void:
		if refusal.is_empty():
			refusal = why

	func _value(from, key: String):
		if typeof(from) != TYPE_DICTIONARY or not from.has(key):
			_fail("the save is missing '%s'" % key)
			return null
		return from[key]

	func _number(from, key: String) -> float:
		var value = _value(from, key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
			_fail("'%s' is not a number" % key)
			return 0.0
		return float(value)

	## A float written by `WorldSave._exact()`: the bits are the value, and the
	## readable number has to agree with them.
	func _float(from, key: String, narrowed := false) -> float:
		var entry = _value(from, key)
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("bits")) != TYPE_STRING \
				or (entry["bits"] as String).length() != 16 or not (entry["bits"] as String).is_valid_hex_number():
			_fail("'%s' is not an exact number" % key)
			return 0.0
		var readable := _number(entry, "value")
		var bytes := (entry["bits"] as String).hex_decode()
		var value := bytes.decode_double(0)
		if is_nan(value) or is_inf(value):
			_fail("'%s' is not a finite number" % key)
			return 0.0
		if not is_equal_approx(value, readable):
			_fail("'%s' reads %s but its exact bits say %s — edited by hand?" % [key, readable, value])
			return 0.0
		# Reports turn these into whole numbers and the chronicle sums them into
		# 32-bit rows; see `MAX_MAGNITUDE`.
		if narrowed and absf(value) > WorldSave.MAX_MAGNITUDE:
			_fail("'%s' is %s, too large for the reports and totals that read it" % [key, value])
			return 0.0
		return value

	## The world's clock: a decimal string for the whole int64 range, or (older
	## saves) a whole JSON number a double holds exactly. A string never goes
	## through float.
	func _turn() -> int:
		var entry = _value(_data, "turn")
		if typeof(entry) == TYPE_STRING:
			var text := entry as String
			var digits := text.length() > 0
			for c in text:
				digits = digits and c >= "0" and c <= "9"
			# Compared as text against INT64_MAX so a larger value is never
			# converted (`to_int()` would saturate).
			var limit := str(WorldMap.LAST_TURN)
			if not digits or text.length() > limit.length() \
					or (text.length() == limit.length() and text > limit):
				_fail("the turn '%s' is not a whole number the clock holds" % text)
				return 0
			return text.to_int()
		var number := _number(_data, "turn")
		if refusal.is_empty() and (number != floorf(number) or number < 0.0 or number > MAX_EXACT_INT):
			_fail("the turn is not a whole number the clock holds")
			return 0
		return int(number)

	func _int(from, key: String) -> int:
		return _whole(_number(from, key), key)
	## A signed decimal string within int64. Textual bounds prevent `to_int()`
	## from saturating on syntactically valid but out-of-range input.
	func _signed_int64(entry, what: String) -> int:
		if typeof(entry) != TYPE_STRING:
			_fail("the %s is not a whole number" % what)
			return 0
		var text := entry as String
		var negative := text.begins_with("-")
		var digits := text.substr(1) if negative else text
		if digits.is_empty():
			_fail("the %s is not a whole number" % what)
			return 0
		for c in digits:
			if c < "0" or c > "9":
				_fail("the %s is not a whole number" % what)
				return 0
		var limit := str(-WorldMap.LAST_TURN - 1) if negative else str(WorldMap.LAST_TURN)
		var magnitude := limit.substr(1) if negative else limit
		if digits.length() > magnitude.length() \
				or (digits.length() == magnitude.length() and digits > magnitude):
			_fail("the %s is not a whole number the game holds" % what)
			return 0
		return text.to_int()


	## A whole number a 64-bit integer holds exactly; the bound keeps `int()` from
	## being handed something it would wrap.
	func _whole(value: float, what: String, limit := MAX_EXACT_INT) -> int:
		if value != floorf(value) or absf(value) > limit:
			_fail("'%s' is not a whole number in range" % what)
			return 0
		return int(value)

	## An agent's id: whole, and one a later birth can follow and be saved exactly.
	func _agent_id(entry) -> int:
		var value := _int(entry, "id")
		if value < 0 or value > WorldSave.MAX_AGENT_ID:
			_fail("an agent's id %d is outside 0..%d" % [value, WorldSave.MAX_AGENT_ID])
			return 0
		return value

	## Whole numbers that fit a 32-bit integer array, so none is wrapped into one
	## it was not.
	func _int32s(from, key: String, size: int) -> PackedInt32Array:
		var row := PackedInt32Array()
		for item in _numbers(from, key, size):
			var value := float(item)
			if value != floorf(value) or absf(value) > INT32_MAX:
				_fail("'%s' holds %s, which is not a whole 32-bit number" % [key, value])
				return PackedInt32Array()
			row.append(int(value))
		return row

	## Numbers narrowed to 32-bit floats; one that is not finite, or that only
	## becomes infinite when narrowed, is refused.
	func _narrowed(values: Array, what: String) -> PackedFloat32Array:
		var row := PackedFloat32Array()
		for item in values:
			var narrow := PackedFloat32Array([float(item)])[0]
			if not is_finite(narrow):
				_fail("'%s' holds %s, which is not a finite 32-bit number" % [what, item])
				return PackedFloat32Array()
			row.append(narrow)
		return row

	func _non_negative_int(from, key: String) -> int:
		var value := _int(from, key)
		if value < 0:
			_fail("'%s' is negative" % key)
			return 0
		return value

	func _non_negative_float(from, key: String, narrowed := false) -> float:
		var value := _float(from, key, narrowed)
		if value < 0.0:
			_fail("'%s' is negative" % key)
			return 0.0
		return value

	## An amount held in something with room for `room`: from nothing up to full.
	## The top is judged with a hair of slack because `deposit()` adds
	## `capacity - held` to `held`, which can land an ulp past `capacity`.
	func _held(from, key: String, room: float) -> float:
		var value := _non_negative_float(from, key, true)
		if value > room + SLACK * maxf(1.0, room):
			_fail("'%s' holds more than its capacity" % key)
			return 0.0
		return value

	func _index(from, key: String, size: int) -> int:
		var value := _int(from, key)
		if value < 0 or value >= size:
			_fail("'%s' points at something that is not in the save" % key)
			return 0
		return value

	func _array(from, key: String, size: int) -> Array:
		return _checked_array(_value(from, key), key, size)

	func _checked_array(value, what: String, size: int) -> Array:
		if typeof(value) != TYPE_ARRAY:
			_fail("'%s' is not a list" % what)
			return []
		if size >= 0 and (value as Array).size() != size:
			_fail("'%s' has %d entries where %d were expected" % [what, (value as Array).size(), size])
			return []
		return value

	func _numbers(from, key: String, size: int) -> Array:
		return _numbers_in(_value(from, key), key, size)

	func _numbers_in(value, what: String, size: int) -> Array:
		var out := _checked_array(value, what, size)
		for item in out:
			if typeof(item) not in [TYPE_INT, TYPE_FLOAT]:
				_fail("'%s' holds something that is not a number" % what)
				return []
		return out

	func _coord(from, key: String, world: WorldMap) -> Vector2i:
		return _coord_of(_value(from, key), world)

	func _coord_of(value, world: WorldMap) -> Vector2i:
		var pair := _numbers_in(value, "coordinate", 2)
		if pair.size() != 2:
			return Vector2i.ZERO
		var x := _whole(float(pair[0]), "coordinate", INT32_MAX)
		var y := _whole(float(pair[1]), "coordinate", INT32_MAX)
		if not refusal.is_empty():
			return Vector2i.ZERO
		var coord := Vector2i(x, y)
		if not world.grid.has_coord(coord):
			_fail("%s is not on the map" % coord)
			return Vector2i.ZERO
		return coord
