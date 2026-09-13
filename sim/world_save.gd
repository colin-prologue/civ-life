class_name WorldSave
extends RefCounted

## A world written to text and read back.
##
## **What a world's state is.** `AgDR-009` once said a save was two numbers, seed
## and turn. That stopped being true the moment a herd's position carried from
## one turn to the next, and `AgDR-021` states what replaced it: the `WorldMap`
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
	"CityNode": ["id", "coord", "kind", "store", "capacity", "last_yield", "took_in", "gave_out"],
	"Route": ["id", "source", "sink", "path"],
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
		})

	var routes := []
	for route in world.routes:
		var path := []
		for coord in route.path:
			path.append(_coord_out(coord))
		routes.append({
			"id": route.id,
			"source": world.nodes.find(route.source),
			"sink": world.nodes.find(route.sink),
			"path": path,
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
		"turn": world.turn,
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
	for agent in world.agents:
		if not (agent is Herd or agent is Citizen):
			return "agent %d is a kind this save format does not know how to write" % agent.id
		if agent is Citizen and not world.routes.has((agent as Citizen).route):
			return "citizen %d walks a route that is not in the world" % agent.id
	for route in world.routes:
		if not (world.nodes.has(route.source) and world.nodes.has(route.sink)):
			return "route %d joins a structure that is not in the world" % route.id
	return ""


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
static func write_file(world: WorldMap, path: String) -> String:
	var why := unsaveable(world)
	if not why.is_empty():
		return why
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "could not write %s (error %d)" % [path, FileAccess.get_open_error()]
	file.store_string(to_text(world))
	file.close()
	return ""


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
	var refusal := ""
	var _data: Dictionary

	func _init(data: Dictionary) -> void:
		_data = data

	func build() -> WorldMap:
		var seed_text = _data.get("seed")
		if typeof(seed_text) != TYPE_STRING or not (seed_text as String).is_valid_int():
			_fail("the seed is not a whole number")
			return null
		var width := _int(_data, "width")
		var height := _int(_data, "height")
		var turn := _int(_data, "turn")
		if not refusal.is_empty():
			return null
		if width <= 0 or height <= 0 or turn < 0:
			_fail("the map size or turn is out of range")
			return null

		var world := WorldMap.new(HexGrid.new(width, height), (seed_text as String).to_int())
		var tiles := world.grid.tile_count()
		world.turn = turn

		world._terrain = PackedInt32Array(_numbers(_data, "terrain", tiles))
		for value in world._terrain:
			if not WorldGen.Terrain.values().has(value):
				_fail("a tile has terrain %d, which is not a terrain" % value)
				return null
		var vitality: Array = _array(_data, "vitality", Land.USE_COUNT)
		for use in range(mini(vitality.size(), Land.USE_COUNT)):
			world._vitality[use] = PackedFloat32Array(_numbers_in(vitality[use], "vitality row", tiles))
		world._forage_demand = PackedFloat32Array(_numbers(_data, "forage_demand", tiles))
		# Empty on a world that has never advanced, a whole row on any other.
		world._forage_demand_at_turn_start = PackedFloat32Array(
				_numbers(_data, "forage_demand_at_turn_start", -1))
		world._grazing_vitality_at_turn_start = PackedFloat32Array(
				_numbers(_data, "grazing_vitality_at_turn_start", -1))
		for row in [world._forage_demand_at_turn_start, world._grazing_vitality_at_turn_start]:
			if row.size() != 0 and row.size() != tiles:
				_fail("a turn-start snapshot does not cover the map")
		# Forage is not in the file: it is recomputed from terrain and season, as
		# every turn recomputes it (`AgDR-009`).
		world._recompute_forage()
		world.report = TurnReport.new(turn)

		var species: Array[Species] = []
		for entry in _array(_data, "species", -1):
			species.append(_species(entry))

		for entry in _array(_data, "nodes", -1):
			if not refusal.is_empty():
				return null
			var coord := _coord(entry, "coord", world)
			var kind := _int(entry, "kind")
			if not CityNode.KIND_NAMES.has(kind):
				_fail("a structure is of kind %d, which is not a kind" % kind)
				return null
			var node := CityNode.new(_int(entry, "id"), coord, kind, _float(entry, "capacity"))
			node.store = _float(entry, "store")
			node.last_yield = _float(entry, "last_yield")
			node.took_in = _float(entry, "took_in")
			node.gave_out = _float(entry, "gave_out")
			world.nodes.append(node)

		for entry in _array(_data, "routes", -1):
			if not refusal.is_empty():
				return null
			var source := _index(entry, "source", world.nodes.size())
			var sink := _index(entry, "sink", world.nodes.size())
			var path: Array[Vector2i] = []
			for step in _array(entry, "path", -1):
				path.append(_coord_of(step, world))
			if not refusal.is_empty():
				return null
			if path.size() < 2 or not Route.is_contiguous(path) \
					or path[0] != world.nodes[source].coord or path[-1] != world.nodes[sink].coord:
				_fail("a route's path does not run between its two structures")
				return null
			world.routes.append(Route.new(_int(entry, "id"), world.nodes[source], world.nodes[sink], path))

		for entry in _array(_data, "agents", -1):
			if not refusal.is_empty():
				return null
			match entry.get("kind") if typeof(entry) == TYPE_DICTIONARY else null:
				"herd":
					var which := _index(entry, "species", species.size())
					var coord := _coord(entry, "coord", world)
					if not refusal.is_empty():
						return null
					var herd := Herd.new(_int(entry, "id"), coord, species[which], _float(entry, "population"))
					herd.start_coord = _coord(entry, "start_coord", world)
					herd._destination = _coord(entry, "destination", world)
					herd._planned_in = _int(entry, "planned_in")
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
					var citizen := Citizen.new(_int(entry, "id"), route, index, _float(entry, "capacity"))
					citizen.coord = _coord(entry, "coord", world)
					citizen.carrying = _float(entry, "carrying")
					citizen.held_up = _int(entry, "held_up")
					world.agents.append(citizen)
				_:
					_fail("an agent is of a kind this build does not know")
					return null

		var chronicle = _data.get("chronicle")
		if typeof(chronicle) != TYPE_DICTIONARY:
			_fail("the chronicle is missing")
			return null
		for key in chronicle:
			world.chronicle._series[str(key)] = PackedFloat32Array(_numbers(chronicle, key, -1))

		return world if refusal.is_empty() else null

	func _species(entry) -> Species:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("name")) != TYPE_STRING:
			_fail("a species is malformed")
			return null
		return Species.new(
			entry["name"],
			_float(entry, "consumption_per_head"),
			_float(entry, "growth_rate"),
			_float(entry, "decline_rate"),
			_int(entry, "move_range"),
			_int(entry, "sense_range"),
			_float(entry, "minimum_population"),
			_float(entry, "starting_population")
		)

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
	func _float(from, key: String) -> float:
		var entry = _value(from, key)
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("bits")) != TYPE_STRING \
				or (entry["bits"] as String).length() != 16 or not (entry["bits"] as String).is_valid_hex_number():
			_fail("'%s' is not an exact number" % key)
			return 0.0
		var readable := _number(entry, "value")
		var bytes := (entry["bits"] as String).hex_decode()
		var value := bytes.decode_double(0)
		if not is_equal_approx(value, readable):
			_fail("'%s' reads %s but its exact bits say %s — edited by hand?" % [key, readable, value])
			return 0.0
		return value

	func _int(from, key: String) -> int:
		var value := _number(from, key)
		if value != floorf(value):
			_fail("'%s' is not a whole number" % key)
			return 0
		return int(value)

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
		var coord := Vector2i(int(pair[0]), int(pair[1]))
		if not world.grid.has_coord(coord):
			_fail("%s is not on the map" % coord)
			return Vector2i.ZERO
		return coord
