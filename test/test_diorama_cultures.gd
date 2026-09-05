extends GutTest
## Roles are semantic, cultures are mappings, and the pair has to hold together.
##
## Three separate things are guarded here and they fail for different reasons:
##
##   CLOSURE   the role vocabulary is finite and shared. Every role a style
##             names resolves in every culture, and no culture carries a role
##             nothing asks for. This is the check that makes an unmapped role
##             a test failure rather than a black part on a sheet nobody looks
##             at closely.
##   VALUE     the addendum's 3D rule. Roles are separated by LIGHTNESS, not
##             just by hue, under both the lit and the shadowed variant, and
##             they keep the same lightness ORDER across the two.
##   INVARIANCE culture is a mapping applied after resolution, so swapping it
##             may change colour and must change nothing else.
##
## The value check runs against the two variants DioramaCultures computes
## rather than against captured pixels: a screenshot test would fail for
## twenty reasons that are not the palette, and the thing being asserted is a
## property of the numbers.

const SEED := 20260826


func _palettes() -> Array:
	var out: Array = []
	for name: String in DioramaCultures.NAMES:
		out.append([name, DioramaCultures.palette(name)])
	return out


# --------------------------------------------------------------- closure

func test_every_role_a_style_names_resolves_in_every_culture() -> void:
	for style: String in DioramaStyles.NAMES:
		var roles := DioramaCompose.roles_in(DioramaStyles.for_name(style))
		assert_gt(roles.size(), 0, "style '%s' names no roles at all" % style)
		for pair in _palettes():
			for role: String in roles:
				assert_true(pair[1].has(role),
						"style '%s' names role '%s'; culture '%s' cannot paint it"
						% [style, role, pair[0]])


func test_the_role_set_is_closed() -> void:
	# Both directions. A style naming something outside the vocabulary is a
	# style with a private colour; a vocabulary word no style uses is dead
	# weight that will be mapped wrong the first time somebody does use it.
	var used := {}
	for style: String in DioramaStyles.NAMES:
		for role: String in DioramaCompose.roles_in(DioramaStyles.for_name(style)):
			assert_true(DioramaCultures.ROLES.has(role),
					"style '%s' names '%s', which is not in the role set"
					% [style, role])
			used[role] = true
	for role: String in DioramaCultures.ROLES:
		assert_true(used.has(role),
				"role '%s' is declared and no style asks for it" % role)


func test_every_culture_maps_exactly_the_role_set() -> void:
	for pair in _palettes():
		var keys: Array = pair[1].keys()
		keys.sort()
		var want: Array = DioramaCultures.ROLES.duplicate()
		want.sort()
		assert_eq(keys, want,
				"culture '%s' does not map the role set exactly" % pair[0])


## The unresolved colour is MAGENTA, not black. This is the half of "fails
## loudly" that a test can reach without tripping the assert in apply_roles:
## before any palette is applied every part carries the placeholder, so a role
## that resolves against nothing stays visibly wrong rather than looking like a
## deliberately dark culture.
func test_an_unpainted_part_is_magenta_not_black() -> void:
	for p: Dictionary in DioramaCompose.build(DioramaStyles.civic(), SEED, 0):
		assert_eq(p["color"], Color.MAGENTA,
				"build() no longer leaves parts on the loud placeholder")


func test_a_style_tree_reports_the_roles_it_actually_contains() -> void:
	# hero_arch reaches every corner of the walker: a stack, a row of children,
	# and a ring's `of`. If roles_in misses one of those three, the closure
	# check above silently stops covering a whole node type.
	var roles := DioramaCompose.roles_in(DioramaStyles.hero_arch())
	for want in ["footing", "structure", "cap", "aspiration"]:
		assert_true(roles.has(want),
				"roles_in missed '%s' in the hero arch" % want)


# ----------------------------------------------------------------- value

## The addendum's rule, stated as a number: every pair of roles differs by at
## least LIT_MIN in Rec.709 luma with the sun on it, and at least SHADE_MIN
## under ambient alone. Hue separation alone passes neither.
func test_roles_are_separated_by_value_under_both_variants() -> void:
	for pair in _palettes():
		var pal: Dictionary = pair[1]
		var names: Array = pal.keys()
		for i in range(names.size()):
			for j in range(i + 1, names.size()):
				var a: Color = pal[names[i]]
				var b: Color = pal[names[j]]
				var d_lit: float = absf(DioramaCultures.luma(DioramaCultures.lit(a))
						- DioramaCultures.luma(DioramaCultures.lit(b)))
				assert_gte(d_lit, DioramaCultures.LIT_MIN,
						"%s: '%s' and '%s' are %.4f apart in lit value (want %.3f)"
						% [pair[0], names[i], names[j], d_lit,
						DioramaCultures.LIT_MIN])
				var d_sh: float = absf(DioramaCultures.luma(DioramaCultures.shaded(a))
						- DioramaCultures.luma(DioramaCultures.shaded(b)))
				assert_gte(d_sh, DioramaCultures.SHADE_MIN,
						"%s: '%s' and '%s' are %.4f apart in shadow (want %.3f)"
						% [pair[0], names[i], names[j], d_sh,
						DioramaCultures.SHADE_MIN])


## The check the two floors do not imply: a tinted ambient must not re-rank the
## roles. Two masses that swap which one reads lighter between the sunny face
## and the shadowed face destroy the reading of which stands in front of which.
func test_the_value_order_survives_going_into_shadow() -> void:
	for pair in _palettes():
		var lit_order := DioramaCultures.value_order(pair[1],
				DioramaCultures.lit)
		var shade_order := DioramaCultures.value_order(pair[1],
				DioramaCultures.shaded)
		assert_eq(lit_order, shade_order,
				"culture '%s' re-ranks its roles in shadow" % pair[0])


