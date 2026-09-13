class_name DioramaCultures
extends RefCounted
## A people's way of building: what colour each role comes out as, what
## proportions they favour, how uniform they are, and what shape they put on
## top.
##
## A culture reaches the renderer along TWO paths that must not be collapsed
## into one. Its MASSING — verticality, thickness, setback, variance, crown —
## is handed to DioramaCompose.build() and moves geometry. Its PALETTE is
## handed to DioramaCompose.apply_roles() afterwards and moves nothing. That
## split is not tidiness: holding one constant while varying the other is the
## only way to tell "we expressed a culture" apart from "we tinted a building",
## and the culture sheet's `uniform_palette` control is exactly that experiment
## run on the geometry half.
##
## A palette alone would not have done it. Measured before the massing levers
## were written: the four styles draw from an almost identical role set, so
## swapping palettes tints all four styles identically. `procedural-art`
## experiment S3 sets the bar — culture must be legible in massing and
## silhouette, not surface marks.
##
## Culture modulates the SHARED style vocabulary rather than forking it. Every
## culture renders the same style trees, because ruins, the assembly tween and
## the whole composer rest on one tree per style; a per-culture fork would
## multiply all of that by the number of civilizations.
##
## Slice 1 shipped ONE mapping, living next to the style trees, with role names
## borrowed from materials: `plaster`, `ochre`, `brass`, `wood`. That is a
## palette wearing a vocabulary's clothes. A role named `ochre` cannot be
## re-expressed by a culture that does not build in ochre — the name has already
## decided the colour — and `wood` was declared and referenced by nothing.
##
## So the roles here name what a part IS FOR, and a culture says what colour
## that comes out as. Four of them, and the set is CLOSED: DioramaCompose
## .roles_in() walks a style tree, and the suite asserts that everything it
## finds resolves in every shipped culture and that no culture carries a role no
## style asks for.
##
##   structure   the mass that holds the building up — walls, piers, tiers,
##               voussoirs, columns
##   footing     what it stands on — plinth, podium, base slab
##   cap         what crowns it — roof, entablature
##   aspiration  gold: deliberate human intention, and scarce on purpose. Two
##               of the four styles carry it, on one part each — a finial and a
##               spire. The intent's rule is that gold stays scarce and patina
##               tells time; scarcity here is a property of the STYLES, not of
##               the palettes, so no choice of colour in this file can make gold
##               ordinary.
##
## Not shipped, and deliberately: `patina`. It is the semantic partner of
## `aspiration` — verdigris is what time does to deliberate metal — but nothing
## in the renderer varies colour with age yet (slice 3 ruled weathering out of
## the condition ladder explicitly), so a `patina` role would resolve for no
## part in any style. Declaring it now would be vocabulary with no caller. It
## belongs to whichever slice makes colour a function of condition, and the
## half of the pair that IS shippable today — scarcity — already holds.

## The closed role set. A style referencing anything outside this fails in the
## suite rather than at render time.
const ROLES := ["structure", "footing", "cap", "aspiration"]


## The lime-plaster culture: pale walls under fired-earth roofs, standing on a
## dark stone footing, with gilt at the top.
##
## This SUPERSEDES the slice-1 default rather than being it. Two changes, both
## forced by the checks below rather than chosen:
##
## 1. `plaster_dim` — the plinth — sat 0.099 in Rec.709 luma below `plaster`,
##    under the floor the value rule sets. The two were separated by hue and
##    barely at all by value, and a plinth that reads as the same tone as the
##    wall above it is not a plinth. It is now a dark stone base, 0.56 below the
##    wall.
## 2. `wood` is gone. No style ever referenced it.
##
## `plaster` and `ochre` carry across unchanged, so what slice 1 shipped is
## still recognisable in this.
const SUNLIT := {
	"structure": Color(0.902, 0.875, 0.800),
	"aspiration": Color(0.882, 0.706, 0.294),
	"cap": Color(0.659, 0.475, 0.290),
	"footing": Color(0.353, 0.310, 0.267),
}

