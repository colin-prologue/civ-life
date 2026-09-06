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
