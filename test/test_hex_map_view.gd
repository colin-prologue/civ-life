extends GutTest

# What can be checked about a picture without looking at it: that every terrain
# has a colour, that no two of them are the same colour, and that the hexes land
# where flat-top packing says they should.
#
# What cannot: whether the result is readable. That is AC7 on the ticket and it
# needs a human. These tests are a floor — they catch a terrain silently
# rendering as the fallback, or two terrains drifting into the same swatch
# during a palette tweak. They are not evidence the map looks like anything.

const MainScene := preload("res://game/main.tscn")

## Minimum straight-line separation in RGB between any two terrain colours.
## Calibrated just under the current tightest pair (water and forest), so a
## tweak that collapses two terrains together fails instead of shipping.
const MIN_COLOR_DISTANCE := 0.30


func test_every_terrain_in_the_simulation_has_a_colour() -> void:
	# Driven off the enum, not off a copy of it: a terrain added in sim/ without
	# a colour here would otherwise render as the fallback and look like a bug in
	# generation rather than a gap in the palette.
	for terrain in WorldGen.Terrain.values():
		assert_true(
			HexMapView.TERRAIN_COLORS.has(terrain),
			"terrain %d has a fill colour" % terrain
		)
		assert_true(
			HexMapView.TERRAIN_NAMES.has(terrain),
			"terrain %d is named in the legend" % terrain
		)


func test_no_two_terrains_share_a_colour() -> void:
	var terrains := WorldGen.Terrain.values()
	for i in range(terrains.size()):
		for j in range(i + 1, terrains.size()):
			var a: Color = HexMapView.TERRAIN_COLORS[terrains[i]]
			var b: Color = HexMapView.TERRAIN_COLORS[terrains[j]]
			var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			assert_gt(
				distance,
				MIN_COLOR_DISTANCE,
				"%s and %s are distinguishable (distance %.3f)" % [
					HexMapView.TERRAIN_NAMES[terrains[i]],
					HexMapView.TERRAIN_NAMES[terrains[j]],
					distance,
				]
			)


func test_the_city_is_drawn_in_colours_no_terrain_uses() -> void:
	# The city has to read as built rather than grown, and the cheapest way that
	# fails is a structure landing on a tile close enough in colour to disappear
	# into it. Not evidence the city is legible — that is AC12 and needs a person
	# — but it catches the palette collapsing during a tweak.
	var city := {
		"farm": HexMapView._FARM_FILL,
		"granary": HexMapView._GRANARY_FILL,
		"road": HexMapView._ROAD_COLOR,
		"citizen": HexMapView._CITIZEN_LOADED,
	}
	for name in city:
		for terrain in WorldGen.Terrain.values():
			var a: Color = city[name]
			var b: Color = HexMapView.TERRAIN_COLORS[terrain]
			var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			assert_gt(
				distance,
				MIN_COLOR_DISTANCE,
				"%s is distinguishable from %s (distance %.3f)" % [
					name, HexMapView.TERRAIN_NAMES[terrain], distance,
				]
			)


func test_the_view_draws_the_city_the_world_actually_has() -> void:
	# The renderer holds no state of its own, so what can be checked without
	# looking at the picture is that the world it is pointed at has something to
	# draw and that drawing it does not fall over.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")
	var world: WorldMap = main.world

	assert_gt(world.nodes.size(), 0, "there are structures on the map to draw")
	assert_gt(world.routes.size(), 0, "and a road")
	assert_gt(world.citizens().size(), 0, "and people on it")
	assert_gt(view.last_draw_usec, 0, "and the view drew the frame containing them")
	for citizen in world.citizens():
		assert_ne(
			view.center_of(citizen.coord),
			Vector2.ZERO,
			"citizen %d has somewhere on screen to be" % citizen.id
		)


func test_every_season_has_an_accent_colour() -> void:
	for season in Seasons.SEASON_ORDER:
		assert_true(
			HexMapView.SEASON_COLORS.has(season),
			"season %s is drawn in a colour of its own" % Seasons.season_name(season)
		)


