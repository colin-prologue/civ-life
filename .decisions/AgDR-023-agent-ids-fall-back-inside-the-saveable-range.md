# AgDR-023 — Agent ids fall back inside the saveable range; stored quantities are bounded by their readers

**Status:** accepted
**Date:** 2026-09-30

## Decision

**Agent ids.** `CityGen.MAX_AGENT_ID` (2^53 - 1, the last integer a JSON number
holds exactly) is the top of the id range, for the game and for `WorldSave`.
`CityGen._next_agent_id()` still returns one past the highest id, so ordinary
worlds number exactly as before. When that would pass the ceiling it returns the
lowest id nobody holds instead. The newcomer is unique, the choice is
deterministic, nobody already in the world is renumbered, and the world still
saves and reloads. Reaching the fallback needs an agent at the ceiling, which
only an edited save produces; exhausting the range would need 2^53 agents.

**Stored quantities.** A store, capacity, carried amount, herd population, yield
or flow is refused on load above `WorldSave.MAX_MAGNITUDE` (2^62). The bound is
derived from the readers, not from balance: `TurnReport._mark_of` does
`floori(value / step)` and `Herd.head_count` does `roundi`, both undefined past a
64-bit integer, and a value that is merely finite as a float32 (1e30) passes
narrowing yet breaks them. Chronicle totals sum these into float32 rows; with each
term at most 2^62 the sum cannot reach float32's ceiling short of about 10^20
agents, so no separate aggregate check is kept. Two readings of 3e38 are refused
for their own size, not for their sum.

## Rejected

- Lowering `MAX_AGENT_ID` by one: the next birth would still need a rule at the
  new ceiling.
- A no-allocation path (refuse to grow past the ceiling): a city that silently
  stops growing is a worse failure than a reused low id.
- A population or store cap chosen for play: it would be a product limit invented
  in the decoder.

## Two more places the same rule applies (revised at gate 8)

An earlier revision capped the clock at 2^52 and the whole world's demand at
`MAX_MAGNITUDE`. Both were product limits invented in the decoder to avoid a
representation problem; both are removed.

- **Turn: lossless supported integers, and a deliberate end of the clock.** `turn`
  is written as a nonnegative decimal string, as `seed` is, so every int64 turn
  saves and loads exactly. The decoder parses the string as text (digits only,
  compared with INT64_MAX as text, never through float). Older saves with a plain
  whole JSON number still load, up to 2^53. `WorldMap.LAST_TURN` (INT64_MAX) can
  save and load but is terminal: `advance_refusal()` names it, `advance_turn()`
  returns the unchanged turn before snapshotting or touching anything, and the
  game stops playing and shows the refusal. This protects the `turn + 1` in the
  report; it does not promise unbounded progression in a finite type.
- **Aggregate demand: format safely, do not bound.** The only reader that took an
  aggregate (several herds' demand on one tile, or a season's forage) down to an
  integer was `TurnChange.describe()`, through `roundi`. It now writes the
  magnitude with `%.0f` of a rounded float, so any finite aggregate reads whole and
  unsigned. A load-time bound would be insufficient anyway, since herds converge
  after loading. Per-value readers (`_mark_of`, `head_count`) keep the per-value
  ceiling above.

## What would make this the wrong call

A second system that assumes ids rise with age (the fallback id is lower than
older agents'). Today `route.carriers` order, not id order, decides who is newest.
A reader of stored quantities that needs a tighter bound than 2^62 moves
`MAX_MAGNITUDE`.