## Gold is scarce because the STYLES are sparing with it, not because a palette
## made it quiet — so the scarcity check belongs on the library, not the colour.
## Two of four styles carry `aspiration`, one part each.
func test_aspiration_stays_rare_across_the_library() -> void:
	var carriers := 0
	for style: String in DioramaStyles.NAMES:
		var parts := DioramaCompose.build(DioramaStyles.for_name(style), SEED, 0)
		var n := 0
		for p: Dictionary in parts:
			if p["role"] == "aspiration":
				n += 1
		if n > 0:
			carriers += 1
			assert_eq(n, 1,
					"style '%s' spends gold on %d parts; one is the budget"
					% [style, n])
	assert_lt(carriers, DioramaStyles.NAMES.size(),
			"every style carries gold — it is no longer scarce")
	assert_gt(carriers, 0, "no style carries gold at all")


# ------------------------------------------------------------ invariance

## AC2 and AC6 together, and they are the same assertion read two ways: one
## tree under two cultures is two distinct buildings, and the distinction is
## ENTIRELY colour. Anything else differing would mean culture had leaked into
## the seeded channels.
func test_two_cultures_repaint_one_tree_and_move_nothing() -> void:
	for style: String in DioramaStyles.NAMES:
		var tree: Dictionary = DioramaStyles.for_name(style)
		var a := DioramaCompose.build(tree, SEED, 4)
		var b := DioramaCompose.build(tree, SEED, 4)
		DioramaCompose.apply_roles(a, DioramaCultures.palette("sunlit"))
		DioramaCompose.apply_roles(b, DioramaCultures.palette("basalt"))
		assert_eq(a.size(), b.size(),
				"style '%s' emitted a different part count per culture" % style)
		var differing := 0
		for i in range(a.size()):
			for key: String in a[i]:
				if key == "color":
					if a[i][key] != b[i][key]:
						differing += 1
					continue
				assert_eq(a[i][key], b[i][key],
						"style '%s' part %d: culture changed '%s'"
						% [style, i, key])
		assert_gt(differing, 0,
				"style '%s' looks identical in both cultures" % style)


func test_the_same_culture_paints_the_same_building_twice() -> void:
	for name: String in DioramaCultures.NAMES:
		var a := DioramaCompose.build(DioramaStyles.stepped(), SEED, 2)
		var b := DioramaCompose.build(DioramaStyles.stepped(), SEED, 2)
		DioramaCompose.apply_roles(a, DioramaCultures.palette(name))
		DioramaCompose.apply_roles(b, DioramaCultures.palette(name))
		assert_eq(a, b, "culture '%s' is not deterministic" % name)


## An unknown culture name must not return an empty palette — every role would
## then fail at once and the error would name four innocent roles instead of
## the one bad export.
func test_an_unknown_culture_falls_back_rather_than_emptying() -> void:
	assert_eq(DioramaCultures.palette("nonesuch"),
			DioramaCultures.palette(DioramaCultures.NAMES[0]),
			"an unknown culture did not fall back to the first")


# ----------------------------------------------------------------- the sheet

func _sheet() -> Node3D:
	var sheet: Node3D = load("res://game/diorama/culture_sheet.tscn").instantiate()
	add_child_autofree(sheet)
	return sheet


func test_the_sheet_has_a_cell_per_style_and_culture() -> void:
	var sheet := _sheet()
	await wait_frames(2)
	var cells := 0
	for child in sheet.get_children():
		if child is MeshInstance3D and child.name.begins_with("Cell_"):
			cells += 1
	assert_eq(cells,
			DioramaStyles.NAMES.size() * DioramaCultures.NAMES.size(),
			"the sheet is not the full style x culture cross-product")
	assert_not_null(sheet.get_node_or_null("Camera"), "no camera")
	assert_not_null(sheet.get_node_or_null("Sun"), "no light")
	assert_not_null(sheet.get_node_or_null("Stage"), "no stage")


## The sheet's entire argument, asserted rather than eyeballed: across a row the
## VERTICES are identical and the COLOURS are not. If the geometry differed the
## frame would be two buildings in two palettes, which says nothing about
## culture; if the colours matched, the culture axis would be doing nothing.
func test_a_row_is_one_building_rendered_in_two_palettes() -> void:
	var sheet := _sheet()
	await wait_frames(2)
	for style: String in DioramaStyles.NAMES:
		var verts: Array = []
		var colors: Array = []
		for culture: String in DioramaCultures.NAMES:
			var cell: MeshInstance3D = sheet.get_node_or_null(
					"Cell_%s_%s" % [style, culture])
			assert_not_null(cell, "no cell for %s/%s" % [style, culture])
			if cell == null:
				continue
			var arrays: Array = cell.mesh.surface_get_arrays(0)
			verts.append(arrays[Mesh.ARRAY_VERTEX])
			colors.append(arrays[Mesh.ARRAY_COLOR])
			assert_eq(cell.scale, sheet.get_node(
					"Cell_%s_%s" % [style, DioramaCultures.NAMES[0]]).scale,
					"row '%s' scales its cultures differently" % style)
		if verts.size() == 2:
			assert_eq(verts[0], verts[1],
					"row '%s' is two different buildings, not one in two palettes"
					% style)
			assert_ne(colors[0], colors[1],
					"row '%s' comes out the same colour in both cultures" % style)
