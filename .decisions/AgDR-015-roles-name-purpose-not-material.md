# AgDR-015 — Colour roles name purpose, the set is closed, and a culture is a mapping

**Status:** proposed
**Date:** 2026-09-04
**Parent intent:** `procedural-art`
**Supersedes:** the single `DioramaStyles.ROLES` mapping shipped by slice 1
**Ticket:** #35

## Decision

A style names **roles**; a **culture** maps every role to a colour. Three
properties make that more than a rename, and each is enforced by a test rather
than by convention.

**Roles name what a part is FOR.** `structure`, `footing`, `cap`, `aspiration`
— not `plaster`, `ochre`, `brass`, `wood`. A role named for a material has
already decided its own colour and leaves a culture nothing to express: there is
no useful answer to "what colour is `ochre` in this culture".

**The set is closed, in both directions.** Every role a style names resolves in
every shipped culture, and no culture carries a role no style asks for. A mass
with no role fails an assert at build time instead of inheriting the wall
colour, and an unresolvable role comes out magenta rather than black — black
being indistinguishable from a deliberately dark culture.

**A culture is data resolved after geometry.** `apply_roles` touches only
`color`. The same style, seed and id under two cultures produces parts differing
in exactly one field, which is asserted per style and also visible on the sheet:
if the geometry ever diverged, the two columns of a row would stop matching.

Colour separation is checked by **value, not hue** — the intent's 3D addendum.
Every pair of roles must differ by at least `LIT_MIN` (0.12) in Rec.709 luma
under this project's own sun, by at least `SHADE_MIN` (0.014) under its ambient
alone, and — the part neither floor implies — the roles must rank in the **same
lightness order** under both.

## Why

Slice 1's mapping was a palette wearing a vocabulary's clothes. Nothing about
it was wrong for one culture; it simply could not be extended to two, which is
the first thing the arc asks of it.

The value rule is the part that is new in 3D and it earned itself immediately.
`plaster_dim`, the plinth colour, sat **0.099** below `plaster` in luma — under
the floor. The two were separated by hue and barely at all by value, which is a
perfectly good distinction on a flat map and nearly the same grey once a
directional light is over it. A plinth that reads as the same tone as the wall
above it is not a plinth. It is now a dark stone base, 0.56 below the wall.

The order check exists because the ambient is **tinted**, so a shadowed face is
not a uniformly darker version of a lit one. Two roles that swap which reads
lighter between sun and shade destroy the reading of which mass stands in front
of which — a failure no pairwise floor detects.

Roles are also where the semantics live. `aspiration` is gold: deliberate human
intention, and scarce on purpose. Making scarcity a property of the **styles**
(two of four carry it, one part each, asserted) rather than of the palettes
means no choice of colour in any culture file can make gold ordinary.

## What was rejected

**Keeping material names and adding a second palette.** The cheapest change and
it fails on the second culture: `basalt`'s walls are not plaster, so either the
role name lies or the culture cannot have stone walls. The name has to stop
naming a material before a second culture can exist at all.

**An escape hatch for literal colours.** A `"color"` key on a mass, for the part
that "just needs to be that colour". Rejected per the ticket's own framing: a
part that needs a literal colour is a **hole in the role vocabulary**, and the
right response is to name the missing role. No part in four styles needed one.

**Shipping `patina` alongside `aspiration`.** They are a semantic pair —
verdigris is what time does to deliberate metal — and shipping both is
tempting. But nothing in the renderer varies colour with age (slice 3 ruled
weathering out of the condition ladder explicitly), so `patina` would resolve
for no part in any style: vocabulary with no caller, and a role the closure test
would then have to make an exception for. It belongs to whichever slice makes
colour a function of condition.

**Hue-distance as the palette check.** The obvious test, and the one that would
have passed the plinth that fails today.

**A `CultureStyle` resource now.** Deferred deliberately to slice 5 and informed
by `docs/superpowers/findings/2026-09-04-culture-style-parameters.md`. The
parameters that vary a style cannot be designed before there are styles to
extract them from, and the finding shows the pre-written candidate list was
about half speculation.

## What this costs

**Two cultures are distinguishable by colour and by nothing else.** That is the
honest result of this slice and it does not meet experiment S3's bar, which asks
that culture be legible in massing and silhouette. The reduction test proves it
rather than leaving it to opinion: at six value bands the two columns of the
sheet are very nearly indistinguishable. This was the expected outcome — a
palette swap is surface marks — but it means the word *culture* is currently
doing more work in the code than in the picture.

**The role set will have to grow, and growth is now a breaking change.** Closure
is asserted in both directions, so adding a role means adding it to every
culture in the same commit. That is the point, and it is friction.

## What would refute this

**If a style needs a colour no purpose-name fits.** The vocabulary is four words
against four styles; four words against twelve styles is a different bet. If
authoring a new style repeatedly ends in an argument about whether something is
`structure` or `cap`, the axis is wrong — the likely missing distinction is
between load-bearing mass and infill, which is one role, not a rewrite.

**If the value floors turn out to be palette-hostile.** `LIT_MIN` of 0.12 across
every pair means N roles must fit inside one unit interval with 0.12 between
each. At four roles that is comfortable; at eight it is a straitjacket, and the
honest fix is separation against *neighbouring* roles in the value order rather
than against all pairs.

**If the lighting model changes.** `SHADE_MIN` is `LIT_MIN` carried through an
almost-neutral ambient multiply, so it is not currently an independent
constraint. A warmer or dimmer ambient moves it and leaves `LIT_MIN` untouched —
it is stated as its own number because it is the one that stops holding first.

**If cultures end up needing per-style palettes.** A culture is one mapping for
all styles. If a real culture wants its monuments in a different material from
its houses, that is a role the styles are missing (`monumental_structure`), not
a reason to key palettes on style — but if the missing-role list grows past two
or three, the mapping shape is wrong.
