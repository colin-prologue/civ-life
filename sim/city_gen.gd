class_name CityGen
extends RefCounted

## Puts the smallest possible city on a freshly generated world: a farm, a
## granary a short walk away, a road between them, and people on it.
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
## paranoia about `HexGrid.line` so much as the boundary where a hand-written
## path would arrive once placement is player-facing.
static func _is_walkable(world: WorldMap, path: Array[Vector2i]) -> bool:
	if not Route.is_contiguous(path):
		return false
	for coord in path:
		if not world.grid.has_coord(coord):
			return false
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			return false
	return true


static func _build(world: WorldMap, path: Array[Vector2i]) -> void:
	var farm := CityNode.new(world.nodes.size(), path[0], CityNode.Kind.FARM)
	world.add_node(farm)
	var granary := CityNode.new(world.nodes.size(), path[-1], CityNode.Kind.GRANARY)
	world.add_node(granary)

	var route := Route.new(world.routes.size(), farm, granary, path)
	world.add_route(route)

	# Citizens start spread along the road rather than stacked at the farm, so
	# the first thing anyone sees is a road in use rather than a queue. They
	# desynchronise on their own after that — whoever reaches the farm first
	# leaves with the harvest and the next has to wait for the following turn.
	for i in range(CITIZENS_PER_ROUTE):
		var start := (i * (path.size() - 1)) / maxi(1, CITIZENS_PER_ROUTE - 1)
		world.add_agent(Citizen.new(world.agents.size(), route, start))
