extends SceneTree

## Prints a fingerprint of the generated map for a fixed list of seeds, one line
## per seed, and nothing else on stdout that varies between runs.
##
## This exists so `test.sh` can generate the same worlds in two separate Godot
## processes and diff the output. The in-process determinism test cannot see a
## divergence that is constant within a process but varies between them — a
## per-process hash salt, an instance id folded into a draw, an engine value
## read once at startup. Those all reproduce perfectly when you generate twice
## inside one run, which is exactly why generating twice inside one run is not
## sufficient evidence for the claim this project rests on.
##
## Deliberately NOT a committed golden hash. The pass condition is "two live
## runs agree", not "the map still equals a number recorded in 2026" — so
## retuning the generator does not require regenerating a fixture, and the check
## carries no assumptions about CPU architecture or float ordering.
##
## Lives outside res://test because GUT scans that directory and treats any
## script there that does not extend GutTest as a broken test.

const SEEDS := [20260815, 987654321, 1, 42, 7, 555]

## Turns each world is run forward before its final fingerprint is taken.
## Deliberately not a multiple of the season length and more than a year, so the
## digest covers a world part-way through a season some distance from where it
## started rather than one that has landed neatly back on spring.
const TURNS := 37


func _init() -> void:
	for world_seed in SEEDS:
		print("%d %d" % [world_seed, _fingerprint(WorldGen.generate(world_seed))])
	quit()


## Order-sensitive rolling hash over every tile in grid order, taken at turn 0
## and again after `TURNS` turns. Every tile is folded in — this is a whole-map
## digest, not a sample.
##
## Forage is folded in alongside terrain because the cross-process check is only
## as wide as what it hashes: a terrain-only digest would keep agreeing across
## processes while every seasonal value in the world diverged.
##
## The same argument applies again to everything that carries state forward.
## Terrain and forage are pure functions of `(seed, turn)` and would keep
## agreeing across processes while every herd, citizen and granary in the world
## diverged, so the live state is folded in too — which is the only part of this
## digest that can actually catch a float or an iteration order behaving
## differently in a second process.
static func _fingerprint(map: WorldMap) -> int:
	var acc := _fold(_fold(17, map.terrain_data()), _quantised_forage(map))
	for i in range(TURNS):
		map.advance_turn()
	acc = _fold(_fold(acc, [map.turn, map.season()]), _quantised_forage(map))
	return _fold(acc, _quantised_state(map))


## Everything that survives a turn, as integers, in step order: where each agent
## is standing, what it is carrying or how many of it there are, and what every
## structure holds.
static func _quantised_state(map: WorldMap) -> Array:
	var out := []
	for agent in map.agents:
		out.append(agent.coord.x)
		out.append(agent.coord.y)
		out.append(roundi(agent.forage_demand() * 1000.0))
	for citizen in map.citizens():
		out.append(roundi(citizen.carrying * 1000.0))
	for node in map.nodes:
		out.append(node.kind)
		out.append(roundi(node.store * 1000.0))
	return out


static func _fold(acc: int, values) -> int:
	var out := acc
	for value in values:
		out = (out * 31 + int(value) + 1) % 1000000007
	return out


## Forage as integers, so the digest is over exact values rather than over the
## text of a float. The table these come from holds constants, so there is no
## arithmetic here to round differently on another host.
static func _quantised_forage(map: WorldMap) -> Array:
	var out := []
	for value in map.forage_data():
		out.append(roundi(value * 10000.0))
	return out
