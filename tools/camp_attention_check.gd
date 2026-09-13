extends SceneTree

## Is the best place to camp the same every year?
##
## #49's gathering node was first tuned against a world whose herds never moved,
## and its test asserted that a camp on the busiest ground out-gathers one on a
## typical tile threefold. Without grazing wear the typical tile saw no herd at
## all for eight years on six of ten seeds, so the ratio measured the static world
## `AgDR-014` exists to cure. The owner's call is that **camps reward attention,
## not siting**, and the honest form of that is a claim about a population of
## seeds: in enough of them, there is a year the typical camp wins.
##
## Measured on `test/test_gathering.gd`'s own site selection, which is why both
## call `tools/camp_sites.gd` rather than each having its own:
##
## | world                         | seeds with a year the typical camp won | median busy best/worst |
## |-------------------------------|-----------------------------------------|------------------------|
## | no wear, live census          | 0 / 10                                  | 1.14                   |
## | #51 with grazing draw removed | 1 / 10                                  | 1.18                   |
## | #51 as merged                 | 6 / 10                                  | 2.32                   |
##
## Lives here rather than in GUT because ten seeds of sixteen simulated years
## each would add about a minute to every suite run, and the two standard seeds
## GUT uses barely separate the worlds.

const CampSites := preload("res://tools/camp_sites.gd")

const SEEDS := [20260815, 987654321, 42, 7, 31337, 2024, 999, 123456, 555, 8675309]

## The same span `test_gathering.gd` measures placement over.
const MEASURED_YEARS := 8

## Seeds that must have at least one year in which the typical camp won.
##
## Sits between the measured worlds: two seeds clear of the world without wear
## (1 of 10) and three below the world with it (6 of 10). **Do not lower it to
## pass** — a bar at or under the world without wear erases the distinction this
## gate exists to draw. If it fails with grazing wear present, the per-seed
## counts printed above the verdict are the finding.
const MIN_SEEDS_WITH_A_FLIP := 3


func _init() -> void:
	var seeds_with_flip := 0
	var swings: Array[float] = []
	for world_seed in SEEDS:
		var measured := CampSites.measure_placement(world_seed, MEASURED_YEARS)
		var flips := CampSites.flip_years(measured)
		if flips > 0:
			seeds_with_flip += 1
		var swing := _swing(measured["busy_years"])
		swings.append(swing)
		print("camp seed %d: typical camp won %d of %d years; busy camp best/worst %s"
				% [world_seed, flips, MEASURED_YEARS, _format(swing)])

	# The upper of the two middle values on an even count, which is the convention
	# every published table of these numbers uses — #42's body, this file's table
	# above, and the retirement note in `test_gathering.gd`. Stated because it is
	# not the only convention and the choice is visible: averaging the two middles
	# reports 2.13 where those tables say 2.32, and a gate whose own docstring
	# disagrees with its output is worse than either number.
	swings.sort()
	var median: float = swings[swings.size() / 2]
	var verdict := "ok  " if seeds_with_flip >= MIN_SEEDS_WITH_A_FLIP else "FAIL"
	print("%s camp attention: %d of %d seeds had a year the typical camp won (bar %d); median busy-camp swing %s"
			% [verdict, seeds_with_flip, SEEDS.size(), MIN_SEEDS_WITH_A_FLIP, _format(median)])
	quit(0 if seeds_with_flip >= MIN_SEEDS_WITH_A_FLIP else 1)


## The busy camp's best year over its worst. A worst year of nothing is reported
## as unbounded rather than dropped: a camp that went dark for a year moved the
## most, and leaving it out would pull the median toward the static world.
static func _swing(years: Array) -> float:
	var best := 0.0
	var worst := INF
	for value in years:
		best = maxf(best, value)
		worst = minf(worst, value)
	if worst <= 0.0:
		return INF
	return best / worst


static func _format(value: float) -> String:
	return "unbounded" if is_inf(value) else "%.2f" % value
