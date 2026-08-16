"""civ-life headless Blender lab - parameters in, deterministic renders out.

Usage:
  python3 build.py --experiment culture   --seed 42
  python3 build.py --experiment trees     --seed 42
  python3 build.py --experiment monuments --seed 42
  python3 build.py --experiment time      --seed 42
  python3 build.py --experiment diorama   --seed 8421
  python3 build.py --experiment all       --seed 42
"""
import argparse
import os
import sys
import time

import bpy  # noqa: F401  (must be imported before mathutils is available)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from civlife_blender import architecture as A
from civlife_blender import vegetation as V
from civlife_blender.aging import ruin, debris
from civlife_blender.core import (add_camera, add_fill, add_sun, fresh_scene,
                                  material, aged_material, obj_from_bmesh,
                                  render, chan)
from civlife_blender.cultures import DECO, ORGANIC
from civlife_blender.diorama import build_valley, _place_parts

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")


def _ground(size=200.0):
    from civlife_blender import primitives as P
    g = P.slab(size, size, 0.1)
    for v in g.verts:
        v.co.z -= 0.1
    obj_from_bmesh(g, "ground", material("indigo", roughness=1.0))


def _grid_positions(n_cols, n_rows, pitch):
    for r in range(n_rows):
        for c in range(n_cols):
            yield c, r, ((c - (n_cols - 1) / 2) * pitch,
                         (r - (n_rows - 1) / 2) * pitch, 0.0)


def sheet_culture(seed):
    """A+: 4x4 buildings per culture, same camera and light."""
    for culture in (DECO, ORGANIC):
        fresh_scene()
        _ground()
        add_sun(elevation_deg=30, azimuth_deg=210, energy=4.5)
        add_fill()
        kinds = ["stepped", "civic", "residential", "stepped",
                 "civic", "residential", "stepped", "civic",
                 "residential", "stepped", "civic", "residential",
                 "stepped", "civic", "residential", "stepped"]
        for i, (c, r, pos) in enumerate(_grid_positions(4, 4, 6.5)):
            parts = A.GENERATORS[kinds[i]](culture, seed * 10 + i)
            _place_parts(parts, "b%d" % i, pos)
        add_camera((0, 0, 2.2), 92.0, fov_deg=20, pitch_deg=26, yaw_deg=8)
        render(os.path.join(OUT, "culture_%s_buildings.png" % culture.name),
               res=(1600, 1000), samples=48)


def sheet_trees(seed):
    """B: the cardstock vegetation language, both dialects."""
    fresh_scene()
    _ground()
    add_sun(elevation_deg=32, azimuth_deg=210, energy=4.5)
    add_fill()
    specs = []
    for i in range(7):
        specs.append(("conifer", {"style": "model"}))
    for i in range(7):
        specs.append(("broadleaf", {}))
    for i in range(4):
        specs.append(("conifer", {"style": "card"}))
    for i in range(3):
        specs.append(("ancient", {}))
    for i in range(4):
        specs.append(("shrub", {}))
    for i in range(3):
        specs.append(("dead", {}))
    for i, (c, r, pos) in enumerate(_grid_positions(7, 4, 2.6)):
        kind, kw = specs[i]
        parts = V.TREES[kind](seed * 20 + i, **kw)
        _place_parts(parts, "t%d" % i, pos)
    add_camera((0, 0, 0.7), 64.0, fov_deg=18, pitch_deg=22, yaw_deg=5)
    render(os.path.join(OUT, "trees.png"), res=(1600, 1000), samples=48)


def sheet_monuments(seed):
    """C: 12 increasingly ambitious hero structures."""
    fresh_scene()
    _ground()
    add_sun(elevation_deg=26, azimuth_deg=215, energy=4.5)
    add_fill()
    for i, (c, r, pos) in enumerate(_grid_positions(4, 3, 13.0)):
        culture = DECO if i % 2 == 0 else ORGANIC
        scale = 1.2 + i * 0.28
        parts = A.hero_arch(culture, seed * 30 + i, scale=scale)
        _place_parts(parts, "h%d" % i, pos)
    add_camera((0, 0, 6.0), 170.0, fov_deg=20, pitch_deg=20, yaw_deg=10)
    render(os.path.join(OUT, "monuments.png"), res=(1600, 1000), samples=48)


