class_name CityGen
extends RefCounted

## How a city gets built — by the generator at worldgen, and by the player after
## it. Both go through the same three calls.
##
## `populate()` puts the smallest possible city on a freshly generated world: a
## farm, a granary a short walk away, a road between them, and people on it.
## `place_node()` and `connect_nodes()` are the same operations with the site
## chosen by somebody rather than drawn — and `populate()` calls them, so there
## is one way to build a city rather than a generator's way and a player's way
## that can drift apart.
##
## **Validity is here, not in `game/`.** Whether a tile can hold a structure and
## whether two structures can be joined are world rules, so they are answered by
## `node_refusal()` and `route_refusal()` and asserted headlessly. The renderer
## works out which tile was clicked and asks. It does not know what water means.
##
## **Refusals are strings, not booleans.** A refusal the player cannot see is
## indistinguishable from an input that was dropped, and "nothing happened" is
## the worst thing a first verb can do. The reason has to survive the trip back
## to whoever clicked, so it travels as the sentence rather than as a code the
## caller looks up in a table that can go stale.
##
## The counterpart to `Herd.populate()`, and built the same way for the same
## reason — its own generator, seeded from the world seed with its own salt, so
## that changing where the city goes does not move a single tile of terrain and
## does not shift a single herd on any existing seed.
##
## Placement here is programmatic and deliberately unclever. The player-facing
## version is a later ticket, and the point of this one is that grain moves, not
## that it moves along a well-chosen road. It picks a productive tile, looks for
## a straight run of land in a fixed direction order, and takes the first that
## works.

## Mixed into the world seed for placement draws. "CITY" in ASCII, for the same
## reason `Herd.PLACEMENT_SALT` spells "HERD" — a salt you can read is a salt
## nobody accidentally reuses.
const PLACEMENT_SALT := 0x43495459

## Steps between the farm and the granary, so the road is this many tiles plus
## one. Two, which is the shortest road that still has a tile in the middle for
## something to stand on.
##
## Short for a measured reason rather than a timid one. A delivery arrives later
## than the harvest it came from by roughly the time it takes to walk the road,
## and on a long road that lag exceeds a season — at which point the granary's
## year is out of phase with the world's, and grain grown at the peak of summer
## lands in autumn. Measured directly: at four steps the delivery peak inverts
## against the forage peak entirely. See `test_the_seasons_reach_the_granary`.
##
## That is a real constraint on this design and it should be known before roads
## become something the player draws across a map. The fix when longer roads are
## wanted is more carriers on them, not a longer sack.
const ROUTE_LENGTH := 2

## How many people work the road. Two rather than one so that there is usually
## someone visible on it in each direction, and so a single carrier being held up
## does not stop the city dead — the `world-growth-tone` reading of a road is
## that it is busy, not that it is a single point of failure.
const CITIZENS_PER_ROUTE := 2

## Spring forage a tile needs before a farm is worth putting on it. Water is
## excluded by having no forage at all, so this doubles as the land check for the
## farm site.
const FARM_MIN_FORAGE := 0.60

## Every reason a placement can be turned down, written as the sentence the
## player reads. Named constants rather than literals at the return sites so a
## test can assert *which* refusal fired without matching prose.
const REFUSAL_OFF_MAP := "that is not on the map"
const REFUSAL_WATER := "nothing is built on water"
const REFUSAL_OCCUPIED := "something already stands there"
const REFUSAL_SAME_STRUCTURE := "a route needs two structures, not one"
const REFUSAL_NOT_A_PAIR := "a route runs from a farm to a granary"
const REFUSAL_ALREADY_LINKED := "those two are already connected"
const REFUSAL_NO_STRAIGHT_RUN := "the straight run between them leaves the land"


## Why a structure cannot go on this tile, or an empty string if one can.
##
## The whole placement rule, in three checks and no more: on the map, out of the
## water, and not already taken. Deliberately not `FARM_MIN_FORAGE` — that is a
## constraint the *generator* puts on itself so it does not drop a starting city
## on a mountainside, and applying it to the player would be a soft cost model
## arriving by the back door on a ticket that says not to build one.
static func node_refusal(world: WorldMap, coord: Vector2i) -> String:
	if not world.grid.has_coord(coord):
		return REFUSAL_OFF_MAP
	if world.terrain_at(coord) == WorldGen.Terrain.WATER:
		return REFUSAL_WATER
	if world.node_at(coord) != null:
		return REFUSAL_OCCUPIED
	return ""


static func can_place_node(world: WorldMap, coord: Vector2i) -> bool:
	return node_refusal(world, coord).is_empty()


## Put a structure on a tile, or return null if the tile refuses it.
##
## Null rather than an assert, because a refused placement is an ordinary thing
## for a player to try and the caller's job is to show the reason. The caller
## that wants the reason asks `node_refusal()` for it.
static func place_node(world: WorldMap, coord: Vector2i, kind: int) -> CityNode:
	if not can_place_node(world, coord):
		return null
	var node := CityNode.new(world.nodes.size(), coord, kind)
	world.add_node(node)
	return node


