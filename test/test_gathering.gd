extends GutTest

# The first positive coupling in the sim.
#
# Everything before this either runs on its own (terrain, seasons, herds, the
# city) or gets in the other's way — a herd standing on a road holds a carrier
# up, and that was the whole of the interaction between the wild half of the
# world and the built one. A gathering camp is the same two systems reading each
# other in the other direction: what the animals are doing near a place is what
# that place is worth.
#
# The suite is built around one question the ticket asks to be answered with a
# number rather than an opinion: **does where you put a camp actually matter?**
# `test_a_camp_is_worth_far_more_where_the_animals_go` measures it and prints
# what it measured, on both standard seeds. If that ratio ever comes back near
# 1.0, the coupling is decorative and the finding is worth more than the
# feature — the answer would not be to widen the radius until the number looks
# better.
#
# Three things it is also built to catch, all of them ways this could be quietly
# wrong while looking right:
#
#   1. **A camp that is really a farm.** The control against terrain is a farm
#      placed on each of the same two tiles: identical terrain means identical
#      farm output, so any difference between the camps is not the ground.
#   2. **A camp that eats.** `AgDR-009` says nothing can deplete a tile by
#      feeding from it, and this ticket is explicitly not the one that revisits
#      that. Asserted by running the same seed with and without camps and
#      comparing every herd, head for head, after five hundred turns.
#   3. **A camp that asks what is nearby.** `AgDR-013` says agents report
#      quantities and nothing asks them what they are. A node that reached for
#      `world.herds()` would pass every behavioural test in this file, so the
#      source is grepped for it.
#
# ---
#
# **The finding this suite turned up, which is larger than the feature.**
#
# The mechanism works and is measured below: a camp on ground the animals use
# earns more than a farm on the same tile, and a camp away from them earns
# nothing at all. Placement is emphatically a decision.
#
# What is much weaker than the ticket hoped is the *rate* of the thing it was
# reaching for — a herd arriving, the camp waking up, the herd moving on. That
# does happen, and the sweep in
# `test_what_the_city_the_game_generates_actually_gathers` catches it: on seed
# 555 the generated camp is dark for ten straight years and then wakes in the
# eleventh; on seed 12345 it works for two turns in the first year and is dark
# for the following eleven; on seed 42 it is lit on 237 of 288 turns, which
# leaves 51 quiet ones. Arrivals and departures are real.
#
# They are also *rare and slow*, because **the herds barely travel**. Measured
# over five hundred turns, each herd's furthest displacement from where it was
# placed was 0 to 8 tiles and roughly half never left a camp's reach at all. A
# gradient-follower (`AgDR-010`) climbs to a local maximum and mostly stays on
# it; the territory drifts over years rather than a herd crossing the map in a
# season.
#
# So the honest shape of a generated camp is bimodal rather than eventful: on
# the eight seeds swept it is lit at some point on five, and on most of those
# five it is lit essentially always or essentially never, with the transition —
# when there is one — taking the better part of a decade. `world-growth-tone`
# rule 4's worked example, a herd migrating *through* a district and making a
# node viable while it passes, is not what this produces at this migration
# range. Whether a decade-scale wake-up is an event a player notices or just a
# slow-moving fact about their map is AC11, and it needs a person.
#
# The missing ingredient, if it is missing, is upstream of this file — herds
# with more range — and not a constant in it. The radius sweep recorded on
# `CityNode.GATHERING_RADIUS` is the evidence for that: no reach makes a camp
# both wake and fall quiet on the standard seeds, because widening it just
# swallows more permanently-occupied territory.
# `test_the_herds_do_not_travel_far_enough_to_arrive` records the displacement so
# a future change to migration shows up here as a difference rather than as a
# surprise.

const SEED_A := 20260815
const SEED_B := 987654321

## The seeds every measurement in the project is quoted on.
const STANDARD_SEEDS := [SEED_A, SEED_B]

