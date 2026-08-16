"""A full-scale hex-sourced world: the honest data-shape test.

Everything here derives from per-hex samples - elevation, moisture, and
terrain class at flat-top axial hex centres (AgDR-006 conventions), roads as
hex-line paths, buildings at hex centres - because that is exactly what the
game's HexRenderState will deliver. The lab's earlier valleys cheated with
continuous noise and free placement; this module answers whether the diorama
look survives the real data shape, and at 40x30-hex scale.
"""
import math

from mathutils import Vector, noise

from . import architecture as A
from . import primitives as P
from . import vegetation as V
from .aging import ruin, debris
from .cultures import DECO, ORGANIC
from .core import chan, material, obj_from_bmesh
from .diorama import _place_parts

import bmesh

SQRT3 = math.sqrt(3.0)

WATER, GRASS, FOREST, HILL, MOUNTAIN = range(5)


# ------------------------------------------------------------------ hex math

def hex_center(q, r, s=1.0):
    """Flat-top, odd-q offset - the sim's convention."""
    x = 1.5 * s * q
    y = SQRT3 * s * (r + 0.5 * (q & 1))
    return x, y


def hex_line(a, b):
    """Hexes on the line a->b (offset coords) via cube lerp + round."""
    def to_cube(q, r):
        cx = q
        cz = r - (q - (q & 1)) // 2
        return cx, -cx - cz, cz

    def from_cube(cx, cy, cz):
        q = cx
        r = cz + (cx - (cx & 1)) // 2
        return q, r

    ac, bc = to_cube(*a), to_cube(*b)
    n = max(abs(ac[i] - bc[i]) for i in range(3))
    out = []
    for i in range(n + 1):
        t = i / max(1, n)
        fx, fy, fz = (ac[j] + (bc[j] - ac[j]) * t for j in range(3))
        rx, ry, rz = round(fx), round(fy), round(fz)
        dx, dy, dz = abs(rx - fx), abs(ry - fy), abs(rz - fz)
        if dx > dy and dx > dz:
            rx = -ry - rz
        elif dy > dz:
            ry = -rx - rz
        else:
            rz = -rx - ry
        out.append(from_cube(rx, ry, rz))
    return out


def chaikin(points, iterations=2):
    pts = list(points)
    for _ in range(iterations):
        nxt = [pts[0]]
        for i in range(len(pts) - 1):
            ax, ay = pts[i]
            bx, by = pts[i + 1]
            nxt.append((ax * 0.75 + bx * 0.25, ay * 0.75 + by * 0.25))
            nxt.append((ax * 0.25 + bx * 0.75, ay * 0.25 + by * 0.75))
        nxt.append(pts[-1])
        pts = nxt
    return pts


# ------------------------------------------------------------------ the world

