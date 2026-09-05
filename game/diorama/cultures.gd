class_name DioramaCultures
extends RefCounted
## Colour roles, and the per-culture mappings that resolve them.
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

## Every culture, in sheet order. Two is what experiment S3 asks for.
const NAMES := ["sunlit", "basalt"]


## The palette for a culture name. An unknown name falls back to the first
## culture rather than returning an empty Dictionary: an empty palette makes
## EVERY role unresolvable, so a typo'd export would surface as four complaints
## about roles that are perfectly fine rather than as one about the culture.
static func palette(name: String) -> Dictionary:
	match name:
		"basalt": return BASALT
		_: return SUNLIT


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