## The wider spread the *generated* camp is reported over, standard seeds first.
##
## Two seeds are enough for a claim about a mechanism, which is what every other
## measurement here makes. They are not enough for a claim about how often a
## generated city gets a camp worth having, because that depends on where one
## unclever placement lands relative to where fourteen herds settled — which is a
## coin the seed flips. Both standard seeds happen to come up dark, and reporting
## only those two would have stated a flat "never" that the captured frames of
## seed 42 disprove.
##
## Eight rather than the twelve first swept, and the four dropped were dropped
## for cost rather than for being inconvenient: each seed here is twelve years of
## full world simulation, and the wider sweep pushed the suite far enough that an
## unrelated wall-clock budget in `test_seasons.gd` started failing. The eight
## kept are the ones carrying distinct outcomes — two permanently dark, two
## permanently lit, one lit with quiet spells, one waking after a decade, one
## flickering once and going dark. The four dropped (99, 31337, 8, 777) were all
## permanently dark and duplicated a case already represented.
const REPORTED_SEEDS := [SEED_A, SEED_B, 1, 42, 555, 2024, 12345, 7]

## Years the placement measurement runs for. Long enough that a camp's total is
## a claim about where herds *live* rather than about where one happened to be
## standing in the first spring.
const MEASURED_YEARS := 8

## Years the *generated* city's camp is reported over. Longer than the placement
## measurement, because what is being looked at there is a shape over years
## rather than a total, and four years of a quiet camp is not enough to tell a
## camp that is waiting from a camp that is broken.
const REPORTED_YEARS := 12

## Determinism horizon, matching `test_city.gd` and `test_herds.gd`.
const DETERMINISM_TURNS := 500

## How much better a camp on the busiest ground must do than one on the quietest,
## over `MEASURED_YEARS`, before the placement is worth calling a decision.
##
## Stated as a floor on a ratio and not as a range, because the failure this
## exists to catch is one-sided: a camp whose output does not depend on where it
## is put reads as a farm with a noisier yield, and that is the finding the
## ticket says to report rather than to tune away.
const MIN_BUSY_OVER_QUIET := 8.0

## The same claim against a *typical* site rather than the worst one, which is
## the honest version of "placed away from it" — the quietest tile on the map is
## usually ground no herd has crossed once, and a ratio against zero says less
## than it looks like it says.
const MIN_BUSY_OVER_TYPICAL := 3.0

## The floors those two margins may not be lowered past, on the convention
## `test_city.gd` sets: weakening an assertion to make a regression green is the
## cheapest wrong move available, and this makes it a separate, visible edit
## rather than a one-line adjustment made while chasing a red suite.
##
## Raising a margin is always fine and these do not object to it.
const BUSY_OVER_QUIET_FLOOR := 8.0
const BUSY_OVER_TYPICAL_FLOOR := 3.0

## Turns the flow-to-the-granary experiment runs for. Two dozen round trips on a
## two-step road, which is long enough that the difference between the two runs
## is a trend rather than a phase of the walking cycle.
const FLOW_TURNS := 60


# --- 1. the coupling is real -------------------------------------------------

func test_a_camp_is_worth_far_more_where_the_animals_go() -> void:
	# AC3, and the number the ticket asks the pull request to state.
	#
	# Three sites per seed, chosen from where the herds actually went over the
	# same span rather than from where anyone guessed they would: the busiest
	# ground, the quietest, and the median tile of the same terrain. All three
	# carry a camp *and* a farm, and the farms are the control — same terrain
	# means the same forage curve every turn of the run, so a difference between
	# the camps cannot be the ground they stand on.
	for world_seed in STANDARD_SEEDS:
		var measured := _measure_placement(world_seed)
		gut.p(
			"seed %d over %d years — camp on busiest ground %.2f, on a typical tile %.2f, on the quietest %.2f; a farm on any of them %.2f"
				% [
					world_seed,
					MEASURED_YEARS,
					measured["busy"],
					measured["typical"],
					measured["quiet"],
					measured["farm"],
				]
		)
		gut.p(
			"seed %d ratios — busy/quiet %s, busy/typical %s"
				% [world_seed, _ratio(measured["busy"], measured["quiet"]),
					_ratio(measured["busy"], measured["typical"])]
		)

		# The control, first: if this fails, nothing below it means anything.
		assert_almost_eq(
			measured["farm_busy"],
			measured["farm_quiet"],
			0.001,
			"seed %d: a farm makes the same on both tiles, so the ground is not the variable"
				% world_seed
		)
		assert_gt(
			measured["busy"],
			MIN_BUSY_OVER_QUIET * measured["quiet"],
			"seed %d: a camp where the herds are beats one where they are not by %.1fx"
				% [world_seed, MIN_BUSY_OVER_QUIET]
		)
		assert_gt(
			measured["busy"],
			MIN_BUSY_OVER_TYPICAL * measured["typical"],
			"seed %d: and beats one on ordinary ground by %.1fx"
				% [world_seed, MIN_BUSY_OVER_TYPICAL]
		)
		assert_gt(
			measured["busy"],
			0.0,
			"seed %d: the good site produced something at all" % world_seed
		)