class HexWorld:
    """Per-hex state, sampled once - the stand-in for HexRenderState."""

    def __init__(self, seed, cols=40, rows=30, s=1.0):
        self.seed, self.cols, self.rows, self.s = seed, cols, rows, s
        off = chan(seed, "world").random() * 100.0
        self.elev, self.moist, self.terr, self.z = {}, {}, {}, {}
        for q in range(cols):
            for r in range(rows):
                x, y = hex_center(q, r, s)
                e = 0.5 + 0.5 * (
                    noise.noise(Vector((x * 0.045 + off, y * 0.045, 0.0))) * 0.75
                    + noise.noise(Vector((x * 0.11 + off, y * 0.11, 3.3))) * 0.35)
                m = 0.5 + 0.5 * noise.noise(
                    Vector((x * 0.06 + off * 2, y * 0.06, 7.7)))
                self.elev[q, r] = e
                self.moist[q, r] = m
                if e < 0.36:
                    t = WATER
                elif e > 0.74:
                    t = MOUNTAIN
                elif e > 0.62:
                    t = HILL
                elif m > 0.54:
                    t = FOREST
                else:
                    t = GRASS
                self.terr[q, r] = t
                # display height per hex - what the renderer exaggerates
                if t == WATER:
                    z = -0.7
                elif t == MOUNTAIN:
                    z = 1.2 + (e - 0.74) * 26.0
                elif t == HILL:
                    z = 0.55 + (e - 0.62) * 6.5
                else:
                    z = (e - 0.36) * 1.8
                self.z[q, r] = z
        cx, cy = hex_center(cols - 1, rows - 1, s)
        self.center = (cx / 2, cy / 2)

    def centers_near(self, x, y, radius=2.6):
        q0 = int(x / (1.5 * self.s))
        r0 = int(y / (SQRT3 * self.s))
        out = []
        for q in range(max(0, q0 - 3), min(self.cols, q0 + 4)):
            for r in range(max(0, r0 - 3), min(self.rows, r0 + 4)):
                hx, hy = hex_center(q, r, self.s)
                d2 = (hx - x) ** 2 + (hy - y) ** 2
                if d2 < radius * radius:
                    out.append((d2, q, r))
        return out

    def height_smooth(self, x, y):
        """IDW over nearby hex centres - hexes present but not obvious."""
        near = self.centers_near(x, y)
        if not near:
            return 0.0
        wsum = zsum = 0.0
        for d2, q, r in near:
            w = 1.0 / (d2 + 0.08) ** 1.5
            wsum += w
            zsum += w * self.z[q, r]
        return zsum / wsum

    def height_hex(self, x, y):
        """Nearest-centre lookup - honest stepped hex plateaus."""
        near = self.centers_near(x, y)
        if not near:
            return 0.0
        return self.z[min(near)[1], min(near)[2]]


# --------------------------------------------------------------- scene build

def terrain_mesh(world, mode="smooth", res=3.2):
    """One mesh over the whole slab; res = grid verts per hex width."""
    f = world.height_smooth if mode == "smooth" else world.height_hex
    w = 1.5 * world.s * world.cols
    h = SQRT3 * world.s * world.rows
    nx, ny = int(w * res), int(h * res)
    bm = bmesh.new()
    grid = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            x = w * i / nx
            y = h * j / ny
            grid[i, j] = bm.verts.new((x, y, f(x, y)))
    for i in range(nx):
        for j in range(ny):
            bm.faces.new((grid[i, j], grid[i + 1, j],
                          grid[i + 1, j + 1], grid[i, j + 1]))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return bm, f


def ground_color_mesh(world, f):
    """Terrain tint per hex: thin hex tiles floated onto the relief for
    forest/hill/mountain hexes, so class reads without texture painting."""
    mats = {FOREST: material("moss2", roughness=0.95),
            HILL: material("hilltint", roughness=0.95),
            MOUNTAIN: material("stone", roughness=0.95)}
    groups = {k: bmesh.new() for k in mats}
    for (q, r), t in world.terr.items():
        if t not in mats:
            continue
        x, y = hex_center(q, r, world.s)
        bm = groups[t]
        ring = []
        for k in range(6):
            a = math.pi / 3 * k
            # corner displacement: the sim stays hexagonal, the picture
            # does not - "softening the grid", pattern 4, now in 3D.
            crng = chan(world.seed, "tintjit",
                        round(x + math.cos(a) * world.s),
                        round(y + math.sin(a) * world.s), t)
            rad = world.s * (1.02 + (crng.random() - 0.5) * 0.5)
            aj = a + (crng.random() - 0.5) * 0.22
            vx = x + math.cos(aj) * rad
            vy = y + math.sin(aj) * rad
            ring.append(bm.verts.new((vx, vy, f(vx, vy) + 0.02)))
        bm.faces.new(ring)
    for t, bm in groups.items():
        name = {FOREST: "tint_forest", HILL: "tint_hill",
                MOUNTAIN: "tint_mtn"}[t]
        obj_from_bmesh(bm, name, mats[t])


