extends GutTest

# Issue #39, AC1 — the prerequisite for predators, and a measurement rather than a
# feature.
#
# The worry: a herd walks one tile a turn and can sense four. If a region
# collapses around it — grazed out now, thinned by predators later — can it get
# out, or does it sit in the crash until the crash ends? Predators build regional
# pressure; this checks that the release already exists before the pressure is
# added.
#
# THE BAR, FIXED BEFORE THIS TEST WAS FIRST RUN (committed ahead of any result so
# it cannot have been chosen to fit one):
#
#   Region     A fixed 10x10 block of the 40x30 map in offset coordinates, the
#              same blocks later regional analysis uses. Only blocks at least 70%
#              land are probed.
#   Depleted   Every tile in the block has grazing vitality at `Land.MIN_VITALITY`
#              before the first turn, and is put back to it after every turn. The
#              region is held collapsed for the whole window, so "the ground
#              recovered under the herd" cannot count as an escape.
#   Probe      One fresh grazer herd at starting population, on the block's land
#              tile nearest its centre, added to the world as generated (its
#              ordinary herds left in place), from turn 0.
#   Escaped    Within ESCAPE_TURNS (48 turns, two years), the probe stands on a
#              tile that is (a) outside the block, (b) at least ESCAPE_DISTANCE (4)
#              hexes from where it started — further than it could see from there
#              — and (c) whose grazing vitality is at least BETTER_GROUND (0.5),
#              more than three times the depleted floor.
#   Pass       Every probed block, on both seeds.
#
# `move_range` 1 and `sense_range` 4 are asserted as preconditions, so this test
# measures the migration that exists rather than a retuned one. If it fails, the
# finding is that migration needs its own ticket — not that this bar should move.

const SEEDS := [20260815, 987654321]
const BLOCK := 10
const MIN_LAND_FRACTION := 0.70
const ESCAPE_TURNS := 48
const ESCAPE_DISTANCE := 4
const BETTER_GROUND := 0.5


func test_a_herd_escapes_a_depleted_region() -> void:
	var species := Species.grazer()
	assert_eq(species.move_range, 1, "measured at the current move range")
	assert_eq(species.sense_range, 4, "measured at the current sense range")

	var probed := 0
	var stuck: Array[String] = []
	for world_seed in SEEDS:
		var layout := WorldGen.generate(world_seed)
		for by in range(layout.grid.height / BLOCK):
			for bx in range(layout.grid.width / BLOCK):
				var result := _probe(world_seed, bx, by)
				if result.is_empty():
					continue
				probed += 1
				gut.p("seed %d block (%d,%d): %s" % [world_seed, bx, by, result.line])
				if not result.escaped:
					stuck.append("seed %d block (%d,%d)" % [world_seed, bx, by])

	gut.p("%d of %d probed herds escaped within %d turns" % [
		probed - stuck.size(), probed, ESCAPE_TURNS,
	])
	assert_gt(probed, 0, "at least one block was land enough to probe")
	assert_eq(stuck.size(), 0, "herds that stayed in a collapsed region: %s" % [stuck])


## One block on one seed. Empty when the block is too wet to probe.
func _probe(world_seed: int, bx: int, by: int) -> Dictionary:
	var world := WorldGen.generate(world_seed)
	var block: Array[Vector2i] = []
	var land := 0
	for row in range(by * BLOCK, (by + 1) * BLOCK):
		for col in range(bx * BLOCK, (bx + 1) * BLOCK):
			var c := HexGrid.from_offset(col, row)
			block.append(c)
			if world.terrain_at(c) != WorldGen.Terrain.WATER:
				land += 1
	if float(land) / float(block.size()) < MIN_LAND_FRACTION:
		return {}

	var centre := HexGrid.from_offset(bx * BLOCK + BLOCK / 2, by * BLOCK + BLOCK / 2)
	var start := centre
	var nearest := 1 << 30
	for c in block:
		if world.terrain_at(c) == WorldGen.Terrain.WATER:
			continue
		var d := HexGrid.distance(c, centre)
		if d < nearest:
			nearest = d
			start = c

	var species := Species.grazer()
	var probe := Herd.new(10_000, start, species, species.starting_population)
	world.add_agent(probe)
	_deplete(world, block)

	var furthest := 0
	for turn in range(ESCAPE_TURNS):
		world.advance_turn()
		_deplete(world, block)
		var here := probe.coord
		furthest = maxi(furthest, HexGrid.distance(here, start))
		if not block.has(here) \
				and HexGrid.distance(here, start) >= ESCAPE_DISTANCE \
				and world.vitality_at(here, Land.Use.GRAZE) >= BETTER_GROUND:
			return {
				"escaped": true,
				"line": "escaped on turn %d to %s, %d hexes out, vitality %.2f" % [
					turn + 1, here, HexGrid.distance(here, start),
					world.vitality_at(here, Land.Use.GRAZE)],
			}
	return {
		"escaped": false,
		"line": "STUCK after %d turns at %s, furthest %d hexes from start, %.1f heads" % [
			ESCAPE_TURNS, probe.coord, furthest, probe.population],
	}


func _deplete(world: WorldMap, block: Array[Vector2i]) -> void:
	for c in block:
		world.set_vitality(c, Land.Use.GRAZE, Land.MIN_VITALITY)
