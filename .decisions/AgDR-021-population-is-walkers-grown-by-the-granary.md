# AgDR-021 — Population is the walkers, and the granary grows it

**Status:** accepted
**Date:** 2026-09-13
**Parent intent:** `world-growth-tone` (rules 1–3) · extends `AgDR-002`, `AgDR-013`

## Decision

**A citizen is the unit of population.** There are no non-walking people. Every
person the city has is on a road, carrying.

**People eat from the granary at the end of their road, and the granary decides
growth.** Each turn a citizen asks its route's sink for `Citizen.APPETITE`. The
node counts mouths and unmet appetite; it cannot tell who asked. After agents
step, a node that fed somebody and held above `GROWTH_FRACTION` of capacity for
`GROWTH_TURNS` gains one carrier on its thinnest road. A node that closes two
years of books (`LEAN_TURNS`) with more than `LEAN_SHARE` (a sixth) of its
people's appetite unmet loses the newest carrier on its busiest road. It never
goes below the `CITIZENS_PER_ROUTE` the road was laid with. One empty season is
at most an eighth of a two-year book, so it can't cross the line.

The loss rule was tuned by measurement, and it went wrong twice first.
- **A run of hungry turns.** A city eating more than its land grows still gets
  a few fed turns after each delivery, and each one restarted the count. A city
  that grew on a fresh field stayed above what the worn field fed, forever.
- **A third of one year.** This left a dead band. On the standard seed, 9 people
  were a quarter short and stayed at 9. 6 people couldn't fill the granary to
  half and stayed at 6. A city knocked from 9 to 6 never came back.

A sixth of two years closes that band. It needs two years because one year
can't tell a single empty season (a quarter of the year) from a city that is a
quarter short.

**The bound is the land, not a cap.** Nothing in `sim/` knows a maximum
population. Farms and camps set what arrives and appetite sets what leaves, so
the count settles where the two meet.

**Roads know their carriers** (`Route.carriers`), because the growth rule runs
inside the turn loop and `AgDR-013` keeps `world.citizens()` out of it.

## Rejected

**Growth without loss.** Simpler, and closer to "no removal". Rejected because
population then only ratchets up. It climbs to what a summer feeds and sits
there, short every winter, and a perturbation has nothing to return from. Rule 3
needs a restoring force in both directions. The founding-crew floor keeps rule 2
intact: hunger can shrink a city, but never below the people its roads started
with.

**A hard population cap.** It would assert AC3 trivially and say nothing about
the world.

**A granary capacity of 5000 with an absolute growth threshold.** At 5000 no
fraction is reachable, so the rule would be stated against a number the city
never sees. Capacity is now 40, which turns surplus into people well before it
turns into refused deliveries.

## What would make this the wrong call

**If the city needs people who are not walkers.** Housing, specialists, or idle
residents would break "one person, one road". If that is needed, the population
count wants its own home and walkers become a share of it.

**If losing people reads as punishment.** A dot vanishing after a lean year may
feel like the famine the intent forbids. If playtesting says so, the fallback is
growth without loss plus a softer restoring force, such as slower walkers while
hungry, not a larger floor.

**If a granary with no roads needs to grow a city.** Growth attaches people to
roads. A granary fed some other way would have nowhere to put them.