def road_mesh(world, f, hexpath, smooth=True, keep=1.0, lift=0.06,
              width=0.34, salt=0):
    pts = [hex_center(q, r, world.s) for q, r in hexpath]
    if smooth:
        pts = chaikin(pts, 2)
    bm = bmesh.new()
    for i in range(len(pts) - 1):
        if chan(world.seed, "roadseg", salt, i).random() > keep:
            continue
        a = Vector((pts[i][0], pts[i][1], 0.0))
        b = Vector((pts[i + 1][0], pts[i + 1][1], 0.0))
        if (b - a).length < 1e-6:
            continue
        d = (b - a).normalized()
        n = Vector((-d.y, d.x, 0.0)) * (width / 2)
        quad = []
        for c in (a - n, a + n, b + n, b - n):
            quad.append(bm.verts.new((c.x, c.y, f(c.x, c.y) + lift)))
        bm.faces.new(quad)
    return bm


def scatter_forests(world, f, per_hex=2, tree_scale=0.75):
    for (q, r), t in world.terr.items():
        if t != FOREST:
            continue
        rng = chan(world.seed, "fh", q, r)
        x, y = hex_center(q, r, world.s)
        n = per_hex if rng.random() < 0.8 else per_hex + 1
        for i in range(n):
            a = rng.random() * 6.28
            d = rng.random() * world.s * 0.55
            tx, ty = x + math.cos(a) * d, y + math.sin(a) * d
            kind = "conifer" if world.elev[q, r] > 0.55 else "broadleaf"
            parts = V.TREES[kind](world.seed * 31 + q * 991 + r * 57 + i,
                                  scale=tree_scale * (0.85 + rng.random() * 0.3))
            _place_parts(parts, "fx_%d_%d_%d" % (q, r, i),
                         (tx, ty, f(tx, ty)), rot_z=rng.random() * 6.28)


def pick_settlement_sites(world, n=4, min_dist=14.0):
    rng = chan(world.seed, "sites")
    cands = [(q, r) for (q, r), t in world.terr.items()
             if t == GRASS and 3 < q < world.cols - 4 and 3 < r < world.rows - 4]
    cands.sort(key=lambda qr: chan(world.seed, "siteh", *qr).random())
    sites = []
    for qr in cands:
        x, y = hex_center(*qr, world.s)
        if all((x - sx) ** 2 + (y - sy) ** 2 > min_dist ** 2
               for sx, sy, _, _ in sites):
            sites.append((x, y, qr[0], qr[1]))
        if len(sites) == n:
            break
    return sites


NEIGHBORS_ODD = [(0, -1), (0, 1), (1, 0), (1, 1), (-1, 0), (-1, 1)]
NEIGHBORS_EVEN = [(0, -1), (0, 1), (1, -1), (1, 0), (-1, -1), (-1, 0)]


def build_settlement(world, f, site, culture, n_bld, cond=(1.0, 1.0),
                     hero=None, reclaim=False, tag="s"):
    x0, y0, q0, r0 = site
    nb = NEIGHBORS_ODD if q0 & 1 else NEIGHBORS_EVEN
    cells = [(q0, r0)] + [(q0 + dq, r0 + dr) for dq, dr in nb]
    kinds = ["residential", "residential", "civic", "residential", "stepped",
             "residential", "residential"]
    rng = chan(world.seed, "bld", q0, r0)
    for i in range(min(n_bld, len(cells))):
        q, r = cells[i]
        if world.terr.get((q, r)) in (None, WATER, MOUNTAIN):
            continue
        x, y = hex_center(q, r, world.s)
        x += (rng.random() - 0.5) * 0.4      # hash jitter off the centre
        y += (rng.random() - 0.5) * 0.4
        parts = A.GENERATORS[kinds[i % len(kinds)]](
            culture, world.seed * 100 + q * 37 + r, scale=0.5)
        c = cond[0] + rng.random() * (cond[1] - cond[0])
        if c < 0.995:
            parts, age = ruin(parts, c, world.seed * 100 + q * 37 + r)
            _place_parts(parts, "%s_b%d" % (tag, i), (x, y, f(x, y)),
                         rot_z=rng.random() * 6.28, age=age)
        else:
            _place_parts(parts, "%s_b%d" % (tag, i), (x, y, f(x, y)),
                         rot_z=rng.random() * 0.6 - 0.3)
        if reclaim and rng.random() < 0.7:
            parts = V.TREES["broadleaf"](world.seed * 61 + i, scale=0.8)
            _place_parts(parts, "%s_v%d" % (tag, i),
                         (x + 0.7, y + 0.4, f(x + 0.7, y + 0.4)))
    if hero is not None:
        hx, hy = x0 + 2.2, y0 - 1.4
        parts = A.hero_arch(culture, world.seed + 7, scale=0.9)
        if hero < 0.995:
            parts, age = ruin(parts, hero, world.seed + 7)
            _place_parts(parts, tag + "_hero", (hx, hy, f(hx, hy)), age=age)
        else:
            _place_parts(parts, tag + "_hero", (hx, hy, f(hx, hy)))


