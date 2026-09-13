extends GutTest

# The turn report: what changed in the world this turn, in an order two runs of
# the same seed agree on.
#
# The suite is in four parts, and the middle two are the ones that matter.
#
#   1. **It is produced at all, and identically twice.** A report that cannot be
#      reproduced from a seed is a report that cannot be debugged, and it would
#      take the world down with it — `AgDR-001`.
#
#   2. **The bars are bars.** Every kind states a threshold; each one is checked
#      from both sides, because a threshold only asserted from above is
#      indistinguishable from no threshold. The quiet turn is a test, not a gap:
#      an empty report is the correct answer to a turn in which nothing crossed.
#
#   3. **The bound is stated and the drop is loud.** Six entries, and when more
#      happens the last slot says how many did not fit. Silent truncation would
#      make a busy turn read as a calm one, which is the exact failure this
#      instrument exists to prevent.
#
#   4. **Nothing in sim/ branches on being watched.** Two worlds from one seed,
#      one with its report read every turn and one with it ignored, stay
#      identical tile for tile.
#
# Most of it runs on a flat world built by hand and driven through
# `TurnReport.since()` with a snapshot taken by the test. That is not avoidance
# of the real thing: a threshold is a claim about a *difference between two
# states*, and on a generated world fourteen herds walk through the measurement.
# Driving the comparison directly tests the report's bars rather than testing
# whether the herd AI happened to cooperate. The end-to-end runs on the generated
# world are in part 1 and part 4.

## The seed the rest of the project measures things on.
const SEED_A := 20260815

## How far the determinism comparison runs. Long enough to cross several seasons
## and to let the generated world's herds get somewhere.
const DETERMINISM_TURNS := 120


# --- 1. it is produced, and produced identically ------------------------------


func test_a_fresh_world_carries_an_empty_report() -> void:
	var world := WorldGen.generate(SEED_A)
	assert_not_null(world.report, "a world that has never advanced still has a report")
	assert_true(world.report.is_empty(), "and nothing has happened in it yet")
	assert_eq(world.report.turn, 0, "which is a report about turn zero")


func test_the_same_seed_reports_identically_at_every_turn() -> void:
	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)
	var described := 0

	for turn in range(DETERMINISM_TURNS):
		first.advance_turn()
		second.advance_turn()
		assert_eq(
			_fingerprint(first.report),
			_fingerprint(second.report),
			"turn %d reports identically" % (turn + 1)
		)
		described += first.report.entries.size()

	# A determinism check over 120 empty reports would pass and mean nothing.
	assert_gt(described, 0, "the run actually reported something to be identical about")
	gut.p("%d entries across %d turns" % [described, DETERMINISM_TURNS])


func test_a_generated_world_does_not_report_every_turn() -> void:
	# The firehose check. Fourteen herds each take a step every turn; if every
	# step were news, every turn would be full.
	var world := WorldGen.generate(SEED_A)
	var quiet := 0
	for turn in range(DETERMINISM_TURNS):
		world.advance_turn()
		if world.report.is_empty():
			quiet += 1
	gut.p("%d of %d turns were quiet" % [quiet, DETERMINISM_TURNS])
	assert_gt(quiet, 0, "some turns crossed no bar at all")


# --- 2. the bars are bars -----------------------------------------------------


func test_a_turn_in_which_nothing_happens_reports_nothing() -> void:
	var world := _flat_world()
	world.advance_turn()
	assert_true(world.report.is_empty(), "an empty world crossed nothing")
	assert_eq(world.report.turn, 1, "and the report is about the turn just run")


func test_the_season_turning_is_reported_once_at_the_turn_it_turns() -> void:
	var world := _flat_world()
	var turning: Array[int] = []
	for turn in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()
		if _kinds_in(world.report).has(TurnChange.Kind.SEASON_TURNED):
			turning.append(world.turn)

	assert_eq(turning, [6, 12, 18, 24] as Array[int], "one report per season boundary")


func test_the_season_entry_has_no_place_on_the_map() -> void:
	var world := _flat_world()
	for i in range(Seasons.TURNS_PER_SEASON):
		world.advance_turn()

	var change := _first_of(world.report, TurnChange.Kind.SEASON_TURNED)
	assert_not_null(change, "the season turned at turn %d" % world.turn)
	assert_eq(change.coord, TurnChange.NOWHERE, "a season happens everywhere, so nowhere")
	assert_false(change.has_place(), "and nothing draws a mark for it")
	assert_eq(change.mark, 0, "so it carries no number")


