extends GutTest
## The MASSING half of a culture: what a people's way of building modulates, and
## what it must leave alone.
##
## A sibling of test_diorama_cultures.gd rather than more cases inside it. That
## file guards the colour half — the closed role set, the value rule, and the
## fact that a palette moves nothing but colour. This one guards the half that
## does move geometry, and the two halves fail for opposite reasons: a palette
## bug paints the right building wrong, a massing bug builds the wrong building.
##
## The property everything here rests on is stated once and asserted several
## ways: culture moves the RANGE a value is sampled from and never the draw.
## Culture must not reach channel(). If it ever does, the same building id stops
## being the same building from one culture to the next, and every claim the
## culture sheet makes about "one building, three peoples" quietly stops being
## true while the frames still look fine.

const SEED := 4242


## Every multiplier at 1.0 — the identity culture. Any test that uses this is
## asserting that modulation with no effect really has no effect.
##
## Built here rather than borrowed from SUNLIT_MASSING, whose numbers happen to
## be the same today: these tests mutate their culture, and a shipped constant
## is not theirs to mutate.
func _plain() -> Dictionary:
	return {"name": "plain", "verticality": 1.0, "thickness": 1.0,
			"setback": 1.0, "variance": 1.0, "crown": "hip"}


func _box(name: String, w: Variant, d: Variant, h: Variant) -> Dictionary:
	return {"mass": {"name": name, "kind": "box", "w": w, "d": d, "h": h,
			"role": "structure"}}


# ------------------------------------------------------------- modulation

func test_the_identity_culture_changes_nothing() -> void:
	var c := _plain()
	assert_eq(DioramaCultures.modulate(0.6, c, "h"), 0.6,
			"a scalar changed under an identity culture")
	var r: Array = DioramaCultures.modulate([0.6, 1.3], c, "h")
	assert_almost_eq(r[0], 0.6, 1e-6, "range lo moved under identity")
	assert_almost_eq(r[1], 1.3, 1e-6, "range hi moved under identity")


func test_scale_moves_a_range_without_changing_its_relative_width() -> void:
	var c := _plain()
	c["verticality"] = 2.0
	var r: Array = DioramaCultures.modulate([0.6, 1.4], c, "h")
	assert_almost_eq(r[0], 1.2, 1e-6, "lo should scale")
	assert_almost_eq(r[1], 2.8, 1e-6, "hi should scale")


func test_variance_widens_around_the_midpoint() -> void:
	# The midpoint must not move — variance is about how uniform a people's
	# buildings are, not about how big they are. Those are separate levers and
	# conflating them would make one unusable.
	var c := _plain()
	c["variance"] = 2.0
	var r: Array = DioramaCultures.modulate([0.6, 1.4], c, "h")
	assert_almost_eq((r[0] + r[1]) * 0.5, 1.0, 1e-6, "midpoint moved")
	assert_almost_eq(r[1] - r[0], 1.6, 1e-6, "width should double")


func test_variance_below_one_narrows_but_never_inverts() -> void:
	var c := _plain()
	c["variance"] = 0.0
	var r: Array = DioramaCultures.modulate([0.6, 1.4], c, "h")
	assert_almost_eq(r[0], 1.0, 1e-6, "a zero variance should collapse to mid")
	assert_true(r[0] <= r[1], "modulation inverted a range")


func test_only_the_stated_purposes_are_modulated() -> void:
	# Scaling `oversize` or `taper` would compound with the mass they modify,
	# and scaling `radius` would break an arch's fit against its own piers.
	var c := _plain()
	c["verticality"] = 3.0
	c["thickness"] = 3.0
	c["setback"] = 3.0
	for purpose in ["oversize", "taper", "radius", "from", "to", "advance",
			"gap", "count"]:
		assert_eq(DioramaCultures.modulate([1.0, 2.0], c, purpose), [1.0, 2.0],
				"'%s' should not be modulated by culture" % purpose)