def sheet_time(seed):
    """D: one structure - new, aged, damaged, ruined, reclaimed."""
    fresh_scene()
    _ground()
    add_sun(elevation_deg=24, azimuth_deg=215, energy=4.5)
    add_fill()
    conditions = [1.0, 0.75, 0.5, 0.25, 0.08]
    for i, cond in enumerate(conditions):
        pos = ((i - 2) * 9.0, 0.0, 0.0)
        parts = A.stepped_monument(DECO, seed * 40, scale=1.6)  # same seed!
        parts, age = ruin(parts, cond, seed * 40)
        _place_parts(parts, "s%d" % i, pos, age=age)
        if cond < 0.6:
            _place_parts(debris(seed * 40 + i, footprint=1.8,
                                count=int((1 - cond) * 12), scale=0.3),
                         "d%d" % i, pos)
        if cond < 0.3:  # reclamation
            rng = chan(seed, "reclaim", i)
            for k in range(int((1 - cond) * 6)):
                import math
                a = rng.random() * 6.28
                r = 1.0 + rng.random() * 1.6
                tp = V.TREES["shrub" if rng.random() < 0.6 else "broadleaf"](
                    seed * 50 + k, scale=1.2)
                _place_parts(tp, "veg%d_%d" % (i, k),
                             (pos[0] + math.cos(a) * r,
                              pos[1] + math.sin(a) * r, 0.0))
    add_camera((0, 0, 2.8), 145.0, fov_deg=20, pitch_deg=18, yaw_deg=4)
    render(os.path.join(OUT, "ruin_progression.png"),
           res=(1800, 900), samples=48)


def sheet_diorama(seed, culture=None, ruined=False, tag=""):
    """E: the tiny diorama."""
    fresh_scene()
    culture = culture or DECO
    target = build_valley(seed, culture,
                          ruin_culture=culture if ruined else None)
    add_sun(elevation_deg=26, azimuth_deg=205, energy=4.5)
    add_camera((0.0, 0.0, 0.3), 80.0, fov_deg=22, pitch_deg=36, yaw_deg=-140)
    name = "diorama_seed_%03d%s.png" % (seed % 1000, tag)
    render(os.path.join(OUT, name), res=(1600, 1000), samples=48)


def sheet_sequence(seed):
    """One valley, seven dates, one camera - then a shareable montage."""
    from civlife_blender.sequence import SEQUENCE, build_date, valley_plan
    plan = valley_plan(seed)
    tiles = []
    for year, label, cfg in SEQUENCE:
        fresh_scene()
        build_date(seed, plan, cfg)
        add_sun(elevation_deg=26, azimuth_deg=205, energy=4.5)
        add_camera((0.0, 0.0, 0.3), 80.0, fov_deg=22, pitch_deg=36,
                   yaw_deg=-140)
        path = os.path.join(OUT, "sequence_year_%04d.png" % year)
        render(path, res=(1600, 1000), samples=48)
        tiles.append((year, label, path))
    montage_sequence(tiles, os.path.join(OUT, "sequence_montage.png"))


def montage_sequence(tiles, out_path):
    from PIL import Image, ImageDraw, ImageFont
    tw, th = 800, 500
    label_h = 46
    cols, rows = 4, 2
    W, H = cols * tw, rows * (th + label_h)
    sheet = Image.new("RGB", (W, H), (14, 16, 24))
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 22)
        small = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 17)
    except OSError:
        font = small = ImageFont.load_default()
    draw = ImageDraw.Draw(sheet)
    for idx, (year, label, path) in enumerate(tiles):
        c, r = idx % cols, idx // cols
        x0, y0 = c * tw, r * (th + label_h)
        img = Image.open(path).resize((tw, th), Image.LANCZOS)
        sheet.paste(img, (x0, y0))
        text = "YEAR %d - %s" % (year, label.upper())
        draw.text((x0 + 14, y0 + th + 11), text, fill=(201, 164, 74),
                  font=font)
    # title card in the last cell
    x0, y0 = 3 * tw, 1 * (th + label_h)
    draw.rectangle([x0, y0, x0 + tw, y0 + th + label_h], fill=(14, 16, 24))
    draw.text((x0 + 44, y0 + 130), "CIV-LIFE", fill=(230, 223, 204),
              font=font)
    lines = ["one valley, seven dates", "same seed, same mountains",
             "", "every difference between", "these frames is a rule,",
             "not an asset",
             "", "tools/blender - headless bpy lab"]
    for i, ln in enumerate(lines):
        draw.text((x0 + 44, y0 + 180 + i * 30), ln, fill=(160, 168, 146),
                  font=small)
    sheet.save(out_path)
    print("montage:", out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--experiment", default="all")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--culture", default="deco")
    ap.add_argument("--ruined", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    t0 = time.time()
    culture = {"deco": DECO, "organic": ORGANIC}[args.culture]
    if args.experiment in ("culture", "all"):
        sheet_culture(args.seed)
    if args.experiment in ("trees", "all"):
        sheet_trees(args.seed)
    if args.experiment in ("monuments", "all"):
        sheet_monuments(args.seed)
    if args.experiment in ("time", "all"):
        sheet_time(args.seed)
    if args.experiment == "sequence":
        sheet_sequence(args.seed)
    if args.experiment in ("diorama", "all"):
        sheet_diorama(args.seed, culture, ruined=args.ruined,
                      tag=('_%s_ruined' % args.culture) if args.ruined else '')
    print("done in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