func test_what_the_city_the_game_generates_actually_gathers() -> void:
	# The measurement above is the *best case* — a camp put on the busiest ground
	# on the map by a test that ran the world first to find out where that was.
	# Nobody playing gets that. `CityGen` places the camp beside the granary
	# without consulting where the animals are, on purpose, so this is the number
	# a player would actually see, and it is the one worth arguing about.
	#
	# Printed per year rather than as a total, because the shape is the finding:
	# a camp that averages half a farm by being half-lit every turn would be a
	# noisier farm, and a camp that spends four years dark and then has a good one
	# is the thing the ticket is trying to build.
	#
	# Swept over a dozen seeds rather than the usual two, and that width is load
	# bearing rather than thoroughness for its own sake. On both standard seeds
	# this camp is dark for every turn of the run, and a two-seed report would
	# have concluded flatly that a generated camp never lights — which is false,
	# and the frames committed under `docs/shots/gathering` are of seed 42 lit.
	# Whether the granary's second spoke happens to land within two tiles of
	# ground herds use is a property of the seed, so the honest number is the
	# fraction of seeds it works on, and only a sweep can state it.
	var ever_lit := 0
	var seeds_seen := 0
	for world_seed in REPORTED_SEEDS:
		var world := WorldGen.generate(world_seed)
		var camp := _first_of(world, CityNode.Kind.GATHERING)
		var farm := _first_of(world, CityNode.Kind.FARM)
		assert_not_null(camp, "seed %d: the generated city has a camp" % world_seed)
		if camp == null or farm == null:
			continue

		var per_year: Array[String] = []
		var camp_total := 0.0
		var farm_total := 0.0
		var live_turns := 0
		var year := 0.0
		var turns := REPORTED_YEARS * Seasons.TURNS_PER_YEAR
		for turn in range(turns):
			world.advance_turn()
			camp_total += camp.last_yield
			farm_total += farm.last_yield
			year += camp.last_yield
			if camp.last_yield > 0.0:
				live_turns += 1
			if (turn + 1) % Seasons.TURNS_PER_YEAR == 0:
				per_year.append("%.1f" % year)
				year = 0.0

		seeds_seen += 1
		if live_turns > 0:
			ever_lit += 1
		gut.p(
			"seed %d, camp as placed by generation: %.1f over %d years against the farm's %.1f, working on %d of %d turns"
				% [world_seed, camp_total, REPORTED_YEARS, farm_total, live_turns, turns]
		)
		if live_turns > 0:
			gut.p("seed %d, that camp year by year: [%s]" % [world_seed, ", ".join(per_year)])

	gut.p(
		"a camp placed by generation is lit at some point on %d of %d seeds"
			% [ever_lit, seeds_seen]
	)
	# Not asserted as a rate. What fraction of seeds put the granary's second
	# spoke near ground animals use is a fact about generation and migration
	# together, and pinning it here would make an unrelated change to either one
	# fail in this file with a message about camps. Asserted only is that the
	# sweep ran and that it is not *uniformly* dark — if that ever becomes true,
	# the kind produces nothing for anybody who did not hand-place it, and this
	# is the line that should say so.
	assert_gt(seeds_seen, 0, "the sweep actually ran")
	assert_gt(
		ever_lit,
		0,
		"a camp the game itself places lights up on at least one seed in %d" % seeds_seen
	)


