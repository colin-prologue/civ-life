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

var _terrain: PackedInt32Array
var _forage: PackedFloat32Array

## Heads standing on each tile, by grid index. A cache, maintained by the
## mutators below rather than recomputed, because the movement code asks for it
## seven times per herd per turn and a scan of every agent per query is the
## difference between a thousand-turn test and no thousand-turn test.
##
## Read for *decisions*, never for reporting: repeated add-and-subtract on
## floats drifts, so anything quoting a total sums the agents themselves.
var _herd_population: PackedFloat32Array


func _init(p_grid: HexGrid, p_seed: int) -> void:
	grid = p_grid
	world_seed = p_seed
	turn = 0
	_terrain = PackedInt32Array()
	_terrain.resize(p_grid.tile_count())
	_forage = PackedFloat32Array()
	_forage.resize(p_grid.tile_count())
	_herd_population = PackedFloat32Array()
	_herd_population.resize(p_grid.tile_count())


## Move the world forward one turn. Returns the turn just entered.
##
## Forage first, then everything alive: an agent decides its turn against the
## season it is actually standing in, never against last turn's.
func advance_turn() -> int:
	turn += 1
	_recompute_forage()
	for agent in agents:
		agent.step(self)
	return turn


## Put an agent into the world. Generation calls this; nothing appends to
## `agents` directly, because the per-tile census has to be told.
func add_agent(agent: Agent) -> void:
	assert(grid.has_coord(agent.coord), "an agent cannot stand off the map")
	agents.append(agent)
	if agent is Herd:
		_herd_population[grid.index_of(agent.coord)] += (agent as Herd).population


## Move an agent one or more tiles. The only way an agent's position changes.
func move_agent(agent: Agent, to: Vector2i) -> void:
	assert(grid.has_coord(to), "an agent cannot step off the map")
	if agent is Herd:
		var herd := agent as Herd
		_herd_population[grid.index_of(herd.coord)] -= herd.population
		_herd_population[grid.index_of(to)] += herd.population
	agent.coord = to


## Set a herd's population. The only way it changes, for the same reason.
func set_herd_population(herd: Herd, value: float) -> void:
	_herd_population[grid.index_of(herd.coord)] += value - herd.population
	herd.population = value


## Heads standing on this tile, across every herd on it.
func herd_population_at(coord: Vector2i) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read population off the map")
	return _herd_population[i]


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


func herd_population_by_index(i: int) -> float:
	return _herd_population[i]


## Every herd in the world, in step order.
func herds() -> Array[Herd]:
	var out: Array[Herd] = []
	for agent in agents:
		if agent is Herd:
			out.append(agent as Herd)
	return out


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


## How many tiles differ from another map of the same size.
func difference_count(other: WorldMap) -> int:
	assert(other.grid.width == grid.width and other.grid.height == grid.height,
		"maps of different sizes are not comparable")
	var differing := 0
	for i in range(_terrain.size()):
		if _terrain[i] != other._terrain[i]:
			differing += 1
	return differing
