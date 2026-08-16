"""The historical sequence: one valley, seven dates, one camera.

Continuity of place is the whole point: terrain, tree positions, building
sites, and road alignment are precomputed once from the seed; each date's
config only decides what exists, in what condition, under which culture.
The mountains never change.
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


# ------------------------------------------------------------ the fixed place

def valley_plan(seed, n_sites=14, n_tree_candidates=420):
    """Everything position-shaped, computed once for all dates."""
    plan = {}
    plan["terrain"] = T.terrain_mesh(seed, size=26.0, res=46,
                                     exaggeration=1.6, terrace=0.45)
    _, f = plan["terrain"]
    plan["f"] = f

    # the old road: bends with the river (the imperial alignment)
    path = []
    for i in range(25):
        t = i / 24.0
        y = -11.0 + 22.0 * t
        x = math.sin(y * 0.14) * 2.2 + 1.8 + math.sin(t * 3.0) * 0.7
        path.append((x, y))
    plan["road_old"] = path

    # the new road: a straighter later alignment, crossing the old one
    path2 = []
    for i in range(25):
        t = i / 24.0
        x = -9.0 + 20.0 * t
        y = -2.5 + 6.0 * t + math.sin(t * 2.2) * 0.8
        path2.append((x, y))
    plan["road_new"] = path2

    # building sites strung along the old road's mid-section
    rng = chan(seed, "sites")
    sites = []
    i_path = 5
    while len(sites) < n_sites and i_path < len(path) - 2:
        px, py = path[i_path]
        side = 1 if rng.random() < 0.5 else -1
        d = 0.9 + rng.random() * 1.2
        x, y = px + side * d, py + (rng.random() - 0.5) * 0.8
        if f(x, y) > -0.1:
            sites.append((x, y, rng.random() * 0.6 - 0.3))
        i_path += 1
    plan["sites"] = sites

    # tree candidates with min spacing; each index keeps its kind forever
    trng = chan(seed, "treecand")
    cands = []
    attempts = 0
    while len(cands) < n_tree_candidates and attempts < n_tree_candidates * 40:
        attempts += 1
        x = (trng.random() - 0.5) * 24.0
        y = (trng.random() - 0.5) * 24.0
        z = f(x, y)
        if z < -0.05:
            continue
        river_x = math.sin(y * 0.14) * 2.2
        if abs(x - river_x) < 1.4:
            continue
        if any((x - q[0]) ** 2 + (y - q[1]) ** 2 < 1.0 for q in cands):
            continue
        cands.append((x, y, z))
    plan["trees"] = cands
    return plan


def _near_path(x, y, path, r):
    return any(abs(x - px) < r and abs(y - py) < r for px, py in path)


def _near_sites(x, y, sites, n, r):
    return any((x - s[0]) ** 2 + (y - s[1]) ** 2 < r * r for s in sites[:n])


# ------------------------------------------------------------- one date built

def build_date(seed, plan, cfg):
    """Assemble the valley at one date. cfg keys:

    valley_density, mtn_density: tree acceptance rates by zone
    clear_settlement: suppress trees near road/sites (people keep them clear)
    reclaim: allow trees inside the settlement footprint (nature crossing)
    road_old: None | (keep_frac, lift, material)
    road_new: None | (keep_frac, lift, material)
    farms: strip count
    deco: (site_count, condition_lo, condition_hi)  - the first culture
    organic: site_count reusing the first sites     - the successor
    hero: None | condition
    scars: dead-tree / debris count near the settlement (hardship marks)
    """
    f = plan["f"]
    tbm, _ = T.terrain_mesh(seed, size=26.0, res=46,
                            exaggeration=1.6, terrace=0.45)
    obj_from_bmesh(tbm, "terrain", material("moss", roughness=0.95))
    obj_from_bmesh(T.water_mesh(26.0, level=-0.30),
                   "water", material("water", roughness=0.15))

    for key, path in (("road_old", plan["road_old"]),
                      ("road_new", plan["road_new"])):
        spec = cfg.get(key)
        if not spec:
            continue
        keep, lift, mat = spec
        bm = T.road_mesh_worn(f, path, seed, width=0.42, lift=lift, keep=keep)
        obj_from_bmesh(bm, key, material(mat, roughness=0.95))

    # farms flank the old road's southern approach
    n_farms = cfg.get("farms", 0)
    fx, fy = plan["road_old"][4][0] - 2.2, plan["road_old"][4][1]
    for i in range(n_farms):
        strip = P.slab(0.35, 2.6, 0.06)
        x = fx - (i % 5) * 0.55
        y = fy + (i // 5) * 3.0
        _place_parts([{"bm": strip, "mat": "ochre" if i % 2 else "plaster2",
                       "tag": "base", "z": 0}], "farm_%d" % i, (x, y, f(x, y)))

    sites = plan["sites"]
    kinds = ["residential", "residential", "residential", "civic", "stepped"]

    # the first culture's fabric (whole or ruined)
    n_deco, c_lo, c_hi = cfg.get("deco", (0, 1.0, 1.0))
    for i in range(min(n_deco, len(sites))):
        x, y, rot = sites[i]
        parts = A.GENERATORS[kinds[i % len(kinds)]](DECO, seed * 100 + i,
                                                    scale=0.55)
        crng = chan(seed, "cond", i)
        cond = c_lo + crng.random() * (c_hi - c_lo)
        if cond < 0.995:
            parts, age = ruin(parts, cond, seed * 100 + i)
            _place_parts(parts, "deco_%d" % i, (x, y, f(x, y)), rot_z=rot,
                         age=age)
            if cond < 0.5:
                _place_parts(debris(seed * 100 + i, footprint=0.8,
                                    count=3, scale=0.1),
                             "deb_%d" % i, (x, y, f(x, y)))
        else:
            _place_parts(parts, "deco_%d" % i, (x, y, f(x, y)), rot_z=rot)

    # the successor culture reuses the oldest foundations, slightly shifted
    n_org = cfg.get("organic", 0)
    for i in range(min(n_org, len(sites))):
        x, y, rot = sites[i]
        parts = A.GENERATORS[kinds[i % len(kinds)]](ORGANIC, seed * 300 + i,
                                                    scale=0.55)
        _place_parts(parts, "org_%d" % i, (x + 0.35, y + 0.25, f(x + 0.35,
                     y + 0.25)), rot_z=rot + 0.8)

    # the hero monument on the rise across the river
    hero_cond = cfg.get("hero")
    if hero_cond is not None:
        hx, hy = -5.0, 3.0
        hz = f(hx, hy)
        hero = A.hero_arch(DECO, seed + 7, scale=1.1)
        if hero_cond < 0.995:
            hero, age = ruin(hero, hero_cond, seed + 7)
            _place_parts(hero, "hero", (hx, hy, hz), rot_z=0.5, age=age)
            _place_parts(debris(seed + 7, footprint=2.0,
                                count=int((1 - hero_cond) * 10), scale=0.22),
                         "hero_deb", (hx, hy, hz))
        else:
            _place_parts(hero, "hero", (hx, hy, hz), rot_z=0.5)

    # hardship marks: dead trees and rubble around the settlement
    for i in range(cfg.get("scars", 0)):
        srng = chan(seed, "scar", i)
        bx, by, _ = sites[i % len(sites)]
        x = bx + (srng.random() - 0.5) * 3.0
        y = by + (srng.random() - 0.5) * 3.0
        if srng.random() < 0.5:
            _place_parts(V.TREES["dead"](seed * 700 + i, scale=1.0),
                         "scar_%d" % i, (x, y, f(x, y)))
        else:
            _place_parts(debris(seed * 700 + i, footprint=0.6, count=4,
                                scale=0.12), "scar_%d" % i, (x, y, f(x, y)))

    # forest: same candidates every date; only acceptance changes
    n_active_sites = max(n_deco, n_org)
    for i, (x, y, z) in enumerate(plan["trees"]):
        mtn = x > 4.0 or x < -8.0
        p = cfg.get("mtn_density", 0.9) if mtn else cfg.get("valley_density",
                                                            0.5)
        in_town = (_near_path(x, y, plan["road_old"][3:20], 1.3)
                   or _near_sites(x, y, sites, len(sites), 1.6))
        if in_town:
            if cfg.get("reclaim"):
                p = min(0.95, p + 0.25)   # nature crosses the old boundaries
            elif cfg.get("clear_settlement"):
                p = 0.0
        if cfg.get("road_new") and _near_path(x, y, plan["road_new"], 1.1):
            p *= 0.15                     # the new culture keeps its road clear
        if n_active_sites and cfg.get("clear_settlement"):
            if _near_sites(x, y, sites, n_active_sites, 2.2):
                p *= 0.2
        if chan(seed, "treekeep", i).random() > p:
            continue
        krng = chan(seed, "treekind", i)
        kind = "conifer" if mtn else ("broadleaf" if krng.random() < 0.7
                                      else "shrub")
        parts = V.TREES[kind](seed * 31 + i, scale=0.9 + krng.random() * 0.5)
        _place_parts(parts, "tree_%d" % i, (x, y, z), rot_z=krng.random() * 6.28)


# ------------------------------------------------------------------ the dates

SEQUENCE = [
    (0, "wild", dict(
        valley_density=0.55, mtn_density=0.92)),
    (800, "settled", dict(
        valley_density=0.35, mtn_density=0.9, clear_settlement=True,
        farms=4, deco=(3, 1.0, 1.0),
        road_old=(0.55, 0.03, "plaster2"))),
    (2000, "the city", dict(
        valley_density=0.2, mtn_density=0.88, clear_settlement=True,
        farms=8, deco=(9, 1.0, 1.0), hero=1.0,
        road_old=(1.0, 0.06, "plaster2"))),
    (3500, "the peak", dict(
        valley_density=0.14, mtn_density=0.85, clear_settlement=True,
        farms=10, deco=(14, 1.0, 1.0), hero=1.0,
        road_old=(1.0, 0.06, "plaster"))),
    (4200, "hardship", dict(
        valley_density=0.22, mtn_density=0.88, clear_settlement=True,
        farms=5, deco=(12, 0.45, 0.85), hero=0.8, scars=8,
        road_old=(0.75, 0.05, "plaster2"))),
    (5000, "silent", dict(
        valley_density=0.5, mtn_density=0.92, reclaim=True,
        farms=0, deco=(10, 0.1, 0.35), hero=0.5,
        road_old=(0.4, 0.02, "stone"))),
    (7000, "the return", dict(
        valley_density=0.4, mtn_density=0.9, clear_settlement=False,
        reclaim=True, farms=3, deco=(9, 0.08, 0.2), organic=5, hero=0.45,
        road_old=(0.3, 0.02, "stone"),
        road_new=(1.0, 0.06, "plaster2"))),
]