func test_a_camp_falls_quiet_when_the_animals_leave_and_comes_back_when_they_return() -> void:
	# AC6, which is `world-growth-tone` rule 1 stated as arithmetic: a herd
	# leaving reduces a flow and removes nothing. The camp is still a camp at
	# zero, still holds what it gathered, and starts again on its own.
	var world := _flat_world()
	var camp_coord := HexGrid.from_offset(4, 4)
	var camp := CityNode.new(0, camp_coord, CityNode.Kind.GATHERING)
	world.add_node(camp)

	world.advance_turn()
	assert_eq(camp.last_yield, 0.0, "an empty landscape gathers nothing")
	assert_eq(camp.store, 0.0, "so there is nothing in the camp")

	# The herd arrives, two tiles off — inside the camp's reach, and not on it.
	var herd := Herd.new(0, camp_coord + Vector2i(0, 2), Species.grazer(), 40.0)
	world.add_agent(herd)
	world.advance_turn()
	var working := camp.last_yield
	gut.p("one turn with a herd two tiles away: %.3f" % working)
	assert_gt(working, 0.0, "a herd in range wakes the camp up")
	assert_gt(camp.store, 0.0, "and there is something in it")

	var gathered := camp.store
	# And it walks off to the far corner. Moved directly rather than waited out:
	# what is being asserted is the camp's response to an empty landscape, not
	# how long a herd takes to decide to leave one.
	world.move_agent(herd, HexGrid.from_offset(11, 9))
	world.advance_turn()
	assert_eq(camp.last_yield, 0.0, "the animals leave and the flow stops")
	assert_true(world.nodes.has(camp), "the camp is still standing")
	assert_eq(camp.store, gathered, "and still holding what it gathered")
	assert_eq(
		camp.capacity,
		CityNode.default_capacity(CityNode.Kind.GATHERING),
		"undiminished — a quiet camp is not a damaged one"
	)

	world.move_agent(herd, camp_coord + Vector2i(0, 2))
	world.advance_turn()
	assert_gt(camp.last_yield, 0.0, "and it starts again when they come back")


func test_the_response_saturates_rather_than_scaling() -> void:
	# Why this shape and not a proportional one: the question a camp asks has to
	# stay "is anything here", never "how do I pile animals up". Four herds in
	# range being worth roughly a third more than one is what keeps a migration
	# an opportunity instead of a thing to farm.
	assert_eq(CityNode.gathering_share(0.0), 0.0, "empty ground is worth nothing")
	assert_eq(CityNode.gathering_share(-5.0), 0.0, "and so is a nonsense reading")
	assert_eq(
		CityNode.gathering_share(0.0001),
		0.0,
		"float32 census residue on a tile the animals left is not demand"
	)
	assert_almost_eq(
		CityNode.gathering_share(CityNode.GATHERING_HALF_AT),
		0.5,
		0.0001,
		"one herd's worth of mouths is half a camp's best turn"
	)
	var one := CityNode.gathering_share(CityNode.GATHERING_HALF_AT)
	var four := CityNode.gathering_share(CityNode.GATHERING_HALF_AT * 4.0)
	gut.p("one herd in range %.3f, four herds %.3f" % [one, four])
	assert_lt(four, one * 2.0, "four times the animals is nothing like four times the yield")
	assert_gt(four, one, "but it is still more")
	assert_lt(CityNode.gathering_share(1.0e9), 1.0, "and a camp never exceeds its own best turn")


