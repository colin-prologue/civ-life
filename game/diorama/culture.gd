class_name DioramaCulture
extends RefCounted
## A culture is a people's way of building: what proportions they favour, how
## uniform they are, what shape they put on top, and what they build in.
##
## It modulates the SHARED vocabulary rather than forking it. Every culture
## renders the same style trees, because ruins, the assembly tween and the
## whole composer rest on one tree per style — a per-culture fork would
## multiply all of that by the number of civilizations.
##
## A palette alone would not do it. Measured before this was written: the four
## styles draw from an almost identical role set — everything is plaster with
## an ochre roof and a brass tip — so swapping palettes tints all four styles
## identically. `procedural-art` experiment S3 sets the bar: culture must be
## legible in massing and silhouette, not surface marks.


## Which culture lever scales which sampled purpose. Anything absent here is
## deliberately unmodulated:
##
##   `oversize` and `taper` are RELATIVE to the mass they modify, so scaling
##   them would compound with the `w`/`d`/`h` scaling already applied.
##
##   `radius`, `from` and `to` describe an arc's SHAPE. Scaling an arch's
##   radius while its voussoirs thin would break the fit against its piers
##   that slice 2 spent a review round getting right.
##
##   `advance` and `gap` are row rhythm, and `count` is repetition. Both are
##   the deferred repetition lever, not this slice.
const SCALES := {
	"h": "verticality",
	"w": "thickness",
	"d": "thickness",
	"setback": "setback",
}


## Transform a proportion spec into the one this culture would build to.
##
## The RANGE moves, not the drawn value. How uniform a civilization's
## architecture is, is itself a cultural trait — a rigid imperial people build
## to a template, a vernacular one does not — so `variance` is a lever of its
## own, and it costs nothing to have it here rather than to retrofit it later.
##
## Returns the spec untouched for an unmodulated purpose, and null for null, so
## the caller's default still applies.
static func modulate(spec: Variant, culture: Dictionary,
		purpose: String) -> Variant:
	if spec == null or not SCALES.has(purpose):
		return spec
	var scale: float = culture.get(SCALES[purpose], 1.0)
	if spec is float or spec is int:
		return float(spec) * scale
	if not (spec is Array and spec.size() == 2):
		return spec
	var lo := float(spec[0])
	var hi := float(spec[1])
	var mid := (lo + hi) * 0.5
	var variance: float = culture.get("variance", 1.0)
	# A negative variance is the only way this arithmetic can invert a range,
	# and it is authoring error, not a runtime condition — every shipped
	# culture has variance >= 0, so this can only fire on a new culture's data.
	assert(variance >= 0.0, "culture '%s' has a negative variance"
			% culture.get("name", "none"))
	# Half-width scales toward zero and never past it, so a variance under 1
	# narrows without inverting the range.
	var half := (hi - lo) * 0.5 * variance
	return [(mid - half) * scale, (mid + half) * scale]


## What a culture's `crown` name means in geometry. Roofline is what the eye
## resolves first at settlement distance, which is why this one substitution
## carries most of the silhouette half of experiment S3's bar.
const CROWNS := {
	"spire": "cone",
	"dome": "dome",
	"hip": "tapered",
	"parapet": "box",
}


## What a crowning mass becomes. A culture that names a crown puts it on every
## style. A culture that names none gets `authored`, the primitive kind the
## crowning mass was drawn with, so a caller building with no culture sees the
## vocabulary as it was authored.
##
## There is deliberately no default crown. There was one: "hip", on the premise
## that three of the four styles were tapered before crowns existed. Only two
## were. hero_arch's finial and stepped's spire were cones, and the default
## turned both into blunt tapered obelisks in every caller that builds without
## a culture (the S0 spike, the lineup, the condition sheet). Nothing failed,
## because a tapered finial is a perfectly valid mass.
static func crown_kind(culture: Dictionary, authored: String) -> String:
	if culture.has("crown"):
		var name: String = culture["crown"]
		# CROWNS[name] fails loudly on a missing key in every build, including
		# release, where Godot strips asserts. A silent fallback here would let
		# a typo'd crown name ship as a hipped roof that reads as a design
		# choice instead of the mistake it is.
		assert(CROWNS.has(name), "unknown crown '%s'" % name)
		return CROWNS[name]
	# A crowning mass with no `default`, under a culture that names no crown,
	# has no shape to take. Refuse rather than guess: a guessed crown is exactly
	# how the arch lost its spire without anything noticing.
	assert(authored != "",
			"a crowning mass records no default and the culture names no crown")
	return authored


## Names in sheet order.
const NAMES := ["lowland", "highland", "delta"]


static func for_name(name: String) -> Dictionary:
	match name:
		"highland": return highland()
		"delta": return delta()
		_: return lowland()


## The baseline for PROPORTIONS and PALETTE: every multiplier is 1.0, and the
## palette is DioramaStyles.ROLES verbatim. It is not the vocabulary
## unmodulated, though. It is a people with a roofline of its own, and it hips
## every crown, the arch's finial and stepped's spire included. The vocabulary
## as authored is what building with NO culture produces.
static func lowland() -> Dictionary:
	return {
		"name": "lowland",
		"palette": {
			"plaster": Color(0.902, 0.875, 0.800),
			"plaster_dim": Color(0.812, 0.776, 0.682),
			"ochre": Color(0.659, 0.475, 0.290),
			"brass": Color(0.788, 0.643, 0.290),
			"wood": Color(0.478, 0.361, 0.220),
		},
		"verticality": 1.0,
		"thickness": 1.0,
		"setback": 1.0,
		"variance": 1.0,
		"crown": "hip",
	}


## Tall, thin-walled, sharply stepped, and irregular — a people building on
## slopes with little flat ground.
static func highland() -> Dictionary:
	return {
		"name": "highland",
		"palette": {
			"plaster": Color(0.784, 0.780, 0.757),
			"plaster_dim": Color(0.663, 0.659, 0.639),
			"ochre": Color(0.427, 0.365, 0.310),
			"brass": Color(0.706, 0.612, 0.353),
			"wood": Color(0.376, 0.325, 0.267),
		},
		"verticality": 1.45,
		"thickness": 0.78,
		"setback": 1.35,
		"variance": 1.30,
		"crown": "spire",
	}


## Low, heavy-walled, barely tapered and highly uniform — a people building to
## a template on flat ground.
static func delta() -> Dictionary:
	return {
		"name": "delta",
		"palette": {
			"plaster": Color(0.918, 0.855, 0.706),
			"plaster_dim": Color(0.831, 0.757, 0.604),
			"ochre": Color(0.741, 0.514, 0.259),
			"brass": Color(0.831, 0.702, 0.318),
			"wood": Color(0.518, 0.400, 0.239),
		},
		"verticality": 0.70,
		"thickness": 1.30,
		"setback": 0.45,
		"variance": 0.55,
		"crown": "dome",
	}
