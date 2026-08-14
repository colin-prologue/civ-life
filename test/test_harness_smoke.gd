extends GutTest

# Placeholder suite. Its only job is to prove the harness itself works: that GUT
# is discovered, that a test runs headlessly with no display attached, and that
# the run is repeatable. Delete or absorb this once real sim tests exist.


func test_harness_runs_a_passing_assertion() -> void:
	assert_true(true, "the harness executes assertions")


func test_harness_reports_a_computed_value() -> void:
	# Slightly more than assert_true(true): proves the runner evaluates real
	# expressions rather than merely collecting the file.
	var total := 0
	for i in range(5):
		total += i
	assert_eq(total, 10, "the harness evaluates real expressions")


func test_seeded_randomness_is_reproducible() -> void:
	# The determinism guarantee sim/ depends on, asserted at the harness level so
	# the project fails loudly if seeded RNG ever stops being reproducible.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 12345
	b.seed = 12345
	var first: Array[int] = []
	var second: Array[int] = []
	for i in range(10):
		first.append(a.randi_range(0, 1000))
		second.append(b.randi_range(0, 1000))
	assert_eq(first, second, "same seed produces the same sequence")
