class_name WorldMap
extends RefCounted

## A generated world: a grid, the seed that produced it, and one terrain value
## per tile.
##
## Terrain lives in a flat `PackedInt32Array` indexed by `grid.index_of()`
## rather than a dictionary keyed by coordinate. Two maps from the same seed can
## then be compared with a single array equality, and nothing about the
## comparison depends on hash iteration order.
##
## This is also where the clock lives. `advance_turn()` counts the turn and then
## runs every per-turn system in a fixed order — currently just forage. That is
## the point: it is the single place a turn happens, so seasons, herds and
## everything after them extend one function rather than racing to invent their
## own update path. The UI calls this; the tests call this; there is no third way
## to move the world forward.
##
## Forage sits beside terrain, in a parallel array on the same index, and is
## recomputed from terrain and season on every turn rather than nudged. A world's
## terrain and forage are therefore fully determined by its seed and its turn
## number, which is what lets two runs be compared after a hundred turns as
## easily as after one.
##
## Agents are the exception, and knowingly so: a herd's position and population
## carry forward from turn to turn, so a world with living things in it is no
## longer reconstructible from `(seed, turn)` alone. Determinism is unaffected —
## the same seed advanced the same number of turns still produces the same
## herds, in the same places, with the same numbers — but a save is now a state
## rather than two integers.

var grid: HexGrid
var world_seed: int

## Turns elapsed since the world was generated. A fresh world is on turn 0.
var turn: int

## Everything alive in the world, in the order it was added and stepped in that
## order every turn. Array order is load-bearing for determinism: two herds
## reaching for the same tile must resolve the same way on every run, and this
## is what decides it.
var agents: Array[Agent] = []

## What the turn just run actually changed, as an ordered list of notable
## changes. Rebuilt from scratch by every `advance_turn()`, empty on a world that
## has not been advanced, and read by nobody the simulation knows about — the
## world produces it whether or not there is a renderer to consume it. See
## `sim/turn_report.gd`.
var report: TurnReport

var _terrain: PackedInt32Array
var _forage: PackedFloat32Array

## One vitality value per tile per use, in the same grid order as `_terrain` and
## `_forage` (`AgDR-006`: flat arrays indexed by position, never a dictionary
## keyed by coordinate).
##
## An `Array` of `PackedFloat32Array`, indexed by `Land.Use`. Kept as separate
## arrays per use rather than one interleaved array so that a whole use can be
## read, hashed or compared in one call — and so that adding a use is appending
## an array rather than restriding every read.
var _vitality: Array = []

## Everything the player has placed: farms, granaries, and the roads between
## them. Stepped in array order for the same reason agents are.
var nodes: Array[CityNode] = []
var routes: Array[Route] = []

## How much of each tile's forage is spoken for, by grid index — the sum of
## every agent's `forage_demand()` on that tile. A cache, maintained by the
## mutators below rather than recomputed, because the movement code asks for it
## seven times per herd per turn and a scan of every agent per query is the
## difference between a thousand-turn test and no thousand-turn test.
##
## Agents report a number into this; nothing here asks what kind of agent it
## came from. That is what lets a citizen notice a herd standing on its road
## without either type knowing the other exists (`AgDR-002`).
##
## Read for *decisions*, never for reporting: repeated add-and-subtract on
## floats drifts, so anything quoting a total sums the agents themselves.
var _forage_demand: PackedFloat32Array


func _init(p_grid: HexGrid, p_seed: int) -> void:
	grid = p_grid
	world_seed = p_seed
	turn = 0
	_terrain = PackedInt32Array()
	_terrain.resize(p_grid.tile_count())
	_forage = PackedFloat32Array()
	_forage.resize(p_grid.tile_count())
	_forage_demand = PackedFloat32Array()
	_forage_demand.resize(p_grid.tile_count())
	_vitality.resize(Land.USE_COUNT)
	for use in range(Land.USE_COUNT):
		var row := PackedFloat32Array()
		row.resize(p_grid.tile_count())
		row.fill(Land.MAX_VITALITY)
		_vitality[use] = row
	report = TurnReport.new(turn)


## Move the world forward one turn. Returns the turn just entered.
##
## Forage first, then what is built, then everything alive: an agent decides its
## turn against the season it is actually standing in, never against last
## turn's, and a carrier standing at a farm leaves with this turn's harvest
## rather than last turn's.
##
## The report is taken around the outside of all of it: a snapshot before
## anything runs, a comparison after everything has. Nothing between those two
## lines knows the report exists, and nothing in it asks whether anybody is going
## to read the answer — a world with no renderer attached does exactly the same
## work as one being watched.
func advance_turn() -> int:
	var before := TurnReport.snapshot(self)
	turn += 1
	_recompute_forage()
	for node in nodes:
		node.produce(self)
	for agent in agents:
		agent.step(self)
	_recover_vitality()
	report = TurnReport.since(self, before)
	return turn


