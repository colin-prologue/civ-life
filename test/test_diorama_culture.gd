extends GutTest
## The culture layer: what a people's way of building modulates, and what it
## must leave alone.


func _plain() -> Dictionary:
	# Every multiplier at 1.0 — the identity culture. Any test that uses this
	# is asserting that modulation with no effect really has no effect.
	return {"name": "plain", "palette": {}, "verticality": 1.0,
			"thickness": 1.0, "setback": 1.0, "variance": 1.0, "crown": "hip"}


func test_the_identity_culture_changes_nothing() -> void:
	var c := _plain()
	assert_eq(DioramaCulture.modulate(0.6, c, "h"), 0.6,
			"a scalar changed under an identity culture")
	var r: Array = DioramaCulture.modulate([0.6, 1.3], c, "h")
	assert_almost_eq(r[0], 0.6, 1e-6, "range lo moved under identity")
	assert_almost_eq(r[1], 1.3, 1e-6, "range hi moved under identity")


func test_scale_moves_a_range_without_changing_its_relative_width() -> void:
	var c := _plain()
	c["verticality"] = 2.0
	var r: Array = DioramaCulture.modulate([0.6, 1.4], c, "h")
	assert_almost_eq(r[0], 1.2, 1e-6, "lo should scale")
	assert_almost_eq(r[1], 2.8, 1e-6, "hi should scale")


func test_variance_widens_around_the_midpoint() -> void:
	# The midpoint must not move — variance is about how uniform a people's
	# buildings are, not about how big they are. Those are separate levers and
	# conflating them would make one unusable.
	var c := _plain()
	c["variance"] = 2.0
	var r: Array = DioramaCulture.modulate([0.6, 1.4], c, "h")
	assert_almost_eq((r[0] + r[1]) * 0.5, 1.0, 1e-6, "midpoint moved")
	assert_almost_eq(r[1] - r[0], 1.6, 1e-6, "width should double")


func test_variance_below_one_narrows_but_never_inverts() -> void:
	var c := _plain()
	c["variance"] = 0.0
	var r: Array = DioramaCulture.modulate([0.6, 1.4], c, "h")
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
		assert_eq(DioramaCulture.modulate([1.0, 2.0], c, purpose), [1.0, 2.0],
				"'%s' should not be modulated by culture" % purpose)


func test_each_purpose_takes_its_own_multiplier() -> void:
	var c := _plain()
	c["verticality"] = 2.0
	c["thickness"] = 3.0
	c["setback"] = 4.0
	assert_eq(DioramaCulture.modulate(1.0, c, "h"), 2.0, "h takes verticality")
	assert_eq(DioramaCulture.modulate(1.0, c, "w"), 3.0, "w takes thickness")
	assert_eq(DioramaCulture.modulate(1.0, c, "d"), 3.0, "d takes thickness")
	assert_eq(DioramaCulture.modulate(1.0, c, "setback"), 4.0,
			"setback takes setback")


func test_null_stays_null() -> void:
	assert_eq(DioramaCulture.modulate(null, _plain(), "h"), null,
			"an absent spec must stay absent so the caller's default applies")


func test_the_three_cultures_differ_in_every_lever() -> void:
	# A culture that matches another on a lever is a wasted culture — the sheet
	# would show two rows differing in fewer ways than it appears to test.
	var cs: Array = []
	for n in DioramaCulture.NAMES:
		cs.append(DioramaCulture.for_name(n))
	for lever in ["verticality", "thickness", "setback", "variance", "crown"]:
		var seen := {}
		for c: Dictionary in cs:
			seen[c[lever]] = true
		assert_eq(seen.size(), cs.size(),
				"two cultures share a '%s' value" % lever)


const SEED := 4242


func _box(name: String, w: Variant, d: Variant, h: Variant) -> Dictionary:
	return {"mass": {"name": name, "kind": "box", "w": w, "d": d, "h": h,
			"role": "plaster"}}


func test_an_unmodulated_purpose_draws_identically_under_every_culture() -> void:
	# `advance` is in no culture's SCALES, so its sampled value must come back
	# byte-identical under every culture. This fails if culture ever reaches the
	# DRAW rather than the range, and it fails if SCALES grows an entry it
	# should not have — neither of which the relative-position test below can
	# see, because that one only ever looks at a purpose that IS modulated.
	var base := DioramaCompose.sample([0.8, 1.2],
			DioramaCompose.new_ctx(SEED, 3), "block", "advance", 1.0)
	for n in DioramaCulture.NAMES:
		var ctx := DioramaCompose.new_ctx(SEED, 3, DioramaCulture.for_name(n))
		assert_almost_eq(DioramaCompose.sample([0.8, 1.2], ctx, "block",
				"advance", 1.0), base, 1e-9,
				"culture '%s' moved an unmodulated purpose" % n)


