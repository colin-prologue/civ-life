extends GutTest
## Properties of the ruin filter.
##
## These are asserted on returned arrays rather than on a picture, so they run
## on a host with no rendering context — the same reason test_diorama_compose.gd
## checks data instead of frames.

const SEED := 4242
const RUNGS := [1.0, 0.75, 0.5, 0.25, 0.05]


func _styles() -> Dictionary:
	return {"residential": DioramaStyles.residential(),
			"hero_arch": DioramaStyles.hero_arch(),
			"civic": DioramaStyles.civic(),
			"stepped": DioramaStyles.stepped()}


func _needs(parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		out.append(p["need"])
	return out


func test_survivors_nest_as_condition_falls() -> void:
	# AC2, ordered loss. Filtering on a fixed per-part threshold is monotone by
	# construction, so this cannot fail without the filter having grown a
	# second rule. Swept over every style and rung pair to keep it honest.
	for style_name: String in _styles():
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			for i in range(RUNGS.size() - 1):
				var higher := DioramaCondition.filter(parts, RUNGS[i])
				var lower := DioramaCondition.filter(parts, RUNGS[i + 1])
				for p: Dictionary in lower:
					assert_true(higher.has(p),
							"%s id %d: a part survived %f but not %f"
							% [style_name, id, RUNGS[i + 1], RUNGS[i]])


func test_condition_zero_means_gone() -> void:
	var parts := DioramaCompose.build(DioramaStyles.civic(), SEED, 1)
	assert_eq(DioramaCondition.filter(parts, 0.0).size(), 0,
			"zero should mean removed, not ruined")
	assert_eq(DioramaCondition.filter(parts, -1.0).size(), 0,
			"a negative condition should also be empty")


func test_a_ruin_is_never_a_bare_footprint() -> void:
	# AC4 and AC5. A single slab is a foundation, not a ruin — the intent asks
	# for a footprint AND a surviving arch or wall.
	for style_name: String in _styles():
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			var distinct := {}
			for n in _needs(parts):
				distinct[n] = true
			var got := DioramaCondition.filter(parts, 0.01)
			assert_gt(got.size(), 0,
					"%s id %d: a positive condition returned nothing"
					% [style_name, id])
			if distinct.size() > 1:
				assert_gt(got.size(), 1,
						"%s id %d: bottomed out at a single part"
						% [style_name, id])


func test_full_condition_keeps_everything() -> void:
	for style_name: String in _styles():
		var parts := DioramaCompose.build(_styles()[style_name], SEED, 2)
		assert_eq(DioramaCondition.filter(parts, 1.0).size(), parts.size(),
				"%s lost a part at full condition" % style_name)


func _arch() -> Dictionary:
	# The voussoirs carry a distinct role purely so the test can identify them
	# structurally. Grouping survivors by their own `need` instead would be
	# true of any threshold filter, and so could never fail.
	return {"stack": {"name": "a", "children": [
		{"mass": {"name": "plinth", "kind": "box", "w": 5.0, "d": 2.0,
				"h": 0.4, "role": "plaster"}},
		{"ring": {"name": "span", "radius": 1.5, "from": 0.0, "to": PI,
				"count": 7,
				"of": {"mass": {"name": "vs", "kind": "box", "w": 0.4,
						"d": 0.6, "role": "brass"}}}}]}}


func test_a_ring_survives_or_falls_whole() -> void:
	# The property the whole assemblies design exists for: an arch is not seven
	# independent stones. Remove one voussoir and the arc collapses, so no
	# condition may leave a partial arc.
	for id in range(12):
		var parts := DioramaCompose.build(_arch(), SEED, id)
		assert_eq(parts.size(), 8, "id %d: fixture should emit plinth + 7" % id)
		for c in [0.0, 0.05, 0.2, 0.4, 0.6, 0.8, 1.0]:
			var standing := 0
			for p: Dictionary in DioramaCondition.filter(parts, c):
				if p["role"] == "brass":
					standing += 1
			assert_true(standing == 0 or standing == 7,
					"id %d at condition %f: %d of 7 voussoirs survived"
					% [id, c, standing])


func test_the_empty_building_filters_to_nothing() -> void:
	assert_eq(DioramaCondition.filter([], 0.5).size(), 0,
			"an empty part list should filter to an empty result")


func test_a_building_with_levels_to_spare_actually_loses_parts() -> void:
	# Every other test here asserts that survivors are PRESENT, so all six pass
	# with `_fragment_floor` mutated to return the maximum `need` — which clamps
	# every condition up to the top of the band and keeps the whole building at
	# every rung. Nothing was asserting that a ruin is ever missing anything.
	#
	# Guarded on three or more distinct needs, not asserted unconditionally: at
	# two levels the standing-fragment floor legitimately clamps to the higher
	# one and the building survives whole, so an unguarded version would be
	# asserting something the design does not promise. At three the floor is the
	# SECOND smallest, which leaves at least one strictly greater need above it
	# — so something must be gone, and that is entailed rather than lucky.
	for style_name: String in _styles():
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			var distinct := {}
			for n in _needs(parts):
				distinct[n] = true
			if distinct.size() < 3:
				continue
			var got := DioramaCondition.filter(parts, 0.05)
			assert_lt(got.size(), parts.size(),
					"%s id %d: %d distinct needs and yet nothing was lost at 0.05"
					% [style_name, id, distinct.size()])


func test_every_style_has_a_ladder_to_decay_down() -> void:
	# The census that motivated this design, standing as a test. Under the old
	# height-band tags residential emitted 0% `base` and stepped 0% `upper`,
	# which meant neither had an ORDER to lose things in — they went from whole
	# to gone. Asserting "has a part at its minimum need" would be vacuous, so
	# assert spread instead.
	for style_name: String in _styles():
		var levels := {}
		var lo := INF
		var hi := -INF
		for id in range(24):
			for n in _needs(DioramaCompose.build(_styles()[style_name], SEED, id)):
				levels[snappedf(n, 0.001)] = true
				lo = minf(lo, n)
				hi = maxf(hi, n)
		assert_gt(levels.size(), 2,
				"%s has %d distinct need levels over 24 ids — too few to decay"
				% [style_name, levels.size()])
		assert_gt(hi - lo, 0.2,
				"%s spans only %f in need; its parts all fall together"
				% [style_name, hi - lo])
		# Both assertions above aggregate over 24 ids, and that hides the exact
		# failure this test is named for. Give every part of a building ONE need
		# drawn from the full band and the `levels` set still fills with 24
		# distinct values across the ids, and the spread is still wide — while
		# every individual building goes from whole straight to gone. A ladder
		# has to exist WITHIN a building, so assert it there too.
		#
		# `mini(parts, 3)` rather than a flat 3: residential legitimately
		# samples down to a single unit, and a two-part building has two levels
		# and no third to give. Three is where condition.gd's standing-fragment
		# floor starts leaving something above it, so it is the point at which
		# demanding a ladder is meaningful rather than lucky.
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			var distinct := {}
			for n in _needs(parts):
				distinct[snappedf(n, 0.000001)] = true
			assert_gte(distinct.size(), mini(parts.size(), 3),
					"%s id %d: %d parts collapsed onto %d distinct need(s)"
					% [style_name, id, parts.size(), distinct.size()])


func test_every_style_loses_something_before_it_loses_everything() -> void:
	# The failure mode stepped had: no ordering, so no rung of the ladder shows
	# a partial building. At least one of the intent's five rungs must leave a
	# style strictly between whole and its floor. This is a DIFFERENT property
	# from test_a_building_with_levels_to_spare_actually_loses_parts above: that
	# test only asserts something is LOST by rung 0.05 (which a collapse
	# straight to zero parts would also satisfy), restricted to buildings with
	# >=3 distinct needs. This one requires a rung where the survivor count is
	# strictly between 0 and the full count — an actual partial ruin — checked
	# across every rung and with no distinct-needs floor, so it also covers the
	# two-distinct-need residential ids that the other test skips.
	for style_name: String in _styles():
		var partial := false
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			for rung in RUNGS:
				var got := DioramaCondition.filter(parts, rung).size()
				if got > 0 and got < parts.size():
					partial = true
		assert_true(partial,
				"%s is never partially ruined at any rung — it goes from whole to gone"
				% style_name)
