extends GutTest

# There is one way to move the world forward and this suite drives it through
# the scene, not around it. The failure this is here to prevent is a UI that
# grows its own update path — a key handler that nudges a counter, a view that
# caches a turn number of its own — because that divergence is invisible until
# the two disagree and then it is a whole afternoon.

const MainScene := preload("res://game/main.tscn")

## A redraw that misses this is a redraw the player feels. Stated as a budget
## rather than a target: if the map has to shrink to meet it, that is a finding
## worth reporting, not something to silently tune around.
const REDRAW_BUDGET_MSEC := 100.0


func _launch() -> Node2D:
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	return main


func test_a_fresh_world_starts_at_turn_zero() -> void:
	var main: Node2D = await _launch()
	assert_eq(main.world.turn, 0, "the world has not been advanced yet")


func test_the_ui_entry_point_advances_the_simulation_turn() -> void:
	var main: Node2D = await _launch()
	var before: int = main.world.turn

	var returned: int = main.advance_turn()

	assert_eq(main.world.turn, before + 1, "the world's own counter moved")
	assert_eq(returned, main.world.turn, "the controller reports the turn the world is on")


func test_advancing_repeatedly_keeps_the_ui_and_the_world_in_step() -> void:
	# A parallel counter in the UI would survive a single advance and drift over
	# several, so this counts rather than checking once.
	var main: Node2D = await _launch()
	for expected in range(1, 6):
		main.advance_turn()
		assert_eq(main.world.turn, expected, "after %d advances" % expected)
	assert_string_contains(main.get_node("Status").text, "Turn 5")


func test_a_turn_advance_redraws_inside_the_frame_budget() -> void:
	var main: Node2D = await _launch()
	var view: HexMapView = main.get_node("HexMapView")
	assert_gt(view.last_draw_usec, 0, "the view actually drew — otherwise this budget is vacuous")

	view.last_draw_usec = 0
	var started := Time.get_ticks_usec()
	main.advance_turn()
	var advance_msec := float(Time.get_ticks_usec() - started) / 1000.0

	# The advance queues the redraw; the draw itself happens on the next frame,
	# and times itself so this measures the map being drawn rather than however
	# long the engine took to get round to a frame.
	await wait_frames(2)
	assert_gt(view.last_draw_usec, 0, "the advance triggered a redraw")

	var total := advance_msec + float(view.last_draw_usec) / 1000.0
	gut.p("advance %.1fms + redraw %.1fms = %.1fms for %d tiles (budget %.0fms)" % [
		advance_msec,
		float(view.last_draw_usec) / 1000.0,
		total,
		main.world.grid.tile_count(),
		REDRAW_BUDGET_MSEC,
	])
	assert_lt(
		total,
		REDRAW_BUDGET_MSEC,
		"advance + redraw took %.1fms for %d tiles" % [total, main.world.grid.tile_count()]
	)


func test_the_whole_map_is_drawn_not_a_visible_corner_of_it() -> void:
	# The cheap way to make a big map fast is to draw less of it. If that ever
	# happens it should be a decision, not a silent one.
	var main: Node2D = await _launch()
	var view: HexMapView = main.get_node("HexMapView")
	assert_eq(
		view.tile_polygon_count(),
		main.world.grid.tile_count(),
		"one polygon per tile on the map"
	)


# --- auto-advance ------------------------------------------------------------
# Watching this world means watching it over years, and a year is 24 turns. The
# tests below exist because the auto-advance is a second thing that can move the
# clock, and the whole point of the suite above is that there is only one path a
# turn travels. These check that the new path is the old path on a timer, and
# that a stalled frame cannot silently fast-forward the world.


func test_drain_holds_a_partial_turn_back() -> void:
	var got := Main.drain(0.75, Main.MAX_TURNS_PER_FRAME)
	assert_eq(got["turns"], 0, "three quarters of a turn is not a turn")
	assert_almost_eq(got["accumulator"], 0.75, 0.0001, "and it is kept for next frame")


func test_drain_yields_whole_turns_and_keeps_the_remainder() -> void:
	var got := Main.drain(2.25, Main.MAX_TURNS_PER_FRAME)
	assert_eq(got["turns"], 2, "two whole turns are due")
	assert_almost_eq(got["accumulator"], 0.25, 0.0001, "the quarter turn carries over")


func test_a_stalled_frame_drops_its_backlog_instead_of_fast_forwarding() -> void:
	# The window was dragged, or the process was suspended, and eighty turns of
	# wall clock went by. Playing those back is a world that lurches; the honest
	# behaviour is to lose the time rather than to spend it.
	var got := Main.drain(80.0, Main.MAX_TURNS_PER_FRAME)
	assert_eq(got["turns"], Main.MAX_TURNS_PER_FRAME, "capped at the per-frame limit")
	assert_almost_eq(got["accumulator"], 0.0, 0.0001, "and the backlog is discarded, not banked")


func test_the_world_does_not_move_on_its_own_until_asked() -> void:
	var main: Node2D = await _launch()
	assert_false(main.playing, "a freshly launched world is paused")
	var before: int = main.world.turn
	await wait_frames(10)
	assert_eq(main.world.turn, before, "ten frames passed and nothing advanced")


func test_playing_advances_the_world_through_the_same_entry_point() -> void:
	var main: Node2D = await _launch()
	main.speed_index = 1  # 1.0 turns per second
	main.set_playing(true)
	var before: int = main.world.turn

	var ran: int = main.tick(3.0)

	assert_eq(ran, 3, "three seconds at one turn a second")
	assert_eq(main.world.turn, before + 3, "and the world's own counter moved by three")
	# The status line is rebuilt only by advance_turn(); if auto-advance had
	# grown its own path this would still say turn 0.
	assert_string_contains(main.get_node("Status").text, "Turn %d" % main.world.turn)


func test_a_paused_world_ignores_the_clock_entirely() -> void:
	var main: Node2D = await _launch()
	var before: int = main.world.turn

	var ran: int = main.tick(10.0)

	assert_eq(ran, 0, "ten seconds bought nothing while paused")
	assert_eq(main.world.turn, before, "paused means paused")


func test_pausing_discards_the_part_turn_it_was_holding() -> void:
	# Otherwise stopping and starting repeatedly banks fractions, and a world
	# that was paused a lot runs faster than one that was not.
	var main: Node2D = await _launch()
	main.speed_index = 1
	main.set_playing(true)
	main.tick(0.9)          # nine tenths of a turn held back
	main.set_playing(false)
	main.set_playing(true)
	var before: int = main.world.turn

	var ran: int = main.tick(0.9)

	assert_eq(ran, 0, "the held fraction did not survive the pause")
	assert_eq(main.world.turn, before, "and no turn was run")


func test_speed_changes_how_much_a_second_buys() -> void:
	var main: Node2D = await _launch()
	main.set_playing(true)
	main.speed_index = 0
	var slow: int = main.tick(4.0)
	main.speed_index = 2
	var fast: int = main.tick(4.0)

	assert_eq(slow, 2, "four seconds at half a turn a second")
	assert_eq(fast, Main.MAX_TURNS_PER_FRAME, "four seconds at two a second, capped per frame")
	assert_gt(fast, slow, "faster is faster")


func test_speed_clamps_at_both_ends() -> void:
	var main: Node2D = await _launch()
	for i in range(20):
		main.faster()
	assert_eq(main.speed_index, Main.TURNS_PER_SECOND.size() - 1, "cannot go past the fastest")
	for i in range(20):
		main.slower()
	assert_eq(main.speed_index, 0, "cannot go below the slowest")