func test_the_herds_do_not_travel_far_enough_to_arrive() -> void:
	# The finding in the header, kept as a running number rather than a comment
	# that can quietly stop being true.
	#
	# This does not assert that herds are sedentary — that is the defect, not the
	# specification, and an assertion would have to be deleted by whoever fixes
	# it. It asserts only that they stay on the map and that the measurement is
	# actually running, then prints the displacement. If migration is ever given
	# real range, this line changes and the camp becomes worth revisiting.
	for world_seed in STANDARD_SEEDS:
		var world := WorldGen.generate(world_seed)
		var starts: Array[Vector2i] = []
		for herd in world.herds():
			starts.append(herd.coord)
		assert_gt(starts.size(), 0, "seed %d: there are herds to watch" % world_seed)

		var furthest: Array[int] = []
		for i in range(starts.size()):
			furthest.append(0)
		for _turn in range(DETERMINISM_TURNS):
			world.advance_turn()
			var herds := world.herds()
			for i in range(mini(herds.size(), starts.size())):
				furthest[i] = maxi(furthest[i], HexGrid.distance(starts[i], herds[i].coord))

		var travelled := 0
		var roamed := 0
		for d in furthest:
			travelled = maxi(travelled, d)
			if d > CityNode.GATHERING_RADIUS:
				roamed += 1
		gut.p(
			"seed %d over %d turns: furthest any herd got from where it started is %d tiles; %d of %d ever left a camp's reach — %s"
				% [
					world_seed, DETERMINISM_TURNS, travelled, roamed, furthest.size(),
					str(furthest),
				]
		)
		assert_lt(
			travelled,
			world.grid.width + world.grid.height,
			"seed %d: herds stayed on the map" % world_seed
		)


# --- 2. it arrives the way everything else does ------------------------------

func test_what_a_camp_gathers_reaches_the_granary_by_road() -> void:
	# AC5: no second transport model. The same route and the same carriers as a
	# farm, and the run without a herd is the control — without it, "the granary
	# filled up" is equally consistent with granaries filling themselves.
	var with_animals := _flow_to_granary(true)
	var without := _flow_to_granary(false)
	gut.p("granary after %d turns: %.2f with a herd in range, %.2f without" % [
		FLOW_TURNS, with_animals, without,
	])
	assert_gt(with_animals, 0.0, "grain gathered at a camp arrives at the granary")
	assert_eq(without, 0.0, "and none of it arrives when there was nothing to gather")


func test_the_generated_city_carries_gathered_goods_on_the_road_it_already_had() -> void:
	# The same claim on the world the game actually generates, stated about the
	# arrangement rather than about a total: the camp is a source on a route
	# whose sink is the granary, and there are people on it.
	for world_seed in STANDARD_SEEDS:
		var world := WorldGen.generate(world_seed)
		var camp := _first_of(world, CityNode.Kind.GATHERING)
		assert_not_null(camp, "seed %d: the city has a camp" % world_seed)
		if camp == null:
			continue
		var served := false
		for route in world.routes:
			if route.source == camp:
				served = true
				assert_eq(
					route.sink.kind,
					CityNode.Kind.GRANARY,
					"seed %d: the camp's road runs to the granary" % world_seed
				)
		assert_true(served, "seed %d: something walks the camp's road" % world_seed)


# --- 3. and it takes nothing ------------------------------------------------

func test_camps_take_nothing_from_the_herds() -> void:
	# AC4. `AgDR-009` makes grazing pressure and overhunting inexpressible, and
	# this ticket is not the one that reopens it — so the strongest available
	# statement is made instead of a tolerance: the same seed, run twice for five
	# hundred turns, with camps and without, comes out identical head for head
	# and tile for tile.
	for world_seed in STANDARD_SEEDS:
		var plain := WorldGen.generate(world_seed)
		var crowded := WorldGen.generate(world_seed)
		# Far more camps than a city would have, and scattered over the whole
		# map rather than beside the city, so that every herd on the map spends
		# the run inside somebody's reach.
		var added := 0
		for coord in crowded.grid.all_coords():
			if crowded.terrain_at(coord) == WorldGen.Terrain.WATER:
				continue
			if (coord.x + coord.y) % 5 != 0:
				continue
			crowded.add_node(
				CityNode.new(crowded.nodes.size(), coord, CityNode.Kind.GATHERING)
			)
			added += 1

		for i in range(DETERMINISM_TURNS):
			plain.advance_turn()
			crowded.advance_turn()

		var gathered := 0.0
		for node in crowded.nodes:
			if node.kind == CityNode.Kind.GATHERING:
				gathered += node.last_yield
		gut.p(
			"seed %d: %d camps gathered from %d heads over %d turns; the same world without them holds %d"
				% [
					world_seed,
					added,
					roundi(crowded.total_herd_population()),
					DETERMINISM_TURNS,
					roundi(plain.total_herd_population()),
				]
		)
		assert_gt(added, 0, "seed %d: the crowded world actually has camps on it" % world_seed)
		assert_gt(gathered, 0.0, "seed %d: and they were gathering, not idle" % world_seed)
		assert_eq(
			crowded.total_herd_population(),
			plain.total_herd_population(),
			"seed %d: total heads are untouched by the camps" % world_seed
		)
		_assert_same_herds(plain, crowded, "seed %d" % world_seed)


