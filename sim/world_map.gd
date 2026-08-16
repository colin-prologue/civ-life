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
## state is therefore fully determined by its seed and its turn number, which is
## what lets two runs be compared after a hundred turns as easily as after one.

var grid: HexGrid
var world_seed: int

## Turns elapsed since the world was generated. A fresh world is on turn 0.
var turn: int

var _terrain: PackedInt32Array
var _forage: PackedFloat32Array


func _init(p_grid: HexGrid, p_seed: int) -> void:
	grid = p_grid
	world_seed = p_seed
	turn = 0
	_terrain = PackedInt32Array()
	_terrain.resize(p_grid.tile_count())
	_forage = PackedFloat32Array()
	_forage.resize(p_grid.tile_count())


## Move the world forward one turn. Returns the turn just entered.
func advance_turn() -> int:
	turn += 1
	_recompute_forage()
	return turn


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
