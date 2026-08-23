"""Building generators: compose primitives under a CultureStyle.

Each generator returns a list of part dicts:
  {"bm": bmesh, "mat": material-name, "tag": one of
   base|mid|upper|crown|accent, "z": approx part centre height}
The tag+z pair is what the aging module uses to ruin a building
deterministically without a separate ruin asset set.
"""
import math

from mathutils import Matrix, Vector

from . import primitives as P
from .core import chan


def _sym_jitter(rng, symmetry, amount):
    """Positional noise that vanishes as symmetry -> 1."""
    return (rng.random() - 0.5) * 2.0 * amount * (1.0 - symmetry)


def stepped_monument(style, seed, scale=1.0):
    rng = chan(seed, "stepped", style.name)
    parts = []
    base_w = (1.6 + rng.random() * 0.8) * scale
    base_h = 0.28 * scale
    parts.append({"bm": P.slab(base_w, base_w, base_h), "mat": style.body,
                  "tag": "base", "z": base_h / 2})
    tiers = 2 + int(style.setback_frequency * 3 + rng.random() * 1.5)
    tier_h = (0.5 + style.verticality * 0.9) * scale
    w = base_w * 0.72
    z = base_h
    shrink = 0.22 + 0.08 * rng.random()
    # each tier is its own part so ruin() can remove modules from the top down
    for t in range(tiers):
        s = (1.0 - shrink) ** t
        tier = P.slab(w * s, w * s, tier_h)
        for v in tier.verts:
            v.co.z += z
        parts.append({"bm": tier, "mat": style.body,
                      "tag": "mid" if t < tiers / 2 else "upper",
                      "z": z + tier_h / 2})
        z += tier_h
    crown_w = w * (1.0 - 0.22) ** tiers
    if rng.random() < style.curvature:
        crown = P.dome(crown_w * 0.75, squash=0.8)
        for v in crown.verts:
            v.co.z += z
        parts.append({"bm": crown, "mat": style.accent, "tag": "crown",
                      "z": z + crown_w * 0.3})
    else:
        ch = 0.5 * scale
        crown = P.slab(crown_w, crown_w, ch, taper=0.35)
        for v in crown.verts:
            v.co.z += z
        parts.append({"bm": crown, "mat": style.secondary, "tag": "crown",
                      "z": z + ch / 2})
        z += ch
    if rng.random() < style.spire_frequency:
        sp_h = (0.8 + style.verticality * 1.4) * scale
        sp = P.spire(crown_w * 0.22, sp_h)
        for v in sp.verts:
            v.co.z += z
        parts.append({"bm": sp, "mat": style.accent, "tag": "accent",
                      "z": z + sp_h / 2})
    return parts


