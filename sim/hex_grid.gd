class_name HexGrid
extends RefCounted

## A rectangular patch of hexes addressed by axial coordinates, flat-top layout.
##
## Coordinates are `Vector2i(q, r)`. Axial is the working coordinate system —
## neighbours and distance are cheap integer arithmetic on it — but a rectangle
## in axial space is a rhombus on screen, so the grid's *extent* is defined in
## odd-q offset space (`col`, `row`) and converted. That keeps the map a tidy
## width x height block while all the arithmetic stays axial.
##
## Iteration order is row-major over offset coordinates and never depends on a
## hash: two grids of the same size always yield tiles in the same order, which
## is what lets a generated map be compared tile-for-tile.

## The six axial neighbour offsets, in a fixed order. Consumers may rely on the
## order: index i here always means the same direction.
const DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

var width: int
var height: int


func _init(p_width: int, p_height: int) -> void:
	assert(p_width > 0 and p_height > 0, "a grid needs a positive extent")
	width = p_width
	height = p_height


## Number of tiles in the grid.
func tile_count() -> int:
	return width * height


## Offset (col, row) -> axial (q, r), odd-q flat-top.
static func from_offset(col: int, row: int) -> Vector2i:
	return Vector2i(col, row - ((col - (col & 1)) >> 1))


## Axial (q, r) -> offset (col, row), odd-q flat-top.
static func to_offset(coord: Vector2i) -> Vector2i:
	return Vector2i(coord.x, coord.y + ((coord.x - (coord.x & 1)) >> 1))


func has_coord(coord: Vector2i) -> bool:
	var off := to_offset(coord)
	return off.x >= 0 and off.x < width and off.y >= 0 and off.y < height


## Stable index for a coordinate, or -1 if it is off the map. Row-major over
## offset space, so it matches the order of `all_coords()`.
func index_of(coord: Vector2i) -> int:
	if not has_coord(coord):
		return -1
	var off := to_offset(coord)
	return off.y * width + off.x


func coord_at(index: int) -> Vector2i:
	assert(index >= 0 and index < tile_count(), "index off the map")
	@warning_ignore("integer_division")
	return from_offset(index % width, index / width)


## Every tile on the map, in stable row-major order.
func all_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.resize(tile_count())
	var i := 0
	for row in range(height):
		for col in range(width):
			out[i] = from_offset(col, row)
			i += 1
	return out


## All six neighbours of a coordinate, whether or not they are on the map.
## Pure coordinate arithmetic — no bounds involved.
static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.resize(6)
	for i in range(6):
		out[i] = coord + DIRECTIONS[i]
	return out


## The neighbours that actually exist on this map. Fewer than six at an edge.
func neighbors_in_bounds(coord: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var n: Vector2i = coord + dir
		if has_coord(n):
			out.append(n)
	return out


## Hex distance in steps between two axial coordinates.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) >> 1