## Why these two structures cannot be joined, or an empty string if they can.
##
## The path is the straight hex run and only that — `HexGrid.line()`, checked for
## land, exactly as `sim/route.gd` says. There is no pathfinding here and a route
## that would cross water is refused rather than routed around: a router would
## have to hold a policy (avoid water? prefer flat? shortest or cheapest?) and
## there is nothing yet to judge one against.
static func route_refusal(world: WorldMap, a: CityNode, b: CityNode) -> String:
	if a == null or b == null or a == b:
		return REFUSAL_SAME_STRUCTURE
	var ends := _grain_order(a, b)
	if ends.is_empty():
		return REFUSAL_NOT_A_PAIR
	if _route_between(world, a, b) != null:
		return REFUSAL_ALREADY_LINKED
	if not _is_walkable(world, HexGrid.line(ends[0].coord, ends[1].coord)):
		return REFUSAL_NO_STRAIGHT_RUN
	return ""


static func can_connect(world: WorldMap, a: CityNode, b: CityNode) -> bool:
	return route_refusal(world, a, b).is_empty()


## Lay a road between two structures and put its carriers on it, or return null
## if the pair refuses the connection.
##
## The route is oriented by what the structures are rather than by which was
## picked first: grain leaves a farm and arrives at a granary, so the direction
## is a property of the pair and clicking them the other way round builds the
## same road. That also makes the result independent of selection order, which
## is one less thing for a replay to have to reproduce.
static func connect_nodes(world: WorldMap, a: CityNode, b: CityNode) -> Route:
	if not can_connect(world, a, b):
		return null
	var ends := _grain_order(a, b)
	return _lay_route(world, ends[0], ends[1])


## The pair as [farm, granary], or empty if it is not one of each.
static func _grain_order(a: CityNode, b: CityNode) -> Array:
	if a.kind == CityNode.Kind.FARM and b.kind == CityNode.Kind.GRANARY:
		return [a, b]
	if b.kind == CityNode.Kind.FARM and a.kind == CityNode.Kind.GRANARY:
		return [b, a]
	return []


## An existing road joining these two, whichever way round it runs.
static func _route_between(world: WorldMap, a: CityNode, b: CityNode) -> Route:
	for route in world.routes:
		if (route.source == a and route.sink == b) or (route.source == b and route.sink == a):
			return route
	return null


## Place one farm, one granary, one route and its citizens. Does nothing if the
## map has no site that satisfies the constraints, which on a mostly-drowned seed
## is the honest outcome rather than a city in the sea.
static func populate(world: WorldMap) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world.world_seed ^ PLACEMENT_SALT

	# Candidates in grid order, so the list a draw indexes into is identical on
	# every run and on every host.
	var sites: Array[Vector2i] = []
	for coord in world.grid.all_coords():
		if world.forage_at(coord) >= FARM_MIN_FORAGE:
			sites.append(coord)
	if sites.is_empty():
		return

	# Bounded rather than looping until it succeeds, for the reason given in
	# `Herd.populate`: a generator that hangs on an unlucky seed is worse than
	# one that places nothing.
	var attempts := 200
	while attempts > 0:
		attempts -= 1
		var farm_coord: Vector2i = sites[rng.randi_range(0, sites.size() - 1)]
		var path := _road_from(world, farm_coord)
		if path.is_empty():
			continue
		_build(world, path)
		return


## A straight run of `ROUTE_LENGTH` land tiles leaving `from`, or an empty array
## if every direction runs into water or off the map.
##
## Directions are tried in `HexGrid.DIRECTIONS` order rather than drawn, so the
## road a given farm site produces never depends on how many draws happened
## before it.
static func _road_from(world: WorldMap, from: Vector2i) -> Array[Vector2i]:
	for candidate_direction in HexGrid.DIRECTIONS:
		var direction: Vector2i = candidate_direction
		var to := from + direction * ROUTE_LENGTH
		if not world.grid.has_coord(to):
			continue
		var path := HexGrid.line(from, to)
		if _is_walkable(world, path):
			return path
	return []


## Whether every tile of a proposed road is on the map and out of the water, and
## whether the road is actually walkable end to end. The last check is not
## paranoia about `HexGrid.line` so much as the boundary a player-drawn route
## arrives at — `route_refusal()` asks this the same way `_road_from` does.
static func _is_walkable(world: WorldMap, path: Array[Vector2i]) -> bool:
	if not Route.is_contiguous(path):
		return false
	for coord in path:
		if not world.grid.has_coord(coord):
			return false
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			return false
	return true


## The generator's city, built through the player's calls.
##
## Nothing here constructs anything directly. `_road_from` has already proved the
## run is land, so neither call can refuse — and if one ever does, the generator
## finds out through the same rule the player does rather than through a second
## copy of it that forgot to be updated.
static func _build(world: WorldMap, path: Array[Vector2i]) -> void:
	var farm := place_node(world, path[0], CityNode.Kind.FARM)
	var granary := place_node(world, path[-1], CityNode.Kind.GRANARY)
	if farm == null or granary == null:
		return
	connect_nodes(world, farm, granary)


## Build the road and the people on it. The one place a `Route` and its carriers
## come into existence; everything that lays a route arrives here.
static func _lay_route(world: WorldMap, source: CityNode, sink: CityNode) -> Route:
	var path := HexGrid.line(source.coord, sink.coord)
	var route := Route.new(world.routes.size(), source, sink, path)
	world.add_route(route)

	# Citizens start spread along the road rather than stacked at the farm, so
	# the first thing anyone sees is a road in use rather than a queue. They
	# desynchronise on their own after that — whoever reaches the farm first
	# leaves with the harvest and the next has to wait for the following turn.
	for i in range(CITIZENS_PER_ROUTE):
		var start := (i * (path.size() - 1)) / maxi(1, CITIZENS_PER_ROUTE - 1)
		world.add_agent(Citizen.new(world.agents.size(), route, start))
	return route