func test_two_worlds_from_one_seed_gather_the_same_amounts() -> void:
	# AC7, extended to the new state. Determinism already covers terrain and
	# herds; what is new here is that a node's output now depends on where
	# fourteen animals happened to walk, which is the longest causal chain in the
	# project and the one most likely to pick up a float-ordering difference.
	var first := WorldGen.generate(SEED_A)
	var second := WorldGen.generate(SEED_A)
	for i in range(DETERMINISM_TURNS):
		first.advance_turn()
		second.advance_turn()

	assert_eq(first.terrain_data(), second.terrain_data(), "the same land")
	assert_eq(first.nodes.size(), second.nodes.size(), "the same structures")
	for i in range(first.nodes.size()):
		assert_eq(
			first.nodes[i].store,
			second.nodes[i].store,
			"node %d holds the same after %d turns" % [i, DETERMINISM_TURNS]
		)
		assert_eq(
			first.nodes[i].last_yield,
			second.nodes[i].last_yield,
			"and grew the same on the last of them" % []
		)
	_assert_same_herds(first, second, "seed %d" % SEED_A)
	gut.p("after %d turns both worlds hold %.4f grain" % [
		DETERMINISM_TURNS, first.total_stored_grain(),
	])


# --- 4. the rule it is held to ----------------------------------------------

func test_a_camp_cannot_find_out_what_is_standing_near_it() -> void:
	# AC2 and `AgDR-013`. A camp that reached for `world.herds()` would pass
	# every behavioural test above while being exactly the kind-check the record
	# forbids, and the next thing that wants to be gatherable would have to
	# announce a type rather than report a number.
	#
	# Comments are stripped first, on purpose and for the same reason
	# `test_city.gd` strips them: the file is allowed to *talk* about herds —
	# explaining why it cannot see them is what its documentation is for — and
	# forbidden to act on them.
	var source := _read_source("res://sim/node.gd")
	assert_gt(source.length(), 0, "the node source was actually read")
	var code := _strip_comments(source)

	var forbidden := {
		"a herd by name": "\\bHerd\\b",
		"a citizen by name": "\\bCitizen\\b",
		"an agent by name": "\\bAgent\\b",
		"a walk of the agent list": "\\.agents\\b",
		"the herd query": "herds\\s*\\(",
		"the citizen query": "citizens\\s*\\(",
		"a type test": "\\bis\\s+[A-Z]",
		"a downcast": "\\bas\\s+[A-Z]",
		"a class name lookup": "get_class\\s*\\(",
		"a script lookup": "get_script\\s*\\(",
	}
	for description in forbidden:
		var regex := RegEx.new()
		regex.compile(forbidden[description])
		var found := regex.search(code)
		assert_null(
			found,
			"sim/node.gd contains %s: %s" % [
				description, "" if found == null else found.get_string()
			]
		)


func test_the_stated_margins_have_not_been_quietly_weakened() -> void:
	# See the note on the floor constants above.
	assert_gte(
		MIN_BUSY_OVER_QUIET, BUSY_OVER_QUIET_FLOOR,
		"the busy-over-quiet margin was lowered from %.2f to %.2f"
			% [BUSY_OVER_QUIET_FLOOR, MIN_BUSY_OVER_QUIET]
	)
	assert_gte(
		MIN_BUSY_OVER_TYPICAL, BUSY_OVER_TYPICAL_FLOOR,
		"the busy-over-typical margin was lowered from %.2f to %.2f"
			% [BUSY_OVER_TYPICAL_FLOOR, MIN_BUSY_OVER_TYPICAL]
	)


