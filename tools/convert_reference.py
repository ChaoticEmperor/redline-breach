#!/usr/bin/env python3
"""Convert a painted or generated pixel-art reference into a game sprite sheet.

    python3 tools/convert_reference.py

The reference is not redrawn. Its own pixels are recovered from its grid and
rebuilt as a proper Atelier document: locked palette, a layer per body part,
one frame per pose, checked against the reference. See "Working from a
reference image" in .claude/skills/atelier-pixel-art/SKILL.md.

Steps: measure the reference's pixel pitch -> recover each pose's native
pixels (dropping the backdrop and ground shadow, closing and filling the
outline) -> lock a palette sized to keep the face -> paint layers and frames
in Atelier -> apply the hand fixes listed in the spec -> run the gates ->
export.

Output: assets/sprites/chars/sheet_player_v3.png, 96x96 cells, the figure
about 78 pixels tall facing right with its feet on row 90:
  0-1 idle (breathing)   2-5 walk   6 kick   7 down
Keep that in step with PLAYER_V3 in scripts/fx.gd. The front fist is its own layer and is also
exported alone as sheet_player_v3_hand.png (same layout): the game draws it over the held weapon. The Atelier document is
kept in tools/out/atelier/ (git-ignored) so it can be inspected and fixed by
region. Exits 0 without writing anything if Atelier or the reference is
missing (the game then uses the older player art).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:  # pragma: no cover
    print("convert_reference: needs numpy and Pillow; nothing converted.")
    sys.exit(0)

from _atelier import ROOT, atelier_binary

SPEC = {
    "source": ROOT / "assets" / "raw" / "player_reference.png",
    "out": ROOT / "assets" / "sprites" / "chars" / "sheet_player_v3.png",
    # the front fist alone, same layout: the game draws it over the held weapon so the hand grips it
    "hand_out": ROOT / "assets" / "sprites" / "chars" / "sheet_player_v3_hand.png",
    "cell": 96,
    "feet": 90,
    "backdrop": (27, 23, 37),
    "rows": (470, 960),                       # source rows holding the figures (not the watermark)
    # pose -> source columns holding it
    "poses": {"idle": (98, 284), "walk0": (425, 629), "walk1": (774, 962), "walk2": (1079, 1329),
              "walk3": (1433, 1661), "kick": (1796, 2154), "down": (2225, 2687)},
    # frames of the exported sheet; "idle_b" is the idle with the upper body one pixel lower (a breath)
    "frames": ["idle", "idle_b", "walk0", "walk1", "walk2", "walk3", "kick", "down"],
    "loops": {"idle": (0, 1), "walk": (2, 5)},
    "palette": (39, 6),                       # main colours + accent slots; sized by the definition test
    # Hand fixes, by region. The far foot fades into the ground shadow in two walk poses, so it is
    # rebuilt: (frame name, rectangle to clear [x, y, w, h], x, y, rows). A = ink, D/E = shoe darks.
    "patches": [
        ("walk0", [38, 85, 5, 3], 32, 80, [".AAA......", "ADDDA.....", "ADDDDAA...", ".AEDDDDAA.", "..AAEDDDDA", "....AAAAA."]),
        ("walk3", [33, 84, 6, 5], 29, 80, ["ADDDA....", "ADDDDA...", ".AEDDDA..", "..AEDDDA.", "...AEDDDA", "....AAAA."]),
    ],
    "patch_colours": {"A": "#030102", "D": "#292530", "E": "#1b151e"},
}
KEYS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
HOME = ROOT / "tools" / "out" / "atelier"


# ------------------------------------------------------------------ grid recovery

def edge_profiles(lum):
    return np.abs(np.diff(lum, axis=1)).sum(0), np.abs(np.diff(lum, axis=0)).sum(1)


def fold(profile, pitch, step=0.25):
    """Best phase for sampling `profile` every `pitch` pixels, and how much edge energy it catches."""
    best = (0.0, -1.0)
    for ph in np.arange(0, pitch, step):
        idx = np.round(np.arange(ph, len(profile), pitch)).astype(int)
        idx = idx[idx < len(profile)]
        score = profile[idx].mean() / max(profile.mean(), 1e-9)
        if score > best[1]:
            best = (float(ph), float(score))
    return best


def measure_pitch(lum) -> float:
    gx, gy = edge_profiles(lum)
    scores = {p: fold(gx, p)[1] + fold(gy, p)[1] for p in np.arange(4.0, 12.01, 0.25)}
    best = max(scores.values())
    # multiples of the true pitch score as well as it does, so take the smallest strong one
    return float(min(p for p, v in scores.items() if v >= best * 0.8))


def grow(mask):
    out = mask.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        out |= np.roll(np.roll(mask, dy, 0), dx, 1)
    return out


def recover(src, name, pitch):
    """Native RGBA pixels of one pose, and where its top-left sits in the source."""
    y0, y1 = SPEC["rows"]
    x0, x1 = SPEC["poses"][name]
    x0, x1 = x0 - 12, x1 + 12
    reg = src[y0:y1, x0:x1]
    gx, gy = edge_profiles(reg.mean(-1))
    px, py = fold(gx, pitch)[0] + 1, fold(gy, pitch)[0] + 1      # edges sit between cells
    xs, ys = np.arange(px, reg.shape[1] - pitch, pitch), np.arange(py, reg.shape[0] - pitch, pitch)
    grid = np.zeros((len(ys), len(xs), 3))
    for j, y in enumerate(ys):
        for i, x in enumerate(xs):
            cx, cy = int(round(x + pitch / 2)), int(round(y + pitch / 2))
            grid[j, i] = np.median(reg[cy - 1:cy + 2, cx - 1:cx + 2].reshape(-1, 3), axis=0)
    backdrop = np.array(SPEC["backdrop"], float)
    fg = np.abs(grid - backdrop).sum(-1) > 30
    dark = grid.mean(-1) < 26
    colour = fg & ~dark
    near = np.zeros_like(colour)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            near |= np.roll(np.roll(colour, dy, 0), dx, 1)
    keep = colour | (dark & near)             # outline stays, the ground shadow goes
    # Whatever is sealed inside the outline belongs to the sprite even if it is close to the
    # backdrop colour; the outline has one-pixel gaps where it fades out, so close those first.
    wall = grow(keep)
    hh, ww = keep.shape
    outside = np.zeros_like(keep)
    stack = [(y, x) for y in range(hh) for x in (0, ww - 1)] + [(y, x) for x in range(ww) for y in (0, hh - 1)]
    while stack:
        y, x = stack.pop()
        if 0 <= y < hh and 0 <= x < ww and not outside[y, x] and not wall[y, x]:
            outside[y, x] = True
            stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    keep = keep | ~grow(outside)
    ys_, xs_ = np.where(keep)
    g = grid[ys_.min():ys_.max() + 1, xs_.min():xs_.max() + 1]
    k = keep[ys_.min():ys_.max() + 1, xs_.min():xs_.max() + 1]
    rgba = np.dstack([g, np.where(k, 255, 0)]).astype(np.uint8)
    return rgba, (x0 + px + xs_.min() * pitch, y0 + py + ys_.min() * pitch)


# ------------------------------------------------------------------ palette

def build_palette(pix, n_main, n_accent, accent_dist=38.0):
    """One ink colour, n_main quantised colours, then slots for colours that are rare but far
    from the rest (eye whites, an iris): plain quantising drops exactly those."""
    ink = pix[pix.mean(1) < 22]
    rest = pix[pix.mean(1) >= 22]
    strip = Image.fromarray(rest.reshape(1, -1, 3).astype(np.uint8), "RGB")
    q = strip.quantize(colors=n_main, method=Image.Quantize.MEDIANCUT, kmeans=6)
    pal = np.vstack([np.median(ink, axis=0).round(), np.array(q.getpalette()[:n_main * 3]).reshape(-1, 3)]).astype(float)
    for _ in range(n_accent):
        d = np.sqrt(((rest[:, None, :] - pal[None, :, :]) ** 2).sum(-1)).min(1)
        far = rest[d > accent_dist]
        if len(far) < 3:
            break
        seed = far[np.argmax(d[d > accent_dist])]
        pal = np.vstack([pal, np.median(far[np.sqrt(((far - seed) ** 2).sum(1)) < accent_dist], axis=0).round()])
    pal = np.unique(pal.astype(int), axis=0)
    return pal[np.argsort(pal.sum(1))]


def definition(pal, rgba, top=0.1, bottom=0.44):
    """Share of face pixels (%) whose nearest palette colour is badly off."""
    h = rgba.shape[0]
    face = rgba[int(h * top):int(h * bottom)]
    p = face[face[..., 3] > 0][:, :3].astype(float)
    d = np.sqrt(((p[:, None, :] - pal[None, :, :].astype(float)) ** 2).sum(-1)).min(1)
    return float((d > 30).mean() * 100)


def front_fist(rgb, opaque):
    """Mask of the leading fist: the skin patch furthest right that is not the face or neck,
    plus the dark outline pixels around it. Empty when the pose shows no such hand."""
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    skin = opaque & (r > 140) & (b > 60) & (r > g + 20) & (g > b)
    todo, parts = skin.copy(), []
    for y, x in zip(*np.where(skin)):
        if not todo[y, x]:
            continue
        todo[y, x] = False
        stack, pts = [(y, x)], []
        while stack:
            cy, cx = stack.pop()
            pts.append((cy, cx))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < skin.shape[0] and 0 <= nx < skin.shape[1] and todo[ny, nx]:
                        todo[ny, nx] = False
                        stack.append((ny, nx))
        parts.append(pts)
    parts.sort(key=len)
    hands = [p for p in parts[:-1] if len(p) >= 15]          # the largest patch is the face
    mask = np.zeros_like(skin)
    if not hands:
        return mask
    for y, x in max(hands, key=lambda p: max(q[1] for q in p)):
        mask[y, x] = True
    ring = np.zeros_like(mask)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ring |= np.roll(np.roll(mask, dy, 0), dx, 1)
    return mask | (ring & opaque & (rgb.mean(-1) < 40))


# ------------------------------------------------------------------ atelier

def make_caller(binary):
    env = dict(os.environ, ATELIER_HOME=str(HOME))

    def call(tool, **args):
        done = subprocess.run([binary, "call", tool, "--stdin"], input=json.dumps(args), env=env,
                              capture_output=True, text=True)
        if "{" not in done.stdout:
            raise SystemExit(f"atelier {tool} failed:\n{done.stdout}\n{done.stderr}")
        return json.loads(done.stdout[done.stdout.index("{"):])
    return call


def main() -> int:
    binary = atelier_binary()
    if binary is None or not SPEC["source"].exists():
        print("convert_reference: atelier or the reference is missing; nothing converted, game falls back")
        return 0
    src_img = Image.open(SPEC["source"]).convert("RGB")
    src = np.asarray(src_img).astype(float)
    y0, y1 = SPEC["rows"]
    first = SPEC["poses"]["idle"]
    pitch = measure_pitch(src[y0:y1, first[0] - 10:first[1] + 10].mean(-1))
    print(f"convert_reference: pixel pitch {pitch:.2f} source pixels per art pixel")

    poses = {name: recover(src, name, pitch) for name in SPEC["poses"]}
    pix = np.concatenate([p[0][p[0][..., 3] > 0][:, :3] for p in poses.values()]).astype(float)
    pal = build_palette(pix, *SPEC["palette"])
    hexes = ["#%02x%02x%02x" % tuple(int(v) for v in c) for c in pal]
    off = definition(pal, poses["idle"][0])
    print(f"  palette: {len(pal)} colours, face pixels badly off: {off:.1f}%" + ("" if off < 0.1 else "  <- raise the palette size"))

    shutil.rmtree(HOME, ignore_errors=True)
    HOME.mkdir(parents=True)
    call = make_caller(binary)
    cell, feet = SPEC["cell"], SPEC["feet"]
    doc = call("doc_new", name="player_v3", width=cell, height=cell)["doc_id"]
    call("doc_palette", op="set", doc_id=doc, colors=hexes)
    call("doc_layer", op="rename", doc_id=doc, index=0, name="legs")
    for layer in ("torso", "head", "hand"):
        call("doc_layer", op="add", doc_id=doc, name=layer)
    for _ in SPEC["frames"][1:]:
        call("doc_frame", op="add", doc_id=doc)
    legend = {KEYS[i]: hexes[i] for i in range(len(pal))}

    def nearest(rgb):
        return int(np.argmin(((pal - np.asarray(rgb, float)) ** 2).sum(1)))

    def is_leg(c):                                   # jeans and shoes: blue-grey
        r, g, b = (int(v) for v in pal[c])
        return b > r + 12 and b >= g

    refs = {}
    for fi, frame in enumerate(SPEC["frames"]):
        name = "idle" if frame == "idle_b" else frame
        rgba, origin = poses[name]
        h, w = rgba.shape[:2]
        ox, oy = (cell - w) // 2, feet - h + 1
        idx = np.full((h, w), -1)
        for y in range(h):
            for x in range(w):
                if rgba[y, x, 3] > 0:
                    idx[y, x] = nearest(rgba[y, x, :3])
        layer_of = np.full((h, w), -1)
        for y in range(h):
            for x in range(w):
                c = idx[y, x]
                if c < 0:
                    continue
                if name == "down":
                    layer_of[y, x] = 0 if is_leg(c) else (2 if x > w * 0.72 else 1)
                elif is_leg(c) and y > h * 0.45:
                    layer_of[y, x] = 0
                else:
                    layer_of[y, x] = 2 if y < int(h * 0.38) else 1
        if name != "down":
            layer_of[front_fist(pal[np.maximum(idx, 0)], idx >= 0)] = 3
        for layer in range(4):
            ys, xs = np.where(layer_of == layer)
            if len(ys) == 0:
                continue
            ya, yb, xa, xb = ys.min(), ys.max(), xs.min(), xs.max()
            rows = ["".join(KEYS[idx[y, x]] if layer_of[y, x] == layer else "." for x in range(xa, xb + 1))
                    for y in range(ya, yb + 1)]
            breath = 1 if frame == "idle_b" and layer > 0 else 0
            call("doc_paint_grid", doc_id=doc, layer=layer, frame=fi, legend=legend, rows=rows,
                 x=int(ox + xa), y=int(oy + ya + breath))
        # the reference window that this canvas covers, for doc_ref
        sx, sy = origin[0] - ox * pitch, origin[1] - oy * pitch
        size = round(cell * pitch)
        ref = Image.new("RGB", (size, size), SPEC["backdrop"])
        ref.paste(src_img.crop((round(sx), round(sy), round(sx) + size, round(sy) + size)), (0, 0))
        refs[frame] = HOME / f"ref_{frame}.png"
        ref.save(refs[frame])

    patch_legend = {k: hexes[nearest([int(v[i:i + 2], 16) for i in (1, 3, 5)])] for k, v in SPEC["patch_colours"].items()}
    for frame, clear, x, y, rows in SPEC["patches"]:
        fi = SPEC["frames"].index(frame)
        call("doc_region", doc_id=doc, op="clear", layer=0, frame=fi, rect=clear)
        call("doc_paint_grid", doc_id=doc, layer=0, frame=fi, legend=patch_legend, x=x, y=y, rows=rows)
    for name, (a, b) in SPEC["loops"].items():
        call("doc_add_tag", doc_id=doc, name=name, **{"from": a, "to": b})
    call("doc_checkpoint", doc_id=doc, action="save", label="converted")

    # ---- gates
    failed = 0
    print("  %-7s %-8s %-7s %-8s %-9s %s" % ("frame", "orphans", "specks", "palette", "contrast", "against the reference"))
    for fi, frame in enumerate(SPEC["frames"]):
        checks = call("doc_critique", doc_id=doc, frame=fi)["checks"]
        specks = call("doc_components", doc_id=doc, frame=fi)["specks_total"]
        call("doc_ref", op="set", doc_id=doc, path=str(refs[frame]))
        cmp = call("doc_ref", op="compare", doc_id=doc, frame=fi)
        bad = checks["orphans"]["count"] or specks or checks["palette_adherence"]["verdict"] != "ok"
        failed += bool(bad)
        print("  %-7s %-8s %-7s %-8s %-9s silhouette %.2f, colour delta %.3f%s" % (
            frame, checks["orphans"]["count"], specks, checks["palette_adherence"]["verdict"],
            checks["contrast"]["verdict"], cmp["silhouette_iou"], cmp["mean_delta"], "  <- FIX" if bad else ""))
    info = call("doc_info", doc_id=doc)
    print(f"  layers {[l['name'] for l in info['layers']]}, {len(info['frames'])} frames, palette {info['palette_len']}")

    SPEC["out"].parent.mkdir(parents=True, exist_ok=True)
    call("doc_export", doc_id=doc, op="sheet", scale=1, out_path=str(SPEC["out"]))
    SPEC["out"].with_suffix(".json").unlink(missing_ok=True)
    for layer in range(3):
        call("doc_layer", op="set", doc_id=doc, index=layer, visible=False)
    call("doc_export", doc_id=doc, op="sheet", scale=1, out_path=str(SPEC["hand_out"]))
    SPEC["hand_out"].with_suffix(".json").unlink(missing_ok=True)
    for layer in range(3):
        call("doc_layer", op="set", doc_id=doc, index=layer, visible=True)
    print(f"  chars/{SPEC['hand_out'].name}  (the 'hand' layer alone)")
    sheet = Image.open(SPEC["out"])
    print(f"  chars/{SPEC['out'].name}  {sheet.width}x{sheet.height}  (document {doc} kept in tools/out/atelier)")
    if failed:
        print(f"convert_reference: {failed} frame(s) failed a gate; fix them by region before using the sheet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