func test_each_purpose_takes_its_own_multiplier() -> void:
	var c := _plain()
	c["verticality"] = 2.0
	c["thickness"] = 3.0
	c["setback"] = 4.0
	assert_eq(DioramaCultures.modulate(1.0, c, "h"), 2.0, "h takes verticality")
	assert_eq(DioramaCultures.modulate(1.0, c, "w"), 3.0, "w takes thickness")
	assert_eq(DioramaCultures.modulate(1.0, c, "d"), 3.0, "d takes thickness")
	assert_eq(DioramaCultures.modulate(1.0, c, "setback"), 4.0,
			"setback takes setback")


func test_null_stays_null() -> void:
	assert_eq(DioramaCultures.modulate(null, _plain(), "h"), null,
			"an absent spec must stay absent so the caller's default applies")


func test_modulate_never_inverts_a_range_for_any_nonnegative_scale_and_variance() -> void:
	# The property this test exists to protect: a bad multiplier must not walk
	# past sample()'s lo <= hi guard any more than a reversed literal range
	# would. That property is unreachable through sample()'s own guard — no
	# shipped culture can produce a negative variance, and GDScript's assert()
	# aborts the function rather than letting GUT observe a failure — so it is
	# checked here, directly against modulate(), at the layer where a bad
	# culture's numbers are actually the thing under test. A negative variance
	# is excluded: modulate() asserts against it as an authoring error, not a
	# range this sweep is meant to reach.
	var c := _plain()
	var ranges := [[1.0, 2.0], [0.6, 1.4], [-3.0, -1.0], [0.0, 0.0], [5.0, 5.0]]
	var scales := [0.0, 0.1, 1.0, 1.7, 3.0]
	var variances := [0.0, 0.1, 1.0, 1.7, 3.0]
	for spec in ranges:
		for scale in scales:
			for variance in variances:
				c["verticality"] = scale
				c["variance"] = variance
				var r: Array = DioramaCultures.modulate(spec, c, "h")
				assert_true(r[0] <= r[1],
						("range %s, scale %s, variance %s produced a reversed "
						+ "result [%s, %s]")
						% [spec, scale, variance, r[0], r[1]])


# ------------------------------------------------ culture never draws

func test_an_unmodulated_purpose_draws_identically_under_every_culture() -> void:
	# `advance` is in no culture's SCALES, so its sampled value must come back
	# byte-identical under every culture. This fails if culture ever reaches the
	# DRAW rather than the range, and it fails if SCALES grows an entry it
	# should not have — neither of which the relative-position test below can
	# see, because that one only ever looks at a purpose that IS modulated.
	var base := DioramaCompose.sample([0.8, 1.2],
			DioramaCompose.new_ctx(SEED, 3), "block", "advance", 1.0)
	for n: String in DioramaCultures.NAMES:
		var ctx := DioramaCompose.new_ctx(SEED, 3, DioramaCultures.massing(n))
		assert_almost_eq(DioramaCompose.sample([0.8, 1.2], ctx, "block",
				"advance", 1.0), base, 1e-9,
				"culture '%s' moved an unmodulated purpose" % n)


func test_a_building_keeps_its_relative_position_across_cultures() -> void:
	# Two cultures' version of one building must be the SAME building
	# differently proportioned — varied, not randomized. Expressed as the
	# fraction of the modulated range the draw landed at: that number is the
	# channel's output, and it must not move.
	var tree := _box("solo", 2.0, 2.0, [1.0, 3.0])
	for id in range(8):
		var frac := -1.0
		for n: String in DioramaCultures.NAMES:
			var c := DioramaCultures.massing(n)
			var parts := DioramaCompose.build(tree, SEED, id, c)
			var r: Array = DioramaCultures.modulate([1.0, 3.0], c, "h")
			var h: float = parts[0]["params"]["size"].y
			var here: float = (h - float(r[0])) / maxf(float(r[1]) - float(r[0]), 1e-9)
			if frac >= 0.0:
				assert_almost_eq(here, frac, 1e-5,
						"id %d landed at a different relative position under '%s'"
						% [id, n])
			frac = here