func test_a_tile_changes_colour_as_its_forage_falls() -> void:
	# The one mechanical check that separates "seasons are visible" from "seasons
	# are a caption": the same terrain must not render the same in a fed season
	# and a lean one. What it cannot check is whether the difference reads as
	# winter — that is the human criterion on the ticket.
	var fed := HexMapView.tile_color(WorldGen.Terrain.GRASS, Seasons.MAX_FORAGE)
	var lean := HexMapView.tile_color(WorldGen.Terrain.GRASS, Seasons.MIN_FORAGE)
	var distance := Vector3(fed.r - lean.r, fed.g - lean.g, fed.b - lean.b).length()
	assert_gt(distance, MIN_COLOR_DISTANCE, "a fed meadow and a bare one look different")

	# Terrain still has to be legible underneath the seasonal wash, or the map
	# has traded one thing the player needs to see for another.
	var lean_forest := HexMapView.tile_color(WorldGen.Terrain.FOREST, Seasons.MIN_FORAGE)
	var apart := Vector3(lean.r - lean_forest.r, lean.g - lean_forest.g, lean.b - lean_forest.b)
	assert_gt(apart.length(), 0.05, "meadow and forest are still told apart at their leanest")

	# Water has no forage in any season, so scaling it would bleach the sea
	# permanently to say something true only about grazing.
	assert_eq(
		HexMapView.tile_color(WorldGen.Terrain.WATER, 0.0),
		HexMapView.TERRAIN_COLORS[WorldGen.Terrain.WATER],
		"the sea does not go dormant"
	)


func test_advancing_into_another_season_repaints_the_map() -> void:
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")

	assert_gt(view.tile_polygon_count(), 0, "the view is drawing the map it is being asked about")

	var before := _fill_sample(main.world)
	for i in range(Seasons.TURNS_PER_SEASON * 3):
		main.advance_turn()
	assert_ne(main.world.season(), Seasons.Season.SPRING, "the world moved to another season")

	var after := _fill_sample(main.world)
	assert_ne(before, after, "the fills the view draws changed with the season")


## The colours the view would draw for a handful of land tiles. Sampled through
## the same function `_rebuild()` uses, so this cannot pass while the map on
## screen is painted some other way.
func _fill_sample(world: WorldMap) -> Array[Color]:
	var out: Array[Color] = []
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			continue
		out.append(HexMapView.tile_color(world.terrain_at(coord), world.forage_at(coord)))
		if out.size() >= 20:
			break
	return out


func test_neighbouring_hexes_are_adjacent_on_screen() -> void:
	# The layout bug that survives a screenshot glance is a spacing constant that
	# is nearly right: hexes overlap slightly, or leave hairline gaps, and it
	# reads as an art problem. Flat-top packing puts every neighbour's centre
	# exactly one hex-width away, so check that instead of eyeballing it.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)

	var view: HexMapView = main.get_node("HexMapView")
	var radius := view.hex_radius()
	assert_gt(radius, 0.0, "the map was fitted to the viewport")

	var expected := sqrt(3.0) * radius  # centre-to-centre for flat-top hexes
	var centre := HexGrid.from_offset(20, 15)
	for neighbor in main.world.grid.neighbors_in_bounds(centre):
		var gap := view.center_of(centre).distance_to(view.center_of(neighbor))
		assert_almost_eq(gap, expected, 0.001, "spacing to neighbour %s" % neighbor)


func test_the_whole_map_fits_in_the_viewport() -> void:
	# Fitting is the only navigation this scene has — no scroll, no zoom — so a
	# map that overflows is a map with tiles the player cannot see at all.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)

	var view: HexMapView = main.get_node("HexMapView")
	var size := main.get_viewport_rect().size
	var radius := view.hex_radius()
	# A flat-top hex is 2r wide and sqrt(3)r tall, so the two half-extents differ.
	var half_tall := sqrt(3.0) * 0.5 * radius

	for coord in main.world.grid.all_coords():
		var c := view.center_of(coord)
		assert_between(c.x, radius, size.x - radius, "tile %s sits inside the width" % coord)
		assert_between(c.y, half_tall, size.y - half_tall, "tile %s sits inside the height" % coord)


func test_a_click_lands_on_the_tile_it_is_drawn_over() -> void:
	# The hit test is the whole of "which tile was clicked", and the way it fails
	# is off-by-one rather than absent: a hex is not a rectangle, so a click near
	# a corner belongs to a different tile than the bounding box it sits in. The
	# check is the round trip — every tile centre must come back as its own tile,
	# and so must a point pushed most of the way toward a neighbour.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)

	var view: HexMapView = main.get_node("HexMapView")
	assert_gt(view.hex_radius(), 0.0, "the map was fitted before anything was clicked on it")

	for coord in main.world.grid.all_coords():
		assert_eq(
			view.coord_at_point(view.center_of(coord)),
			coord,
			"the centre of tile %s is on tile %s" % [coord, coord]
		)

	# Well inside the hex but nowhere near its centre — the region a rectangular
	# hit test gets wrong.
	var centre := HexGrid.from_offset(20, 15)
	for neighbor in main.world.grid.neighbors_in_bounds(centre):
		var toward := view.center_of(centre).lerp(view.center_of(neighbor), 0.4)
		assert_eq(view.coord_at_point(toward), centre, "a point 40%% of the way to %s" % neighbor)


