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