## Slice 3's ruins survive slice 4 because culture never touches `need`: need
## bands are partitioned from node STRUCTURE, and a culture changes proportions,
## colour and crown shape but not what rests on what. So the same building must
## emit the same number of parts carrying the same `need`s, in the same order,
## under every culture.
##
## This replaced a test that filtered one culture's parts at descending rungs
## and checked each survivor set nested in the last. That could not fail:
## DioramaCondition.filter keeps a part when `effective >= need` against ONE
## threshold, so "kept at a lower rung implies kept at a higher one" holds for
## any `need` values whatsoever, culture-dependent or not.
func test_culture_never_touches_need() -> void:
	for style: String in DioramaStyles.NAMES:
		var tree: Dictionary = DioramaStyles.for_name(style)
		for id in [0, 1, 2, 5, 11]:
			var ref_name: String = DioramaCultures.NAMES[0]
			var ref := DioramaCompose.build(tree, SEED, id,
					DioramaCultures.massing(ref_name))
			# An empty building would make every comparison below vacuous.
			assert_gt(ref.size(), 0, "%s id %d emitted no parts" % [style, id])
			for n: String in DioramaCultures.NAMES.slice(1):
				var parts := DioramaCompose.build(tree, SEED, id,
						DioramaCultures.massing(n))
				assert_eq(parts.size(), ref.size(),
						"%s id %d: '%s' emits %d parts, '%s' emits %d"
						% [style, id, n, parts.size(), ref_name, ref.size()])
				var moved := 0
				var first := ""
				for i in range(mini(parts.size(), ref.size())):
					if parts[i]["need"] != ref[i]["need"]:
						moved += 1
						if first == "":
							first = (" (first: part %d, %f under '%s' vs %f)"
									% [i, parts[i]["need"], n, ref[i]["need"]])
				assert_eq(moved, 0,
						"%s id %d: %d part(s) changed `need` under '%s'%s — "
						% [style, id, moved, n, first]
						+ "culture reached the ruin order")


# --------------------------------------------------------------- threading

func test_stack_threads_culture_to_a_nested_mass() -> void:
	# _stack builds its child_ctx by hand; the single-mass tests above would not
	# notice if `"culture": ctx["culture"]` were dropped from that literal — the
	# nested mass would silently stop being modulated while everything still
	# rendered.
	var tree := {"stack": {"name": "outer",
			"children": [_box("inner", 2.0, 2.0, [1.0, 3.0])]}}
	var strong := _plain()
	strong["verticality"] = 5.0
	var plain_h: float = DioramaCompose.build(tree, SEED, 9, _plain())[0][
			"params"]["size"].y
	var strong_h: float = DioramaCompose.build(tree, SEED, 9, strong)[0][
			"params"]["size"].y
	assert_ne(plain_h, strong_h,
			"a mass nested under a stack did not receive the culture")


func test_row_threads_culture_to_a_nested_mass() -> void:
	# Same requirement as the stack test above, against _row's own hand-built
	# child_ctx literal — a separate line the stack test cannot exercise.
	var tree := {"row": {"name": "outer",
			"children": [_box("inner", 2.0, 2.0, [1.0, 3.0])]}}
	var strong := _plain()
	strong["verticality"] = 5.0
	var plain_h: float = DioramaCompose.build(tree, SEED, 9, _plain())[0][
			"params"]["size"].y
	var strong_h: float = DioramaCompose.build(tree, SEED, 9, strong)[0][
			"params"]["size"].y
	assert_ne(plain_h, strong_h,
			"a mass nested under a row did not receive the culture")


