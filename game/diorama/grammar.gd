class_name DioramaGrammar
extends RefCounted
## Building recipes: composed primitives under one architectural style.
##
## Each recipe emits parts as data — {kind, xf, params, color, tag, y} — so a
## later condition transform can ruin a building by filtering parts (and, per
## the motion verdict, assemble one by running the same filter in reverse).
## S0 uses a single style on purpose; CultureStyle parameters arrive with S3.

const PLASTER := Color(0.902, 0.875, 0.800)
const PLASTER_DIM := Color(0.812, 0.776, 0.682)
const ROOF := Color(0.659, 0.475, 0.290)
const BRASS := Color(0.788, 0.643, 0.290)
const WOOD := Color(0.478, 0.361, 0.220)


static func _part(kind: String, xf: Transform3D, params: Dictionary,
		col: Color, tag: String, y: float) -> Dictionary:
	return {"kind": kind, "xf": xf, "params": params, "color": col,
			"tag": tag, "y": y}


static func residential(seed: int, id: int, s: float = 0.55) -> Array:
	var parts: Array = []
	var n := 1 + int(DioramaHexKit.h01(seed, 51, id) * 3.0)
	var x := 0.0
	for i in range(n):
		var w := (0.55 + DioramaHexKit.h01(seed, 52, id, i) * 0.5) * s
		var d := (0.55 + DioramaHexKit.h01(seed, 53, id, i) * 0.5) * s
		var h := (0.6 + DioramaHexKit.h01(seed, 54, id, i) * 0.7) * s
		var at := Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
		parts.append(_part("box", at, {"size": Vector3(w, h, d)},
				PLASTER, "mid", h * 0.5))
		var rt := Transform3D(Basis.IDENTITY, Vector3(x, h, 0))
		parts.append(_part("tapered", rt,
				{"size": Vector3(w * 1.08, 0.22 * s, d * 1.08), "taper": 0.8},
				ROOF, "upper", h + 0.1 * s))
		x += w * 0.95
	return parts


static func civic(seed: int, id: int, s: float = 0.55) -> Array:
	var parts: Array = []
	var pw := (2.4 + DioramaHexKit.h01(seed, 61, id)) * s
	var pd := pw * 0.62
	var ph := 0.2 * s
	parts.append(_part("box", Transform3D.IDENTITY,
			{"size": Vector3(pw, ph, pd)}, PLASTER_DIM, "base", ph * 0.5))
	var n_col := 5
	var col_h := 1.0 * s
	for i in range(n_col):
		var cx := -pw * 0.38 + pw * 0.76 * i / (n_col - 1)
		var ct := Transform3D(Basis.IDENTITY, Vector3(cx, ph, pd * 0.3))
		parts.append(_part("prism", ct,
				{"radius": 0.06 * s, "height": col_h}, PLASTER, "mid",
				ph + col_h * 0.5))
	var hall_h := col_h * 1.1
	var ht := Transform3D(Basis.IDENTITY, Vector3(0, ph, -pd * 0.1))
	parts.append(_part("box", ht,
			{"size": Vector3(pw * 0.72, hall_h, pd * 0.55)}, PLASTER, "mid",
			ph + hall_h * 0.5))
	var rt := Transform3D(Basis.IDENTITY, Vector3(0, ph + hall_h, -pd * 0.1))
	parts.append(_part("tapered", rt,
			{"size": Vector3(pw * 0.66, 0.3 * s, pd * 0.5), "taper": 0.5},
			ROOF, "crown", ph + hall_h + 0.15 * s))
	return parts


static func stepped(seed: int, id: int, s: float = 0.55) -> Array:
	var parts: Array = []
	var base_w := (1.5 + DioramaHexKit.h01(seed, 71, id) * 0.7) * s
	var base_h := 0.24 * s
	parts.append(_part("box", Transform3D.IDENTITY,
			{"size": Vector3(base_w, base_h, base_w)}, PLASTER_DIM, "base",
			base_h * 0.5))
	var tiers := 3 + int(DioramaHexKit.h01(seed, 72, id) * 2.0)
	var tier_h := 0.85 * s
	var w := base_w * 0.72
	var y := base_h
	var shrink := 0.24 + DioramaHexKit.h01(seed, 73, id) * 0.06
	for t in range(tiers):
		var tw: float = w * pow(1.0 - shrink, t)
		var tt := Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
		parts.append(_part("box", tt, {"size": Vector3(tw, tier_h, tw)},
				PLASTER, "mid" if t < tiers / 2.0 else "upper",
				y + tier_h * 0.5))
		y += tier_h
	var spire_h := 1.1 * s
	var st := Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
	parts.append(_part("cone", st,
			{"radius": w * pow(1.0 - shrink, tiers) * 0.4, "height": spire_h},
			BRASS, "accent", y + spire_h * 0.5))
	return parts


## The hero arch — piers and voussoirs as separate parts, so a future ruin
## keeps its stumps or a partial span. Voussoir long axis lies TANGENT to the
## arc (lab finding: radial orientation makes an M-shaped scallop).
static func hero_arch(seed: int, s: float = 1.1) -> Array:
	var parts: Array = []
	var w := (2.2 + DioramaHexKit.h01(seed, 81, 0) * 0.8) * s
	var h := (2.6 + DioramaHexKit.h01(seed, 82, 0) * 0.6) * s
	var t := 0.28 * s
	var base_h := 0.22 * s
	parts.append(_part("box", Transform3D.IDENTITY,
			{"size": Vector3(w * 1.3, base_h, t * 2.8)}, PLASTER_DIM, "base",
			base_h * 0.5))
	var span := w - 2.0 * t
	var radius := span * 0.5 + t * 0.5
	var pier_h := maxf(0.05, h - radius)
	for side in [-1.0, 1.0]:
		var pt := Transform3D(Basis.IDENTITY,
				Vector3(side * (w * 0.5 - t * 0.5), base_h, 0))
		parts.append(_part("box", pt, {"size": Vector3(t, pier_h, t * 1.5)},
				PLASTER, "mid", base_h + pier_h * 0.5))
	var segments := 9
	for i in range(segments):
		var a0 := PI * i / segments
		var a1 := PI * (i + 1) / segments
		var mid := (a0 + a1) * 0.5
		var seg_len := radius * (a1 - a0) * 1.15
		var origin := Vector3(cos(mid) * radius, base_h + pier_h + sin(mid) * radius, 0)
		var basis := Basis(Vector3(0, 0, 1), mid)  # long axis tangent
		var vt := Transform3D(basis, origin)
		# box helper builds y in [0, size.y]; recentre the voussoir on origin
		vt = vt * Transform3D(Basis.IDENTITY, Vector3(0, -seg_len * 0.5, 0))
		parts.append(_part("box", vt, {"size": Vector3(t, seg_len, t * 1.5)},
				PLASTER, "upper", origin.y))
	var beam_y := base_h + pier_h + radius + t * 0.4
	var bt := Transform3D(Basis.IDENTITY, Vector3(0, beam_y, 0))
	parts.append(_part("box", bt, {"size": Vector3(w * 1.15, 0.3 * s, t * 1.7)},
			ROOF, "upper", beam_y + 0.15 * s))
	var st := Transform3D(Basis.IDENTITY, Vector3(0, beam_y + 0.3 * s, 0))
	parts.append(_part("cone", st, {"radius": t * 0.55, "height": 1.0 * s},
			BRASS, "accent", beam_y + 0.8 * s))
	return parts


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
