"""Faceted relief terrain: broad planes, stepped valleys, strong silhouette.

Deliberately simplified - architectural model, not terrain engine.
"""
import math

import bmesh
from mathutils import noise, Vector

from .core import chan


def height_field(seed, exaggeration=1.0, terrace=0.45, mountain_side=1.0):
    """Returns f(x, y) -> z for a valley running along +Y with mountains on +X."""
    off = chan(seed, "terrain").random() * 100.0

    def f(x, y):
        n = noise.noise(Vector((x * 0.08 + off, y * 0.08, 0.0)))
        n2 = noise.noise(Vector((x * 0.2 + off * 2, y * 0.2, 3.7)))
        base = n * 0.8 + n2 * 0.3
        # valley profile: low near river line (x ~ 0), rising to +X mountains
        rise = max(0.0, x * mountain_side) ** 1.6 * 0.028
        rise += max(0.0, -x - 6.0) ** 1.5 * 0.02  # gentle far-bank lift
        z = (base * 0.9 + rise) * exaggeration
        # river carve
        river_x = math.sin(y * 0.14) * 2.2
        d = abs(x - river_x)
        z -= max(0.0, 1.6 - d) ** 2 * 0.55 * exaggeration
        # terracing: quantize partially for stepped geological forms
        step = 0.6
        zq = round(z / step) * step
        return z + (zq - z) * terrace

    return f


def terrain_mesh(seed, size=26.0, res=42, exaggeration=1.6, terrace=0.45):
    f = height_field(seed, exaggeration, terrace)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=res, y_segments=res, size=size / 2)
    for v in bm.verts:
        v.co.z = f(v.co.x, v.co.y)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return bm, f


def water_mesh(size=26.0, level=-0.32):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size / 2)
    for v in bm.verts:
        v.co.z = level
    return bm


def road_mesh(f, path_points, width=0.5, lift=0.06):
    """Ribbon of quads draped over the height function."""
    bm = bmesh.new()
    prev = None
    for i in range(len(path_points) - 1):
        a = Vector((path_points[i][0], path_points[i][1], 0.0))
        b = Vector((path_points[i + 1][0], path_points[i + 1][1], 0.0))
        d = (b - a).normalized()
        n = Vector((-d.y, d.x, 0.0)) * (width / 2)
        quad = []
        for corner in (a - n, a + n, b + n, b - n):
            z = f(corner.x, corner.y) + lift
            quad.append(bm.verts.new((corner.x, corner.y, z)))
        bm.faces.new(quad)
    return bm


def road_mesh_worn(f, path_points, seed, width=0.5, lift=0.06, keep=1.0):
    """Road ribbon with hash-chosen missing segments - worn to ghost trace."""
    import bmesh as _bmesh
    from .core import chan
    from mathutils import Vector as _V
    bm = _bmesh.new()
    for i in range(len(path_points) - 1):
        if chan(seed, "roadkeep", i).random() > keep:
            continue
        a = _V((path_points[i][0], path_points[i][1], 0.0))
        b = _V((path_points[i + 1][0], path_points[i + 1][1], 0.0))
        d = (b - a).normalized()
        n = _V((-d.y, d.x, 0.0)) * (width / 2)
        quad = []
        for corner in (a - n, a + n, b + n, b - n):
            z = f(corner.x, corner.y) + lift
            quad.append(bm.verts.new((corner.x, corner.y, z)))
        bm.faces.new(quad)
    return bm
