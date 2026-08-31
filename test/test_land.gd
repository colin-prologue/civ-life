extends GutTest
## The arithmetic of land wearing out and coming back, with no world attached.
##
## Kept pure and separate because the interesting properties here — that nothing
## reaches zero, that recovery never overshoots, where continuous maximum use
## actually settles — are claims about the numbers, and they are far easier to
## trust asserted directly than inferred from a world.


func test_recovery_moves_toward_the_ceiling_and_stops_there() -> void:
	assert_almost_eq(Land.recovered(Land.MAX_VITALITY), Land.MAX_VITALITY, 0.0001,
			"full land stays full rather than overshooting")
	var half := Land.recovered(0.5)
	assert_gt(half, 0.5, "worn land recovers")
	assert_lt(half, Land.MAX_VITALITY, "but not all at once")


func test_recovery_reaches_half_way_back_in_one_half_life() -> void:
	# The constant is stated as a half-life so it can be reasoned about in
	# seasons; this asserts the rate actually derived from it does that.
	var v := 0.0
	for i in range(Land.RECOVERY_HALF_LIFE_TURNS):
		v = Land.recovered(v)
	assert_almost_eq(v, 0.5, 0.02, "half the distance closed in one half-life")


func test_depletion_never_reaches_zero() -> void:
	var v := Land.MAX_VITALITY
	for i in range(500):
		v = Land.depleted(v, 1.0)
	assert_eq(v, Land.MIN_VITALITY, "five hundred turns of maximum use stops at the floor")
	assert_gt(Land.MIN_VITALITY, 0.0, "and the floor is above zero")


func test_no_use_is_no_depletion() -> void:
	assert_eq(Land.depleted(0.7, 0.0), 0.7, "land nobody worked is land unchanged")


func test_continuous_maximum_use_settles_one_recovery_step_above_the_floor() -> void:
	# The turn order is deplete-then-recover, so ground worked flat out is
	# clamped to the floor and then lifted one step before the turn ends. The
	# attractor is therefore MIN_VITALITY + one recovery step, not MIN_VITALITY.
	#
	# Asserted tightly and against a derived value rather than a literal: a loose
	# tolerance here is what let an earlier, wrong claim about this equilibrium
	# pass by about 0.007.
	var v := Land.MAX_VITALITY
	for i in range(400):
		v = Land.recovered(Land.depleted(v, 1.0))
	assert_almost_eq(v, Land.continuous_use_equilibrium(), 0.001,
			"continuous full use settles one recovery step above the floor")
	assert_gt(v, Land.MIN_VITALITY, "and therefore strictly above it")


func test_intensity_scales_how_fast_land_wears() -> void:
	var light := Land.depleted(Land.MAX_VITALITY, 0.25)
	var heavy := Land.depleted(Land.MAX_VITALITY, 1.0)
	assert_gt(light, heavy, "lighter use wears the ground more slowly")