func test_a_herd_changing_the_country_it_stands_in_is_reported() -> void:
	var world := _flat_world()
	var was := HexGrid.from_offset(3, 3)
	var onto := HexGrid.from_offset(4, 3)
	world.set_terrain(onto, WorldGen.Terrain.FOREST)
	var herd := Herd.new(1, was, Species.grazer(), 30.0)
	world.add_agent(herd)

	var before := TurnReport.snapshot(world)
	world.move_agent(herd, onto)
	var report := TurnReport.since(world, before)

	var change := _first_of(report, TurnChange.Kind.HERD_CROSSED)
	assert_not_null(change, "crossing onto different ground is news")
	assert_eq(change.coord, onto, "reported where it arrived, not where it left")
	assert_almost_eq(change.magnitude, 30.0, 0.01, "the size of what crossed")


func test_a_herd_stepping_within_the_same_country_is_not_reported() -> void:
	# The other side of the same bar, and the one that keeps this from being a
	# feed: a herd walks a tile a turn and most of those steps are not news.
	var world := _flat_world()
	var herd := Herd.new(1, HexGrid.from_offset(3, 3), Species.grazer(), 30.0)
	world.add_agent(herd)

	var before := TurnReport.snapshot(world)
	world.move_agent(herd, HexGrid.from_offset(4, 3))
	var report := TurnReport.since(world, before)

	assert_false(
		_kinds_in(report).has(TurnChange.Kind.HERD_CROSSED),
		"one step across the same meadow crossed no bar"
	)


func test_a_herd_crossing_a_population_mark_is_reported_and_a_smaller_change_is_not() -> void:
	var world := _flat_world()
	var herd := Herd.new(1, HexGrid.from_offset(3, 3), Species.grazer(), 95.0)
	world.add_agent(herd)

	var before := TurnReport.snapshot(world)
	world.set_herd_population(herd, 98.0)
	assert_false(
		_kinds_in(TurnReport.since(world, before)).has(TurnChange.Kind.HERD_POPULATION),
		"three head inside the same fifty is not a change worth a line"
	)

	world.set_herd_population(herd, 104.0)
	var change := _first_of(TurnReport.since(world, before), TurnChange.Kind.HERD_POPULATION)
	assert_not_null(change, "crossing a hundred head is")
	assert_almost_eq(change.magnitude, 100.0, 0.01, "the mark crossed, not the nine head that crossed it")
	assert_string_contains(change.describe(), "passed 100 head")


func test_a_herd_falling_back_past_a_mark_says_so() -> void:
	var world := _flat_world()
	var herd := Herd.new(1, HexGrid.from_offset(3, 3), Species.grazer(), 104.0)
	world.add_agent(herd)

	var before := TurnReport.snapshot(world)
	world.set_herd_population(herd, 96.0)
	var change := _first_of(TurnReport.since(world, before), TurnChange.Kind.HERD_POPULATION)
	assert_not_null(change, "falling past a mark is as notable as rising past it")
	assert_almost_eq(change.magnitude, -100.0, 0.01, "the same mark, signed the other way")
	assert_string_contains(change.describe(), "fell back below 100 head")


func test_a_granary_crossing_a_store_mark_is_reported_and_a_smaller_delivery_is_not() -> void:
	var world := _flat_world()
	var granary := CityNode.new(0, HexGrid.from_offset(5, 5), CityNode.Kind.GRANARY)
	world.add_node(granary)
	granary.store = 21.0

	var before := TurnReport.snapshot(world)
	granary.store = 28.0
	assert_false(
		_kinds_in(TurnReport.since(world, before)).has(TurnChange.Kind.GRANARY_STORE),
		"seven grain inside the same ten is not news"
	)

	granary.store = 33.0
	var change := _first_of(TurnReport.since(world, before), TurnChange.Kind.GRANARY_STORE)
	assert_not_null(change, "crossing thirty is")
	assert_eq(change.coord, granary.coord, "reported at the granary")
	assert_almost_eq(change.magnitude, 30.0, 0.01, "the mark crossed, not the grain that crossed it")
	assert_string_contains(change.describe(), "passed 30 grain")