def build_world(seed, terrain_mode="smooth", road_smooth=True,
                with_cartography=False):
    """The full slab. Returns (world, f, sites) for camera/salience use."""
    world = HexWorld(seed)
    tbm, f = terrain_mesh(world, mode=terrain_mode)
    obj_from_bmesh(tbm, "terrain", material("moss", roughness=0.95))
    ground_color_mesh(world, f)
    # water table
    w = 1.5 * world.s * world.cols
    h = SQRT3 * world.s * world.rows
    wb = bmesh.new()
    vs = [wb.verts.new(p) for p in
          ((-2, -2, -0.12), (w + 2, -2, -0.12),
           (w + 2, h + 2, -0.12), (-2, h + 2, -0.12))]
    wb.faces.new(vs)
    obj_from_bmesh(wb, "water", material("water", roughness=0.15))

    scatter_forests(world, f)

    sites = pick_settlement_sites(world, n=4)
    configs = [
        (DECO, 7, (1.0, 1.0), 1.0, False),      # the living capital
        (ORGANIC, 5, (1.0, 1.0), None, False),  # the successor village
        (DECO, 6, (0.1, 0.3), 0.5, True),       # the silent city
        (DECO, 3, (1.0, 1.0), None, False),     # a hamlet
    ]
    for i, (site, (cul, n, cond, hero, rec)) in enumerate(zip(sites, configs)):
        build_settlement(world, f, site, cul, n, cond, hero, rec,
                         tag="s%d" % i)

    # roads: capital to each other site; the silent city's road is a ghost
    for i, target in enumerate(sites[1:], start=1):
        a = (sites[0][2], sites[0][3])
        b = (target[2], target[3])
        path = [h_ for h_ in hex_line(a, b)
                if world.terr.get(h_) not in (None, WATER)]
        ghost = (i == 2)
        bm = road_mesh(world, f, path, smooth=road_smooth,
                       keep=0.35 if ghost else 1.0,
                       lift=0.02 if ghost else 0.06, salt=i)
        obj_from_bmesh(bm, "road_%d" % i,
                       material("stone" if ghost else "plaster2",
                                roughness=0.95))

    if with_cartography:
        add_cartography(world, f, sites)
    return world, f, sites


# ------------------------------------------------------- printed information

def add_cartography(world, f, sites):
    """Contours + a territory ring: drawn onto the model, map-style."""
    w = 1.5 * world.s * world.cols
    h = SQRT3 * world.s * world.rows
    # contour ribbons by marching the sample grid at fixed heights
    levels = [0.55, 1.3, 2.2, 3.4]
    step = 0.45
    bm = bmesh.new()
    nx, ny = int(w / step), int(h / step)
    zs = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            zs[i, j] = f(i * step, j * step)
    for level in levels:
        for i in range(nx):
            for j in range(ny):
                pts = []
                cell = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                for k in range(4):
                    a, b = cell[k], cell[(k + 1) % 4]
                    za, zb = zs[a], zs[b]
                    if (za - level) * (zb - level) < 0:
                        t = (level - za) / (zb - za)
                        pts.append(((a[0] + (b[0] - a[0]) * t) * step,
                                    (a[1] + (b[1] - a[1]) * t) * step))
                if len(pts) == 2:
                    _ribbon(bm, pts[0], pts[1], f, width=0.05, lift=0.06)
    obj_from_bmesh(bm, "contours", material("plaster", roughness=1.0))
    # territory ring around the capital
    bm2 = bmesh.new()
    cx, cy = sites[0][0], sites[0][1]
    radius = 5.2
    segs = 64
    ring = [(cx + math.cos(2 * math.pi * k / segs) * radius,
             cy + math.sin(2 * math.pi * k / segs) * radius)
            for k in range(segs + 1)]
    for k in range(segs):
        _ribbon(bm2, ring[k], ring[k + 1], f, width=0.14, lift=0.07)
    obj_from_bmesh(bm2, "territory", material("verdigris", roughness=0.9))


