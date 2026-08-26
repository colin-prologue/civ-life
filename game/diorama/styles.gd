class_name DioramaStyles
extends RefCounted
## The style library: buildings as data.
##
## A style names roles rather than colours, so the same tree can be rendered in
## two cultures' palettes without touching its geometry. Slice 1 ships one
## mapping; per-culture mappings arrive with S3.

const ROLES := {
	"plaster": Color(0.902, 0.875, 0.800),
	"plaster_dim": Color(0.812, 0.776, 0.682),
	"ochre": Color(0.659, 0.475, 0.290),
	"brass": Color(0.788, 0.643, 0.290),
	"wood": Color(0.478, 0.361, 0.220),
}


## A terrace of one to three units, each a plaster body under a tapered ochre
## roof that overhangs it. Compare against DioramaGrammar.residential(), which
## says the same thing in sixteen lines of arithmetic — if this is harder to
## read than that was, the whole design has failed its own premise.
static func residential() -> Dictionary:
	return {"row": {"name": "block", "count": [1, 4.0], "advance": 0.95, "of":
		{"stack": {"name": "unit", "children": [
			{"mass": {"name": "body", "kind": "box",
					"w": [0.55, 1.05], "d": [0.55, 1.05], "h": [0.60, 1.30],
					"role": "plaster"}},
			{"mass": {"name": "roof", "kind": "tapered", "taper": 0.8,
					"h": 0.22, "oversize": 1.08, "role": "ochre"}}]}}}}