func test_a_mark_crossed_by_a_hair_still_says_which_mark() -> void:
	# The defect this wording replaced: a store drifting over a mark by a
	# fraction reported "the granary took in 0 grain" — an entry that met the bar
	# and then said nothing. Reporting the bar cannot produce that sentence.
	var world := _flat_world()
	var granary := CityNode.new(0, HexGrid.from_offset(5, 5), CityNode.Kind.GRANARY)
	world.add_node(granary)
	granary.store = 29.999

	var before := TurnReport.snapshot(world)
	granary.store = 30.001
	var change := _first_of(TurnReport.since(world, before), TurnChange.Kind.GRANARY_STORE)
	assert_not_null(change, "a hair over the mark is still over the mark")
	assert_string_contains(change.describe(), "passed 30 grain")
	assert_false(change.describe().contains(" 0 grain"), "and never reports nothing happening")


func test_a_farm_filling_up_is_not_reported_as_a_granary() -> void:
	var world := _flat_world()
	var farm := CityNode.new(0, HexGrid.from_offset(5, 5), CityNode.Kind.FARM)
	world.add_node(farm)

	var before := TurnReport.snapshot(world)
	farm.store = 60.0
	assert_true(TurnReport.since(world, before).is_empty(), "the bar is about stores, not fields")


func test_a_carrier_reports_the_turn_it_is_first_held_up_and_not_after() -> void:
	var world := _flat_world()
	var route := _lay_road(world)
	var citizen := world.citizens()[0]

	var before := TurnReport.snapshot(world)
	citizen.held_up = 1
	var change := _first_of(TurnReport.since(world, before), TurnChange.Kind.ROUTE_BLOCKED)
	assert_not_null(change, "the turn the road's throughput actually dropped")
	assert_eq(change.coord, citizen.coord, "reported where the carrier is standing")

	citizen.held_up = 3
	assert_false(
		_kinds_in(TurnReport.since(world, before)).has(TurnChange.Kind.ROUTE_BLOCKED),
		"a hold-up already reported is not re-reported every turn of it"
	)
	assert_gt(route.length(), 0, "the road this ran on exists")


func test_a_blocked_road_counts_the_mouths_actually_standing_in_it() -> void:
	var world := _flat_world()
	_lay_road(world)
	var citizen := world.citizens()[0]
	world.add_agent(Herd.new(200, citizen.coord, Species.grazer(), 12.0))
	world.add_agent(Herd.new(201, citizen.coord, Species.grazer(), 7.0))

	var expected := 0.0
	for agent in world.agents:
		if agent.coord == citizen.coord:
			expected += agent.forage_demand()

	var before := TurnReport.snapshot(world)
	citizen.held_up = 1
	var change := _first_of(TurnReport.since(world, before), TurnChange.Kind.ROUTE_BLOCKED)
	assert_not_null(change, "the carrier is held up")
	assert_almost_eq(
		change.magnitude,
		expected,
		0.0001,
		"the mouths in the road are the ones standing there"
	)


func test_the_mouths_in_the_road_are_counted_rather_than_read_off_the_cache() -> void:
	# The per-tile demand cache is maintained by adding and subtracting floats as
	# agents move, and `WorldMap` documents it as something to decide by and never
	# to quote — after enough turns it drifts off the truth. This number is quoted
	# ("3 mouths in the road") and it ranks entries when the report has to drop
	# some, so it has to come from the agents.
	#
	# Corrupting the cache outright is the cheapest way to tell the two sources
	# apart: drift is this, only smaller and slower.
	var world := _flat_world()
	_lay_road(world)
	var citizen := world.citizens()[0]
	world.add_agent(Herd.new(200, citizen.coord, Species.grazer(), 9.0))

	var honest := world.forage_demand_summed_at(citizen.coord)
	world._forage_demand[world.grid.index_of(citizen.coord)] = 999.0

	var before := TurnReport.snapshot(world)
	citizen.held_up = 1
	var change := _first_of(TurnReport.since(world, before), TurnChange.Kind.ROUTE_BLOCKED)
	assert_not_null(change, "the carrier is held up")
	assert_almost_eq(
		change.magnitude,
		honest,
		0.0001,
		"the report counted the agents rather than believing the cache"
	)