def _ribbon(bm, a, b, f, width=0.06, lift=0.05):
    av = Vector((a[0], a[1], 0.0))
    bv = Vector((b[0], b[1], 0.0))
    if (bv - av).length < 1e-6:
        return
    d = (bv - av).normalized()
    n = Vector((-d.y, d.x, 0.0)) * (width / 2)
    quad = []
    for c in (av - n, av + n, bv + n, bv - n):
        quad.append(bm.verts.new((c.x, c.y, f(c.x, c.y) + lift)))
    try:
        bm.faces.new(quad)
    except ValueError:
        pass


# ----------------------------------------------------------------- salience

def place_events(world, f, n=12):
    """Must-notice changes scattered world-wide; returns [(kind, x, y, z)]."""
    events = []
    rng = chan(world.seed, "events")
    kinds = ["new_building", "fire", "herd"]
    hexes = [(q, r) for (q, r), t in world.terr.items()
             if t in (GRASS, FOREST) and 2 < q < world.cols - 3
             and 2 < r < world.rows - 3]
    hexes.sort(key=lambda qr: chan(world.seed, "evh", *qr).random())
    for i, (q, r) in enumerate(hexes[:n]):
        kind = kinds[i % len(kinds)]
        x, y = hex_center(q, r, world.s)
        z = f(x, y)
        if kind == "new_building":
            parts = A.GENERATORS["residential"](DECO, world.seed * 500 + i,
                                                scale=0.5)
            _place_parts(parts, "ev_b%d" % i, (x, y, z))
            events.append((kind, x, y, z + 0.5))
        elif kind == "fire":
            for k in range(3):
                _place_parts(V.TREES["dead"](world.seed * 600 + i * 9 + k,
                                             scale=0.9),
                             "ev_f%d_%d" % (i, k),
                             (x + (rng.random() - 0.5), y + (rng.random() - 0.5),
                              f(x, y)))
            _place_parts(debris(world.seed * 600 + i, footprint=0.5, count=4,
                                scale=0.12), "ev_fd%d" % i, (x, y, z))
            events.append((kind, x, y, z + 0.4))
        else:
            for k in range(6):
                a = rng.random() * 6.28
                d = rng.random() * 0.6
                hb = P.blob(0.14, squash=0.8, subdivisions=1)
                for v_ in hb.verts:
                    v_.co.z += 0.12
                _place_parts([{"bm": hb, "mat": "ochre", "tag": "mid",
                               "z": 0.1}], "ev_h%d_%d" % (i, k),
                             (x + math.cos(a) * d, y + math.sin(a) * d,
                              f(x + math.cos(a) * d, y + math.sin(a) * d)))
            events.append((kind, x, y, z + 0.25))
    return events


def salience_report(events, margin=0.5):
    """Ray-cast each event from the active camera: visible or occluded?"""
    import bpy
    scene = bpy.context.scene
    deps = bpy.context.evaluated_depsgraph_get()
    cam = scene.camera
    origin = cam.matrix_world.translation
    results = []
    for kind, x, y, z in events:
        target = Vector((x, y, z))
        d = target - origin
        dist = d.length
        hit, loc, *_ = scene.ray_cast(deps, origin, d.normalized())
        visible = (not hit) or (loc - origin).length > dist - margin
        results.append((kind, x, y, z, visible))
    return results
