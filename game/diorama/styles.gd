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
## roof that overhangs it. This replaced a sixteen-line function that computed
## the same geometry with hand arithmetic; the bar set when it was written was
## that the data form must not read worse than the code it replaced, and by
## three independent judgements at the time, it did. What justifies it is not
## elegance but ordering: node names ARE a building's identity, so the channels
## had to be chosen before styles were authored or they could not be chosen.
static func residential() -> Dictionary:
	return {"row": {"name": "block", "count": [1, 3], "advance": 0.95, "of":
		{"stack": {"name": "unit", "children": [
			{"mass": {"name": "body", "kind": "box",
					"w": [0.55, 1.05], "d": [0.55, 1.05], "h": [0.60, 1.30],
					"role": "plaster"}},
			{"mass": {"name": "roof", "kind": "tapered", "taper": 0.8,
					"h": 0.22, "oversize": 1.08, "role": "ochre"}}]}}}}


## The hero structure: a monument whose scale breaks the settlement's
## hierarchy. This replaced about forty lines of trigonometry: the arc, the
## tangent rotation and the pier placement were all hand-derived there and are
## vocabulary here, which is the whole point — the next monument does not
## re-derive them.
##
## The pier height is a SCALAR and not a range, which is a modelling statement
## rather than a limitation worked around: a pier's height is not its own
## property, it is where the arch springs from, and the two ends of one arch
## are the same thing. Written as a range they sampled independently — channels
## are keyed on node names, so `west` and `east` drew different values and the
## arc rested on the taller while floating above the shorter. The vocabulary
## has no way to say "these two siblings share a draw"; if a style ever wants
## genuinely coupled-but-varying dimensions, that is the gap to close.
##
## Read outward: a base slab, then two piers with a clear opening between them,
## then the arc spanning that opening, then a beam across the top and a brass
## finial above it. `gap` is what makes the opening sayable — as a ratio it
## would be a number derived from the pier thickness, which is not something a
## style author can write down.
static func hero_arch() -> Dictionary:
	return {"stack": {"name": "arch", "children": [
		{"mass": {"name": "plinth", "kind": "box",
				"w": [4.6, 5.4], "d": 1.2, "h": 0.33,
				"role": "plaster_dim"}},
		{"row": {"name": "piers", "gap": 2.6, "children": [
			{"mass": {"name": "west", "kind": "box",
					"w": 0.42, "d": 0.63, "h": 1.62, "role": "plaster"}},
			{"mass": {"name": "east", "kind": "box",
					"w": 0.42, "d": 0.63, "h": 1.62, "role": "plaster"}}]}},
		{"ring": {"name": "span", "radius": 1.51, "from": 0.0, "to": PI,
				"count": 9,
				"of": {"mass": {"name": "voussoir", "kind": "box",
						"w": 0.42, "d": 0.63, "role": "plaster"}}}},
		{"mass": {"name": "entablature", "kind": "box",
				"h": 0.45, "oversize": 1.1, "role": "ochre"}},
		{"mass": {"name": "finial", "kind": "cone",
				"w": 0.31, "d": 0.31, "h": 1.5, "role": "brass"}}]}}


## A civic hall: a podium, a hall under a tapered roof, and a colonnade
## standing in front of it. The `axis: "z"` row is what makes "in front of"
## sayable — the portico and the hall sit side by side in DEPTH, which is
## neither stacking nor standing beside in width.
##
## A z-row lists its children BACK TO FRONT, the order they occur along +z,
## which is the direction the diorama camera looks from.
static func civic() -> Dictionary:
	return {"stack": {"name": "civic", "children": [
		{"mass": {"name": "podium", "kind": "box",
				"w": [1.7, 2.5], "d": [1.1, 1.6], "h": 0.15,
				"role": "plaster_dim"}},
		{"row": {"name": "front", "axis": "z", "children": [
			{"stack": {"name": "hall", "children": [
				{"mass": {"name": "walls", "kind": "box",
						"w": [1.2, 1.8], "d": [0.6, 0.9], "h": 0.8,
						"role": "plaster"}},
				{"mass": {"name": "roof", "kind": "tapered", "taper": 0.5,
						"h": 0.22, "oversize": 1.06, "role": "ochre"}}]}},
			{"row": {"name": "colonnade", "count": 5, "advance": 2.6, "of":
				{"mass": {"name": "column", "kind": "prism",
						"w": 0.09, "d": 0.09, "h": 0.72,
						"role": "plaster"}}}}]}}]}}


## A stepped monument: a plinth, three or four tiers each set back from the one
## below, and a brass spire. `setback` is the whole shape — without it the
## tiers would be a column, and a style would have to restate every width.
static func stepped() -> Dictionary:
	return {"stack": {"name": "stepped", "setback": [0.24, 0.30], "children": [
		{"mass": {"name": "plinth", "kind": "box",
				"w": [1.1, 1.6], "d": [1.1, 1.6], "h": 0.17,
				"role": "plaster_dim"}},
		{"mass": {"name": "tier0", "kind": "box", "h": 0.61, "role": "plaster"}},
		{"mass": {"name": "tier1", "kind": "box", "h": 0.61, "role": "plaster"}},
		{"mass": {"name": "tier2", "kind": "box", "h": 0.61, "role": "plaster"}},
		{"mass": {"name": "spire", "kind": "cone",
				"h": 0.79, "oversize": 0.5, "role": "brass"}}]}}


## Style trees by name, for scenes that pick one from an export. Centralised
## here so lineup.gd and condition_sheet.gd do not each carry their own ladder
## of `if`s that drifts out of sync as styles are added.
static func for_name(name: String) -> Dictionary:
	match name:
		"hero_arch": return hero_arch()
		"civic": return civic()
		"stepped": return stepped()
		_: return residential()


## Every style, in sheet order.
const NAMES := ["residential", "civic", "stepped", "hero_arch"]