func test_a_building_keeps_its_relative_position_across_cultures() -> void:
	# Two cultures' version of one building must be the SAME building
	# differently proportioned — varied, not randomized.
	var tree := _box("solo", 2.0, 2.0, [1.0, 3.0])
	for id in range(8):
		var frac := -1.0
		for n in DioramaCulture.NAMES:
			var c := DioramaCulture.for_name(n)
			var parts := DioramaCompose.build(tree, SEED, id, c)
			var r: Array = DioramaCulture.modulate([1.0, 3.0], c, "h")
			var h: float = parts[0]["params"]["size"].y
			var here: float = (h - float(r[0])) / maxf(float(r[1]) - float(r[0]), 1e-9)
			if frac >= 0.0:
				assert_almost_eq(here, frac, 1e-5,
						"id %d landed at a different relative position under '%s'"
						% [id, n])
			frac = here


func test_stack_threads_culture_to_a_nested_mass() -> void:
	# _stack builds its child_ctx by hand; every one of the other tests here
	# builds a single top-level `mass`, so none of them would notice if
	# `"culture": ctx["culture"]` were dropped from that literal — the nested
	# mass would silently stop being modulated while everything still
	# rendered. Nest a mass one level inside a stack and prove the nested
	# mass's height moves under a strongly different verticality.
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
	# Every pre-culture caller passes no culture; they must be unaffected.
	var tree := _box("solo", [1.0, 2.0], 2.0, [1.0, 3.0])
	var before := DioramaCompose.build(tree, SEED, 3)
	var after := DioramaCompose.build(tree, SEED, 3, {})
	assert_eq(before[0]["params"]["size"], after[0]["params"]["size"],
			"an empty culture changed the geometry")


func test_cultures_actually_produce_different_buildings() -> void:
	# Asserted by FINDING a difference rather than comparing one dimension
	# that might coincide — the same shape of test that caught a cohesive row
	# masquerading as an articulated one in slice 3.
	var tree := _box("solo", [1.0, 2.0], [1.0, 2.0], [1.0, 3.0])
	var pairs := 0
	for i in range(DioramaCulture.NAMES.size()):
		for j in range(i + 1, DioramaCulture.NAMES.size()):
			var a := DioramaCompose.build(tree, SEED, 5,
					DioramaCulture.for_name(DioramaCulture.NAMES[i]))
			var b := DioramaCompose.build(tree, SEED, 5,
					DioramaCulture.for_name(DioramaCulture.NAMES[j]))
			assert_ne(a[0]["params"]["size"], b[0]["params"]["size"],
					"'%s' and '%s' built the same thing"
					% [DioramaCulture.NAMES[i], DioramaCulture.NAMES[j]])
			pairs += 1
	assert_eq(pairs, 3, "expected three culture pairs to compare")


func test_modulate_never_inverts_a_range_for_any_nonnegative_scale_and_variance() -> void:
	# The property this test exists to protect: a bad multiplier must not walk
	# past the lo <= hi guard any more than a reversed literal range would.
	# That property is unreachable through sample()'s own guard — none of the
	# three shipped cultures can produce a negative variance, and GDScript's
	# assert() aborts the function rather than letting GUT observe a failure —
	# so it is checked here, directly against modulate(), at the layer where a
	# bad culture's numbers are actually the thing under test. A negative
	# variance is excluded: modulate() now asserts against it as an authoring
	# error, not a range this sweep is meant to reach.
	var c := _plain()
	var ranges := [[1.0, 2.0], [0.6, 1.4], [-3.0, -1.0], [0.0, 0.0], [5.0, 5.0]]
	var scales := [0.0, 0.1, 1.0, 1.7, 3.0]
	var variances := [0.0, 0.1, 1.0, 1.7, 3.0]
	for spec in ranges:
		for scale in scales:
			for variance in variances:
				c["verticality"] = scale
				c["variance"] = variance
				var r: Array = DioramaCulture.modulate(spec, c, "h")
				assert_true(r[0] <= r[1],
						("range %s, scale %s, variance %s produced a reversed "
						+ "result [%s, %s]")
						% [spec, scale, variance, r[0], r[1]])