## The opposite culture, and opposite on the axis this slice can actually vary:
## VALUE POLARITY. Sunlit is a light building on its own dark base; basalt is a
## dark cool building under a pale cap. Under the reduction test one reads as an
## outline and the other as a filled mass, and that is the whole extent of the
## silhouette-level difference a palette swap can produce — see the finding in
## docs/superpowers/findings/.
##
## Its aspiration metal is the BRIGHTEST role it has, where sunlit's is second
## to its walls. Same semantic role, opposite position in its own culture's
## value order: gold against pale plaster is a warm darkening, gold against
## basalt is the one bright thing on the building.
const BASALT := {
	"aspiration": Color(0.867, 0.694, 0.412),
	"cap": Color(0.565, 0.553, 0.498),
	"structure": Color(0.251, 0.278, 0.325),
	"footing": Color(0.106, 0.114, 0.141),
}

## The third position on the value axis, and the reason it exists. Sunlit puts
## its walls at the top of its own value order; basalt puts its gold there. Marl
## puts its CAP there: a lime-washed vault over buff river clay, standing on wet
## silt. It is a people who build the bright thing overhead rather than on the
## walls or at the tip, which is what a vaulting culture looks like from a
## distance.
##
## Its gold sits THIRD of four, below the walls — the only shipped culture where
## aspiration is not in the top two. Same scarce role, a third position in a
## third culture's ordering, which is the most a palette axis has left to say
## once two cultures have taken the obvious two.
const MARL := {
	"cap": Color(0.957, 0.941, 0.906),
	"structure": Color(0.776, 0.682, 0.545),
	"aspiration": Color(0.678, 0.478, 0.180),
	"footing": Color(0.290, 0.263, 0.231),
}

## Every culture, in sheet order. Three, not the two experiment S3 asks for:
## the crown vocabulary has four shapes in it and two cultures can only ever
## show two of them. With three, `hip`, `parapet` and `dome` are all on the
## sheet and `spire` is what the callers that build with NO culture keep showing
## (the authored default on the arch's finial and stepped's spire), so every
## primitive a crown can resolve to appears in some shipped frame.
const NAMES := ["sunlit", "basalt", "marl"]


## The palette for a culture name. An unknown name falls back to the first
## culture rather than returning an empty Dictionary: an empty palette makes
## EVERY role unresolvable, so a typo'd export would surface as four complaints
## about roles that are perfectly fine rather than as one about the culture.
static func palette(name: String) -> Dictionary:
	match name:
		"basalt": return BASALT
		"marl": return MARL
		_: return SUNLIT


# ------------------------------------------------------------- the massing
#
# The other half of a culture, and the half that answers experiment S3. Held in
# their own dictionaries rather than as extra keys on the palettes above,
# because the suite asserts that a culture's palette maps the role set EXACTLY
# — a `verticality` key sitting in SUNLIT would read as a fifth role and take
# the closure check down with it. Two dictionaries per culture, one check each,
# and neither can quietly become the other.


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


## What a culture's `crown` name means in geometry. Roofline is what the eye
## resolves first at settlement distance, which is why this one substitution
## carries most of the silhouette half of experiment S3's bar.
const CROWNS := {
	"spire": "cone",
	"dome": "dome",
	"hip": "tapered",
	"parapet": "box",
}


## The baseline, and baseline in both halves: every multiplier is 1.0, so a
## sunlit building is the style tree at the proportions it was authored to.
## That makes it the honest control palette AND the honest control massing —
## the culture sheet renders every row through sunlit's colours to isolate
## geometry, and it can only do that because sunlit adds no geometry of its own.
##
## It is not the vocabulary untouched, though. It is a people with a roofline,
## and `hip` puts a tapered roof on every crowning mass — the arch's finial and
## stepped's spire included, both of which are cones when nothing says
## otherwise. The vocabulary as authored is what building with NO culture at all
## produces.
const SUNLIT_MASSING := {
	"name": "sunlit",
	"verticality": 1.0,
	"thickness": 1.0,
	"setback": 1.0,
	"variance": 1.0,
	"crown": "hip",
}

## Tall, thin-walled, sharply stepped and irregular, under flat parapets — the
## dark cliff-city to sunlit's lime-plaster town. `parapet` is the one crown
## that resolves to a plain box, so basalt's silhouette is the only one on the
## sheet with no shaped top at all: the building simply stops. Paired with a
## palette whose walls are the second-darkest thing it has, that is a mass
## rather than an outline, which is the reading the reduction test found.
const BASALT_MASSING := {
	"name": "basalt",
	"verticality": 1.45,
	"thickness": 0.78,
	"setback": 1.35,
	"variance": 1.30,
	"crown": "parapet",
}

