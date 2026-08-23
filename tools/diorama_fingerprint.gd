extends SceneTree

## Prints a fingerprint of the diorama spike's generated geometry for a fixed
## list of seeds, one line per seed, in the same shape `tools/world_fingerprint.gd`
## emits — so `test.sh` diffs both across two separate Godot processes with one
## mechanism.
##
## The suite already asserts that two builds of the same seed inside one process
## agree. That check is structurally blind to the thing this project has written
## down twice: a value that is constant within a process and differs between
## them reproduces perfectly when you build twice in one run. Mesh generation is
## exactly where that would hide — an instance id folded into a transform, an
## engine constant read at startup, a dictionary iterated in address order.
##
## The tree placement pass is the reason this is worth the two extra seconds.
## It walks `valley.terrain.keys()`, and a Dictionary's key order is an
## implementation detail rather than a promise; the pass sorts them for that
## reason, and a sort that quietly stops being applied is invisible to an
## in-process test and visible here.
##
## No golden hash, same as the sim tool: the pass condition is "two live runs
## agree", so retuning the generator costs nothing and the check makes no claim
## about CPU architecture.
##
## Lives outside res://test because GUT treats any script there that does not
## extend GutTest as a broken test.

const SEEDS := [42, 7, 20260815]


func _init() -> void:
	for world_seed in SEEDS:
		print("%d %d" % [world_seed, _fingerprint(world_seed)])
	quit()


## Folds every surface's fingerprint in sorted-key order. Keyed by position in
## that order rather than by hashing the key text: the string hash would itself
## be an untested assumption inside the check meant to test assumptions.
static func _fingerprint(world_seed: int) -> int:
	var spike: DioramaSpike = load("res://game/diorama/spike.gd").new()
	spike.world_seed = world_seed
	spike._build()
	var keys := spike.last_fingerprints.keys()
	keys.sort()
	var acc := 17
	for i in range(keys.size()):
		acc = (acc * 31 + i + 1) % 1000000007
		var v: int = int(spike.last_fingerprints[keys[i]]) % 1000000007
		acc = (acc * 31 + v + 1000000007) % 1000000007
	spike.free()
	return acc