## Put an agent into the world. Generation calls this; nothing appends to
## `agents` directly, because the per-tile census has to be told.
func add_agent(agent: Agent) -> void:
	assert(grid.has_coord(agent.coord), "an agent cannot stand off the map")
	agents.append(agent)
	_forage_demand[grid.index_of(agent.coord)] += agent.forage_demand()


## Move an agent one or more tiles. The only way an agent's position changes.
func move_agent(agent: Agent, to: Vector2i) -> void:
	assert(grid.has_coord(to), "an agent cannot step off the map")
	var demand := agent.forage_demand()
	if demand != 0.0:
		_forage_demand[grid.index_of(agent.coord)] -= demand
		_forage_demand[grid.index_of(to)] += demand
	agent.coord = to


## Put a structure into the world. Nodes do not move and are never removed —
## `world-growth-tone` rule 1 — so this is the only mutator they need.
func add_node(node: CityNode) -> void:
	assert(grid.has_coord(node.coord), "a structure cannot stand off the map")
	nodes.append(node)


## Lay a route between two nodes already in the world.
func add_route(route: Route) -> void:
	for coord in route.path:
		assert(grid.has_coord(coord), "a route cannot run off the map")
	routes.append(route)


## The structure standing on this tile, or null if the tile is free.
##
## Linear over `nodes`, for the reason `Route.index_of()` is linear: a city is a
## handful of chunky structures (`AgDR-002`), and an index keyed by coordinate
## would be a cache that can disagree with the array it summarises.
##
## This is a *query*, and the one placement asks before it is allowed to build.
## Keeping it here rather than in whatever is doing the placing is what lets the
## rule "a tile holds one structure" be asserted without a scene tree.
func node_at(coord: Vector2i) -> CityNode:
	for node in nodes:
		if node.coord == coord:
			return node
	return null


## Set a herd's population. The only way it changes, for the same reason.
func set_herd_population(herd: Herd, value: float) -> void:
	_forage_demand[grid.index_of(herd.coord)] += value - herd.population
	herd.population = value


## How much of this tile's forage is spoken for, across everything standing on
## it. Zero on a tile with nothing grazing it, whoever else is passing through.
func forage_demand_at(coord: Vector2i) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read forage demand off the map")
	return _forage_demand[i]


## The same figure, summed from the agents actually standing there rather than
## read off the cache — the version anything *quoting* the number has to use.
##
## `_forage_demand` above is maintained by adding and subtracting floats as
## agents move, which is exact enough to decide by and not exact enough to say
## out loud after a thousand turns of it. Same split as `total_herd_population()`
## against the per-tile forage cache, and for the same reason.
##
## Walks `agents` in array order, so the sum is bit-for-bit the same on two runs
## of one seed (`AgDR-001`). Linear in the world's agents, which is why the
## movement code does not call it: this runs once per held-up carrier per turn,
## not seven times per herd.
func forage_demand_summed_at(coord: Vector2i) -> float:
	var total := 0.0
	for agent in agents:
		if agent.coord == coord:
			total += agent.forage_demand()
	return total


## The same three fields by grid index rather than by coordinate.
##
## Not a convenience. A herd looking around asks for the terrain, the forage and
## the crowd on each tile it can see, and going through coordinates means three
## separate bounds-checked coordinate conversions for one tile — measured at
## roughly a third of the whole turn loop once herds could see further than one
## step. The caller resolves the index once and reads all three off it.
func terrain_by_index(i: int) -> int:
	return _terrain[i]


func forage_by_index(i: int) -> float:
	return _forage[i]


func forage_demand_by_index(i: int) -> float:
	return _forage_demand[i]


## Every herd in the world, in step order.
##
## A kind-check, and deliberately one: this is a *query* asked from outside, by a
## renderer drawing markers or a test checking populations. Nothing inside the
## turn loop calls it. The claim `AgDR-002` makes is about behaviour — that no
## agent's turn branches on what kind of agent it is — not that a heterogeneous
## array can be filtered without naming the thing being filtered for.
func herds() -> Array[Herd]:
	var out: Array[Herd] = []
	for agent in agents:
		if agent is Herd:
			out.append(agent as Herd)
	return out


## Every citizen in the world, in step order. Same caveat as `herds()`.
func citizens() -> Array[Citizen]:
	var out: Array[Citizen] = []
	for agent in agents:
		if agent is Citizen:
			out.append(agent as Citizen)
	return out


## Grain held across every structure in the world. Summed from the nodes rather
## than tracked, for the same reason `total_herd_population()` is.
func total_stored_grain() -> float:
	var total := 0.0
	for node in nodes:
		total += node.store
	return total


## Grain held in granaries alone — the number that says whether the city is
## getting anywhere, as distinct from what is sitting in a barn waiting to be
## carried.
func total_granary_store() -> float:
	var total := 0.0
	for node in nodes:
		if node.kind == CityNode.Kind.GRANARY:
			total += node.store
	return total


