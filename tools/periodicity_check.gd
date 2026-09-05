extends SceneTree

## Does the world still settle into a repeating cycle?
##
## `AgDR-014` exists because it did. Before land had any memory, a probe
## fingerprinting each year found **every seed** converging to a fixed annual
## cycle — settling at years 7, 17, 11 and 5 — with three of the four doing
## precisely the same thing every year forever after. Forage was a pure function
## of terrain and season, terrain never changed, and a deterministic
## gradient-follower over a periodic field has nowhere to go but a limit cycle.
##
## This is the gate that says that stopped being true. It prints one line per
## seed and exits non-zero if any world settles.
##
## The fingerprint is exact string match over quantised floats, which makes it
## *conservative in the right direction*: a world that is effectively static but
## jittering in the last decimal place will be reported as varying. If this gate
## passes, non-convergence is at least as good as it claims.

## Every seed Probe B measured, not a sample of them.
##
## All four settled in the baseline — years 7, 17, 11 and 5 — so a gate covering
## a subset could pass while a documented converging seed still settles, and
## `./test.sh` would report success with the primary acceptance criterion unmet.
const SEEDS := [20260815, 987654321, 42, 7]
const YEARS := 200


func _init() -> void:
	var failed := false
	for world_seed in SEEDS:
		var world := WorldGen.generate(world_seed)

		var prints: Array[String] = []
		for year in range(YEARS):
			for i in range(Seasons.TURNS_PER_YEAR):
				world.advance_turn()
			prints.append(_fingerprint(world))

		var period := -1
		var settled_at := -1
		for i in range(prints.size()):
			for j in range(i + 1, prints.size()):
				if prints[i] == prints[j] and _confirms(prints, i, j - i):
					settled_at = i
					period = j - i
					break
			if period > 0:
				break

		if period > 0:
			failed = true
			print("FAIL seed %d settled at year %d, repeating every %d year(s)"
					% [world_seed, settled_at + 1, period])
		else:
			print("ok   seed %d did not settle in %d years (%d distinct year-states)"
					% [world_seed, YEARS, prints.size()])

	quit(1 if failed else 0)


## A single pair of equal fingerprints is not a cycle.
##
## These digests are lossy — populations and vitality are quantised, and each
## vitality row is folded modulo a prime — so two sampled years can collide while
## the world goes on diverging afterwards. Acting on one match would let the
## primary acceptance gate report a false convergence and fail `./test.sh` on a
## world that is behaving correctly, which is the worse direction for this gate
## to be wrong in: a false alarm gets tuned away, and tuning away a real one is
## how the finding this record exists for gets lost.
##
## A candidate period is only accepted if every remaining sample repeats it.
static func _confirms(prints: Array, start: int, period: int) -> bool:
	var checked := 0
	for k in range(start + period, prints.size()):
		if prints[k] != prints[k - period]:
			return false
		checked += 1
	# Require the claim to rest on more than the pair that suggested it.
	return checked >= period * 2


## Herds and land together. Herd state alone was what the original probe hashed;
## vitality is folded in because it is the thing that is supposed to be keeping
## the world moving, and a gate that cannot see it would pass on a world where
## only the animals wobbled.
func _fingerprint(world: WorldMap) -> String:
	var parts: Array[String] = []
	for herd in world.herds():
		parts.append("%d:%d,%d:%d" % [herd.id, herd.coord.x, herd.coord.y,
				roundi(herd.population * 100.0)])
	for use in range(Land.USE_COUNT):
		var acc := 0
		var i := 0
		for value in world.vitality_data(use):
			acc = (acc * 31 + roundi(value * 1000.0) + i) % 1000000007
			i += 1
		parts.append("v%d:%d" % [use, acc])
	return "|".join(parts)
