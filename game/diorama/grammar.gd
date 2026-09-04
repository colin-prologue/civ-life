class_name DioramaGrammar
extends RefCounted
## Renders a parts list into a mesh builder.
##
## This file used to hold the building recipes as well — residential, civic,
## stepped and hero_arch, each a function that computed its own geometry. They
## are gone: a style is now data (see DioramaStyles) resolved by DioramaCompose,
## and this is the one thing that was always renderer rather than recipe.
##
## A part is {kind, xf, params, color, need, y}. `need` — the condition at or
## above which the part survives — is settled during resolution, where the
## tree still knows what rests on what; `y` is derived afterward, from the
## resolved parts alone. Neither is authored by the style, so a condition
## transform can ruin a building by filtering parts on `need` — and, per the
## motion verdict, assemble one by running the same filter in reverse.


## Render a parts list into a builder at a world transform.
static func emit(builder: DioramaMeshKit, parts: Array, world: Transform3D) -> void:
	for p in parts:
		var xf: Transform3D = world * p["xf"]
		match p["kind"]:
			"box":
				builder.add_box(xf, p["params"]["size"], p["color"])
			"tapered":
				builder.add_tapered_box(xf, p["params"]["size"],
						p["params"]["taper"], p["color"])
			"prism":
				builder.add_prism(xf, p["params"]["radius"],
						p["params"]["height"], p["color"])
			"cone":
				builder.add_cone(xf, p["params"]["radius"],
						p["params"]["height"], p["color"])
			"dome":
				builder.add_dome(xf, p["params"]["radius"],
						p["params"]["squash"], p["color"])
