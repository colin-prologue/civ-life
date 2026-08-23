"""Turn-lapse motion test: does discrete per-turn change read as growth
or as popping?

One 120-turn timeline over the sequence valley, rendered twice from the
same schedule:
  - 'cut'   : elements appear/vanish at full size the turn they change -
              what a naive turn-based renderer does.
  - 'eased' : same discrete schedule, but the view interprets it - each
              element scales in/out over a few turns, aging tints move
              continuously, ruin steps are finer. Tween the view, never
              the sim.
The sim-side truth (the schedule) is identical in both; only the
interpretation differs. That is exactly the contract the game layer has.
"""
import math

from . import architecture as A
from . import primitives as P
from . import terrain as T
from . import vegetation as V
from .aging import ruin, debris
from .cultures import DECO, ORGANIC
from .core import chan, material, obj_from_bmesh
from .diorama import _place_parts


TURNS = 120


def _lerp_steps(t, steps):
    """Piecewise-linear value through [(turn, value), ...]."""
    if t <= steps[0][0]:
        return steps[0][1]
    for (t0, v0), (t1, v1) in zip(steps, steps[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * (t - t0) / max(1e-6, t1 - t0)
    return steps[-1][1]


def build_schedule(seed, plan):
    """Every element's presence/condition as a pure function of turn."""
    sched = {}

    # --- buildings: deco fabric, then organic return on the same sites
    n_sites = len(plan["sites"])
    n_deco, n_org = min(9, n_sites), min(5, n_sites)
    deco = []
    for i in range(n_deco):
        appear = 18 + i * 5
        target = 0.10 + chan(seed, "ctar", i).random() * 0.25
        deco.append({"appear": appear, "target": target})
    sched["deco"] = deco
    sched["org"] = [{"appear": 100 + j * 4} for j in range(n_org)]
    sched["hero_appear"] = 50

    # --- roads as revealed/decaying segment lists (smoothed once)
    from .hexworld import chaikin
    old_pts = chaikin(plan["road_old"], 2)
    new_pts = chaikin(plan["road_new"], 2)
    sched["road_old_pts"] = old_pts
    sched["road_new_pts"] = new_pts
    return sched


def deco_condition(t, target):
    if t < 72:
        return 1.0
    if t < 95:
        return 1.0 + (target - 1.0) * (t - 72) / 23.0
    return target


def tree_presence(seed, plan, i, t, active_sites):
    """Presence of tree candidate i at turn t - monotonic per hash."""
    x, y, _ = plan["trees"][i]
    mtn = x > 4.0 or x < -8.0  # unused zoning from the 2D valley; keep simple
    # density by phase (valley floor)
    d = _lerp_steps(t, [(0, 0.55), (25, 0.35), (45, 0.20), (65, 0.14),
                        (80, 0.22), (95, 0.50), (120, 0.40)])
    in_town = _near_town(plan, x, y)
    if in_town:
        if 20 <= t <= 88:
            d = 0.0
        elif t > 88:
            d = min(0.95, d + 0.25)
    if t > 100 and _near_pts(plan["road_new"], x, y, 1.1):
        d *= 0.15
    return chan(seed, "treekeep", i).random() < d


def _near_town(plan, x, y):
    if _near_pts(plan["road_old"][3:20], x, y, 1.3):
        return True
    return any((x - s[0]) ** 2 + (y - s[1]) ** 2 < 1.6 ** 2
               for s in plan["sites"][:9])


def _near_pts(pts, x, y, r):
    return any(abs(x - px) < r and abs(y - py) < r for px, py in pts)


def presence_intervals(seed, plan, n):
    """[(appear, vanish), ...] per tree across the whole timeline."""
    out = []
    for i in range(n):
        iv = []
        prev = False
        start = None
        for t in range(TURNS + 1):
            p = tree_presence(seed, plan, i, t, 9)
            if p and not prev:
                start = t
            if prev and not p:
                iv.append((start, t))
            prev = p
        if prev:
            iv.append((start, TURNS + 1))
        out.append(iv)
    return out


RAMP_IN = 4.0   # turns an arriving element takes to reach full size
RAMP_OUT = 3.0  # turns a leaving element takes to shrink away


def _ramp(t, appear, vanish, ease):
    """Scale factor for an element alive on [appear, vanish)."""
    if not ease:
        return 1.0 if appear <= t < vanish else 0.0
    if t < appear or t >= vanish + RAMP_OUT:
        return 0.0
    s = 1.0
    if t < appear + RAMP_IN:
        s = min(s, (t - appear + 1) / RAMP_IN)
    if t >= vanish:
        s = min(s, max(0.0, 1.0 - (t - vanish + 1) / RAMP_OUT))
    return s


def build_frame(seed, plan, sched, tree_iv, t, ease):
    """Assemble the valley at turn t under one interpretation."""
    f = plan["f"]
    tbm, _ = T.terrain_mesh(seed, size=26.0, res=46,
                            exaggeration=1.6, terrace=0.45)
    obj_from_bmesh(tbm, "terrain", material("moss", roughness=0.95))
    obj_from_bmesh(T.water_mesh(26.0, level=-0.30),
                   "water", material("water", roughness=0.15))

    # roads: reveal along their length; the old one decays after 85
    for key, pts, t_start, t_span, decay in (
            ("road_old", sched["road_old_pts"], 14, 26, True),
            ("road_new", sched["road_new_pts"], 100, 14, False)):
        import bmesh
        bm = bmesh.new()
        n_seg = len(pts) - 1
        for k in range(n_seg):
            reveal = t_start + t_span * k / n_seg
            if t < reveal:
                continue
            if decay and t > 85:
                if chan(seed, "roaddecay", k).random() < (t - 85) / 30 * 0.75:
                    continue
            from mathutils import Vector
            a = Vector((pts[k][0], pts[k][1], 0.0))
            b = Vector((pts[k + 1][0], pts[k + 1][1], 0.0))
            if (b - a).length < 1e-6:
                continue
            d = (b - a).normalized()
            nv = Vector((-d.y, d.x, 0.0)) * 0.21
            quad = []
            worn = decay and t > 85
            for c in (a - nv, a + nv, b + nv, b - nv):
                quad.append(bm.verts.new((c.x, c.y,
                                          f(c.x, c.y) + (0.02 if worn else 0.06))))
            bm.faces.new(quad)
        obj_from_bmesh(bm, key,
                       material("stone" if (decay and t > 85) else "plaster2",
                                roughness=0.95))

    kinds = ["residential", "residential", "residential", "civic", "stepped"]
    sites = plan["sites"]

    # deco fabric
    for i, b in enumerate(sched["deco"]):
        s = _ramp(t, b["appear"], TURNS + 10, ease)
        if s <= 0.0:
            continue
        cond = deco_condition(t, b["target"])
        step = 0.05 if ease else 0.25
        cond_q = max(step, round(cond / step) * step)
        parts = A.GENERATORS[kinds[i % len(kinds)]](DECO, seed * 100 + i,
                                                    scale=0.55)
        x, y, rot = sites[i]
        if cond_q < 0.995:
            parts, age = ruin(parts, cond_q, seed * 100 + i)
            if not ease:
                age = round(age * 4) / 4.0
            _place_parts(parts, "d%d" % i, (x, y, f(x, y)), rot_z=rot,
                         scale=s, age=age)
        else:
            _place_parts(parts, "d%d" % i, (x, y, f(x, y)), rot_z=rot,
                         scale=s)

    # organic return
    for j, b in enumerate(sched["org"]):
        s = _ramp(t, b["appear"], TURNS + 10, ease)
        if s <= 0.0:
            continue
        x, y, rot = sites[j]
        parts = A.GENERATORS[kinds[j % len(kinds)]](ORGANIC, seed * 300 + j,
                                                    scale=0.55)
        _place_parts(parts, "o%d" % j, (x + 0.35, y + 0.25,
                                        f(x + 0.35, y + 0.25)),
                     rot_z=rot + 0.8, scale=s)

    # hero monument: built at 50, decays from 78
    s = _ramp(t, sched["hero_appear"], TURNS + 10, ease)
    if s > 0.0:
        cond = _lerp_steps(t, [(0, 1.0), (78, 1.0), (102, 0.45), (120, 0.45)])
        step = 0.05 if ease else 0.25
        cond_q = max(step, round(cond / step) * step)
        hx, hy = -5.0, 3.0
        parts = A.hero_arch(DECO, seed + 7, scale=1.1)
        if cond_q < 0.995:
            parts, age = ruin(parts, cond_q, seed + 7)
            if not ease:
                age = round(age * 4) / 4.0
            _place_parts(parts, "hero", (hx, hy, f(hx, hy)), rot_z=0.5,
                         scale=s, age=age)
        else:
            _place_parts(parts, "hero", (hx, hy, f(hx, hy)), rot_z=0.5,
                         scale=s)

    # farms
    for i in range(5):
        s = _ramp(t, 16 + i * 3, 82 + i * 2, ease)
        if s <= 0.0:
            continue
        strip = P.slab(0.35, 2.6, 0.06)
        fx = plan["road_old"][4][0] - 2.2 - i * 0.55
        fy = plan["road_old"][4][1]
        _place_parts([{"bm": strip, "mat": "ochre" if i % 2 else "plaster2",
                       "tag": "base", "z": 0}], "farm_%d" % i,
                     (fx, fy, f(fx, fy)), scale=s)

    # trees from precomputed intervals
    for i, ivs in enumerate(tree_iv):
        s = 0.0
        for a, b in ivs:
            s = max(s, _ramp(t, a, b, ease))
        if s <= 0.0:
            continue
        x, y, z = plan["trees"][i]
        krng = chan(seed, "treekind", i)
        kind = "broadleaf" if krng.random() < 0.7 else "shrub"
        parts = V.TREES[kind](seed * 31 + i, scale=0.9 + krng.random() * 0.5)
        _place_parts(parts, "t%d" % i, (x, y, z), rot_z=krng.random() * 6.28,
                     scale=s)
