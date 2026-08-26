extends GutTest
## Keeps the Godot palette honest against the Blender lab's.
##
## The lab is the art-direction reference (see the intent's addendum: the
## sheets are reproducible from their seeds, and the rules derived from them
## are inherited by S0-S5). If the two palettes drift, every "parity" claim
## made from a Godot frame is quietly comparing against a different world.
##
## The scaffold had already drifted: five roles matched the lab hexes exactly
## while seven had been eyeballed, and the whole table was being fed to Godot
## as if it were linear when it was authored as sRGB.

const LAB_CORE := "res://tools/blender/civlife_blender/core.py"


## Pull `_lin("#rrggbb")` entries straight out of the lab's PALETTE literal, so
## this test reads the reference rather than a copy of it.
func _lab_palette() -> Dictionary:
	var f := FileAccess.open(LAB_CORE, FileAccess.READ)
	assert_not_null(f, "cannot read the lab palette at %s" % LAB_CORE)
	if f == null:
		return {}
	var src := f.get_as_text()
	f.close()
	var start := src.find("PALETTE = {")
	assert_gt(start, -1, "no PALETTE literal in the lab core")
	if start < 0:
		return {}
	var body := src.substr(start, src.find("}", start) - start)
	var out := {}
	var re := RegEx.create_from_string(
			'"([a-z0-9]+)"\\s*:\\s*_lin\\("(#[0-9a-fA-F]{6})"\\)')
	for m in re.search_all(body):
		out[m.get_string(1)] = m.get_string(2).to_lower()
	return out


func test_every_lab_role_exists_here_with_the_same_hex() -> void:
	var lab := _lab_palette()
	assert_gt(lab.size(), 0, "parsed no roles out of the lab palette")
	for role: String in lab:
		assert_true(DioramaPalette.HEX.has(role),
				"lab role '%s' is missing from DioramaPalette" % role)
		if DioramaPalette.HEX.has(role):
			assert_eq(String(DioramaPalette.HEX[role]).to_lower(), lab[role],
					"role '%s' has drifted from the lab sheet" % role)


func test_no_extra_roles_invented_on_the_godot_side() -> void:
	var lab := _lab_palette()
	for role: String in DioramaPalette.HEX:
		assert_true(lab.has(role),
				"'%s' exists in Godot but not in the lab — either add it to "
				% role + "the lab or stop calling the result parity")


func test_colours_are_returned_linear_not_srgb() -> void:
	# #e6dfcc is a light value; linearised its red channel drops well below the
	# 0.902 sRGB float. If this ever reads ~0.902 again, the conversion is gone.
	var plaster := DioramaPalette.col("plaster")
	assert_lt(plaster.r, 0.85, "plaster looks like raw sRGB, not linear")
	assert_almost_eq(plaster.r, Color("#e6dfcc").srgb_to_linear().r, 1e-6,
			"linearisation does not match the lab's _lin()")


func test_roles_separate_in_value_not_just_hue() -> void:
	# The intent's reduction test: identity must survive as value alone. These
	# three carry the composition — ground, civilisation, and the road line —
	# and must stay distinguishable in greyscale.
	var moss := DioramaPalette.value_of("moss")
	var plaster := DioramaPalette.value_of("plaster")
	var water := DioramaPalette.value_of("water")
	assert_gt(absf(plaster - moss), 0.15,
			"civilisation and ground collapse together in greyscale")
	assert_gt(absf(moss - water), 0.02,
			"ground and water collapse together in greyscale")
	assert_gt(plaster, moss, "plaster should read lighter than ground")


func test_unknown_role_is_not_silently_a_colour() -> void:
	assert_false(DioramaPalette.HEX.has("chartreuse"),
			"guard role leaked into the palette")


func test_srgb_and_linear_accessors_are_not_interchangeable() -> void:
	# If these ever coincide, one of the two conversions has been lost and
	# every albedo in the diorama is about to shift by ~6x.
	var lin := DioramaPalette.col("water")
	var srgb := DioramaPalette.srgb("water")
	assert_ne(lin, srgb, "col() and srgb() returned the same colour")
	assert_lt(lin.g, srgb.g, "linear should be darker than sRGB for a midtone")
	assert_eq(srgb, Color(DioramaPalette.HEX["water"]),
			"srgb() must hand back the palette hex untouched")