func test_a_click_outside_the_map_is_reported_as_outside_the_map() -> void:
	# The legend and the margins are inside the window and on no tile at all.
	# Clamping to the nearest real tile would make the map's edge sticky, and
	# would make clicking the legend build something.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)

	var view: HexMapView = main.get_node("HexMapView")
	var grid: HexGrid = main.world.grid
	assert_false(grid.has_coord(view.coord_at_point(Vector2(-40.0, -40.0))), "above and left")
	var size := main.get_viewport_rect().size
	assert_false(grid.has_coord(view.coord_at_point(size + Vector2(40.0, 40.0))), "below and right")


func test_the_text_over_the_map_does_not_eat_the_clicks_under_it() -> void:
	# The status and prompt labels overlap the top rows of the map, and a
	# Label's default mouse filter is STOP — it would swallow a click before
	# `_unhandled_input` ever saw it. The hit-test checks above would not
	# notice, because they call `coord_at_point()` directly rather than
	# clicking through the GUI, so the filter itself is the thing to pin.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	for label_name in ["Status", "Prompt"]:
		var label: Control = main.get_node(label_name)
		assert_eq(
			label.mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"the %s label lets clicks through to the map" % label_name
		)


func test_the_selected_tile_is_outlined_in_a_colour_nothing_else_uses() -> void:
	# The selection has to read as "this one" rather than as another thing
	# standing on the tile, which is why it is unsaturated. Not evidence that it
	# is visible — that is the human criterion — but it catches the ring drifting
	# into a terrain colour during a palette tweak.
	var swatches := {
		"selection": HexMapView._SELECTION_COLOR,
		"route armed": HexMapView._ROUTE_ARMED_COLOR,
	}
	for name in swatches:
		for terrain in WorldGen.Terrain.values():
			var a: Color = swatches[name]
			var b: Color = HexMapView.TERRAIN_COLORS[terrain]
			var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			assert_gt(
				distance,
				MIN_COLOR_DISTANCE,
				"the %s ring is distinguishable from %s" % [name, HexMapView.TERRAIN_NAMES[terrain]]
			)
	var armed: Color = HexMapView._ROUTE_ARMED_COLOR
	var idle: Color = HexMapView._SELECTION_COLOR
	assert_gt(
		Vector3(armed.r - idle.r, armed.g - idle.g, armed.b - idle.b).length(),
		MIN_COLOR_DISTANCE,
		"a selection with a route started from it looks different from one without"
	)


# --- flows, not stocks -------------------------------------------------------
#
# The tests below are about the rates the map shows. Same caveat as everything
# above: they check that a difference exists and that it comes from the world,
# never that the difference reads as the thing it means.

## Turns to run before asking a view what the trends are. Past the chronicle's
## whole window, so a comparison between two views is comparing a full history
## rather than two worlds that have barely started.
const TREND_HORIZON := Chronicle.WINDOW * 2 + 2

## The frame budget an overlaid redraw has to stay inside. The same number
## `test_turn_advance.gd` holds the plain map to — an overlay that needed its own
## looser budget would be the finding rather than the feature.
const REDRAW_BUDGET_MSEC := 100.0


## The one test the ticket says is binding: a trend is history, and history the
## view kept for itself would not survive the view being thrown away.
func test_a_second_view_of_the_same_world_reports_the_same_trends() -> void:
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var first: HexMapView = main.get_node("HexMapView")
	var world: WorldMap = main.world

	for i in range(TREND_HORIZON):
		main.advance_turn()

	# Built now, having watched none of those turns happen.
	var second := HexMapView.new()
	add_child_autofree(second)
	second.show_world(world, main.get_viewport_rect().size)
	await wait_frames(2)

	var a := first.readout()
	var b := second.readout()
	assert_false(a.is_empty(), "the view has something to report")
	assert_eq(
		int(a["turns_recorded"]),
		Chronicle.WINDOW,
		"the comparison is over a full window rather than an empty one"
	)
	for key in a:
		assert_eq(b.get(key), a[key], "the two views agree about %s" % key)


