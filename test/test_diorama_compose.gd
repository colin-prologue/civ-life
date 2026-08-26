extends GutTest
## Resolver invariants for the style-tree composer.
##
## These are asserted on returned data rather than on a picture, so they run on
## a host with no rendering context — the same reason test_diorama_mesh_kit.gd
## checks buffers instead of frames.

const SEED := 4242


func _ctx() -> Dictionary:
	return DioramaCompose.new_ctx(SEED, 7)


func _box(name: String, w: Variant, d: Variant, h: Variant) -> Dictionary:
	return {"mass": {"name": name, "kind": "box", "w": w, "d": d, "h": h,
			"role": "plaster"}}


func test_str_hash_is_stable_and_distinguishes() -> void:
	assert_eq(DioramaCompose.str_hash("body"), DioramaCompose.str_hash("body"),
			"same string hashed twice differs")
	assert_ne(DioramaCompose.str_hash("body"), DioramaCompose.str_hash("roof"),
			"different strings collided")


func test_channel_is_deterministic_and_in_range() -> void:
	var a := DioramaCompose.channel(SEED, 7, "block/unit/body", "w")
	var b := DioramaCompose.channel(SEED, 7, "block/unit/body", "w")
	assert_eq(a, b, "same channel gave two values")
	assert_between(a, 0.0, 1.0, "channel escaped [0,1]")


func test_channel_varies_by_path_purpose_and_building() -> void:
	var base := DioramaCompose.channel(SEED, 7, "block/unit/body", "w")
	assert_ne(base, DioramaCompose.channel(SEED, 7, "block/unit/roof", "w"),
			"two different nodes drew the same value")
	assert_ne(base, DioramaCompose.channel(SEED, 7, "block/unit/body", "h"),
			"two fields of one node drew the same value")
	assert_ne(base, DioramaCompose.channel(SEED, 8, "block/unit/body", "w"),
			"two buildings drew the same value")


func test_sample_scalar_is_fixed_and_range_is_inside_bounds() -> void:
	assert_eq(DioramaCompose.sample(0.75, SEED, 7, "p", "w", 1.0), 0.75,
			"a scalar spec was not returned verbatim")
	var v := DioramaCompose.sample([0.5, 1.5], SEED, 7, "p", "w", 1.0)
	assert_between(v, 0.5, 1.5, "sampled value escaped its range")
	assert_eq(DioramaCompose.sample(null, SEED, 7, "p", "w", 0.25), 0.25,
			"a missing spec did not fall back to the default")


func test_mass_emits_one_part_with_the_contract_keys() -> void:
	var out := DioramaCompose.resolve(_box("body", 1.0, 2.0, 3.0), _ctx())
	assert_eq(out["parts"].size(), 1, "a mass produced the wrong part count")
	var p: Dictionary = out["parts"][0]
	for key in ["kind", "xf", "params", "color", "tag", "y"]:
		assert_true(p.has(key), "part is missing contract key '%s'" % key)
	assert_eq(p["kind"], "box", "part kind was not carried through")
	assert_eq(p["params"]["size"], Vector3(1.0, 3.0, 2.0),
			"box size is (w, h, d) — check the axis order")


func test_mass_frame_reports_its_own_extent() -> void:
	var out := DioramaCompose.resolve(_box("body", 1.0, 2.0, 3.0), _ctx())
	assert_eq(out["frame"]["footprint"], Vector2(1.0, 2.0), "footprint wrong")
	assert_eq(out["frame"]["height"], 3.0, "frame height wrong")


func test_mass_with_a_zero_dimension_emits_nothing() -> void:
	var out := DioramaCompose.resolve(_box("body", 1.0, 0.0, 3.0), _ctx())
	assert_eq(out["parts"].size(), 0,
			"a degenerate mass still emitted a part")
	assert_eq(out["frame"]["height"], 0.0,
			"a degenerate mass claimed vertical extent")


func test_mass_inherits_the_incoming_footprint_when_it_omits_one() -> void:
	# A roof declares no w/d: it takes the frame it sits on, scaled by oversize.
	var ctx := _ctx()
	ctx["frame"]["footprint"] = Vector2(2.0, 4.0)
	var roof := {"mass": {"name": "roof", "kind": "box", "h": 0.5,
			"oversize": 1.5, "role": "ochre"}}
	var out := DioramaCompose.resolve(roof, ctx)
	assert_eq(out["frame"]["footprint"], Vector2(3.0, 6.0),
			"oversize did not scale the inherited footprint")


func _two_tier() -> Dictionary:
	return {"stack": {"name": "unit", "children": [
		_box("lower", 2.0, 2.0, 1.0),
		_box("upper", 1.0, 1.0, 3.0)]}}


func test_stack_sums_height_and_takes_the_widest_footprint() -> void:
	var out := DioramaCompose.resolve(_two_tier(), _ctx())
	assert_eq(out["parts"].size(), 2, "stack lost a child")
	assert_almost_eq(out["frame"]["height"], 4.0, 1e-5,
			"stack height is not the sum of its children")
	assert_eq(out["frame"]["footprint"], Vector2(2.0, 2.0),
			"stack footprint is not the widest child's")


func test_stack_places_each_child_on_top_of_the_one_below() -> void:
	var out := DioramaCompose.resolve(_two_tier(), _ctx())
	var lower: Dictionary = out["parts"][0]
	var upper: Dictionary = out["parts"][1]
	assert_almost_eq(lower["xf"].origin.y, 0.0, 1e-5,
			"first child should sit on the incoming base plane")
	assert_almost_eq(upper["xf"].origin.y, 1.0, 1e-5,
			"second child should sit on top of the first, at its height")


func test_a_zero_height_child_does_not_lift_its_successor() -> void:
	var tree := {"stack": {"name": "unit", "children": [
		_box("ghost", 1.0, 1.0, 0.0),
		_box("real", 1.0, 1.0, 2.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_eq(out["parts"].size(), 1, "the degenerate child emitted a part")
	assert_almost_eq(out["parts"][0]["xf"].origin.y, 0.0, 1e-5,
			"a zero-height child still pushed its successor upward")


func test_adding_a_named_sibling_does_not_disturb_the_others() -> void:
	# The whole reason channels are keyed on names. If this fails, someone has
	# reintroduced index-based hashing and every edit will reshuffle the town.
	var before := DioramaCompose.resolve(
			{"stack": {"name": "unit", "children": [
				_box("body", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0]),
				_box("roof", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0])]}}, _ctx())
	var after := DioramaCompose.resolve(
			{"stack": {"name": "unit", "children": [
				_box("porch", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0]),
				_box("body", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0]),
				_box("roof", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0])]}}, _ctx())
	assert_eq(before["parts"][0]["params"]["size"],
			after["parts"][1]["params"]["size"],
			"inserting 'porch' re-rolled 'body'")
	assert_eq(before["parts"][1]["params"]["size"],
			after["parts"][2]["params"]["size"],
			"inserting 'porch' re-rolled 'roof'")
