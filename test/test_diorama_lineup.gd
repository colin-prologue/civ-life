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