## Total heads alive in the world. Summed from the herds rather than from the
## per-tile cache, so it is exact however long the world has been running.
func total_herd_population() -> float:
	var total := 0.0
	for herd in herds():
		total += herd.population
	return total


## The season the world is currently in. Derived from the turn rather than
## stored, so there is no second clock that can disagree with the first.
func season() -> int:
	return Seasons.season_for_turn(turn)


## The year the world is currently in, counting from 1.
func year() -> int:
	return Seasons.year_for_turn(turn)


func set_terrain(coord: Vector2i, terrain: int) -> void:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot set terrain off the map")
	_terrain[i] = terrain
	# Kept consistent here rather than in a separate pass generation has to
	# remember to call: a tile's forage is never allowed to disagree with the
	# terrain under it, not even for the length of one function.
	_forage[i] = Seasons.forage_for(terrain, season())


func terrain_at(coord: Vector2i) -> int:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read terrain off the map")
	return _terrain[i]


## The raw terrain values in grid order. Useful for whole-map comparison.
func terrain_data() -> PackedInt32Array:
	return _terrain.duplicate()


## What this tile can feed this season, in `Seasons.MIN_FORAGE`..`MAX_FORAGE`.
## Water is zero in every season.
func forage_at(coord: Vector2i) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read forage off the map")
	return _forage[i]


## The raw forage values in grid order, matching `terrain_data()` index for
## index. The other half of a whole-world comparison.
func forage_data() -> PackedFloat32Array:
	return _forage.duplicate()


## How worn this tile is for this use, in `Land.MIN_VITALITY`..`MAX_VITALITY`.
func vitality_at(coord: Vector2i, use: int) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read vitality off the map")
	return vitality_by_index(i, use)


func vitality_by_index(i: int, use: int) -> float:
	var row: PackedFloat32Array = _vitality[use]
	return row[i]


## The whole vitality row for one use, in grid order.
func vitality_data(use: int) -> PackedFloat32Array:
	var row: PackedFloat32Array = _vitality[use]
	return row.duplicate()


## What this tile is actually worth to this use right now: the terrain-and-season
## curve scaled by how worn the ground is for that use.
##
## The curve remains the ceiling — vitality is a fraction and never exceeds 1.0 —
## which is the half of `AgDR-009` that survives `AgDR-014`.
func forage_for_use(coord: Vector2i, use: int) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read forage off the map")
	return forage_for_use_by_index(i, use)


## The same value by index, for callers scanning many tiles per turn.
##
## `Herd._best_ground()` scores every tile in its sense range every time it
## re-plans and reads by index for exactly that reason. It needs this rather than
## raw `forage_by_index()`, or destinations stay blind to wear while the tile
## underfoot is not — and a herd that cannot see worn ground keeps walking onto
## it, which would leave the rotation `AgDR-014` is about with no effect on where
## anything goes.
func forage_for_use_by_index(i: int, use: int) -> float:
	return _forage[i] * vitality_by_index(i, use)


## Set a tile's vitality for a use directly.
##
## Exists for generation and for tests that need to start from a worn world.
## Ordinary wear goes through `draw_vitality()`; this is not the path play takes.
func set_vitality(coord: Vector2i, use: int, value: float) -> void:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot write vitality off the map")
	var row: PackedFloat32Array = _vitality[use]
	row[i] = clampf(value, Land.MIN_VITALITY, Land.MAX_VITALITY)
	_vitality[use] = row


## Forage summed over the whole map. The map-scale quantity seasons are supposed
## to move, so it is worth being able to read it in one call.
func total_forage() -> float:
	var total := 0.0
	for value in _forage:
		total += value
	return total


## Recompute every tile from its terrain and the season the world is now in.
##
## The row is fetched once and indexed per tile, rather than a lookup per tile:
## this runs `tile_count()` times per turn and is the only thing standing
## between the project and a turn loop too slow to run five hundred of.
func _recompute_forage() -> void:
	var row := Seasons.forage_row(season())
	for i in range(_terrain.size()):
		_forage[i] = row[_terrain[i]]


## Every tile, every use, one turn closer to full.
##
## Runs last in the turn so that what recovers is what is left after the turn's
## work has been taken — and runs over every tile unconditionally, because
## `AgDR-014` makes recovery the world's default behaviour rather than something
## anybody has to cause. Same flat-array pass as `_recompute_forage`, for the
## same reason: this runs `tile_count()` times per use per turn.
func _recover_vitality() -> void:
	for use in range(Land.USE_COUNT):
		_vitality[use] = Land.recovered_row(_vitality[use])


## How many tiles differ from another map of the same size.
func difference_count(other: WorldMap) -> int:
	assert(other.grid.width == grid.width and other.grid.height == grid.height,
		"maps of different sizes are not comparable")
	var differing := 0
	for i in range(_terrain.size()):
		if _terrain[i] != other._terrain[i]:
			differing += 1
	return differing