func test_the_readout_is_the_world_talking_and_not_the_view() -> void:
	# The other half of the same claim, stated so it fails loudly if somebody
	# adds a member variable to hold a running total: every value the panel draws
	# has to be obtainable from the world alone.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")
	var world: WorldMap = main.world
	for i in range(TREND_HORIZON):
		main.advance_turn()

	var data := view.readout()
	assert_eq(int(data["people"]), world.citizen_count(), "people")
	assert_eq(int(data["held_up"]), world.held_up_count(), "held up")
	assert_almost_eq(data["granary_store"], world.total_granary_store(), 0.001, "store")
	assert_almost_eq(data["farm_yield"], world.farm_yield_rate(), 0.001, "yield")
	assert_eq(
		int(data["granary_store_trend"]),
		world.chronicle.trend(Chronicle.GRANARY_STORE),
		"the store's direction comes out of the ledger"
	)


func test_the_granary_reports_an_outflow_of_zero_rather_than_omitting_it() -> void:
	# AC4. Nothing consumes yet (#29), so the honest outflow is zero — and a
	# panel that simply left it out would be saying "nothing is leaving" and
	# "I do not track what leaves" in the same breath.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")
	for i in range(TREND_HORIZON):
		main.advance_turn()

	var data := view.readout()
	assert_true(data.has("granary_out"), "the outflow is a number the panel holds")
	assert_eq(data["granary_out"], 0.0, "and while nothing consumes, it is zero")
	assert_gt(data["granary_in"], 0.0, "against an inflow that is not")


func test_a_people_count_says_how_many_are_working_and_how_many_are_stuck() -> void:
	# AC1 and AC2's numeric half. The interesting number is the second one: a
	# citizen held up by a herd is the only place the wild world touches the
	# built one, and before this it was neither drawn nor counted.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")
	var world: WorldMap = main.world

	assert_gt(view.readout()["people"], 0, "there are people to count")
	assert_eq(view.readout()["held_up"], 0, "and on an open road, none of them are stuck")

	# Put an animal on top of somebody. Nothing else changes.
	var stopped: Citizen = world.citizens()[0]
	world.add_agent(Herd.new(9001, stopped.coord, Species.grazer(), 40.0))
	main.advance_turn()

	assert_true(stopped.is_held_up(), "the citizen under the herd could not move")
	assert_gt(view.readout()["held_up"], 0, "and the panel says somebody is held up")


func test_a_held_up_citizen_is_marked_in_a_colour_nothing_else_uses() -> void:
	# AC2's visual half. What can be checked is that the mark is not the same
	# colour as the figure it is drawn around, or as the ground under it.
	var against := {
		"a walking citizen": HexMapView._CITIZEN_FILL,
		"a laden citizen": HexMapView._CITIZEN_LOADED,
		"the road": HexMapView._ROAD_COLOR,
	}
	for terrain in WorldGen.Terrain.values():
		against["the " + HexMapView.TERRAIN_NAMES[terrain]] = HexMapView.TERRAIN_COLORS[terrain]
	for what in against:
		assert_gt(
			_separation(HexMapView._CITIZEN_HELD, against[what]),
			MIN_COLOR_DISTANCE,
			"the held-up ring is distinguishable from %s" % what
		)


func test_a_farm_in_spring_and_the_same_farm_in_winter_do_not_draw_alike() -> void:
	# AC3. The farm's square is filled by what its field grows this turn, so the
	# same structure on the same tile has to look different in two seasons.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var world: WorldMap = main.world
	var farm: CityNode = null
	for node in world.nodes:
		if node.kind == CityNode.Kind.FARM:
			farm = node
	assert_not_null(farm, "the generated world has a farm to look at")

	var by_season := {}
	for i in range(Seasons.TURNS_PER_YEAR):
		main.advance_turn()
		by_season[world.season()] = HexMapView.farm_fill_share(farm, world)

	gut.p("farm fill by season: %s" % by_season)
	assert_gt(
		absf(by_season[Seasons.Season.SPRING] - by_season[Seasons.Season.WINTER]),
		0.1,
		"a farm on a spring tile and a farm on a winter tile are filled differently"
	)


# --- the overlay -------------------------------------------------------------