func test_an_empty_culture_leaves_geometry_untouched() -> void:
	# Every caller that names no culture — the spike, the lineup, the condition
	# sheet — must be unaffected by this whole layer existing.
	var tree := _box("solo", [1.0, 2.0], 2.0, [1.0, 3.0])
	var before := DioramaCompose.build(tree, SEED, 3)
	var after := DioramaCompose.build(tree, SEED, 3, {})
	assert_eq(before[0]["params"]["size"], after[0]["params"]["size"],
			"an empty culture changed the geometry")


# ------------------------------------------------------------ the cultures

func test_the_shipped_cultures_differ_in_every_lever() -> void:
	# A culture that matches another on a lever is a wasted culture — the sheet
	# would show rows differing in fewer ways than it appears to test.
	var cs: Array = []
	for n: String in DioramaCultures.NAMES:
		cs.append(DioramaCultures.massing(n))
	for lever in ["verticality", "thickness", "setback", "variance", "crown"]:
		var seen := {}
		for c: Dictionary in cs:
			seen[c[lever]] = true
		assert_eq(seen.size(), cs.size(),
				"two cultures share a '%s' value" % lever)


## The first culture is the baseline both halves of the sheet lean on: the
## control frame paints every row through its palette, and that only isolates
## geometry if its own massing adds none.
func test_the_first_culture_is_the_identity_massing() -> void:
	var base := DioramaCultures.massing(DioramaCultures.NAMES[0])
	for lever in ["verticality", "thickness", "setback", "variance"]:
		assert_eq(base[lever], 1.0,
				"the baseline culture scales '%s'; the control frame would then "
				% lever + "vary colour AND geometry and isolate neither")


func test_cultures_actually_produce_different_buildings() -> void:
	# Asserted by FINDING a difference rather than comparing one dimension
	# that might coincide.
	var tree := _box("solo", [1.0, 2.0], [1.0, 2.0], [1.0, 3.0])
	var pairs := 0
	for i in range(DioramaCultures.NAMES.size()):
		for j in range(i + 1, DioramaCultures.NAMES.size()):
			var a := DioramaCompose.build(tree, SEED, 5,
					DioramaCultures.massing(DioramaCultures.NAMES[i]))
			var b := DioramaCompose.build(tree, SEED, 5,
					DioramaCultures.massing(DioramaCultures.NAMES[j]))
			assert_ne(a[0]["params"]["size"], b[0]["params"]["size"],
					"'%s' and '%s' built the same thing"
					% [DioramaCultures.NAMES[i], DioramaCultures.NAMES[j]])
			pairs += 1
	assert_gt(pairs, 0, "fewer than two cultures to compare")


# ------------------------------------------------------------------ crowns

func test_each_crown_name_resolves_to_its_primitive() -> void:
	# Every word in CROWNS, not only the three the shipped cultures name. A
	# vocabulary word no test touches is a word that resolves to whatever a
	# typo left behind on the day a fourth people starts using it.
	var expected := {"spire": "cone", "dome": "dome", "hip": "tapered",
			"parapet": "box"}
	assert_eq(DioramaCultures.CROWNS, expected,
			"CROWNS gained or lost a word without this test noticing")
	for crown: String in expected:
		var c := _plain()
		c["crown"] = crown
		# `d` is declared even though a round crown would force it to equal `w`
		# anyway: _mass's degenerate gate reads w/d/h BEFORE it reads `kind`, so
		# a top-level mass with no `d` and no inherited footprint is dropped
		# before crown resolution ever runs, for every crown name.
		var tree := {"mass": {"name": "cap", "kind": "crown", "w": 2.0,
				"d": 2.0, "h": 1.0, "role": "structure"}}
		var parts := DioramaCompose.build(tree, SEED, 1, c)
		assert_eq(parts[0]["kind"], expected[crown],
				"crown '%s' resolved wrong" % crown)