# --- 3. the bound, and what it says when it truncates -------------------------


func test_the_report_never_carries_more_than_its_stated_maximum() -> void:
	var world := _busy_world(20)
	var before := TurnReport.snapshot(world)
	_disturb(world, 20)
	var report := TurnReport.since(world, before)

	assert_eq(
		report.entries.size(),
		TurnReport.MAX_ENTRIES,
		"twenty changes fit into the stated maximum, not into twenty lines"
	)


func test_a_truncated_report_says_how_many_it_dropped() -> void:
	var world := _busy_world(20)
	var before := TurnReport.snapshot(world)
	_disturb(world, 20)
	var report := TurnReport.since(world, before)

	assert_true(report.was_truncated(), "the report admits it is standing in for more")
	var dropped := _first_of(report, TurnChange.Kind.DROPPED)
	assert_not_null(dropped, "and says so as an entry rather than in silence")
	assert_eq(
		roundi(dropped.magnitude),
		20 - (TurnReport.MAX_ENTRIES - 1),
		"the count is what did not fit: everything, less the slots that were kept"
	)
	assert_string_contains(dropped.describe(), "not shown")


func test_an_untruncated_report_carries_no_dropped_entry() -> void:
	var world := _busy_world(3)
	var before := TurnReport.snapshot(world)
	_disturb(world, 3)
	var report := TurnReport.since(world, before)

	assert_eq(report.entries.size(), 3, "three changes are three lines")
	assert_false(report.was_truncated(), "nothing was dropped, so nothing says it was")


func test_what_survives_a_crowded_turn_is_the_biggest_of_the_top_kind() -> void:
	# The drop rule, stated in the code as "kind first, then magnitude". Here the
	# candidates are all one kind, so the rule reduces to: the big ones live.
	var world := _busy_world(20)
	var before := TurnReport.snapshot(world)
	_disturb(world, 20)
	var report := TurnReport.since(world, before)

	var kept_sizes: Array[float] = []
	for change in report.entries:
		if change.kind != TurnChange.Kind.DROPPED:
			kept_sizes.append(absf(change.magnitude))
	kept_sizes.sort()
	assert_gt(kept_sizes.size(), 0, "something survived")
	# `_disturb` moves herd i by i+1 head, so the survivors are the last few.
	assert_gte(
		kept_sizes[0],
		float(20 - kept_sizes.size()),
		"nothing small survived while something large was dropped"
	)


# --- 4. order, marks, and not being watched -----------------------------------


func test_entries_run_the_map_in_grid_order_with_the_season_first() -> void:
	var world := _busy_world(4)
	# Stand the clock on the last turn of a season, so the turn about to run is
	# the one that turns it. Set rather than advanced, because advancing would
	# also let four herds walk about and this test is about ordering.
	world.turn = Seasons.TURNS_PER_SEASON - 1

	var before := TurnReport.snapshot(world)
	world.turn += 1
	_disturb(world, 4)
	var report := TurnReport.since(world, before)

	assert_eq(
		report.entries[0].kind,
		TurnChange.Kind.SEASON_TURNED,
		"the whole map comes before any one place on it"
	)
	var last_index := -2
	for change in report.entries:
		if not change.has_place():
			continue
		assert_gte(change.order_index, last_index, "grid order, top-left to bottom-right")
		last_index = change.order_index


func test_the_order_does_not_depend_on_the_order_changes_were_found() -> void:
	# AgDR-001 forbids an ordering that comes out of iteration order. The check
	# is that two worlds holding the same herds in the *opposite* add order
	# report the same tiles in the same sequence.
	var forward := _busy_world(6)
	var backward := _busy_world(6, true)

	var before_forward := TurnReport.snapshot(forward)
	var before_backward := TurnReport.snapshot(backward)
	_disturb(forward, 6)
	_disturb(backward, 6)

	assert_eq(
		_coords_in(TurnReport.since(forward, before_forward)),
		_coords_in(TurnReport.since(backward, before_backward)),
		"the report reads down the map, not down the agent list"
	)