func test_every_overlay_names_a_query_the_world_actually_answers() -> void:
	var world := WorldGen.generate(20260815)
	for entry in HexMapView.OVERLAYS:
		assert_true(
			world.has_method(String(entry["row"])),
			"overlay '%s' reads a method the world has" % entry["name"]
		)
		var row := HexMapView.overlay_row(world, entry)
		assert_eq(
			row.size(),
			world.grid.tile_count(),
			"overlay '%s' produces one value per tile" % entry["name"]
		)
		assert_gt(
			_separation(
				HexMapView.overlay_fill(entry, float(entry["min"])),
				HexMapView.overlay_fill(entry, float(entry["max"]))
			),
			MIN_COLOR_DISTANCE,
			"the two ends of overlay '%s' are told apart" % entry["name"]
		)


func test_every_overlay_caption_fits_the_panel_it_is_drawn_in() -> void:
	# The panel is a fixed width in from the right edge and the caption is drawn
	# at its left with no wrapping, so a caption longer than the panel runs off
	# the side of the window. That is how "forage — what the land feeds" shipped
	# as "forage — what the land fee". Caught here rather than in a frame,
	# because the next overlay's caption is written by whoever adds the entry.
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	for entry in HexMapView.OVERLAYS:
		var caption := String(entry["caption"])
		var width: float = font.get_string_size(
			caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		assert_lt(
			width,
			HexMapView.PANEL_INSET,
			"overlay '%s' caption %s fits in %d px, needs %d" % [
				entry["name"], caption, HexMapView.PANEL_INSET, width,
			]
		)


func test_a_second_scalar_is_an_entry_rather_than_a_new_system() -> void:
	# AC5's real requirement. This builds the vitality overlay #38 will add — not
	# as a preview of that ticket, but as proof that adding it is an array element
	# and nothing else. Note the argument: `vitality_data` takes a use, which is
	# the case a registry of bare method names would not have covered.
	var world := WorldGen.generate(20260815)
	var entry := {
		"name": "vitality",
		"caption": "vitality — how worn the grazing is",
		"row": "vitality_data",
		"args": [Land.Use.GRAZE],
		"min": Land.MIN_VITALITY,
		"max": Land.MAX_VITALITY,
		"low": Color(0.62, 0.16, 0.18),
		"high": Color(0.30, 0.80, 0.36),
	}

	var row := HexMapView.overlay_row(world, entry)
	assert_eq(row.size(), world.grid.tile_count(), "one value per tile, from a query taking an argument")
	assert_ne(
		HexMapView.overlay_fill(entry, Land.MIN_VITALITY),
		HexMapView.overlay_fill(entry, Land.MAX_VITALITY),
		"worn ground and fresh ground land on different ends of the ramp"
	)


func test_turning_the_overlay_on_repaints_the_land_and_leaves_the_sea() -> void:
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")
	var world: WorldMap = main.world

	var plain := {}
	for coord in world.grid.all_coords():
		plain[coord] = view.tile_fill(coord)

	assert_true(view.set_overlay_named("forage"), "the overlay is on")
	await wait_frames(2)

	var changed := 0
	for coord in world.grid.all_coords():
		var now := view.tile_fill(coord)
		if world.terrain_at(coord) == WorldGen.Terrain.WATER:
			assert_eq(now, plain[coord], "the sea keeps its colour under the overlay")
		elif now != plain[coord]:
			changed += 1
	assert_gt(changed, 0, "land tiles are painted by the overlay")

	# And off again, back to exactly the map that was there before.
	assert_true(view.set_overlay_named(""), "the overlay is off")
	await wait_frames(2)
	for coord in world.grid.all_coords():
		assert_eq(view.tile_fill(coord), plain[coord], "tile %s is back as it was" % coord)


func test_cycling_the_overlay_key_visits_every_entry_and_returns_to_none() -> void:
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")

	assert_true(view.active_overlay().is_empty(), "the map starts unoverlaid")
	var seen := []
	for i in range(HexMapView.OVERLAYS.size()):
		view.cycle_overlay()
		seen.append(String(view.active_overlay()["name"]))
	view.cycle_overlay()
	assert_true(view.active_overlay().is_empty(), "and cycles back off the end")
	assert_eq(seen.size(), HexMapView.OVERLAYS.size(), "every overlay is reachable from the key")


func test_an_unknown_overlay_name_is_refused_rather_than_ignored() -> void:
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")
	assert_false(view.set_overlay_named("fertility"), "a name that is not an overlay says so")


func test_the_overlay_redraws_inside_the_same_budget_the_plain_map_has() -> void:
	# The ticket's stated assumption, as an assertion: if a colour ramp over the
	# hex draw costs more than the frame budget, that is the finding.
	var main: Node2D = MainScene.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var view: HexMapView = main.get_node("HexMapView")

	view.set_overlay_named("forage")
	view.last_draw_usec = 0
	await wait_frames(2)
	var overlaid := float(view.last_draw_usec) / 1000.0

	gut.p("redraw with the forage overlay on: %.1fms (budget %.0fms)" % [
		overlaid, REDRAW_BUDGET_MSEC,
	])
	assert_gt(overlaid, 0.0, "the overlaid frame was actually drawn")
	assert_lt(overlaid, REDRAW_BUDGET_MSEC, "an overlaid redraw stays inside the frame budget")


# --- direction ---------------------------------------------------------------

func test_rising_falling_and_steady_are_three_different_marks() -> void:
	# AC6's palette half. The shapes differ too — a triangle up, a triangle down,
	# a flat bar — which is what carries the meaning when colour does not.
	assert_gt(
		_separation(HexMapView._TREND_RISING, HexMapView._TREND_FALLING),
		MIN_COLOR_DISTANCE,
		"rising and falling are not the same colour"
	)
	for moving in [HexMapView._TREND_RISING, HexMapView._TREND_FALLING]:
		assert_gt(
			_separation(moving, HexMapView._TREND_STEADY),
			MIN_COLOR_DISTANCE,
			"a moving quantity does not look like a still one"
		)


## Straight-line distance between two colours in RGB. The same measure the
## palette tests above use, pulled out so the newer ones can share it.
func _separation(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- the marks this turn's report puts on the map ----------------------------


func test_two_changes_on_one_tile_share_a_mark_that_names_them_both() -> void:
	# One herd can have a big turn: walk into different country *and* pass a
	# head-count mark, two entries in the report at one coordinate. Drawn a ring
	# and a number per entry, the second number lands exactly on the first and a
	# line of the report ends up pointing at a mark that is not on screen. The
	# tile gets one ring and reads out both numbers instead.
	var world := _herd_world()
	var herd := world.herds()[0]
	var before := TurnReport.snapshot(world)
	world.move_agent(herd, _FOREST)
	world.set_herd_population(herd, 51.0)
	var report := TurnReport.since(world, before)

	assert_eq(report.entries.size(), 2, "the herd crossed and grew, in one place")
	assert_eq(report.entries[0].coord, report.entries[1].coord, "both in the same place")

	var marks := HexMapView.change_marks(report)
	assert_eq(marks.size(), 1, "one ring on the tile, not two rings on top of each other")
	assert_eq(marks[0][0], _FOREST, "ringed where it happened")
	assert_eq(marks[0][1], "1,2", "the ring reads out both of the report's numbers")


func test_a_tile_with_one_change_is_labelled_with_just_its_number() -> void:
	var world := _herd_world()
	var before := TurnReport.snapshot(world)
	world.move_agent(world.herds()[0], _FOREST)
	var report := TurnReport.since(world, before)

	var marks := HexMapView.change_marks(report)
	assert_eq(marks.size(), 1, "one change, one mark")
	assert_eq(marks[0][1], "1", "no comma where there is nothing to join")


func test_changes_with_no_place_on_the_map_are_not_marked() -> void:
	# The season turning and the dropped-entry count happen everywhere and
	# nowhere. Drawing them somewhere would be inventing a location.
	var world := _herd_world()
	var report := TurnReport.new(1)
	report.entries = [
		TurnChange.new(TurnChange.NOWHERE, TurnChange.Kind.SEASON_TURNED, 4.0),
		TurnChange.new(TurnChange.NOWHERE, TurnChange.Kind.DROPPED, 3.0),
	]
	assert_eq(HexMapView.change_marks(report).size(), 0, "nothing placeless is drawn")
	assert_eq(HexMapView.change_marks(null).size(), 0, "and a world with no report draws nothing")
	assert_gt(world.grid.tile_count(), 0, "the world this ran against exists")


## A flat grass world with a forest tile beside a herd of 49 head, so one move
## crosses both the country and the fifty-head mark.
const _ORIGIN := Vector2i(3, 3)
const _FOREST := Vector2i(4, 3)


func _herd_world() -> WorldMap:
	var world := WorldMap.new(HexGrid.new(12, 10), 20260815)
	for coord in world.grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.GRASS)
	world.set_terrain(_FOREST, WorldGen.Terrain.FOREST)
	world.add_agent(Herd.new(1, _ORIGIN, Species.grazer(), 49.0))
	return world
