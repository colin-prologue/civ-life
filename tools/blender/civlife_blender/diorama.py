"""The tiny diorama: valley, river, forest, road, settlement, hero monument.

Deterministic placement rules only - no simulation. This is the 'does the
whole thing look like civ-life?' test.
"""
import math

from mathutils import Matrix, Vector

from . import architecture as A
from . import primitives as P
from . import terrain as T
from . import vegetation as V
from .aging import ruin, debris
from .core import chan, material, aged_material, obj_from_bmesh


def _place_parts(parts, name, loc, rot_z=0.0, scale=1.0, age=0.0):
    objs = []
    m = (Matrix.Translation(Vector(loc))
         @ Matrix.Rotation(rot_z, 4, "Z")
         @ Matrix.Scale(scale, 4))
    for i, p in enumerate(parts):
        mat = aged_material(p["mat"], age) if age > 0.05 else material(p["mat"])
        objs.append(obj_from_bmesh(p["bm"], "%s_%d" % (name, i), mat, m))
    return objs


def build_valley(seed, culture, exaggeration=1.6, terrace=0.45,
                 n_trees=44, n_buildings=9, ruin_culture=None):
    """Assemble the diorama; returns the camera target point."""
    rng = chan(seed, "diorama")

    tbm, f = T.terrain_mesh(seed, size=26.0, res=46,
                            exaggeration=exaggeration, terrace=terrace)
    obj_from_bmesh(tbm, "terrain", material("moss", roughness=0.95))
    obj_from_bmesh(T.water_mesh(26.0, level=-0.30 * exaggeration / 1.6),
                   "water", material("water", roughness=0.15))

    # road: crosses the valley, bends with the river
    path = []
    for i in range(25):
        t = i / 24.0
        y = -11.0 + 22.0 * t
        x = math.sin(y * 0.14) * 2.2 + 1.8 + math.sin(t * 3.0) * 0.7
        path.append((x, y))
    obj_from_bmesh(T.road_mesh(f, path, width=0.42),
                   "road", material("plaster2", roughness=0.95))

    # settlement: buildings strung along the road's mid-section
    kinds = ["residential", "residential", "residential", "civic", "stepped"]
    placed = 0
    i_path = 6
    while placed < n_buildings and i_path < len(path) - 2:
        px, py = path[i_path]
        side = 1 if rng.random() < 0.5 else -1
        d = 0.9 + rng.random() * 1.2
        x, y = px + side * d, py + (rng.random() - 0.5) * 0.8
        z = f(x, y)
        if z > -0.1:  # keep out of the river
            kind = kinds[placed % len(kinds)]
            parts = A.GENERATORS[kind](culture, seed * 100 + placed, scale=0.55)
            _place_parts(parts, "bld_%d" % placed, (x, y, z),
                         rot_z=rng.random() * 0.6 - 0.3)
            placed += 1
        i_path += 1

    # farm: furrow strips beside the settlement
    fx, fy = path[4][0] - 2.2, path[4][1]
    for i in range(5):
        strip = P.slab(0.35, 2.6, 0.06)
        x = fx - i * 0.55
        z = f(x, fy)
        _place_parts([{"bm": strip, "mat": "ochre" if i % 2 else "plaster2",
                       "tag": "base", "z": 0}], "farm_%d" % i, (x, fy, z))

    # hero monument on the rise across the river
    hx, hy = -5.0, 3.0
    hz = f(hx, hy)
    hero = A.hero_arch(culture, seed + 7, scale=1.1)
    if ruin_culture is not None:
        hero, age = ruin(hero, 0.45, seed + 7)
        _place_parts(hero, "hero", (hx, hy, hz), rot_z=0.5, age=age)
        _place_parts(debris(seed + 7, footprint=2.5, count=8, scale=0.3),
                     "hero_debris", (hx, hy, hz))
    else:
        _place_parts(hero, "hero", (hx, hy, hz), rot_z=0.5)

    # forest: min-distance scatter, denser on the mountain side and far bank
    pts = []
    attempts = 0
    while len(pts) < n_trees and attempts < n_trees * 30:
        attempts += 1
        x = (rng.random() - 0.5) * 24.0
        y = (rng.random() - 0.5) * 24.0
        z = f(x, y)
        if z < -0.05:
            continue
        river_x = math.sin(y * 0.14) * 2.2
        if abs(x - river_x) < 1.4:      # river banks stay clear
            continue
        near_road = any(abs(x - px) < 1.3 and abs(y - py) < 1.3
                        for px, py in path[3:20])
        if near_road and rng.random() < 0.8:
            continue
        density = 0.9 if x > 4.0 or x < -8.0 else 0.25
        if rng.random() > density:
            continue
        if any((x - q[0]) ** 2 + (y - q[1]) ** 2 < 1.1 for q in pts):
            continue
        pts.append((x, y, z))
    for i, (x, y, z) in enumerate(pts):
        kind = "conifer" if x > 4.0 else ("broadleaf" if rng.random() < 0.7
                                          else "shrub")
        parts = V.TREES[kind](seed * 31 + i, scale=0.9 + rng.random() * 0.5)
        _place_parts(parts, "tree_%d" % i, (x, y, z),
                     rot_z=rng.random() * 6.28)

    return (0.5, 0.0, 0.5)  # camera target
