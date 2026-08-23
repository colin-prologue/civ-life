"""Ruin transformation: damage the generated building itself.

Same seed -> same damage. A culture's handwriting survives its collapse
because the surviving parts keep its proportions.
"""
from . import primitives as P
from .core import chan


def ruin(parts, condition, seed):
    """Filter/age a building's part list by condition in [0,1].

    Parts are ranked by height; high parts fall first. Accents and crowns go
    early (condition < ~0.8), the mid fabric erodes progressively, bases
    survive to the end. Returns (surviving_parts, age) where age in [0,1]
    drives material weathering.
    """
    rng = chan(seed, "ruin")
    if not parts:
        return parts, 0.0
    zmax = max(p["z"] for p in parts) or 1.0
    survivors = []
    for p in parts:
        zn = p["z"] / zmax
        tag = p.get("tag", "mid")
        # fall threshold: how much condition this part needs to survive
        need = 0.15 + zn * 0.75
        if tag == "accent":
            need = max(need, 0.82)
        elif tag == "crown":
            need = max(need, 0.68)
        elif tag == "base":
            need = 0.02
        need += (rng.random() - 0.5) * 0.12
        if condition >= need:
            survivors.append(p)
    if not survivors:  # a footprint always remains
        lowest = min(parts, key=lambda p: p["z"])
        survivors = [lowest]
    age = 1.0 - condition
    return survivors, age


def debris(seed, footprint=1.5, count=6, scale=0.14):
    """Small tumbled slabs scattered around a ruin."""
    import math
    from mathutils import Matrix
    rng = chan(seed, "debris")
    parts = []
    for i in range(count):
        s = scale * (0.5 + rng.random())
        b = P.slab(s, s * (0.5 + rng.random() * 0.8), s * 0.6)
        ang = rng.random() * math.pi * 2
        r = footprint * (0.5 + rng.random() * 0.8)
        rot = Matrix.Rotation(rng.random() * math.pi, 4, "Z")
        tip = Matrix.Rotation((rng.random() - 0.5) * 0.5, 4, "X")
        for v in b.verts:
            v.co = rot @ (tip @ v.co)
            v.co.x += math.cos(ang) * r
            v.co.y += math.sin(ang) * r
        parts.append({"bm": b, "mat": "stone", "tag": "base", "z": 0.05})
    return parts