func test_a_crown_resolving_round_still_reports_a_square_footprint() -> void:
	# The ordering trap: crown resolution has to happen BEFORE _mass forces
	# d = w for round kinds, or a spire reports a rectangular footprint and
	# whatever stacks on it inherits that.
	for crown in ["spire", "dome"]:
		var c := _plain()
		c["crown"] = crown
		var tree := {"stack": {"name": "s", "children": [
			{"mass": {"name": "cap", "kind": "crown", "w": 4.0, "d": 9.0,
					"h": 1.0, "role": "structure"}}]}}
		var out := DioramaCompose.resolve(tree,
				DioramaCompose.new_ctx(SEED, 1, c))
		assert_almost_eq(out["frame"]["footprint"].x,
				out["frame"]["footprint"].y, 1e-6,
				"crown '%s' reported a non-square footprint" % crown)


func _kinds(parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		out.append(p["kind"])
	out.sort()
	return out


func test_every_style_actually_crowns_through_the_culture() -> void:
	# Asserting that the SAME style produces DIFFERENT kinds under two crowns
	# can only hold if `crown` is genuinely plumbed for that style. A style
	# left with a literal "kind": "cone" produces identical kinds either way
	# and fails here — which is the omission this test exists to catch, and it
	# is exactly the omission a merge that took one side's style file wholesale
	# would introduce.
	for style_name: String in DioramaStyles.NAMES:
		var spire := _plain()
		spire["crown"] = "spire"
		var parapet := _plain()
		parapet["crown"] = "parapet"
		assert_ne(
				_kinds(DioramaCompose.build(DioramaStyles.for_name(style_name),
						SEED, 0, spire)),
				_kinds(DioramaCompose.build(DioramaStyles.for_name(style_name),
						SEED, 0, parapet)),
				("'%s' produced identical kinds under spire and parapet — its "
				+ "crowning mass is probably still a literal kind") % style_name)


## The kind each style's crowning mass had before crowns existed, as literals
## read from the merge base (4cae245). A test that pinned one default for all
## four ("tapered") is how two of them lost their spires: that premise was false
## for hero_arch and stepped, and nothing checked it.
const AUTHORED_CROWNS := {"residential": "tapered", "civic": "tapered",
		"hero_arch": "cone", "stepped": "cone"}


func test_an_empty_culture_builds_each_crown_as_authored() -> void:
	# A fifth style must say what its crown was authored as, not skip this.
	var names: Array = DioramaStyles.NAMES.duplicate()
	names.sort()
	var pinned: Array = AUTHORED_CROWNS.keys()
	pinned.sort()
	assert_eq(pinned, names, "AUTHORED_CROWNS does not cover every style")
	# Parts carry no names, so the crowning part is found by what a culture
	# changes: rebuild under a culture naming a crown of some OTHER kind, and
	# the parts whose kind moved are the crowns.
	for style_name: String in AUTHORED_CROWNS:
		var expected: String = AUTHORED_CROWNS[style_name]
		var named := _plain()
		named["crown"] = "parapet"
		assert_ne(DioramaCultures.CROWNS["parapet"], expected,
				"the comparison crown must differ from what it is compared to")
		var tree := DioramaStyles.for_name(style_name)
		var bare := DioramaCompose.build(tree, SEED, 0, {})
		var crowned := DioramaCompose.build(tree, SEED, 0, named)
		assert_eq(bare.size(), crowned.size(),
				"'%s' emitted a different part count under a crown" % style_name)
		var crowns := 0
		for i in range(mini(bare.size(), crowned.size())):
			if bare[i]["kind"] == crowned[i]["kind"]:
				continue
			crowns += 1
			assert_eq(bare[i]["kind"], expected,
					"'%s' crowned '%s' with no culture, but was authored '%s'"
					% [style_name, bare[i]["kind"], expected])
		assert_gt(crowns, 0,
				("no part of '%s' changed kind under a crown: its crowning mass "
				+ "is missing or already a box") % style_name)


func test_every_shipped_culture_names_a_real_crown() -> void:
	# The assert inside crown_kind() cannot be observed from GUT, so guard the
	# DATA instead: a typo in a culture's `crown` is the actual failure mode,
	# and this fails the moment a fourth culture is added with a bad name.
	for n: String in DioramaCultures.NAMES:
		var c := DioramaCultures.massing(n)
		assert_true(DioramaCultures.CROWNS.has(c["crown"]),
				"culture '%s' names crown '%s', which is not in CROWNS"
				% [n, c["crown"]])


# -------------------------------------------------------------- the dome

## The bug these three cover, stated once: a dome's geometry used to be
## `radius * squash` tall with `squash` sampled from its own authored proportion
## (default 0.85), which meant the sampled `h` was computed and then thrown
## away. Three consequences, one per test below — a dome ignored `verticality`,
## it grew with `thickness` instead, and `_mass` went on reporting `h` as the
## frame height, so anything stacked on a dome overlapped it or floated.
##
## All three pass trivially for every other primitive, which is why the bug
## survived: nothing else in the library derives its height from its width.

func test_a_dome_crown_is_as_tall_as_its_sampled_height() -> void:
	var c := _plain()
	c["crown"] = "dome"
	# Wide and shallow, so the old `w * 0.5 * 0.85` (1.275) and the authored
	# height (0.4) cannot be confused for each other by a loose tolerance.
	var tree := {"mass": {"name": "cap", "kind": "crown", "w": 3.0, "d": 3.0,
			"h": 0.4, "role": "structure"}}
	var out := DioramaCompose.resolve(tree, DioramaCompose.new_ctx(SEED, 1, c))
	var part: Dictionary = out["parts"][0]
	assert_eq(part["kind"], "dome", "the crown did not resolve to a dome")
	assert_almost_eq(DioramaCompose.part_height(part), 0.4, 1e-6,
			"the dome's emitted geometry is not as tall as its sampled height")
	assert_almost_eq(out["frame"]["height"], 0.4, 1e-6,
			"the frame height and the emitted dome disagree")


func test_a_dome_crown_takes_verticality_and_not_thickness() -> void:
	# The lever test, and the one that says WHY the height matters: a roofline
	# that grows when a people build thicker walls is not a roofline.
	var tree := {"mass": {"name": "cap", "kind": "crown", "w": 2.0, "d": 2.0,
			"h": 1.0, "role": "structure"}}
	var base := _plain()
	base["crown"] = "dome"
	var tall := base.duplicate()
	tall["verticality"] = 2.0
	var wide := base.duplicate()
	wide["thickness"] = 2.0
	var h0 := DioramaCompose.part_height(
			DioramaCompose.build(tree, SEED, 1, base)[0])
	var h_tall := DioramaCompose.part_height(
			DioramaCompose.build(tree, SEED, 1, tall)[0])
	var h_wide := DioramaCompose.part_height(
			DioramaCompose.build(tree, SEED, 1, wide)[0])
	assert_almost_eq(h_tall, h0 * 2.0, 1e-6,
			"verticality did not reach the dome's height")
	assert_almost_eq(h_wide, h0, 1e-6,
			"thickness moved the dome's height; only its radius should move")


func test_a_part_stacked_on_a_dome_sits_on_its_apex() -> void:
	# The consequence of the frame height and the geometry disagreeing, in the
	# form a reader would actually see it: a floating or sunken part.
	var c := _plain()
	c["crown"] = "dome"
	var tree := {"stack": {"name": "s", "children": [
		{"mass": {"name": "cap", "kind": "crown", "w": 3.0, "d": 3.0,
				"h": 0.4, "role": "structure"}},
		{"mass": {"name": "pin", "kind": "box", "w": 0.2, "d": 0.2, "h": 0.2,
				"role": "structure"}}]}}
	var parts := DioramaCompose.build(tree, SEED, 1, c)
	assert_eq(parts.size(), 2, "the stack did not emit both masses")
	var apex: float = parts[0]["xf"].origin.y + DioramaCompose.part_height(parts[0])
	assert_almost_eq(parts[1]["xf"].origin.y, apex, 1e-6,
			"the part above the dome does not stand on it")
