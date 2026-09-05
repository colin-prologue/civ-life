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


func test_recovery_is_stated_in_seasons_rather_than_bare_turns() -> void:
	# AC9, first half. The half-life is meant to be reasoned about against the
	# calendar, so it is expressed as a multiple of the season rather than picked
	# as a number of turns that happens to feel right.
	assert_eq(Land.RECOVERY_HALF_LIFE_TURNS % Seasons.TURNS_PER_SEASON, 0,
			"the recovery half-life is a whole number of seasons")
	assert_gt(Land.RECOVERY_HALF_LIFE_TURNS, 0, "and a positive one")


func test_the_wear_and_recovery_clocks_stay_within_a_season_of_each_other() -> void:
	# AC9, second half, and the assertion that stops `DEPLETION_PER_UNIT` being
	# tuned on its own. It is the one constant here that nothing else was checking:
	# the floor, the ceiling and the half-life are all pinned by the tests above,
	# but depletion could be moved by any factor without turning this file red.
	#
	# The claim is proportion, not a value. Land that wears much faster than it
	# recovers reads as decline; land that recovers much faster than it wears reads
	# as static. Rotation is the regime where the two clocks are comparable, so
	# that is what gets asserted — and asserted against `Seasons.TURNS_PER_SEASON`
	# rather than a literal, so the calendar stays the unit.
	var wear := Land.wear_half_life_turns()
	gut.p("wear half-life %d turns, recovery half-life %d turns, season %d turns"
			% [wear, Land.RECOVERY_HALF_LIFE_TURNS, Seasons.TURNS_PER_SEASON])
	assert_gt(wear, 0,
			"unbroken maximum use must actually be able to halve a tile")
	assert_almost_eq(float(wear), float(Land.RECOVERY_HALF_LIFE_TURNS),
			float(Seasons.TURNS_PER_SEASON),
			"wear (%d turns) and recovery (%d turns) are within a season of each other"
					% [wear, Land.RECOVERY_HALF_LIFE_TURNS])


func test_the_row_recovery_agrees_with_the_single_value_one() -> void:
	# recovered_row() hoists the rate out of the loop for speed, which means the
	# arithmetic exists twice. This is what stops the two drifting apart.
	var row := PackedFloat32Array([Land.MIN_VITALITY, 0.3, 0.5, 0.87, Land.MAX_VITALITY])
	var expected := PackedFloat32Array()
	for value in row:
		expected.append(Land.recovered(value))

	var got := Land.recovered_row(row)

	assert_eq(got.size(), expected.size(), "same length back")
	for i in range(expected.size()):
		assert_almost_eq(got[i], expected[i], 0.000001,
				"row recovery matches single-value recovery at %d" % i)
