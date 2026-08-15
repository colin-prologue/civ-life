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


func _init() -> void:
	for world_seed in SEEDS:
		print("%d %d" % [world_seed, _fingerprint(WorldGen.generate(world_seed))])
	quit()


## Order-sensitive rolling hash over every tile in grid order. Every tile is
## folded in — this is a whole-map digest, not a sample.
static func _fingerprint(map: WorldMap) -> int:
	var data := map.terrain_data()
	var acc := 17
	for i in range(data.size()):
		acc = (acc * 31 + data[i] + 1) % 1000000007
	return acc
