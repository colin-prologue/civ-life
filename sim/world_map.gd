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
## This is also where the clock lives. `advance_turn()` currently does nothing
## but count, and that is the point: it is the single place a turn happens, so
## seasons, herds and everything after them extend one function rather than
## racing to invent their own update path. The UI calls this; the tests call
## this; there is no third way to move the world forward.

var grid: HexGrid
var world_seed: int

## Turns elapsed since the world was generated. A fresh world is on turn 0.
var turn: int

var _terrain: PackedInt32Array


func _init(p_grid: HexGrid, p_seed: int) -> void:
	grid = p_grid
	world_seed = p_seed
	turn = 0
	_terrain = PackedInt32Array()
	_terrain.resize(p_grid.tile_count())


## Move the world forward one turn. Returns the turn just entered.
func advance_turn() -> int:
	turn += 1
	return turn


func set_terrain(coord: Vector2i, terrain: int) -> void:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot set terrain off the map")
	_terrain[i] = terrain


func terrain_at(coord: Vector2i) -> int:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read terrain off the map")
	return _terrain[i]


## The raw terrain values in grid order. Useful for whole-map comparison.
func terrain_data() -> PackedInt32Array:
	return _terrain.duplicate()


## How many tiles differ from another map of the same size.
func difference_count(other: WorldMap) -> int:
	assert(other.grid.width == grid.width and other.grid.height == grid.height,
		"maps of different sizes are not comparable")
	var differing := 0
	for i in range(_terrain.size()):
		if _terrain[i] != other._terrain[i]:
			differing += 1
	return differing
