"""Animate our infected from their drawn still (assets-debt I1).

The still's material map (`draw_infected.py`) is split into parts (body and head, near and far
arm, near and far leg), each part is posed per frame (leg shear and lift, body bob, head loll,
arm swing, arms raised by rotation round the shoulder), and every frame is shaded and outlined
again by `draw_infected.render`, so the pixels stay clean instead of being pushed about as
finished art. The hand-painted details (eyes, wounds) ride on the body as an overlay taken from
the Tandem still (`<kind>_handpass.json` beside the reference).

Output, like the game's infected sheets (`scripts/infected_atlas.gd`): one row of CELL x CELL
cells, feet on row FEET, facing right: walk, lunge, then the downed pose.

    python3 tools/animate_infected.py shambler <reference_lock.png> <handpass.json> out.png

For the game: out.png = assets/sprites/chars/infected_shambler.png; the layout goes to
out.json beside it, and `tools/import_infected.py` writes it into the atlas.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image

import draw_infected as D

CELL, FEET = 112, 104

# Where the parts of the shambler's still are (material-map coordinates, after the row drops).
SHAMBLER = {
    "hip": 59, "split": 19, "knee": 66, "foot": 75, "shoe": 71,
    "near_arm": lambda mat, x, y: mat == "skin" and y >= 35 and x <= 11,
    "far_arm": lambda mat, x, y: mat == "skin_far" and y >= 33 and x >= 22,
    "near_shoulder": (6, 37), "far_shoulder": (25, 35),
}


def split_parts(m, spec):
    H, W = len(m), len(m[0])

    def base(mat, x, y):
        if mat is None:
            return None
        if mat != "line":
            if spec["near_arm"](mat, x, y):
                return "near_arm"
            if spec["far_arm"](mat, x, y):
                return "far_arm"
        if y >= spec["hip"]:
            return "far_leg" if x >= spec["split"] else "near_leg"
        return "body"

    part = [[base(m[y][x], x, y) if m[y][x] != "line" else None for x in range(W)] for y in range(H)]
    # line pixels go with the part most of their neighbours belong to
    for y in range(H):
        for x in range(W):
            if m[y][x] != "line":
                continue
            votes = {}
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < W and 0 <= yy < H and m[yy][xx] not in (None, "line"):
                        p = part[yy][xx]
                        votes[p] = votes.get(p, 0) + 1
            part[y][x] = max(votes, key=votes.get) if votes else base("line", x, y)
    parts = {}
    for y in range(H):
        for x in range(W):
            if m[y][x] is not None:
                parts.setdefault(part[y][x], []).append((x, y, m[y][x]))
    return parts


def shear_leg(px, hip, foot, shoe, dx_foot, lift):
    out = []
    for x, y, mat in px:
        t = max(0.0, min(1.0, (y - hip) / (foot - hip)))
        up = lift if y >= shoe else round(lift * max(0.0, (y - (shoe - 6)) / 6))
        out.append((x + round(dx_foot * t), y - up, mat))
    return out


def swing_arm(px, shoulder, dx_hand, angle=0.0):
    """Shear the arm from the shoulder down (swing), then rotate it round the shoulder."""
    sx, sy = shoulder
    bottom = max(y for _, y, _ in px)
    sheared = {}
    for x, y, mat in px:
        t = max(0.0, (y - sy) / max(1, bottom - sy))
        sheared[(x + round(dx_hand * t), y)] = mat
    if not angle:
        return [(x, y, m) for (x, y), m in sheared.items()]
    # rotate by inverse mapping, so the rotated arm has no holes
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    xs = [x for x, _ in sheared]
    ys = [y for _, y in sheared]
    r = int(max(abs(max(xs) - sx), abs(min(xs) - sx), abs(max(ys) - sy), abs(min(ys) - sy))) + 2
    out = []
    for ty in range(sy - r, sy + r + 1):
        for tx in range(sx - r, sx + r + 1):
            ux, uy = tx - sx, ty - sy
            fx = round(sx + ux * ca + uy * sa)
            fy = round(sy - ux * sa + uy * ca)
            if (fx, fy) in sheared:
                out.append((tx, ty, sheared[(fx, fy)]))
    return out


def move(px, dx, dy):
    return [(x + dx, y + dy, m) for x, y, m in px]


def lean(px, pivot_y, top_dx):
    """Lean the body forward (top_dx > 0) or back, keeping the hips (pivot_y) in place."""
    top = min(y for _, y, _ in px)
    return [(x + round(top_dx * (pivot_y - y) / max(1, pivot_y - top)) if y < pivot_y else x, y, m)
            for x, y, m in px]


def compose(layers, W, H):
    m = [[None] * W for _ in range(H)]
    for px in layers:
        for x, y, mat in px:
            if 0 <= x < W and 0 <= y < H:
                m[y][x] = mat
    # A line that bordered a part which has since moved is left outlining nothing: drop line
    # pixels with fewer than two coloured neighbours (render outlines the figure again anyway).
    for _ in range(2):
        drop = []
        for y in range(H):
            for x in range(W):
                if m[y][x] != "line":
                    continue
                n = sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                        if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H
                        and m[y + dy][x + dx] not in (None, "line"))
                if n < 2:
                    drop.append((x, y))
        for x, y in drop:
            m[y][x] = None
    return m


def pose(parts, spec, overlay, *, leg_near=0, leg_far=0, lift_near=0, lift_far=0, bob=0, head=0,
         arm_near=0, arm_far=0, rot_near=0.0, rot_far=0.0, reach_near=0, reach_far=0, lean_dx=0, pad=8):
    hip, foot, shoe = spec["hip"], spec["foot"], spec["shoe"]
    body = lean(parts["body"], hip, lean_dx)
    # head loll: rows above the neck move a little more than the body
    body = [(x + (head if y < 24 else 0), y, mat) for x, y, mat in body]
    body = move(body, 0, bob)

    def shoulder(p):
        sx, sy = spec[p]
        return sx + round(lean_dx * (hip - sy) / hip), sy + bob

    na = move(swing_arm(move(lean(parts["near_arm"], hip, lean_dx), 0, bob), shoulder("near_shoulder"), arm_near, rot_near), reach_near, 0)
    fa = move(swing_arm(move(lean(parts["far_arm"], hip, lean_dx), 0, bob), shoulder("far_shoulder"), arm_far, rot_far), reach_far, 0)
    nl = shear_leg(parts["near_leg"], hip, foot, shoe, leg_near, lift_near)
    fl = shear_leg(parts["far_leg"], hip, foot, shoe, leg_far, lift_far)
    layers = [fa, fl, body, nl, na]
    layers = [move(px, pad, pad) for px in layers]
    W = max(x for px in layers for x, _, _ in px) + pad + 1
    H = max(y for px in layers for _, y, _ in px) + pad + 1
    out = D.render(compose(layers, W, H))
    # the hand-painted details, carried by the body
    for x, y, c in overlay:
        dx = round(lean_dx * (hip - y) / hip) if y < hip else 0
        tx, ty = x + dx + (head if y < 24 else 0) + pad, y + bob + pad
        if 0 <= ty < H and 0 <= tx < W and out[ty][tx]:
            out[ty][tx] = c
    return out


def keep_body(im: Image.Image) -> Image.Image:
    """One body per frame: keep the largest 8-connected shape, drop stray specks."""
    W, H = im.size
    a = im.load()
    seen, best = set(), []
    for y in range(H):
        for x in range(W):
            if a[x, y][3] and (x, y) not in seen:
                comp, st = [], [(x, y)]
                seen.add((x, y))
                while st:
                    cx, cy = st.pop()
                    comp.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            n = (cx + dx, cy + dy)
                            if 0 <= n[0] < W and 0 <= n[1] < H and n not in seen and a[n][3]:
                                seen.add(n)
                                st.append(n)
                if len(comp) > len(best):
                    best = comp
    out = Image.new("RGBA", im.size)
    for p in best:
        out.putpixel(p, a[p])
    return out


def to_cell(px, feet_row_in_px) -> Image.Image:
    """Place a rendered frame in a CELL x CELL cell, feet on FEET, centred on the hips."""
    im = keep_body(D.to_image_full(px))
    cell = Image.new("RGBA", (CELL, CELL))
    b = im.getbbox()
    cx = (b[0] + b[2]) // 2
    cell.alpha_composite(im, (CELL // 2 - cx, FEET - feet_row_in_px))
    return cell


def shambler_frames(parts, spec, overlay, pad=8):
    feet = spec["foot"] + pad + 1  # the sole's contour row
    walk = []
    for i in range(8):
        ph = 2 * math.pi * i / 8
        s, c = math.sin(ph), math.cos(ph)
        walk.append(pose(parts, spec, overlay,
                         leg_far=round(3 * s), leg_near=round(-3 * s),
                         lift_far=2 if c > 0.3 and s > -0.2 else 0,
                         lift_near=2 if c < -0.3 and s < 0.2 else 0,
                         bob=1 if abs(s) > 0.6 else 0,
                         head=round(0.9 * math.sin(ph + 1.2)),
                         arm_near=round(-1.5 * s), arm_far=round(1.5 * s), pad=pad))
    # lunge: gather, throw the arms and the head forward, hold the grab, recover
    keys = [dict(lean_dx=-1, rot_near=10, rot_far=10, bob=1),
            dict(lean_dx=3, rot_near=-40, rot_far=-30, reach_near=4, reach_far=1, leg_far=2),
            dict(lean_dx=5, rot_near=-78, rot_far=-62, reach_near=10, reach_far=3, leg_far=4, leg_near=-1),
            dict(lean_dx=5, rot_near=-80, rot_far=-66, reach_near=11, reach_far=4, leg_far=4, leg_near=-1, head=1),
            dict(lean_dx=2, rot_near=-35, rot_far=-25, reach_near=4, reach_far=1, leg_far=2)]
    lunge = [pose(parts, spec, overlay, pad=pad, **k) for k in keys]
    return walk, lunge, feet


def main() -> None:
    kind, ref, handpass, out = sys.argv[1:5]
    regions, drop = D.KINDS[kind]
    m = D.material_map(ref, regions, drop)
    # the hand pass painted in Tandem (eyes, wounds), saved as pixels in material-map coordinates
    overlay = [tuple(p) for p in json.loads(Path(handpass).read_text())["pixels"]]
    parts = split_parts(m, SHAMBLER)
    walk, lunge, feet = shambler_frames(parts, SHAMBLER, overlay)
    frames = walk + lunge
    sheet = Image.new("RGBA", (CELL * (len(frames) + 1), CELL))
    for i, f in enumerate(frames):
        sheet.alpha_composite(to_cell(f, feet), (i * CELL, 0))
    # downed pose: the standing still turned onto its back
    still = D.to_image_full(pose(parts, SHAMBLER, overlay))
    lying = still.crop(still.getbbox()).rotate(90, expand=True)
    cell = Image.new("RGBA", (CELL, CELL))
    cell.alpha_composite(lying, ((CELL - lying.width) // 2, FEET - lying.height))
    sheet.alpha_composite(cell, (len(frames) * CELL, 0))
    sheet.save(out)
    # the layout beside the sheet; import_infected.py puts it into scripts/infected_atlas.gd
    height = max(to_cell(f, feet).getbbox()[3] - to_cell(f, feet).getbbox()[1] for f in walk)
    layout = {"walk": [0, len(walk), 8.0, True], "lunge": [len(walk), len(lunge), 10.0, True],
              "down": [len(walk) + len(lunge), 1, 1.0, False], "height": height}
    Path(out).with_suffix(".json").write_text(json.dumps(layout) + "\n")
    print(f"{out}: walk {len(walk)}, lunge {len(lunge)}, down 1, figure {height} px")


if __name__ == "__main__":
    main()
