# AgDR-002 — The city is decentralised, and everything that moves is one kind of thing

**Status:** accepted
**Date:** 2026-08-15
**Parent intent:** `world-growth-tone`

## Decision

A city is **not a tile with numbers on it.** It is a set of nodes placed on
separate hexes — farms, granaries, markets, workshops — connected by routes,
with citizens physically travelling between them. Closer to the Impressions
city-builders (Caesar, Pharaoh) than to Civilization's single-tile city.

Second half, and the load-bearing one: **citizens, herds, and bands are the same
kind of object on the same movement layer.** One entity type with a position, a
route or a drive, and behaviour. Not three parallel systems that happen to share
a map.

## Why

The two halves of this project — a world that lives on its own, and a city the
player builds — were otherwise going to be separate simulations sharing a
coordinate space. That makes world pressure reach the player only as a stat
penalty, which is exactly the abstraction this game exists to avoid.

Unifying them means the herd that wanders through your farm district and the
farmer walking to the granary are the same kind of object, interacting through
ordinary co-location rather than through a special-case rule. The world's
activity lands on the player *mechanically* and legibly.

It also answers what the player's verb is. **You place and connect nodes; the
world moves through and around them.** Routes become the surface where the two
halves meet.

One property falls out that was not designed in and is worth keeping: roads are
simultaneously your infrastructure and your exposure. Every route that makes the
city work is a route something else can travel.

## Tuning constraint this inherits

The walker layer must be **boringly reliable when nothing is stressing it.**

This is the known failure mode of the genre. Caesar's walkers wander, coverage
depends on road topology, and the game becomes one-tile layout puzzles — precise
micro-optimisation, which `world-growth-tone` rules out. If routing is reliable
under normal conditions, layout is something you set up once and the interest
comes from the world interacting with it. If routing is fragile, every world
event lands on top of an already-annoying baseline.

Fewer, chunkier nodes rather than many small buildings pushes the same way.

## What was rejected

**Civ-style single-tile cities with worked tiles in a radius.** Far simpler,
well understood, and it would have let the ecology be a modifier on tile yields.
Rejected because it makes the living world decorative: herds moving would change
a number rather than change a place, and the entire premise is that the world is
somewhere you live rather than a spreadsheet you read.

**Separate systems for citizens and wildlife.** Simpler to build each, and each
could be tuned independently. Rejected because every interaction between them
would then need bespoke code, which is precisely the coupling that
`world-growth-tone` rule 4 says serendipity depends on. Making them one type
means new interactions come from behaviour rather than from new special cases.

## What would make this the wrong call

**If node placement turns out to be the whole game.** If players spend their
time arranging nodes and roads rather than watching the world, this has become a
layout puzzle with ecology as set dressing — the opposite of the intent, and the
unified layer would be elaborate machinery serving the wrong activity.

**If one entity type cannot carry both behaviours without becoming a
type-switch.** If citizen logic and wildlife logic share a class but no actual
behaviour — every method branching on which kind it is — then the unification is
nominal, and two clean systems would have been better than one confused one.

Early signal for both: watch what ticket 6 has to write. If citizens need a
route-following behaviour that herds share, the unification is real. If it needs
`if entity.is_citizen`, it is not.