## Low, heavy-walled, barely stepped and highly uniform, under domes. The
## levers and the crown are one statement rather than two: a people who vault
## in clay build thick and squat because that is what a vault stands on, and
## they build to a template because a vault is not something you improvise —
## hence the lowest `variance` of the three.
const MARL_MASSING := {
	"name": "marl",
	"verticality": 0.70,
	"thickness": 1.30,
	"setback": 0.45,
	"variance": 0.55,
	"crown": "dome",
}


## The massing for a culture name, falling back the same way palette() does and
## for the same reason: one complaint about the culture beats four about the
## geometry it produced.
static func massing(name: String) -> Dictionary:
	match name:
		"basalt": return BASALT_MASSING
		"marl": return MARL_MASSING
		_: return SUNLIT_MASSING


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


# ----------------------------------------------------------- the value rule
#
# The intent's 3D addendum: "role colors need enough VALUE separation to survive
# light and shadow, not just hue separation — the palette tests extend to lit
# and shadowed variants."
#
# Two colours of the same lightness in different hues are a perfectly good
# distinction on a flat 2D map and are nearly the same grey once a directional
# light is over them. So the check reduces each role to Rec.709 luma under two
# exposures and asserts a floor on every pair, plus one thing no floor catches.
#
#   1. LIT       every pair of roles differs by at least LIT_MIN in luma with
#                the sun on it.
#   2. SHADOWED  every pair still differs by at least SHADE_MIN under ambient
#                alone — the faces turned away from the sun.
#   3. ORDER     the ranking of roles by luma is IDENTICAL under the two. A
#                tinted ambient must not re-shuffle which role reads lighter.
#
# Worth saying plainly rather than leaving to be discovered: this project's
# ambient is close to neutral, so shadowing multiplies luma by about 0.14
# uniformly, and SHADE_MIN is therefore LIT_MIN carried through that multiply
# rather than an independent constraint. It is stated as its own number anyway,
# because it is the number that stops holding first if the lighting model
# changes — a warmer or dimmer ambient moves it and leaves LIT_MIN untouched.
#
# Part 3 is the part that is genuinely not implied by the other two, and it is
# what a hue-only separation actually costs: two roles that swap places between
# light and shade destroy the reading of which mass stands in front of which.
const LIT_MIN := 0.12
const SHADE_MIN := 0.014

## The lighting these variants stand in for — the diorama sheets' own sun and
## ambient rather than invented constants. Held here instead of read off a
## WorldEnvironment because this file touches no scene tree: the check has to
## run in the headless suite.
const SUN_ENERGY := 1.5
const AMBIENT_TINT := Color(0.46, 0.44, 0.40)
const AMBIENT_ENERGY := 0.55

## Exposure. Without it a pale albedo under a 1.5-energy sun exceeds 1.0 and
## clips, and two bright roles that clip both come out white — the check would
## report a palette failure that is really an exposure failure, and the fix
## would be to darken colours the renderer displays perfectly well. Normalising
## so that a white surface in full sun lands exactly at 1.0 puts the two
## variants on one scale and removes the clipping from the question.
const EXPOSURE := 1.0 / (SUN_ENERGY + AMBIENT_ENERGY)


## Rec.709 luma — the standard weighting for perceived lightness, and the same
## one tools/spike_reduce.gd uses to flatten a captured frame.
static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## An albedo under ambient light alone. Per-channel, because the ambient is
## TINTED — which is the entire reason a shadowed variant can rank two roles
## differently from a lit one, and so the entire reason check 3 exists.
static func shaded(c: Color) -> Color:
	var k := AMBIENT_ENERGY * EXPOSURE
	return Color(c.r * AMBIENT_TINT.r * k, c.g * AMBIENT_TINT.g * k,
			c.b * AMBIENT_TINT.b * k)


## An albedo facing the sun: direct light plus the same ambient.
static func lit(c: Color) -> Color:
	var s := shaded(c)
	var k := SUN_ENERGY * EXPOSURE
	return Color(c.r * k + s.r, c.g * k + s.g, c.b * k + s.b)


## Roles ranked light to dark under one of the two variants. No tie-break is
## needed: the value floors already forbid two roles landing on one luma.
static func value_order(pal: Dictionary, variant: Callable) -> Array:
	var names: Array = pal.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return luma(variant.call(pal[a])) > luma(variant.call(pal[b])))
	return names
