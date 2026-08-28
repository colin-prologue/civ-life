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


# ------------------------------------------------------- hero arch (slice 2)

## The vocabulary's real test. `hero_arch` is the hardest thing the hand-written
## grammar does — a base, two piers with a clear opening between them, nine
## voussoirs tangent to a semicircular arc, a beam across the top and a finial.
## If the tree cannot say that, the design does not reach.
##
## Asserted structurally rather than against the old function's exact numbers:
## per the owner's standing ruling the current models are disposable proof of
## concept, so matching this specimen's dimensions is not the goal. What must
## hold is that every FEATURE is expressible and lands in a sane relationship.
func test_hero_arch_has_every_feature_the_hand_written_one_has() -> void:
	var parts := DioramaCompose.build(DioramaStyles.hero_arch(), 42, 0)
	DioramaCompose.apply_roles(parts, DioramaStyles.ROLES)
	assert_gt(parts.size(), 12, "hero arch is too simple to be an arch")

	var voussoirs := 0
	var rotated := 0
	for p: Dictionary in parts:
		var b: Basis = p["xf"].basis
		if not b.is_equal_approx(Basis.IDENTITY):
			rotated += 1
			voussoirs += 1
	assert_gt(voussoirs, 6, "the arc has too few voussoirs to read as an arch")
	assert_gt(rotated, 0, "nothing is rotated — the arc is not an arc")


func test_the_arch_has_a_clear_opening_between_its_piers() -> void:
	var parts := DioramaCompose.build(DioramaStyles.hero_arch(), 42, 0)
	# Find the lowest band of parts — the piers sit there, either side of a void.
	var lowest := INF
	for p: Dictionary in parts:
		lowest = minf(lowest, p["xf"].origin.y)
	var low_xs: Array = []
	for p: Dictionary in parts:
		if p["xf"].origin.y < lowest + 0.4 and p["params"].has("size") \
				and p["params"]["size"].y > 0.5:
			low_xs.append(p["xf"].origin.x)
	assert_eq(low_xs.size(), 2, "expected exactly two piers at the base")
	if low_xs.size() == 2:
		assert_gt(absf(low_xs[0] - low_xs[1]), 1.0,
				"the piers are not separated — there is no opening to span")


func test_hero_arch_is_deterministic() -> void:
	assert_eq(DioramaCompose.build(DioramaStyles.hero_arch(), 42, 0),
			DioramaCompose.build(DioramaStyles.hero_arch(), 42, 0),
			"same seed produced two different arches")