def civic_hall(style, seed, scale=1.0):
    rng = chan(seed, "civic", style.name)
    parts = []
    plat_w = (2.6 + rng.random()) * scale
    plat_d = plat_w * (0.6 + 0.2 * rng.random())
    plat_h = 0.22 * scale
    parts.append({"bm": P.slab(plat_w, plat_d, plat_h), "mat": style.body,
                  "tag": "base", "z": plat_h / 2})
    n_cols = 4 + int(style.repetition * 5)
    col_h = (0.8 + style.verticality * 0.8) * scale
    use_arches = rng.random() < style.arch_frequency
    if use_arches:
        n_arch = max(2, n_cols // 2)
        pitch = plat_w * 0.82 / n_arch
        for i in range(n_arch):
            x = -plat_w * 0.41 + pitch * (i + 0.5)
            a = P.arch(pitch * 0.92, 0.16 * scale, col_h, 0.10 * scale,
                       segments=5)
            for v in a.verts:
                v.co.x += x + _sym_jitter(rng, style.symmetry, 0.05)
                v.co.y += plat_d * 0.38
                v.co.z += plat_h
            parts.append({"bm": a, "mat": style.body, "tag": "mid",
                          "z": plat_h + col_h / 2})
    else:
        pitch = plat_w * 0.82 / (n_cols - 1)
        for i in range(n_cols):
            x = -plat_w * 0.41 + pitch * i
            c = P.column(0.07 * scale, col_h, segments=6)
            for v in c.verts:
                v.co.x += x + _sym_jitter(rng, style.symmetry, 0.04)
                v.co.y += plat_d * 0.38
                v.co.z += plat_h
            parts.append({"bm": c, "mat": style.body, "tag": "mid",
                          "z": plat_h + col_h / 2})
    hall_w = plat_w * 0.7
    hall_d = plat_d * 0.55
    hall_h = col_h * (0.9 + 0.3 * style.verticality)
    hall = P.slab(hall_w, hall_d, hall_h)
    for v in hall.verts:
        v.co.y -= plat_d * 0.1
        v.co.z += plat_h
    parts.append({"bm": hall, "mat": style.body, "tag": "mid",
                  "z": plat_h + hall_h / 2})
    ztop = plat_h + hall_h
    if rng.random() < style.curvature:
        d = P.dome(hall_d * 0.55, squash=0.85)
        for v in d.verts:
            v.co.y -= plat_d * 0.1
            v.co.z += ztop
        parts.append({"bm": d, "mat": style.accent, "tag": "crown",
                      "z": ztop + hall_d * 0.2})
    else:
        r = P.slab(hall_w * 0.9, hall_d * 0.9, 0.3 * scale, taper=0.5)
        for v in r.verts:
            v.co.y -= plat_d * 0.1
            v.co.z += ztop
        parts.append({"bm": r, "mat": style.secondary, "tag": "crown",
                      "z": ztop + 0.15})
    return parts


def residential(style, seed, scale=1.0):
    rng = chan(seed, "res", style.name)
    parts = []
    n_mass = 1 + int(rng.random() * 3)
    x = 0.0
    for i in range(n_mass):
        w = (0.55 + rng.random() * 0.5) * scale
        d = (0.55 + rng.random() * 0.5) * scale
        h = (0.5 + style.verticality * 1.2 + rng.random() * 0.4) * scale
        m = P.slab(w, d, h)
        ox = x + _sym_jitter(rng, style.symmetry, 0.15)
        oy = _sym_jitter(rng, style.symmetry, 0.3)
        for v in m.verts:
            v.co.x += ox
            v.co.y += oy
        parts.append({"bm": m, "mat": style.body, "tag": "mid", "z": h / 2})
        if rng.random() < style.curvature * 0.7:
            r = P.dome(min(w, d) * 0.5, squash=0.7)
            for v in r.verts:
                v.co.x += ox
                v.co.y += oy
                v.co.z += h
            parts.append({"bm": r, "mat": style.secondary, "tag": "upper",
                          "z": h + 0.1})
        else:
            r = P.slab(w * 1.05, d * 1.05, 0.22 * scale, taper=0.8)
            for v in r.verts:
                v.co.x += ox
                v.co.y += oy
                v.co.z += h
            parts.append({"bm": r, "mat": style.secondary, "tag": "upper",
                          "z": h + 0.1})
        x += w * 0.95
    return parts


def hero_arch(style, seed, scale=3.0):
    """The monument that breaks the scale hierarchy."""
    rng = chan(seed, "hero", style.name)
    parts = []
    w = (2.2 + rng.random() * 0.8) * scale
    h = (2.0 + style.verticality * 1.6) * scale
    t = 0.28 * scale
    base_h = 0.25 * scale
    base = P.slab(w * 1.25, t * 2.6, base_h)
    parts.append({"bm": base, "mat": style.body, "tag": "base", "z": base_h / 2})
    # piers and voussoirs as separate parts: a ruined arch keeps its stumps
    # and, sometimes, its span - "three surviving arches above the canopy"
    for piece_bm, piece_z in P.arch_pieces(w, t * 1.4, h, t, segments=9):
        for v in piece_bm.verts:
            v.co.z += base_h
        tag = "mid" if piece_z < h * 0.55 else "upper"
        parts.append({"bm": piece_bm, "mat": style.body, "tag": tag,
                      "z": base_h + piece_z})
    top = base_h + h + (w / 2 - t) * 0  # arch tops out near base_h + h
    beam_h = 0.35 * scale
    b = P.beam(w * 1.1, t * 1.6, beam_h)
    for v in b.verts:
        v.co.z += base_h + h + t * 0.5
    parts.append({"bm": b, "mat": style.secondary, "tag": "upper",
                  "z": base_h + h + beam_h / 2})
    if rng.random() < max(0.3, style.spire_frequency):
        sp_h = 1.1 * scale
        sp = P.spire(t * 0.55, sp_h, segments=6)
        for v in sp.verts:
            v.co.z += base_h + h + t * 0.5 + beam_h
        parts.append({"bm": sp, "mat": style.accent, "tag": "accent",
                      "z": base_h + h + beam_h + sp_h / 2})
    else:
        ball = P.blob(t * 0.7, squash=1.0, subdivisions=1)
        for v in ball.verts:
            v.co.z += base_h + h + t * 0.5 + beam_h + t * 0.5
        parts.append({"bm": ball, "mat": style.accent, "tag": "accent",
                      "z": base_h + h + beam_h + t})
    return parts


GENERATORS = {
    "stepped": stepped_monument,
    "civic": civic_hall,
    "residential": residential,
    "hero": hero_arch,
}