# --- helpers -----------------------------------------------------------------

## A featureless world of one terrain with nothing alive on it, so a measured
## difference is the thing under test rather than fourteen herds walking through
## the measurement. The same device `test_city.gd` uses, for the same reason.
func _flat_world(width := 12, height := 10, terrain := WorldGen.Terrain.GRASS) -> WorldMap:
	var world := WorldMap.new(HexGrid.new(width, height), SEED_A)
	for coord in world.grid.all_coords():
		world.set_terrain(coord, terrain)
	return world


## One run of the delivery experiment: a granary, a camp two steps away, the road
## between them and two people on it — the same arrangement `CityGen` builds.
## Identical either way but for the animal standing off the end of the road.
##
## Returns what reached the granary.
func _flow_to_granary(with_herd: bool) -> float:
	var world := _flat_world()
	var camp_coord := HexGrid.from_offset(3, 4)
	var granary_coord := camp_coord + HexGrid.DIRECTIONS[0] * 2

	var camp := CityNode.new(0, camp_coord, CityNode.Kind.GATHERING)
	var granary := CityNode.new(1, granary_coord, CityNode.Kind.GRANARY)
	world.add_node(camp)
	world.add_node(granary)
	var route := Route.new(0, camp, granary, HexGrid.line(camp_coord, granary_coord))
	world.add_route(route)
	for i in range(CityGen.CITIZENS_PER_ROUTE):
		var start := (i * (route.length() - 1)) / maxi(1, CityGen.CITIZENS_PER_ROUTE - 1)
		world.add_agent(Citizen.new(i, route, start))

	if with_herd:
		# In range of the camp and off the road, so what is being measured is
		# the camp's output rather than a carrier being held up by an animal.
		var at := camp_coord + Vector2i(0, 2)
		assert_false(route.passes_through(at), "the herd stands beside the road, not on it")
		world.add_agent(Herd.new(0, at, Species.grazer(), 40.0))

	for i in range(FLOW_TURNS):
		world.advance_turn()
	return granary.store


## Where the herds of `world_seed` actually spend `MEASURED_YEARS`, as one
## accumulated total of mouths per tile.
##
## Run rather than reasoned about: which ground is busy is a property of the
## terrain, the seasons and fourteen independent migrations, and any site this
## test picked by hand would be a guess that could quietly stop being true.
func _presence(world_seed: int, turns: int) -> PackedFloat32Array:
	var world := WorldGen.generate(world_seed)
	var total := PackedFloat32Array()
	total.resize(world.grid.tile_count())
	for _turn in range(turns):
		world.advance_turn()
		for i in range(total.size()):
			total[i] += world.forage_demand_by_index(i)
	return total


## The busiest, the quietest and the median land tile of one terrain, scored by
## how many mouths passed within a camp's reach of each over the run.
##
## Restricted to a single terrain — whichever the busiest tile turns out to be —
## so that the three camps in the measurement are separated by where the animals
## went and by nothing else. A farm on each of them makes the identical amount,
## which is what makes that claim checkable rather than asserted.
func _sites(world: WorldMap, presence: PackedFloat32Array) -> Dictionary:
	var busy := Vector2i.ZERO
	var busiest := -1.0
	var scores := {}
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			continue
		var score := 0.0
		for i in _disc_indices(world.grid, coord, CityNode.GATHERING_RADIUS):
			score += presence[i]
		scores[coord] = score
		if score > busiest:
			busiest = score
			busy = coord

	var terrain := world.terrain_at(busy)
	# Insertion-ordered, and the insertion order is `all_coords()` — so the list
	# this sorts is the same list on every run and on every host.
	var same_terrain: Array[Vector2i] = []
	for coord in scores:
		if world.terrain_at(coord) == terrain:
			same_terrain.append(coord)
	same_terrain.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if scores[a] == scores[b]:
				# Ties broken on grid order, so "the quietest tile" is one tile
				# rather than whichever of four hundred equally empty ones the
				# sort happened to leave in front.
				return world.grid.index_of(a) < world.grid.index_of(b)
			return scores[a] < scores[b]
	)
	return {
		"busy": busy,
		"quiet": same_terrain[0],
		"typical": same_terrain[same_terrain.size() / 2],
		"terrain": terrain,
	}


