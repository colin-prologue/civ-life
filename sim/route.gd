class_name Route
extends RefCounted

## A road between two nodes, written out as the ordered list of hexes it runs
## along.
##
## The path is stored, not derived. `AgDR-002` makes routes the surface where the
## built city and the living world meet, and that only works if a route is a
## *place* — a specific set of tiles a herd can be standing on — rather than a
## claim that two nodes are connected. Derived adjacency would have no tiles in
## it for anything to interfere with.
##
## Routes are placed explicitly. There is no pathfinding here and none is wanted
## yet: the player-facing version of placement is a later ticket, and inventing a
## router now would fix a policy (avoid water? prefer flat? shortest or
## cheapest?) before there is anything to judge it against. `HexGrid.line()` lays
## a straight run of hexes for callers that just want the obvious road, and
## `is_contiguous()` is the check anything constructing a path by other means has
## to pass.

var id: int

## The node grain is picked up from, and the node it is carried to. Direction is
## a property of the route rather than of the citizen, because it is the road
## that has a farm at one end and a granary at the other.
var source: CityNode
var sink: CityNode

## Every tile the route runs through, in order, starting on `source.coord` and
## ending on `sink.coord`. Consecutive entries are always neighbours, so a
## carrier walks it by stepping the index.
var path: Array[Vector2i]


func _init(p_id: int, p_source: CityNode, p_sink: CityNode, p_path: Array[Vector2i]) -> void:
	assert(p_path.size() >= 2, "a route connects two tiles or more")
	assert(p_path[0] == p_source.coord, "a route starts at the node it collects from")
	assert(p_path[-1] == p_sink.coord, "a route ends at the node it delivers to")
	assert(is_contiguous(p_path), "a route's tiles have to be walkable one to the next")
	id = p_id
	source = p_source
	sink = p_sink
	path = p_path


## Tiles on the route. The length a carrier walks one-way is one less than this.
func length() -> int:
	return path.size()


## Where on the route this tile sits, or -1 if it is not on it. Linear, because a
## route is a handful of tiles and an index keyed by coordinate would be a cache
## that can disagree with the path.
func index_of(coord: Vector2i) -> int:
	return path.find(coord)


func passes_through(coord: Vector2i) -> bool:
	return path.has(coord)


## Whether every step in a path lands on a neighbour of the one before it. A path
## that fails this is not walkable, and the failure is worth catching where the
## route is built rather than where a carrier gets stuck on it.
static func is_contiguous(path_: Array[Vector2i]) -> bool:
	for i in range(1, path_.size()):
		if HexGrid.distance(path_[i - 1], path_[i]) != 1:
			return false
	return true