func test_each_crown_name_resolves_to_its_primitive() -> void:
	var expected := {"spire": "cone", "dome": "dome", "hip": "tapered",
			"parapet": "box"}
	for crown: String in expected:
		var c := _plain()
		c["crown"] = crown
		# THIRD BRIEF DEFECT (beyond the two corrected above): the brief's tree
		# here declared no "d" and this mass has no inherited footprint (it is
		# not nested in a stack), so _mass's degenerate gate — which reads w/d/h
		# before it reads `kind`, unconditionally on kind — drops the mass before
		# crown resolution ever runs, for every crown name, not only round ones.
		# Verified as pre-existing and unrelated to crowns: a bare
		# `"kind": "cone"` mass with the same shape (w and h only, no d, no
		# inherited footprint) is dropped the same way before this task's
		# changes. Declaring "d" here — matching "w", exactly what a round crown
		# would force it to anyway — sidesteps the gate without touching it,
		# which is out of this task's scope per the brief.
		var tree := {"mass": {"name": "cap", "kind": "crown", "w": 2.0,
				"d": 2.0, "h": 1.0, "role": "plaster"}}
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
					"h": 1.0, "role": "plaster"}}]}}
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
	# and fails here — which is the omission this test exists to catch.
	for style_name in DioramaStyles.NAMES:
		var spire := _plain()
		spire["crown"] = "spire"
		var parapet := _plain()
		parapet["crown"] = "parapet"
		assert_ne(
				_kinds(DioramaCompose.build(DioramaStyles.for_name(style_name),
						SEED, 0, spire)),
				_kinds(DioramaCompose.build(DioramaStyles.for_name(style_name),
						SEED, 0, parapet)),
				"'%s' produced identical kinds under spire and parapet — its crowning mass is probably still a literal kind"
						% style_name)


func test_an_empty_culture_crowns_hipped() -> void:
	# Stated requirement: crown_kind({}) must return "tapered" so pre-culture
	# callers get the hipped roof three of the four styles had before crowns
	# existed. Nothing else pins this default — mutating it to "spire" would
	# go undetected and silently flip every pre-culture caller's residential
	# and civic roofline from hipped to conical.
	assert_eq(DioramaCulture.crown_kind({}), "tapered",
			"an empty culture must crown hipped (tapered), not something else")


func test_every_shipped_culture_names_a_real_crown() -> void:
	# The assert inside crown_kind() cannot be observed from GUT, so guard the
	# DATA instead: a typo in a culture's `crown` is the actual failure mode,
	# and this fails the moment a fourth culture is added with a bad name.
	for n in DioramaCulture.NAMES:
		var c := DioramaCulture.for_name(n)
		assert_true(DioramaCulture.CROWNS.has(c["crown"]),
				"culture '%s' names crown '%s', which is not in CROWNS"
				% [n, c["crown"]])


func test_apply_culture_colours_every_part_from_the_palette() -> void:
	var parts := DioramaCompose.build(DioramaStyles.residential(), SEED, 1,
			DioramaCulture.highland())
	DioramaCompose.apply_culture(parts, DioramaCulture.highland())
	var pal: Dictionary = DioramaCulture.highland()["palette"]
	for p: Dictionary in parts:
		assert_eq(p["color"], pal[p["role"]],
				"role '%s' did not take its culture's colour" % p["role"])


func test_two_cultures_colour_the_same_building_differently() -> void:
	var found := false
	for n in DioramaCulture.NAMES:
		var c := DioramaCulture.for_name(n)
		var parts := DioramaCompose.build(DioramaStyles.residential(), SEED, 1, c)
		DioramaCompose.apply_culture(parts, c)
		if parts[0]["color"] != DioramaCulture.lowland()["palette"][parts[0]["role"]]:
			found = true
	assert_true(found, "no culture produced a colour differing from lowland's")


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
	for style in DioramaStyles.NAMES:
		var tree: Dictionary = DioramaStyles.for_name(style)
		for id in [0, 1, 2, 5, 11]:
			var ref_name: String = DioramaCulture.NAMES[0]
			var ref := DioramaCompose.build(tree, SEED, id,
					DioramaCulture.for_name(ref_name))
			# An empty building would make every comparison below vacuous.
			assert_gt(ref.size(), 0, "%s id %d emitted no parts" % [style, id])
			for n in DioramaCulture.NAMES.slice(1):
				var parts := DioramaCompose.build(tree, SEED, id,
						DioramaCulture.for_name(n))
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