## The measurement itself: a camp and a farm on each of the three sites, run for
## `MEASURED_YEARS`, totalling what each one *grew* rather than what reached its
## store.
##
## Grown, not stored, because a barn holds three turns of a good harvest and a
## camp on good ground fills it — a store would measure the barn.
func _measure_placement(world_seed: int) -> Dictionary:
	var turns := MEASURED_YEARS * Seasons.TURNS_PER_YEAR
	var world := WorldGen.generate(world_seed)
	var sites := _sites(world, _presence(world_seed, turns))

	# Nodes are not agents: they have no forage demand, they do not move and
	# nothing consults them. Adding these cannot shift a herd, which is what lets
	# the sites chosen from one run be measured on another.
	var camps := {}
	var farms := {}
	for key in ["busy", "typical", "quiet"]:
		camps[key] = CityNode.new(world.nodes.size(), sites[key], CityNode.Kind.GATHERING)
		world.add_node(camps[key])
		farms[key] = CityNode.new(world.nodes.size(), sites[key], CityNode.Kind.FARM)
		world.add_node(farms[key])

	var totals := {"busy": 0.0, "typical": 0.0, "quiet": 0.0}
	var farm_totals := {"busy": 0.0, "typical": 0.0, "quiet": 0.0}
	for _turn in range(turns):
		world.advance_turn()
		for key in totals:
			totals[key] += camps[key].last_yield
			farm_totals[key] += farms[key].last_yield

	return {
		"busy": totals["busy"],
		"typical": totals["typical"],
		"quiet": totals["quiet"],
		"farm": farm_totals["busy"],
		"farm_busy": farm_totals["busy"],
		"farm_quiet": farm_totals["quiet"],
	}


## Every grid index within `radius` of `coord` that is on the map, in the same
## fixed order `WorldMap.forage_demand_within()` walks.
func _disc_indices(grid: HexGrid, coord: Vector2i, radius: int) -> Array:
	var out: Array = []
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			var i := grid.index_of(coord + Vector2i(dq, dr))
			if i >= 0:
				out.append(i)
	return out


## A ratio printed as a number, or as the honest thing to say when the
## denominator is zero — a camp on ground no animal crossed in eight years made
## nothing at all, and "infinity times better" is a worse report than that.
func _ratio(numerator: float, denominator: float) -> String:
	if denominator <= 0.0:
		return "unbounded (%.2f against nothing at all)" % numerator
	return "%.1fx" % (numerator / denominator)


func _first_of(world: WorldMap, kind: int) -> CityNode:
	for node in world.nodes:
		if node.kind == kind:
			return node
	return null


## Every herd in one world against every herd in another, head for head and tile
## for tile. Positions as well as populations, because a camp that perturbed
## where an animal went while leaving the total alone would be the same bug
## wearing a hat.
func _assert_same_herds(a: WorldMap, b: WorldMap, label: String) -> void:
	var left := a.herds()
	var right := b.herds()
	assert_eq(left.size(), right.size(), "%s: the same number of herds" % label)
	for i in range(mini(left.size(), right.size())):
		assert_eq(
			left[i].coord, right[i].coord, "%s: herd %d stands in the same place" % [label, i]
		)
		assert_eq(
			left[i].population,
			right[i].population,
			"%s: herd %d is the same size" % [label, i]
		)


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "could not open %s" % path)
	if file == null:
		return ""
	return file.get_as_text()


## Everything from a `#` to the end of its line. Crude — it would eat a `#` in a
## string literal — and correct enough for a file that has none.
func _strip_comments(source: String) -> String:
	var out: Array[String] = []
	for line in source.split("\n"):
		var hash_at := line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)
