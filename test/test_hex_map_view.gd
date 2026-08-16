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
