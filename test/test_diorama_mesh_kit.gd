extends GutTest
## Geometry invariants for the diorama's triangle accumulator.
##
## These exist because a spike frame that renders is not a spike frame that
## renders *correctly*: the scaffold's two-sided emission produced coincident
## coplanar triangles that z-fought, so roughly half of every surface shaded
## with an inward normal and took no directional light at all. The scene still
## drew — it just had no cast shadow, no plane separation, and speckle where
## the depth test tied. Nothing in a headless suite noticed.
##
## So the contract is asserted on the buffers instead of the picture, which
## keeps it runnable on a host with no rendering context (see capture.sh):
##
##   1. no two triangles occupy the same three positions   (nothing z-fights)
##   2. a closed primitive's faces all point away from it  (windings agree)
##
## Together those are what "single-sided, consistently wound" means in data.

const EPS := 1e-5


## Every triangle as [a, b, c], in emission order.
func _tris(kit: DioramaMeshKit) -> Array:
	var out: Array = []
	var v := kit.verts
	for i in range(0, v.size(), 3):
		out.append([v[i], v[i + 1], v[i + 2]])
	return out


## Position-set key: same three corners in any order collapse to one key, so a
## triangle and its reversed twin collide.
func _face_key(tri: Array) -> String:
	var pts: Array = []
	for p: Vector3 in tri:
		pts.append("%.4f,%.4f,%.4f" % [p.x, p.y, p.z])
	pts.sort()
	return "|".join(pts)


func _assert_no_coincident_faces(kit: DioramaMeshKit, what: String) -> void:
	var seen := {}
	var dupes := 0
	for tri in _tris(kit):
		var key := _face_key(tri)
		if seen.has(key):
			dupes += 1
		seen[key] = true
	assert_eq(dupes, 0,
			"%s emitted %d coincident triangle(s) — these z-fight, and the "
			% [what, dupes] +
			"loser shades with the wrong normal and takes no directional light")


## For a closed primitive, every face's STORED normal must point away from the
## solid's centroid. The stored normal is what the light uses, so this is the
## assertion that "the outside of this shape is lit like an outside".
func _assert_outward(kit: DioramaMeshKit, what: String) -> void:
	var centroid := Vector3.ZERO
	for v in kit.verts:
		centroid += v
	centroid /= maxf(1.0, float(kit.verts.size()))
	var inward := 0
	var first_bad := ""
	var v := kit.verts
	for i in range(0, v.size(), 3):
		var face_mid := (v[i] + v[i + 1] + v[i + 2]) / 3.0
		var outward := face_mid - centroid
		if outward.length_squared() < EPS:
			continue
		if kit.normals[i].dot(outward.normalized()) <= 0.0:
			inward += 1
			if first_bad == "":
				first_bad = " first at %v" % face_mid
	assert_eq(inward, 0,
			"%s has %d face(s) whose stored normal points inward%s — they "
			% [what, inward, first_bad] +
			"take no light on the side you actually see")


# --------------------------------------------------------------- the contract

func test_add_tri_emits_one_triangle() -> void:
	var kit := DioramaMeshKit.new()
	kit.add_tri(Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1), Color.WHITE)
	assert_eq(kit.verts.size(), 3,
			"a triangle is one triangle; a back face is a second surface at "
			+ "the same depth")


## Pins the engine convention this whole file exists because of: Godot treats
## the CLOCKWISE winding as front-facing, i.e. the one whose right-hand normal
## points away from the viewer. So a face that is visible AND correctly lit
## from outside must carry a stored normal that is the exact negation of its
## own emitted winding's right-hand normal. If a future Godot flips this, the
## diorama goes invisible and this test says why in one line.
func test_emitted_winding_is_opposite_its_stored_normal() -> void:
	var kit := DioramaMeshKit.new()
	kit.add_box(Transform3D.IDENTITY, Vector3.ONE, Color.WHITE)
	var v := kit.verts
	var n := kit.normals
	for i in range(0, v.size(), 3):
		var rh := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		if rh.length_squared() < EPS:
			continue
		assert_almost_eq(rh.normalized().dot(n[i]), -1.0, 1e-3,
				"winding/normal pair no longer matches Godot's clockwise "
				+ "front-face rule — geometry will cull or light inside-out")


func test_primitives_have_no_coincident_faces() -> void:
	for case in _primitive_cases():
		_assert_no_coincident_faces(case["kit"], case["name"])


func test_closed_primitives_are_wound_outward() -> void:
	for case in _primitive_cases():
		if not case["closed"]:
			continue
		_assert_outward(case["kit"], case["name"])


func test_full_scene_has_no_coincident_faces() -> void:
	# the real check: the composed diorama, not just the vocabulary
	var spike: DioramaSpike = load("res://game/diorama/spike.gd").new()
	spike._build()
	var terrain: MeshInstance3D = spike.get_node_or_null("Terrain")
	assert_not_null(terrain, "terrain never built")
	var arrays := terrain.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var seen := {}
	var dupes := 0
	for i in range(0, verts.size(), 3):
		var key := _face_key([verts[i], verts[i + 1], verts[i + 2]])
		if seen.has(key):
			dupes += 1
		seen[key] = true
	assert_eq(dupes, 0,
			"terrain mesh carries %d coincident triangle(s)" % dupes)
	spike.free()


func _primitive_cases() -> Array:
	var box := DioramaMeshKit.new()
	box.add_box(Transform3D.IDENTITY, Vector3(1.0, 2.0, 3.0), Color.WHITE)
	var tapered := DioramaMeshKit.new()
	tapered.add_tapered_box(Transform3D.IDENTITY, Vector3(2.0, 1.0, 2.0), 0.4,
			Color.WHITE)
	var prism := DioramaMeshKit.new()
	prism.add_prism(Transform3D.IDENTITY, 0.5, 1.5, Color.WHITE, 6, 0.15)
	var cone := DioramaMeshKit.new()
	cone.add_cone(Transform3D.IDENTITY, 0.6, 1.2, Color.WHITE, 7)
	var dome := DioramaMeshKit.new()
	dome.add_dome(Transform3D.IDENTITY, 0.8, 0.7, Color.WHITE, 10, 4)
	var blob := DioramaMeshKit.new()
	blob.add_blob(Transform3D.IDENTITY, 0.5, 0.75, Color.WHITE)
	return [
		{"name": "add_box", "kit": box, "closed": true},
		{"name": "add_tapered_box", "kit": tapered, "closed": true},
		{"name": "add_prism", "kit": prism, "closed": true},
		{"name": "add_cone", "kit": cone, "closed": true},
		# a hemisphere is open at its base; only the duplicate check applies
		{"name": "add_dome", "kit": dome, "closed": false},
		{"name": "add_blob", "kit": blob, "closed": false},
	]
