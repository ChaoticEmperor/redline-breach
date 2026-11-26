"""Critique a character sprite before it goes near the game.

Measures what can be measured and marks it on an enlarged copy, so a person (or an agent
looking at the picture) can judge the rest. Checks:

  size      the figure against the player: height within 5% (12% is the smoke-test limit),
            width within 20%. A family of actors keeps one body size, the cell and the feet
            row fixed; only weapons and reaching limbs go past it.
  key       bright green-dominant pixels: chroma backdrop left inside the figure (between the
            legs, under an arm), or a palette lock that turned it into a neon green.
  contour   figure pixels that touch transparency without an outline pixel (gaps), and
            outline two pixels thick where the style is one.
  orphans   single pixels unlike all eight neighbours (noise).
  flat      one colour covering a big connected area: no form shading.
  palette   colours outside the allowed palette, and the colour count.

    python3 tools/critique_sprite.py sprite.png [--cell N --frame I] [--palette sheet.png]
            [--allow '#b8ff40,...'] [--out marked.png] [--json]

Exit status 1 when a check fails, so it can gate a pipeline. The thresholds are set so the
approved player (`sheet_player_v3`, idle and frame 3) passes; `--self-test` checks that it
still does. Run frames 1 and 2 have real holes in the trousers (assets-debt I4).
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
PLAYER = ROOT / "assets/sprites/chars/sheet_player_v3.png"
OUTLINE = (3, 1, 2)
MARK = {"key": (0, 255, 255), "gap": (255, 0, 255), "thick": (255, 160, 0),
        "orphan": (255, 255, 0), "flat": (255, 60, 60), "palette": (80, 160, 255)}


def hexc(c) -> str:
    return "#%02x%02x%02x" % tuple(c[:3])


def load(path, cell=None, frame=0) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    if cell:
        cols = im.width // cell
        x, y = (frame % cols) * cell, (frame // cols) * cell
        im = im.crop((x, y, x + cell, y + cell))
    return im


def player_size() -> tuple[int, int]:
    b = load(PLAYER, 96, 0).getbbox()
    return b[2] - b[0], b[3] - b[1]


def critique(im: Image.Image, palette=None, allow=(), outline=OUTLINE):
    W, H = im.size
    px = im.load()
    op = lambda x, y: 0 <= x < W and 0 <= y < H and px[x, y][3] > 0
    col = lambda x, y: px[x, y][:3]
    # The contour is any very dark pixel: the style puts coloured outlines inside a dark
    # contour, and the dark hair or shoe colour on the edge counts as contour too.
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    is_out = lambda x, y: op(x, y) and lum(col(x, y)) < 34
    allow = {a.lower() for a in allow}
    marks: dict[str, list] = {k: [] for k in MARK}
    res: dict = {}

    b = im.getbbox()
    area = sum(1 for y in range(H) for x in range(W) if op(x, y))
    fw, fh = b[2] - b[0], b[3] - b[1]
    pw, ph = player_size()
    hr, wr = fh / ph, fw / pw
    res["size"] = {
        "figure": [fw, fh], "player": [pw, ph], "height_ratio": round(hr, 3), "width_ratio": round(wr, 3),
        "verdict": "fail" if abs(hr - 1) > 0.12 else "warn" if abs(hr - 1) > 0.05 or abs(wr - 1) > 0.20 else "ok",
    }

    colours = {}
    for y in range(H):
        for x in range(W):
            if not op(x, y):
                continue
            r, g, bl = col(x, y)
            colours[hexc((r, g, bl))] = colours.get(hexc((r, g, bl)), 0) + 1
            if g - max(r, bl) > 40 and g > 150 and hexc((r, g, bl)) not in allow:
                marks["key"].append((x, y))
            if not is_out(x, y):
                if any(not op(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    marks["gap"].append((x, y))
                n8 = [col(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                      if (dx or dy) and op(x + dx, y + dy)]
                if len(n8) == 8 and all(c != col(x, y) for c in n8):
                    marks["orphan"].append((x, y))
            else:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if not op(x + dx, y + dy) and is_out(x - dx, y - dy) and op(x - 2 * dx, y - 2 * dy) \
                            and not is_out(x - 2 * dx, y - 2 * dy):
                        marks["thick"].append((x, y))
                        break
    res["key"] = {"pixels": len(marks["key"]),
                  "colours": sorted({hexc(col(x, y)) for x, y in marks["key"]}),
                  "verdict": "fail" if marks["key"] else "ok"}
    contour = sum(1 for y in range(H) for x in range(W) if is_out(x, y))
    res["contour"] = {"gaps": len(marks["gap"]), "thick": len(marks["thick"]),
                      "thick_share": round(len(marks["thick"]) / max(contour, 1), 3),
                      "verdict": "fail" if len(marks["gap"]) > 3 or len(marks["thick"]) > contour * 0.15
                      else "warn" if marks["gap"] or marks["thick"] else "ok"}
    share = len(marks["orphan"]) / max(area, 1)
    res["orphans"] = {"pixels": len(marks["orphan"]), "share": round(share, 3),
                      "verdict": "warn" if share > 0.10 else "ok"}

    seen = set()
    flats = []
    for y in range(H):
        for x in range(W):
            if (x, y) in seen or not op(x, y) or is_out(x, y):
                continue
            c, comp, q = col(x, y), [], deque([(x, y)])
            seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if (nx, ny) not in seen and op(nx, ny) and col(nx, ny) == c:
                        seen.add((nx, ny))
                        q.append((nx, ny))
            if len(comp) > area * 0.08:
                flats.append((hexc(c), len(comp)))
                marks["flat"].extend(comp)
    res["flat"] = {"areas": flats, "verdict": "warn" if flats else "ok"}

    if palette:
        off = {c for c in colours if c not in palette}
        for y in range(H):
            for x in range(W):
                if op(x, y) and hexc(col(x, y)) in off:
                    marks["palette"].append((x, y))
        res["palette"] = {"colours": len(colours), "off_palette": sorted(off),
                          "verdict": "fail" if off else "ok"}
    else:
        res["palette"] = {"colours": len(colours), "verdict": "ok" if len(colours) <= 48 else "warn"}
    return res, marks


def marked(im: Image.Image, marks, scale=6) -> Image.Image:
    """Sprite and marked copy side by side, with the player's height drawn as guide lines."""
    W, H = im.size
    big = im.resize((W * scale, H * scale), Image.NEAREST)
    pw, ph = player_size()
    pl = load(PLAYER, 96, 0)
    pb = pl.getbbox()
    pl = pl.crop(pb).resize((pw * scale, ph * scale), Image.NEAREST)
    gap = 4 * scale
    out = Image.new("RGBA", (pl.width + 2 * big.width + 3 * gap, max(big.height, pl.height) + 2 * gap),
                    (205, 205, 210, 255))
    base = out.height - gap
    out.alpha_composite(pl, (gap, base - pl.height))
    fb = im.getbbox()
    for i in range(2):
        out.alpha_composite(big, (pl.width + gap * (2 + i) + big.width * i, base - fb[3] * scale))
    d = ImageDraw.Draw(out)
    x0 = pl.width + 3 * gap + big.width
    oy = base - fb[3] * scale
    for kind, pts in marks.items():
        for x, y in pts:
            d.rectangle((x0 + x * scale, oy + y * scale, x0 + x * scale + scale - 1, oy + y * scale + scale - 1),
                        outline=MARK[kind] + (255,), width=max(1, scale // 3))
    for y in (base - ph * scale, base):
        d.line((0, y, out.width, y), fill=(40, 120, 255, 255), width=1)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sprite", nargs="?")
    ap.add_argument("--cell", type=int)
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--palette", help="a PNG whose colours are the allowed palette")
    ap.add_argument("--allow", default="", help="comma-separated colours that are meant to be green")
    ap.add_argument("--out", help="write a marked, enlarged copy here")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--self-test", action="store_true", help="the approved player must pass")
    a = ap.parse_args(argv)
    if a.self_test:
        bad = [f for f in (0, 3) if any(v["verdict"] == "fail" for v in critique(load(PLAYER, 96, f))[0].values())]
        print("self-test:", "ok" if not bad else f"player frames {bad} fail")
        return 1 if bad else 0
    im = load(a.sprite, a.cell, a.frame)
    pal = None
    if a.palette:
        pi = Image.open(a.palette).convert("RGBA")
        pal = {hexc(p) for p in pi.getdata() if p[3] > 0}
    res, marks = critique(im, pal, [c for c in a.allow.split(",") if c])
    if a.out:
        marked(im, marks).save(a.out)
    if a.json:
        print(json.dumps(res, indent=1))
    else:
        for k, v in res.items():
            print(f"{v['verdict']:>4}  {k:8} " + ", ".join(f"{kk}={vv}" for kk, vv in v.items() if kk != "verdict"))
    return 1 if any(v["verdict"] == "fail" for v in res.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
