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


func test_row_advances_by_a_fraction_of_the_previous_width() -> void:
	var tree := {"row": {"name": "block", "advance": 0.5, "children": [
		_box("a", 2.0, 1.0, 1.0),
		_box("b", 2.0, 1.0, 1.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	# Asserted as a STEP rather than as absolute positions: a row centres itself
	# on the transform it was handed, so where the pair sits depends on the
	# group's extent, while the step between them is the thing `advance` means.
	var step: float = out["parts"][1]["xf"].origin.x - out["parts"][0]["xf"].origin.x
	assert_almost_eq(step, 1.0, 1e-5,
			"advance 0.5 on width-2 children should step 1.0, not 2.0")


func test_row_template_repeats_with_distinct_channels_per_index() -> void:
	var tree := {"row": {"name": "block", "count": 3, "advance": 1.0,
			"of": _box("unit", [1.0, 3.0], 1.0, 1.0)}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_eq(out["parts"].size(), 3, "count did not repeat the template")
	var w0: float = out["parts"][0]["params"]["size"].x
	var w1: float = out["parts"][1]["params"]["size"].x
	assert_ne(w0, w1, "repeated units are identical — index is not in the channel")


func test_row_template_growing_count_does_not_disturb_earlier_units() -> void:
	# The row analogue of test_adding_a_named_sibling_does_not_disturb_the_others
	# above: this branch's central claim is that channels are keyed on a
	# NAME path rather than an index path, and it is precisely as fragile
	# here as it is for a stack — growing a templated row's count must not
	# re-roll the units that were already there, because each repeat's
	# channel is keyed on its own indexed name ("unit0", "unit1", ...) rather
	# than on the total count.
	var two := DioramaCompose.resolve(
			{"row": {"name": "block", "count": 2, "advance": 1.0, "of":
				_box("unit", [1.0, 3.0], [1.0, 3.0], [1.0, 3.0])}}, _ctx())
	var three := DioramaCompose.resolve(
			{"row": {"name": "block", "count": 3, "advance": 1.0, "of":
				_box("unit", [1.0, 3.0], [1.0, 3.0], [1.0, 3.0])}}, _ctx())
	assert_eq(two["parts"][0]["params"]["size"], three["parts"][0]["params"]["size"],
			"growing count from 2 to 3 re-rolled the first unit")
	assert_eq(two["parts"][1]["params"]["size"], three["parts"][1]["params"]["size"],
			"growing count from 2 to 3 re-rolled the second unit")


func test_row_with_zero_count_is_legal_and_empty() -> void:
	var tree := {"row": {"name": "block", "count": 0, "advance": 1.0,
			"of": _box("unit", 1.0, 1.0, 1.0)}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_eq(out["parts"].size(), 0, "count 0 still produced parts")
	assert_eq(out["frame"]["height"], 0.0, "an empty row claimed height")
	assert_eq(out["frame"]["footprint"], Vector2.ZERO,
			"an empty row claimed a footprint")


func test_row_frame_spans_its_children_and_takes_the_tallest() -> void:
	var tree := {"row": {"name": "block", "advance": 1.0, "children": [
		_box("a", 2.0, 1.0, 1.0),
		_box("b", 2.0, 3.0, 5.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_almost_eq(out["frame"]["footprint"].x, 4.0, 1e-5,
			"row width should span first near edge to last far edge")
	assert_almost_eq(out["frame"]["footprint"].y, 3.0, 1e-5,
			"row depth should be its deepest child")
	assert_almost_eq(out["frame"]["height"], 5.0, 1e-5,
			"row height should be its tallest child")


func test_row_frame_spans_true_edges_with_unequal_widths() -> void:
	# test_row_frame_spans_its_children_and_takes_the_tallest above uses two
	# EQUAL-width children, so "far edge of the last child minus the row's own
	# origin" and "true near-edge-to-far-edge span" come out equal by
	# coincidence and the bug they are meant to catch is invisible. A wide
	# first child and a narrower last child pulls them apart. `a` is 4 wide,
	# centred on the row origin, so it occupies [-2, 2]. `b` is 2 wide and sits
	# flush against it — the cursor steps by half of each, (2 + 1) = 3 — so it
	# occupies [2, 4]. The true span is -2..4, i.e. 6, centred on +1. The old
	# "row origin to the last child's far edge" arithmetic reported 5.
	var tree := {"row": {"name": "block", "advance": 1.0, "children": [
		_box("a", 4.0, 1.0, 1.0),
		_box("b", 2.0, 1.0, 1.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_almost_eq(out["frame"]["footprint"].x, 6.0, 1e-5,
			"row width should span the first child's near edge to the last "
			+ "child's far edge, not the origin to the last child's far edge")
	# The frame's origin is the transform the row was handed — the row centres
	# its geometry there rather than growing away from it.
	assert_almost_eq(out["frame"]["xf"].origin.x, 0.0, 1e-5,
			"a row's frame should stay on the transform it was handed")
	var a_lo: float = out["parts"][0]["xf"].origin.x \
			- out["parts"][0]["params"]["size"].x * 0.5
	var b_hi: float = out["parts"][1]["xf"].origin.x \
			+ out["parts"][1]["params"]["size"].x * 0.5
	assert_almost_eq((a_lo + b_hi) * 0.5, 0.0, 1e-5,
			"the row's geometry is not centred")


func _tower() -> Dictionary:
	return {"stack": {"name": "tower", "children": [
		_box("plinth", 4.0, 4.0, 1.0),
		_box("shaft", 3.0, 3.0, 6.0),
		{"mass": {"name": "spire", "kind": "cone", "w": 0.4, "d": 0.4,
				"h": 3.0, "role": "brass"}}]}}


func test_build_tags_every_part() -> void:
	for p: Dictionary in DioramaCompose.build(_tower(), SEED, 1):
		assert_ne(p["tag"], "", "a part came back untagged")


func test_tag_bands_follow_height() -> void:
	var parts := DioramaCompose.build(_tower(), SEED, 1)
	assert_eq(parts[0]["tag"], "base", "the bottom part is not tagged base")
	assert_eq(parts[1]["tag"], "mid", "the middle part is not tagged mid")


func test_a_small_cone_on_top_is_an_accent() -> void:
	var parts := DioramaCompose.build(_tower(), SEED, 1)
	assert_eq(parts[2]["tag"], "accent",
			"a slim cone above the mass should read as an accent")


func test_y_is_the_part_centre_height() -> void:
	var parts := DioramaCompose.build(_tower(), SEED, 1)
	assert_almost_eq(parts[0]["y"], 0.5, 1e-5, "plinth centre should be h/2")
	assert_almost_eq(parts[1]["y"], 4.0, 1e-5, "shaft centre should be 1 + 6/2")


func test_tags_are_monotonic_in_height() -> void:
	# The property the ruin filter depends on: nothing tagged base sits above
	# anything tagged upper. Uses its own four-box fixture rather than _tower()
	# — the tower tops out in `mid` and `accent`, so running this against it
	# would pass without ever comparing a base to an upper.
	var tall := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("b", 2.0, 2.0, 2.0),
		_box("c", 2.0, 2.0, 2.0), _box("d", 2.0, 2.0, 2.0)]}}
	var parts := DioramaCompose.build(tall, SEED, 1)
	var highest_base := -INF
	var lowest_upper := INF
	for p: Dictionary in parts:
		if p["tag"] == "base":
			highest_base = maxf(highest_base, p["y"])
		elif p["tag"] == "upper":
			lowest_upper = minf(lowest_upper, p["y"])
	assert_gt(highest_base, -INF, "fixture produced no base part to compare")
	assert_lt(lowest_upper, INF, "fixture produced no upper part to compare")
	assert_lt(highest_base, lowest_upper,
			"a base part sits above an upper part")


## A mass stacked on a row has to land over the row's CENTRE, not over the
## transform the row was handed.
##
## `_row` returns a frame whose `xf` is the true centre of its children — it
## has to, because a row of unequal widths advancing by a fraction of each
## width does not end up centred on where it started. `_stack` was handing
## every child `base_xf` and reading only the child's footprint, so the roof
## came out correctly SIZED and in the wrong PLACE: over a 4/1/2 terrace
## spanning -2..6 it sat at -4..4, overhanging empty ground on one side and
## leaving the last unit bare. Nothing caught it because the shipped
## `residential` puts its roofs inside each unit's stack, with the row on the
## outside — the arrangement that breaks is the one slice 2 reaches for first.
func test_a_mass_stacked_on_a_row_is_centred_over_it() -> void:
	var tree := {"stack": {"name": "terrace", "children": [
		{"row": {"name": "units", "advance": 1.0, "children": [
			_box("a", 4.0, 2.0, 1.0),
			_box("b", 1.0, 2.0, 1.0),
			_box("c", 2.0, 2.0, 1.0)]}},
		{"mass": {"name": "roof", "kind": "box", "h": 0.5, "role": "ochre"}}]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	var roof: Dictionary = out["parts"][3]
	# Units are 4, 1 and 2 wide, each flush against the last: a occupies
	# [-2, 2], b steps by (2 + 0.5) to occupy [2, 3], c steps by (0.5 + 1) to
	# occupy [3, 5]. The terrace is therefore -2..5 — 7 wide, centred on +1.5.
	# The terrace centres itself, so both it and the roof sit on the stack's
	# own axis; what matters is that they coincide and that the roof covers it.
	var t_lo := INF
	var t_hi := -INF
	for i in range(3):
		var half: float = out["parts"][i]["params"]["size"].x * 0.5
		t_lo = minf(t_lo, out["parts"][i]["xf"].origin.x - half)
		t_hi = maxf(t_hi, out["parts"][i]["xf"].origin.x + half)
	assert_almost_eq(roof["xf"].origin.x, (t_lo + t_hi) * 0.5, 1e-5,
			"roof did not land over the terrace's centre")
	assert_almost_eq(roof["params"]["size"].x, t_hi - t_lo, 1e-5,
			"roof did not span the whole terrace")


## The mirror of test_a_mass_stacked_on_a_row_is_centred_over_it: a row whose
## child reports a centre of its own has to follow it too, or the outer row
## reports bounds that do not cover its own geometry.
func test_a_row_follows_a_nested_row_s_reported_centre() -> void:
	var inner := {"row": {"name": "inner", "advance": 1.0, "children": [
		_box("wide", 4.0, 2.0, 1.0),
		_box("narrow", 1.0, 2.0, 1.0)]}}
	# inner: wide sits at 0 spanning [-2, 2]; narrow is 1 wide and flush against
	# it, stepping by (2 + 0.5), so it occupies [2, 3]. inner spans [-2, 3] —
	# width 5, centre +0.5, which is half a unit to the RIGHT of the transform
	# it was handed.
	var outer := {"row": {"name": "outer", "advance": 1.0, "children": [
		inner,
		_box("tail", 2.0, 2.0, 1.0)]}}
	var out := DioramaCompose.resolve(outer, _ctx())
	# outer: inner really occupies [-2, 3]. Placing tail flush means its near
	# edge meets inner's far edge at 3, so tail occupies [3, 5] — which needs
	# inner's centre offset (+0.5), not just its width, or tail lands at
	# [2.5, 4.5] and overlaps by half a unit at advance 1.0. Union is [-2, 5]:
	# width 7, centre +1.5.
	assert_almost_eq(out["frame"]["footprint"].x, 7.0, 1e-5,
			"outer row's span ignored the nested row's real extent")
	assert_almost_eq(out["frame"]["xf"].origin.x, 0.0, 1e-5,
			"a row's frame should stay on the transform it was handed")


## An optional child that resolves to nothing must not widen the row it is in.
## `count: 0` is the supported way for a style to say "sometimes absent", so a
## row carrying one has to come out the same size as a row without it.
func test_an_empty_child_does_not_widen_a_row() -> void:
	var absent := {"row": {"name": "maybe", "count": 0, "advance": 1.0,
			"of": _box("unit", 1.0, 1.0, 1.0)}}
	var with_gap := {"row": {"name": "outer", "advance": 1.0, "children": [
		_box("real", 2.0, 2.0, 1.0), absent]}}
	var without := {"row": {"name": "outer", "advance": 1.0, "children": [
		_box("real", 2.0, 2.0, 1.0)]}}
	var a := DioramaCompose.resolve(with_gap, _ctx())
	var b := DioramaCompose.resolve(without, _ctx())
	assert_almost_eq(a["frame"]["footprint"].x, b["frame"]["footprint"].x, 1e-5,
			"an empty child widened the row")
	assert_almost_eq(a["frame"]["xf"].origin.x, b["frame"]["xf"].origin.x, 1e-5,
			"an empty child pushed the row off centre")


## A row whose declared children ALL resolve to nothing must report a zero
## frame, not -INF and NaN. Guarding the accumulation but then testing the
## declared child count instead of whether anything accumulated leaves the
## sentinels in place, and an enclosing row's cursor goes infinite.
func test_a_row_of_only_empty_children_is_a_zero_frame() -> void:
	var nothing := {"row": {"name": "gone", "count": 0, "advance": 1.0,
			"of": _box("unit", 1.0, 1.0, 1.0)}}
	var all_empty := {"row": {"name": "outer", "advance": 1.0, "children": [
		nothing, _box("ghost", 1.0, 1.0, 0.0)]}}
	var out := DioramaCompose.resolve(all_empty, _ctx())
	assert_eq(out["parts"].size(), 0, "an all-empty row produced parts")
	assert_eq(out["frame"]["footprint"], Vector2.ZERO,
			"an all-empty row reported a non-zero footprint")
	assert_eq(out["frame"]["height"], 0.0, "an all-empty row claimed height")
	assert_true(is_finite(out["frame"]["xf"].origin.x),
			"an all-empty row's centre is not a finite number")


## And it must not poison a row that contains it alongside real geometry.
func test_an_all_empty_row_does_not_poison_its_parent() -> void:
	var nothing := {"row": {"name": "gone", "count": 0, "advance": 1.0,
			"of": _box("unit", 1.0, 1.0, 1.0)}}
	var mixed := {"row": {"name": "outer", "advance": 1.0, "children": [
		nothing, _box("real", 2.0, 2.0, 1.0)]}}
	var out := DioramaCompose.resolve(mixed, _ctx())
	assert_almost_eq(out["frame"]["footprint"].x, 2.0, 1e-5,
			"an all-empty child changed the parent's width")
	assert_true(is_finite(out["parts"][0]["xf"].origin.x),
			"the real child got a non-finite transform")


## `advance` is documented as "1.0 is flush, below overlaps, above gaps". That
## is only true when neighbours are the same width: stepping by the PRECEDING
## width alone leaves a width-4 child and a width-2 child one unit apart at
## advance 1.0. residential samples every unit's width independently, so its
## intended 5% overlap can come out as a visible gap — which is what the
## committed specimen sheet shows on several cells.
func test_row_advance_is_measured_between_adjacent_edges() -> void:
	var tree := {"row": {"name": "block", "advance": 1.0, "children": [
		_box("wide", 4.0, 2.0, 1.0),
		_box("narrow", 2.0, 2.0, 1.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	# wide occupies [-2, 2]; flush means narrow's near edge is at 2, so its
	# centre is 3 — a step of (4 + 2) / 2, not of 4.
	var step2: float = out["parts"][1]["xf"].origin.x - out["parts"][0]["xf"].origin.x
	assert_almost_eq(step2, 3.0, 1e-5,
			"row stepped by the preceding width alone, leaving a gap")
	assert_almost_eq(out["frame"]["footprint"].x, 6.0, 1e-5,
			"row span should be the two children flush against each other")


## A cone or prism is emitted as a circle of radius w/2 — `d` never reaches the
## renderer. Reporting a frame of (w, d) therefore describes geometry that does
## not exist, and anything stacking on it inherits the lie.
func test_a_round_mass_reports_the_footprint_it_actually_occupies() -> void:
	var tree := {"mass": {"name": "spire", "kind": "cone",
			"w": 2.0, "d": 5.0, "h": 3.0, "role": "brass"}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_eq(out["frame"]["footprint"], Vector2(2.0, 2.0),
			"round mass reported its declared depth, not its emitted radius")


## Flush placement has to use where a child's edges ACTUALLY are, which for a
## composite is not derivable from its width alone. A nested row of unequal
## widths reports a centre off its own origin; stepping by widths alone then
## overlaps it even at advance 1.0, which is meant to be exactly flush.
func test_a_composite_neighbour_is_placed_from_its_real_edge() -> void:
	var inner := {"row": {"name": "inner", "advance": 1.0, "children": [
		_box("wide", 4.0, 2.0, 1.0),
		_box("narrow", 1.0, 2.0, 1.0)]}}
	# inner: wide [-2, 2], narrow flush at [2, 3]. Far edge 3, centre +0.5.
	var tree := {"row": {"name": "outer", "advance": 1.0, "children": [
		inner, _box("tail", 2.0, 2.0, 1.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	var tail: Dictionary = out["parts"][2]
	# tail is 2 wide, so flush against inner's far edge of 3 puts its centre
	# at 4. Ignoring inner's +0.5 offset would land it at 3.5 — a half-unit
	# overlap at the one advance value that is supposed to mean "touching".
	# Flush means zero clearance between inner's far edge and tail's near edge,
	# wherever the centred group as a whole ends up sitting.
	var inner_hi := -INF
	for i in range(2):
		inner_hi = maxf(inner_hi, out["parts"][i]["xf"].origin.x
				+ out["parts"][i]["params"]["size"].x * 0.5)
	var tail_lo: float = tail["xf"].origin.x - tail["params"]["size"].x * 0.5
	assert_almost_eq(tail_lo - inner_hi, 0.0, 1e-5,
			"a composite neighbour was placed from its width, not its edge")


# ------------------------------------------------------------------ ring

## The go/no-go for the whole vocabulary: voussoirs tangent to an arc.
##
## This began as a golden comparison against the hand-written hero_arch recipe,
## which was known to look right, and it passed at zero position and zero basis
## delta. That referent is gone now — the hardcoded recipes were the thing
## slice 2 removed — so the property it was really checking is asserted
## directly instead: each voussoir's long axis is PERPENDICULAR to its own
## radius, which is what "tangent" means. That is a stronger check than
## agreeing with another implementation, because it cannot both be wrong in the
## same way.
##
## The lab finding it encodes: voussoirs lie tangent, not radial. Radial
## orientation makes an M-shaped scallop rather than an arch.
func test_ring_lays_its_children_tangent_to_the_arc() -> void:
	var radius := 2.0
	var out := DioramaCompose.resolve({"ring": {"name": "span",
			"radius": radius, "from": 0.0, "to": PI, "count": 9,
			"of": {"mass": {"name": "voussoir", "kind": "box",
					"w": 0.4, "d": 0.6, "role": "plaster"}}}},
			DioramaCompose.new_ctx(42, 0))
	var parts: Array = out["parts"]
	assert_eq(parts.size(), 9, "ring produced the wrong number of voussoirs")
	var seen_angles: Array = []
	for i in range(parts.size()):
		var xf: Transform3D = parts[i]["xf"]
		var size: Vector3 = parts[i]["params"]["size"]
		# Centre of the voussoir: the box builds upward from its own origin.
		var centre: Vector3 = xf * Vector3(0, size.y * 0.5, 0)
		var radial := Vector2(centre.x, centre.y).normalized()
		var long_axis := Vector2(xf.basis.y.x, xf.basis.y.y).normalized()
		assert_almost_eq(absf(radial.dot(long_axis)), 0.0, 1e-4,
				"voussoir %d is not tangent — its long axis is not "
				% i + "perpendicular to its own radius")
		assert_almost_eq(Vector2(centre.x, centre.y).length(), radius, 1e-4,
				"voussoir %d does not sit on the arc" % i)
		seen_angles.append(atan2(centre.y, centre.x))
	# Evenly spaced across the half-turn, in order.
	for i in range(1, seen_angles.size()):
		var d: float = seen_angles[i] - seen_angles[i - 1]
		assert_almost_eq(d, PI / 9.0, 1e-4,
				"voussoirs %d and %d are not evenly spaced" % [i - 1, i])


## A ring's footprint has to describe the geometry it actually emitted, not the
## circle it was described by: tangent boxes stick out past the arc by half
## their thickness, so 2*radius under-reports by ~14% on this arch.
func test_ring_reports_the_footprint_it_actually_occupies() -> void:
	var ctx := DioramaCompose.new_ctx(7, 0)
	var out := DioramaCompose.resolve({"ring": {"name": "span",
			"radius": 2.0, "from": 0.0, "to": PI, "count": 9,
			"of": {"mass": {"name": "v", "kind": "box", "w": 0.4, "d": 0.4,
					"role": "plaster"}}}}, ctx)
	assert_gt(out["frame"]["footprint"].x, 4.0,
			"ring reported 2*radius, ignoring the thickness of its own parts")
	assert_lt(out["frame"]["footprint"].x, 4.5,
			"ring footprint is implausibly large for radius 2 thickness 0.4")


## `advance` is a ratio, so it cannot say "these two are a specific distance
## apart". The arch's piers need exactly that: their clear opening is a real
## dimension of the building, and expressing it as a ratio would make the style
## carry `w/t - 1` — a number derived from other sampled dimensions, which no
## author can write as a literal.
func test_row_gap_is_an_absolute_edge_to_edge_distance() -> void:
	var tree := {"row": {"name": "piers", "gap": 3.0, "children": [
		_box("left", 1.0, 1.0, 2.0),
		_box("right", 1.0, 1.0, 2.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	# left occupies [-0.5, 0.5]; a clear gap of 3 puts right's near edge at 3.5,
	# so its centre is 4.0 — regardless of how wide either pier happens to be.
	var left_far: float = out["parts"][0]["xf"].origin.x \
			+ out["parts"][0]["params"]["size"].x * 0.5
	var right_near: float = out["parts"][1]["xf"].origin.x \
			- out["parts"][1]["params"]["size"].x * 0.5
	assert_almost_eq(right_near - left_far, 3.0, 1e-5,
			"gap was not measured edge to edge")
	assert_almost_eq(out["frame"]["footprint"].x, 5.0, 1e-5,
			"row span should cover both piers and the opening between them")


func test_row_gap_holds_when_the_children_differ_in_width() -> void:
	var tree := {"row": {"name": "piers", "gap": 2.0, "children": [
		_box("fat", 4.0, 1.0, 1.0),
		_box("thin", 1.0, 1.0, 1.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	# fat occupies [-2, 2]; clear gap 2 puts thin's near edge at 4, centre 4.5.
	var fat_far: float = out["parts"][0]["xf"].origin.x \
			+ out["parts"][0]["params"]["size"].x * 0.5
	var thin_near: float = out["parts"][1]["xf"].origin.x \
			- out["parts"][1]["params"]["size"].x * 0.5
	assert_almost_eq(thin_near - fat_far, 2.0, 1e-5,
			"gap should be independent of the children's widths")


## A node occupies a box CENTRED on the transform it was handed. `_row` built
## rightward from its first child instead, so a symmetric pair came back
## centred half its own span to the right — and in a stack, everything above it
## inherited that offset. The hero arch showed it plainly: the plinth sat under
## nothing, and the arch floated off to one side of its own base.
func test_a_row_is_centred_on_the_transform_it_was_handed() -> void:
	var tree := {"row": {"name": "piers", "gap": 2.0, "children": [
		_box("left", 1.0, 1.0, 2.0),
		_box("right", 1.0, 1.0, 2.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_almost_eq(out["frame"]["xf"].origin.x, 0.0, 1e-5,
			"a row's frame should be centred where it was placed")
	var lo := INF
	var hi := -INF
	for p: Dictionary in out["parts"]:
		var half: float = p["params"]["size"].x * 0.5
		lo = minf(lo, p["xf"].origin.x - half)
		hi = maxf(hi, p["xf"].origin.x + half)
	assert_almost_eq((lo + hi) * 0.5, 0.0, 1e-5,
			"the row's geometry is not centred on its origin")
	assert_almost_eq(hi - lo, 4.0, 1e-5, "span changed unexpectedly")


func test_a_ring_is_centred_on_the_transform_it_was_handed() -> void:
	var out := DioramaCompose.resolve({"ring": {"name": "span",
			"radius": 2.0, "from": 0.0, "to": PI, "count": 9,
			"of": {"mass": {"name": "v", "kind": "box", "w": 0.4, "d": 0.4,
					"role": "plaster"}}}}, _ctx())
	assert_almost_eq(out["frame"]["xf"].origin.x, 0.0, 1e-5,
			"a ring's frame should be centred where it was placed")


## `setback` shrinks each successive child of a stack relative to the one below
## — a stepped monument's tiers. Held back from slice 1 because nothing called
## it; `stepped` calls it now.
func test_stack_setback_shrinks_each_tier_against_the_one_below() -> void:
	var tree := {"stack": {"name": "ziggurat", "setback": 0.25, "children": [
		_box("t0", 4.0, 4.0, 1.0),
		{"mass": {"name": "t1", "kind": "box", "h": 1.0, "role": "plaster"}},
		{"mass": {"name": "t2", "kind": "box", "h": 1.0, "role": "plaster"}}]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	var w0: float = out["parts"][0]["params"]["size"].x
	var w1: float = out["parts"][1]["params"]["size"].x
	var w2: float = out["parts"][2]["params"]["size"].x
	assert_almost_eq(w1, w0 * 0.75, 1e-5, "tier 1 did not set back from tier 0")
	assert_almost_eq(w2, w1 * 0.75, 1e-5, "setback did not compound per tier")


func test_setback_leaves_a_child_that_states_its_own_width_alone() -> void:
	# Setback shrinks what a child INHERITS. A child that declares a width means
	# that width, or a style could never break the taper deliberately.
	var tree := {"stack": {"name": "s", "setback": 0.5, "children": [
		_box("a", 4.0, 4.0, 1.0),
		_box("b", 3.0, 3.0, 1.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_almost_eq(out["parts"][1]["params"]["size"].x, 3.0, 1e-5,
			"setback overrode a width the child stated explicitly")


## A portico is a colonnade standing IN FRONT OF a hall — side by side in
## depth, not stacked and not side by side in width. Same row semantics, other
## axis.
func test_a_row_can_run_along_z() -> void:
	var tree := {"row": {"name": "portico", "axis": "z", "children": [
		_box("colonnade", 3.0, 1.0, 2.0),
		_box("hall", 3.0, 2.0, 3.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	var dz: float = out["parts"][1]["xf"].origin.z - out["parts"][0]["xf"].origin.z
	assert_almost_eq(dz, 1.5, 1e-5,
			"children should step along z by half of each depth")
	assert_almost_eq(out["parts"][0]["xf"].origin.x,
			out["parts"][1]["xf"].origin.x, 1e-5,
			"a z-row should not spread its children in x")
	assert_almost_eq(out["frame"]["footprint"].y, 3.0, 1e-5,
			"a z-row's depth should span its children")
	assert_almost_eq(out["frame"]["footprint"].x, 3.0, 1e-5,
			"a z-row's width should be its widest child, not their sum")


## A ring built its parts with `params.size` whatever kind the template
## declared, so a documented ring-of-columns emitted kind "prism" with box
## params and `emit()` died on a missing `radius`. Rings go through the same
## kind-aware path masses do.
func test_a_ring_of_round_primitives_gets_round_params() -> void:
	var out := DioramaCompose.resolve({"ring": {"name": "colonnade",
			"radius": 3.0, "from": 0.0, "to": PI, "count": 4,
			"of": {"mass": {"name": "column", "kind": "prism",
					"w": 0.5, "d": 0.5, "role": "plaster"}}}},
			DioramaCompose.new_ctx(9, 0))
	assert_gt(out["parts"].size(), 0, "ring emitted nothing")
	for p: Dictionary in out["parts"]:
		assert_eq(p["kind"], "prism", "kind was not carried through")
		assert_true(p["params"].has("radius"),
				"a prism needs a radius — emit() reads it and would crash")
		assert_true(p["params"].has("height"), "a prism needs a height")
		assert_false(p["params"].has("size"),
				"a prism should not be handed box params")


# --------------------------------------------------------------- need (slice 3)

func test_a_mass_draws_its_need_in_band_and_deterministically() -> void:
	var tree := _box("solo", 2.0, 2.0, 2.0)
	var a := DioramaCompose.build(tree, SEED, 3)
	var b := DioramaCompose.build(tree, SEED, 3)
	assert_eq(a.size(), 1, "fixture should emit exactly one part")
	assert_eq(a[0]["need"], b[0]["need"], "same seed and id gave two needs")
	assert_true(a[0]["need"] >= DioramaCompose.ENDURE_LO,
			"need %f fell below the band floor" % a[0]["need"])
	assert_true(a[0]["need"] <= DioramaCompose.ENDURE_HI,
			"need %f rose above the band ceiling" % a[0]["need"])


func test_two_ids_draw_different_needs() -> void:
	# Otherwise every building in a city ruins identically, which is the whole
	# reason need is drawn rather than computed from geometry.
	var tree := _box("solo", 2.0, 2.0, 2.0)
	var differ := false
	for id in range(12):
		if not is_equal_approx(
				DioramaCompose.build(tree, SEED, 0)[0]["need"],
				DioramaCompose.build(tree, SEED, id)[0]["need"]):
			differ = true
	assert_true(differ, "twelve ids all drew the same need")


func test_a_mass_never_outlives_the_floor_it_was_handed() -> void:
	var ctx := DioramaCompose.new_ctx(SEED, 7)
	ctx["need_floor"] = 0.95
	var out := DioramaCompose.resolve(_box("solo", 2.0, 2.0, 2.0), ctx)
	assert_almost_eq(out["parts"][0]["need"], 0.95, 1e-6,
			"a floor above the draw band should win")
	assert_almost_eq(out["need"], 0.95, 1e-6,
			"the node should report the need it settled on")


func test_every_part_of_a_ring_carries_need() -> void:
	# _ring builds its parts directly rather than through _mass, so it has its
	# own literal to forget the key on — this caught it missing entirely.
	var out := DioramaCompose.resolve({"ring": {"name": "colonnade",
			"radius": 3.0, "from": 0.0, "to": PI, "count": 4,
			"of": {"mass": {"name": "column", "kind": "prism",
					"w": 0.5, "d": 0.5, "role": "plaster"}}}}, _ctx())
	assert_gt(out["parts"].size(), 0, "ring emitted nothing")
	for p: Dictionary in out["parts"]:
		assert_true(p.has("need"), "a ring part is missing the 'need' key")


func test_need_is_non_decreasing_up_a_stack() -> void:
	# The load-path property: nothing survives its own support. Swept over many
	# ids because a single draw could satisfy this by luck.
	var tall := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("b", 2.0, 2.0, 2.0),
		_box("c", 2.0, 2.0, 2.0), _box("d", 2.0, 2.0, 2.0)]}}
	for id in range(24):
		var parts := DioramaCompose.build(tall, SEED, id)
		assert_eq(parts.size(), 4, "fixture should emit four parts")
		for i in range(1, parts.size()):
			assert_true(parts[i]["need"] >= parts[i - 1]["need"],
					"id %d: part %d (need %f) outlives its support (need %f)"
					% [id, i, parts[i]["need"], parts[i - 1]["need"]])


func test_a_stack_reports_the_need_of_its_weakest_link() -> void:
	# What rests on a stack fails when any part of that stack fails, so the
	# stack must report its MAXIMUM need, not its minimum or its last child's.
	var tall := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("b", 2.0, 2.0, 2.0),
		_box("c", 2.0, 2.0, 2.0)]}}
	var out := DioramaCompose.resolve(tall, DioramaCompose.new_ctx(SEED, 5))
	var worst := -INF
	for p: Dictionary in out["parts"]:
		worst = maxf(worst, p["need"])
	assert_almost_eq(out["need"], worst, 1e-6,
			"stack under-reported how soon it fails")


func test_a_stack_child_that_resolves_away_does_not_raise_the_floor() -> void:
	# A zero-height mass emits nothing. If it still raised the running floor,
	# a style could make everything above it fragile by declaring a part it
	# never renders — an invisible cause for a visible problem.
	var with_ghost := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("ghost", 2.0, 2.0, 0.0),
		_box("c", 2.0, 2.0, 2.0)]}}
	var without := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("c", 2.0, 2.0, 2.0)]}}
	var a := DioramaCompose.build(with_ghost, SEED, 5)
	var b := DioramaCompose.build(without, SEED, 5)
	assert_eq(a.size(), 2, "the zero-height child should emit nothing")
	assert_almost_eq(a[1]["need"], b[1]["need"], 1e-6,
			"a child that emitted nothing changed what stacks above it")
