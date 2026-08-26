extends GutTest
## The first style expressed as data rather than as a function.
##
## These assertions are structural on purpose. A tolerance against the old
## grammar.gd function would either be so loose it asserts nothing or so tight
## it freezes a proof-of-concept model the owner has called disposable — the
## thing under test is the vocabulary, not this specimen.

const SEED := 20260826


func _built(id: int) -> Array:
	var parts := DioramaCompose.build(DioramaStyles.residential(), SEED, id)
	DioramaCompose.apply_roles(parts, DioramaStyles.ROLES)
	return parts


func test_residential_is_one_to_three_body_and_roof_pairs() -> void:
	for id in range(12):
		var parts := _built(id)
		assert_between(parts.size(), 2, 6,
				"seed %d produced %d parts; expected 1-3 units of 2"
				% [id, parts.size()])
		assert_eq(parts.size() % 2, 0, "parts did not come in body/roof pairs")


func test_each_roof_sits_directly_on_its_own_body() -> void:
	var parts := _built(3)
	for i in range(0, parts.size(), 2):
		var body: Dictionary = parts[i]
		var roof: Dictionary = parts[i + 1]
		assert_almost_eq(roof["xf"].origin.y,
				body["xf"].origin.y + body["params"]["size"].y, 1e-5,
				"roof %d is not resting on its body" % i)
		assert_gt(roof["params"]["size"].x, body["params"]["size"].x,
				"roof should overhang its body")


func test_style_has_range_across_seeds() -> void:
	var sizes := {}
	for id in range(12):
		sizes[str(_built(id).size())] = true
	assert_gt(sizes.size(), 1,
			"twelve seeds produced buildings of one single size — no range")


func test_roles_resolve_to_palette_colours() -> void:
	for p: Dictionary in _built(1):
		assert_ne(p["color"], Color.MAGENTA,
				"a part kept its placeholder colour — role never resolved")


func test_same_seed_and_id_rebuild_identically() -> void:
	assert_eq(_built(5), _built(5), "same inputs produced different buildings")
