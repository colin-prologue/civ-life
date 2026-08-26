extends GutTest
## The specimen sheet: a grid of staged buildings, one camera, one light.
##
## The sheet is a SCENE rather than a montage of separate renders — one frame,
## no compositing step, deterministic by construction, and it drops onto the
## existing capture.sh --scene. These assertions cover structure only; whether
## the buildings are any good is the thing a human looks at the PNG to decide.


func test_lineup_builds_one_specimen_and_caption_per_cell() -> void:
	var scene: PackedScene = load("res://game/diorama/lineup.tscn")
	var lineup: Node3D = scene.instantiate()
	lineup.specimen_count = 6
	add_child_autofree(lineup)
	await wait_frames(2)
	var meshes := 0
	var labels := 0
	for child in lineup.get_children():
		if child is MeshInstance3D and child.name.begins_with("Specimen"):
			meshes += 1
		elif child is Label3D:
			labels += 1
	assert_eq(meshes, 6, "wrong number of specimens")
	assert_eq(labels, 6, "every specimen needs a caption or the sheet is unreadable")
	assert_not_null(lineup.get_node_or_null("Camera"), "no camera")
	assert_not_null(lineup.get_node_or_null("Sun"), "no light")


func test_specimens_are_laid_out_on_a_grid_without_overlap() -> void:
	var scene: PackedScene = load("res://game/diorama/lineup.tscn")
	var lineup: Node3D = scene.instantiate()
	lineup.specimen_count = 4
	lineup.columns = 2
	lineup.cell_size = 4.0
	add_child_autofree(lineup)
	await wait_frames(2)
	var seen := {}
	for child in lineup.get_children():
		if child is MeshInstance3D and child.name.begins_with("Specimen"):
			var key := "%.2f,%.2f" % [child.position.x, child.position.z]
			assert_false(seen.has(key), "two specimens share a cell at " + key)
			seen[key] = true
	assert_eq(seen.size(), 4, "specimens did not spread over the grid")


## A columns of 0 is reachable from the inspector, and the layout loop divides
## and mods by it. Guarding only the row count leaves the scene taking itself
## down on a value a human can type.
func test_zero_columns_does_not_take_the_scene_down() -> void:
	var scene: PackedScene = load("res://game/diorama/lineup.tscn")
	var lineup: Node3D = scene.instantiate()
	lineup.specimen_count = 3
	lineup.columns = 0
	add_child_autofree(lineup)
	await wait_frames(2)
	var built := 0
	for child in lineup.get_children():
		if child.name.begins_with("Specimen"):
			built += 1
	assert_eq(built, 3, "a zero columns should degrade to one column, not fail")


## The sheet is evidence, and evidence has to be reproducible from its own
## labels. The seed is fixed across every cell; the building id is what varies.
func test_captions_name_the_id_not_the_seed() -> void:
	var scene: PackedScene = load("res://game/diorama/lineup.tscn")
	var lineup: Node3D = scene.instantiate()
	lineup.specimen_count = 2
	add_child_autofree(lineup)
	await wait_frames(2)
	for child in lineup.get_children():
		if child is Label3D:
			assert_false((child as Label3D).text.begins_with("seed"),
					"caption calls the building id a seed — the seed is fixed")


## A negative columns is as reachable as zero, and it hits a different path:
## the stage is built from `columns * cell_size`, which goes negative and whose
## triangles are then discarded, leaving the specimens standing on nothing.
func test_a_negative_columns_still_builds_a_stage() -> void:
	var scene: PackedScene = load("res://game/diorama/lineup.tscn")
	var lineup: Node3D = scene.instantiate()
	lineup.specimen_count = 2
	lineup.columns = -1
	add_child_autofree(lineup)
	await wait_frames(2)
	var stage: MeshInstance3D = lineup.get_node_or_null("Stage")
	assert_not_null(stage, "no stage node")
	if stage != null:
		assert_gt(stage.mesh.surface_get_array_len(0), 0,
				"the stage has no geometry — its width went non-positive")