func test_every_placed_entry_is_numbered_and_the_words_carry_the_number() -> void:
	var world := _busy_world(4)
	var before := TurnReport.snapshot(world)
	_disturb(world, 4)
	var report := TurnReport.since(world, before)

	var lines := report.lines()
	assert_eq(lines.size(), report.entries.size(), "one line per entry")

	var expected := 0
	for i in range(report.entries.size()):
		var change := report.entries[i]
		if not change.has_place():
			assert_eq(change.mark, 0, "a placeless change is not numbered")
			continue
		expected += 1
		assert_eq(change.mark, expected, "marks count 1..n over the entries with a place")
		assert_string_contains(lines[i], "%d. " % expected)


func test_the_world_runs_the_same_whether_or_not_the_report_is_read() -> void:
	var watched := WorldGen.generate(SEED_A)
	var ignored := WorldGen.generate(SEED_A)

	for turn in range(DETERMINISM_TURNS):
		watched.advance_turn()
		# Read it, the way a renderer would, every single turn.
		var _text := watched.report.lines()
		var _size := watched.report.entries.size()
		ignored.advance_turn()

	assert_eq(
		watched.difference_count(ignored),
		0,
		"a world being watched does exactly the work of one that is not"
	)
	assert_almost_eq(
		watched.total_herd_population(),
		ignored.total_herd_population(),
		0.001,
		"down to the animals in it"
	)


# --- helpers -----------------------------------------------------------------


## A featureless world of one terrain with nothing alive on it, so a measured
## difference is the one the test made.
func _flat_world(width := 12, height := 10) -> WorldMap:
	var world := WorldMap.new(HexGrid.new(width, height), SEED_A)
	for coord in world.grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.GRASS)
	return world


## A flat world with `count` herds strung across it, each standing on grass with
## a forest tile beside it to cross onto. Herd `i` holds `i + 1` head, so the
## changes they make have distinct sizes and the drop rule has something to rank.
##
## `reversed` adds the same herds in the opposite order. Nothing else about the
## world differs, which is what makes it a test of whether report order comes
## from the map or from the agent list.
func _busy_world(count: int, reversed := false) -> WorldMap:
	var world := _flat_world(24, 10)
	var order := range(count)
	if reversed:
		order.reverse()
	for i in order:
		world.set_terrain(_herd_destination(i), WorldGen.Terrain.FOREST)
		world.add_agent(Herd.new(100 + i, _herd_origin(i), Species.grazer(), float(i + 1)))
	return world


## Walk every herd `_busy_world` placed onto the forest beside it. Coordinates
## are recomputed from the herd's id rather than stepped from where it stands, so
## this stays a single deliberate move even if something else moved it first.
func _disturb(world: WorldMap, count: int) -> void:
	for herd in world.herds():
		var i := herd.id - 100
		if i < 0 or i >= count:
			continue
		world.move_agent(herd, _herd_destination(i))


func _herd_origin(i: int) -> Vector2i:
	return HexGrid.from_offset(1 + i, 2 + (i % 4))


func _herd_destination(i: int) -> Vector2i:
	return HexGrid.from_offset(2 + i, 2 + (i % 4))


## A farm, a granary, the road between them and one carrier on it.
func _lay_road(world: WorldMap) -> Route:
	var farm := CityNode.new(0, HexGrid.from_offset(2, 4), CityNode.Kind.FARM)
	var granary := CityNode.new(1, HexGrid.from_offset(7, 4), CityNode.Kind.GRANARY)
	world.add_node(farm)
	world.add_node(granary)
	var route := Route.new(0, farm, granary, HexGrid.line(farm.coord, granary.coord))
	world.add_route(route)
	world.add_agent(Citizen.new(0, route, 2))
	return route


## Everything about a report that two runs of the same seed have to agree on,
## flattened to a string so a mismatch prints as a diff rather than as "false".
func _fingerprint(report: TurnReport) -> String:
	var parts := PackedStringArray()
	parts.append("turn=%d" % report.turn)
	for change in report.entries:
		parts.append("%d/%d,%d/%.4f/%d" % [
			change.kind, change.coord.x, change.coord.y, change.magnitude, change.mark
		])
	return "|".join(parts)


func _kinds_in(report: TurnReport) -> Array[int]:
	var out: Array[int] = []
	for change in report.entries:
		out.append(change.kind)
	return out


func _coords_in(report: TurnReport) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for change in report.entries:
		out.append(change.coord)
	return out


func _first_of(report: TurnReport, kind: int) -> TurnChange:
	for change in report.entries:
		if change.kind == kind:
			return change
	return null
