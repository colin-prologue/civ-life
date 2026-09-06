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


func test_a_reversed_range_is_caught_after_modulation_not_before() -> void:
	# The assert exists to catch authoring typos. It must see the range the
	# sampler actually uses, or a bad multiplier walks straight past the guard.
	var c := _plain()
	var r: Array = DioramaCulture.modulate([1.0, 2.0], c, "h")
	assert_true(r[0] <= r[1], "identity modulation produced a reversed range")
	c["variance"] = 0.0
	var flat: Array = DioramaCulture.modulate([1.0, 2.0], c, "h")
	assert_true(flat[0] <= flat[1], "zero variance produced a reversed range")
