extends GutTest

# The ledger the world keeps so that something drawing it can say which way a
# number is going.
#
# The interesting property is not arithmetic — it is that this is a record and
# not a rule. `test_sim_headless_boundary.gd` polices what `sim/` may import;
# what this file polices is that nothing in the turn loop reads the ledger back,
# because the moment something does, a display aid has become a game mechanic.


func test_a_series_nothing_has_been_written_to_reports_an_honest_nothing() -> void:
	var ledger := Chronicle.new()
	assert_eq(ledger.latest(Chronicle.GRANARY_IN), 0.0, "no reading yet")
	assert_eq(ledger.rate(Chronicle.GRANARY_IN), 0.0, "no rate yet")
	assert_eq(ledger.trend(Chronicle.GRANARY_IN), 0, "and no direction yet")
	assert_eq(ledger.span(Chronicle.GRANARY_IN), 0, "and it says so rather than guessing")


func test_the_window_is_bounded_and_drops_the_oldest_reading() -> void:
	# A world runs for thousands of turns in the herd tests. An unbounded log
	# would grow with them, and nothing here wants to answer a question about
	# last year.
	var ledger := Chronicle.new()
	for i in range(Chronicle.WINDOW * 4):
		ledger.record(Chronicle.FARM_YIELD, float(i))

	assert_eq(ledger.span(Chronicle.FARM_YIELD), Chronicle.WINDOW, "one window, no more")
	assert_eq(
		ledger.latest(Chronicle.FARM_YIELD),
		float(Chronicle.WINDOW * 4 - 1),
		"holding the newest reading"
	)
	var kept := ledger.samples(Chronicle.FARM_YIELD)
	assert_eq(kept[0], float(Chronicle.WINDOW * 3), "and having dropped from the front")


func test_the_rate_is_the_mean_of_the_window() -> void:
	var ledger := Chronicle.new()
	for i in range(Chronicle.WINDOW):
		ledger.record(Chronicle.GRANARY_IN, 4.0)
	assert_almost_eq(ledger.rate(Chronicle.GRANARY_IN), 4.0, 0.0001, "a steady flow")

	var mixed := Chronicle.new()
	mixed.record(Chronicle.GRANARY_IN, 0.0)
	mixed.record(Chronicle.GRANARY_IN, 8.0)
	assert_almost_eq(mixed.rate(Chronicle.GRANARY_IN), 4.0, 0.0001, "a lumpy one averages out")


func test_rising_falling_and_steady_are_three_answers() -> void:
	var rising := Chronicle.new()
	var falling := Chronicle.new()
	var flat := Chronicle.new()
	for i in range(Chronicle.WINDOW):
		rising.record(Chronicle.GRANARY_STORE, 100.0 + float(i) * 10.0)
		falling.record(Chronicle.GRANARY_STORE, 100.0 - float(i) * 10.0)
		flat.record(Chronicle.GRANARY_STORE, 100.0)

	assert_eq(rising.trend(Chronicle.GRANARY_STORE), 1, "a filling granary reads as filling")
	assert_eq(falling.trend(Chronicle.GRANARY_STORE), -1, "an emptying one as emptying")
	assert_eq(flat.trend(Chronicle.GRANARY_STORE), 0, "and a still one as still")


func test_a_quantity_arriving_in_lumps_still_reads_as_rising() -> void:
	# The reason `trend()` compares halves rather than the last two readings.
	# Deliveries land or they do not, so a step-by-step comparison on a granary
	# being filled steadily would alternate between up and flat forever.
	var ledger := Chronicle.new()
	var store := 0.0
	for i in range(Chronicle.WINDOW):
		if i % 2 == 0:
			store += 20.0
		ledger.record(Chronicle.GRANARY_STORE, store)
	assert_eq(ledger.trend(Chronicle.GRANARY_STORE), 1, "lumpy filling is still filling")


func test_the_deadband_scales_with_the_quantity_it_is_asked_about() -> void:
	# The same function is asked about a granary holding hundreds and a yield of
	# under one. A fixed threshold would be all noise on one and all silence on
	# the other.
	assert_eq(Chronicle.direction(1000.0, 1000.5), 0, "half a grain in a thousand is noise")
	assert_eq(Chronicle.direction(0.20, 0.40), 1, "the same absolute move in a small number is news")
	assert_eq(Chronicle.direction(0.0, 0.0), 0, "nothing against nothing is steady, not rising")


func test_nothing_in_the_simulation_reads_the_ledger_back() -> void:
	# The line this file exists on the right side of. The chronicle is written at
	# the end of a turn and consulted by nobody until a renderer asks; if any
	# rule ever branches on a value in it, a display aid has quietly become a
	# mechanic and `AgDR-001`'s boundary has moved.
	#
	# Checked by reading the sources rather than by behaviour, because "no system
	# consults it" is a claim about every future system too, and the failure mode
	# is somebody adding the first one.
	var offenders: Array[String] = []
	for path in _sim_scripts():
		if path.ends_with("chronicle.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		for call in ["chronicle.latest", "chronicle.rate", "chronicle.trend",
				"chronicle.samples", "chronicle.span"]:
			if text.find(call) >= 0:
				offenders.append("%s calls %s()" % [path.get_file(), call])
	assert_eq(
		offenders,
		[] as Array[String],
		"the ledger is written by sim/ and read only from outside it"
	)


func _sim_scripts() -> Array[String]:
	var out: Array[String] = []
	for name in DirAccess.get_files_at("res://sim"):
		if name.ends_with(".gd"):
			out.append("res://sim/" + name)
	assert_gt(out.size(), 0, "there are simulation sources to scan")
	return out
