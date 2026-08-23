extends GutTest
## S0 spike scaffold: determinism and structure, headless-checkable.
##
## The composition question (does it look like a monumental miniature) is
## human-judged from captured frames and NOT covered here — these tests pin
## the agent-verifiable half of ticket #17: same seed, same geometry; no
## sim/ involvement; the scene builds and contains what it claims.


func test_synth_valley_is_deterministic() -> void:
	var a := SynthValley.new(42)
	var b := SynthValley.new(42)
	assert_eq(a.height, b.height, "per-hex heights differ between builds")
	assert_eq(a.terrain, b.terrain, "terrain classes differ between builds")
	assert_eq(a.road, b.road, "road path differs between builds")
	assert_eq(a.sites, b.sites, "building sites differ between builds")


func test_different_seeds_differ() -> void:
	var a := SynthValley.new(42)
	var b := SynthValley.new(43)
	assert_ne(a.height, b.height, "different seeds produced identical worlds")


func test_geometry_fingerprints_are_stable() -> void:
	var a: DioramaSpike = load("res://game/diorama/spike.gd").new()
	var b: DioramaSpike = load("res://game/diorama/spike.gd").new()
	a._build()
	b._build()
	assert_eq(a.last_fingerprints, b.last_fingerprints,
			"same seed produced different generated geometry")
	assert_true(a.last_fingerprints.has("terrain"), "terrain never built")
	assert_true(a.last_fingerprints.has("settlement"), "settlement never built")
	assert_true(a.last_fingerprints.has("trees"), "trees never built")
	a.free()
	b.free()


func test_scene_builds_expected_structure() -> void:
	var scene: PackedScene = load("res://game/diorama/spike.tscn")
	var spike: DioramaSpike = scene.instantiate()
	add_child_autofree(spike)
	await wait_frames(2)
	assert_not_null(spike.get_node_or_null("Terrain"), "no terrain node")
	assert_not_null(spike.get_node_or_null("Settlement"), "no settlement node")
	assert_not_null(spike.get_node_or_null("Water"), "no water node")
	assert_not_null(spike.get_node_or_null("Camera"), "no camera node")
	assert_not_null(spike.get_node_or_null("Sun"), "no sun node")
	assert_not_null(spike.get_node_or_null("Env"), "no environment node")
	var terrain: MeshInstance3D = spike.get_node("Terrain")
	assert_gt(terrain.mesh.surface_get_array_len(0), 0, "terrain mesh empty")
	var settlement: MeshInstance3D = spike.get_node("Settlement")
	assert_gt(settlement.mesh.surface_get_array_len(0), 0,
			"settlement mesh empty")
	var trees_found := 0
	for child in spike.get_children():
		if child is MultiMeshInstance3D:
			trees_found += (child as MultiMeshInstance3D).multimesh.instance_count
	assert_gt(trees_found, 10, "vegetation is missing or not instanced")


func test_camera_fov_in_intent_range() -> void:
	var spike: DioramaSpike = load("res://game/diorama/spike.gd").new()
	assert_between(spike.fov_horizontal_deg, 15.0, 30.0,
			"default horizontal FOV outside the intent's long-lens range")
	spike.free()
