"""Cardboard nature: faceted masses and cardstock silhouettes.

Two languages are generated side by side so the contact sheet can decide:
  - 'model' trees: faceted icosphere canopies on prism trunks
  - 'card' trees: crossed thin cards with real thickness
"""
import math

from mathutils import Matrix

from . import primitives as P
from .core import chan


def conifer(seed, scale=1.0, style="model"):
    rng = chan(seed, "conifer")
    parts = []
    trunk_h = 0.25 * scale
    parts.append({"bm": P.column(0.05 * scale, trunk_h, segments=5),
                  "mat": "wood", "tag": "mid", "z": trunk_h / 2})
    if style == "card":
        h = (0.9 + rng.random() * 0.5) * scale
        for k in range(2):
            c = P.card(0.55 * scale, h, thickness=0.025 * scale)
            rot = Matrix.Rotation(math.pi / 2 * k + rng.random() * 0.3, 4, "Z")
            for v in c.verts:
                v.co = rot @ v.co
                v.co.z += trunk_h * 0.4
            # taper card to triangle-ish
            for v in c.verts:
                if v.co.z > trunk_h * 0.4 + h * 0.55:
                    v.co.x *= 0.25
                    v.co.y *= 0.25
            parts.append({"bm": c, "mat": "moss2", "tag": "upper",
                          "z": trunk_h + h / 2})
    else:
        z = trunk_h
        tiers = 2 + int(rng.random() * 2)
        r = 0.34 * scale
        for t in range(tiers):
            th = (0.45 - t * 0.08) * scale
            cone = P.spire(r * (1.0 - t * 0.25), th * 1.6, segments=7)
            for v in cone.verts:
                v.co.z += z
            parts.append({"bm": cone, "mat": "moss2" if t % 2 else "moss",
                          "tag": "upper", "z": z + th / 2})
            z += th * 0.62
    return parts


def broadleaf(seed, scale=1.0):
    rng = chan(seed, "broadleaf")
    parts = []
    trunk_h = (0.35 + rng.random() * 0.15) * scale
    parts.append({"bm": P.column(0.05 * scale, trunk_h, segments=5),
                  "mat": "wood", "tag": "mid", "z": trunk_h / 2})
    n = 2 + int(rng.random() * 3)
    for i in range(n):
        r = (0.22 + rng.random() * 0.14) * scale
        b = P.blob(r, squash=0.75, subdivisions=1)
        for v in b.verts:
            v.co.x += (rng.random() - 0.5) * 0.3 * scale
            v.co.y += (rng.random() - 0.5) * 0.3 * scale
            v.co.z += trunk_h + r * 0.5 + rng.random() * 0.2 * scale
        parts.append({"bm": b, "mat": "moss" if rng.random() < 0.7 else "moss2",
                      "tag": "upper", "z": trunk_h + r})
    return parts


def ancient_tree(seed, scale=1.8):
    rng = chan(seed, "ancient")
    parts = []
    trunk_h = 0.5 * scale
    parts.append({"bm": P.column(0.11 * scale, trunk_h, segments=6, taper=0.3),
                  "mat": "wood", "tag": "mid", "z": trunk_h / 2})
    for i in range(4 + int(rng.random() * 3)):
        r = (0.3 + rng.random() * 0.2) * scale
        b = P.blob(r, squash=0.6, subdivisions=1)
        for v in b.verts:
            v.co.x += (rng.random() - 0.5) * 0.8 * scale
            v.co.y += (rng.random() - 0.5) * 0.8 * scale
            v.co.z += trunk_h + 0.1 * scale + rng.random() * 0.25 * scale
        parts.append({"bm": b, "mat": "moss2" if rng.random() < 0.5 else "moss",
                      "tag": "upper", "z": trunk_h + r})
    return parts


def shrub(seed, scale=0.5):
    rng = chan(seed, "shrub")
    r = (0.3 + rng.random() * 0.2) * scale
    b = P.blob(r, squash=0.6, subdivisions=1)
    for v in b.verts:
        v.co.z += r * 0.4
    return [{"bm": b, "mat": "moss2", "tag": "upper", "z": r * 0.4}]


def dead_tree(seed, scale=1.0):
    rng = chan(seed, "dead")
    parts = []
    trunk_h = (0.6 + rng.random() * 0.3) * scale
    parts.append({"bm": P.column(0.04 * scale, trunk_h, segments=5, taper=0.5),
                  "mat": "stone", "tag": "mid", "z": trunk_h / 2})
    for i in range(2):
        bl = (0.25 + rng.random() * 0.2) * scale
        br = P.beam(bl, 0.03 * scale, 0.03 * scale)
        ang = rng.random() * math.pi * 2
        tilt = Matrix.Rotation(0.5 + rng.random() * 0.5, 4, "Y")
        rot = Matrix.Rotation(ang, 4, "Z")
        for v in br.verts:
            v.co = rot @ (tilt @ v.co)
            v.co.z += trunk_h * (0.55 + 0.3 * i)
        parts.append({"bm": br, "mat": "stone", "tag": "upper",
                      "z": trunk_h * 0.7})
    return parts


TREES = {
    "conifer": conifer,
    "broadleaf": broadleaf,
    "ancient": ancient_tree,
    "shrub": shrub,
    "dead": dead_tree,
}
