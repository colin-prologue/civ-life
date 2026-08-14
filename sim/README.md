# sim/ — the headless world simulation

Plain GDScript classes. **No `Node` dependency, no rendering, no input, no
wall-clock time, no unseeded randomness.**

Everything here must be constructible and runnable without an engine scene tree,
because that is what makes the world testable headlessly and reproducible from a
seed. See `.decisions/AgDR-001-headless-sim-core.md` for why this boundary is
load-bearing and what would refute it.

If something here needs to reach into `game/`, the boundary is in the wrong
place — say so in the PR rather than working around it.
