"""Draws REDLINE's prototype world art: floor and wall tiles, props and floor weapons, in the
agreed round-4 look (vintage 1980s colour, black outlines on objects, floors unoutlined with
darker grout). Placeholder art drawn in code until Tandem's tileset and sprites replace it
(same JSON layout).

    python3 tools/draw_topdown_world.py   # writes assets/sprites/world/{tiles,props}.{png,json}
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/sprites/world"
T = 32
K = (0, 0, 0, 255)


def C(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def tile(fn):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    fn(ImageDraw.Draw(im))
    return im


def rose(d):  # lobby/bar tile: dusty rose squares, grout one step darker
    d.rectangle((0, 0, T - 1, T - 1), fill=C("#b8707a"))
    for v in (0, 16):
        d.line((v, 0, v, T - 1), fill=C("#965a64"))
        d.line((0, v, T - 1, v), fill=C("#965a64"))
    d.point([(5, 9), (22, 26), (27, 6)], fill=C("#c4808a"))


def dance(d):  # dancefloor: dusty rose and dark brown checks
    for y in (0, 16):
        for x in (0, 16):
            d.rectangle((x, y, x + 15, y + 15), fill=C("#c9707a") if (x + y) % 32 == 0 else C("#3a2418"))
    for v in (0, 16):
        d.line((v, 0, v, T - 1), fill=C("#24160e"))
        d.line((0, v, T - 1, v), fill=C("#24160e"))


def carpet(d):  # lounge: faded maroon carpet with a small repeating diamond
    d.rectangle((0, 0, T - 1, T - 1), fill=C("#6a1e2a"))
    for y in range(0, T, 8):
        for x in range(0, T, 8):
            cx, cy = x + 4, y + 4
            d.polygon([(cx, cy - 2), (cx + 2, cy), (cx, cy + 2), (cx - 2, cy)], fill=C("#82303a"))
            d.point((cx, cy), fill=C("#a8524a"))


def wood(d):  # bar floor: warm planks, ends staggered so no two rows line up
    d.rectangle((0, 0, T - 1, T - 1), fill=C("#8a5a36"))
    for i, y in enumerate(range(0, T, 8)):
        d.line((0, y, T - 1, y), fill=C("#5e3a22"))
        x = (i * 11) % T
        d.line((x, y, x, y + 7), fill=C("#5e3a22"))
        d.point((x + 5, y + 4), fill=C("#9a6a42"))


def cream(d):  # restroom: cream tile, small grout
    d.rectangle((0, 0, T - 1, T - 1), fill=C("#e8dcc0"))
    for v in range(0, T, 8):
        d.line((v, 0, v, T - 1), fill=C("#c4b494"))
        d.line((0, v, T - 1, v), fill=C("#c4b494"))


def wall(d):  # a wall seen from above: a flat pale top; the game draws its black outline along the edge
    d.rectangle((0, 0, T - 1, T - 1), fill=C("#d8c9a0"))
    d.point([(7, 9), (23, 21), (15, 27)], fill=C("#cbbc92"))


def counter(d):  # bar counter: dark wood top, outlined
    d.rectangle((0, 0, T - 1, T - 1), fill=K)
    d.rectangle((1, 2, T - 2, T - 3), fill=C("#6b3e2a"))
    d.rectangle((1, 2, T - 2, 6), fill=C("#9a6040"))
    d.point([(8, 14), (24, 18)], fill=C("#b0b0b8"))  # glasses on the bar


def booth(d):  # booth seat: olive cushions, outlined
    d.rectangle((0, 0, T - 1, T - 1), fill=K)
    d.rectangle((2, 2, T - 3, T - 3), fill=C("#5a6a30"))
    d.rectangle((2, 2, T - 3, 9), fill=C("#7a8a44"))
    d.line((T // 2, 10, T // 2, T - 4), fill=C("#46521f"))


TILES = [(".", "rose tile", rose, False), (",", "dancefloor", dance, False), ("_", "carpet", carpet, False),
         ("=", "wood floor", wood, False), ("w", "restroom tile", cream, False), ("#", "wall", wall, True),
         ("C", "bar counter", counter, True), ("K", "booth", booth, True)]


def props():
    out = {}
    im = Image.new("RGBA", (28, 28), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse((1, 1, 26, 26), fill=K); d.ellipse((2, 2, 25, 25), fill=C("#7a4a2e")); d.ellipse((5, 4, 22, 18), fill=C("#9a6040"))
    d.point([(10, 11), (17, 15)], fill=C("#d8d8e0"))
    out["table"] = im
    im = Image.new("RGBA", (12, 12), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse((0, 0, 11, 11), fill=K); d.ellipse((1, 1, 10, 10), fill=C("#8a2a34")); d.ellipse((3, 2, 8, 6), fill=C("#b0444c"))
    out["stool"] = im
    im = Image.new("RGBA", (32, 6), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rectangle((0, 1, 31, 4), fill=K); d.rectangle((1, 2, 30, 3), fill=C("#a8d4d8")); d.line((4, 2, 12, 2), fill=C("#ffffff"))
    out["glass"] = im
    im = Image.new("RGBA", (32, 6), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for x0 in (0, 29):
        d.rectangle((x0, 1, x0 + 2, 4), fill=K)
    for x in (6, 13, 19, 25):
        d.point((x, 3), fill=C("#a8d4d8"))
    out["glass_broken"] = im
    im = Image.new("RGBA", (28, 6), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 27, 5), fill=K); d.rectangle((1, 1, 26, 4), fill=C("#8a5a36")); d.line((1, 1, 26, 1), fill=C("#a87048"))
    d.point((23, 3), fill=C("#d9a52b"))
    out["door"] = im
    for name, length, col, width in (("pipe", 18, "#bfbfbf", 2), ("bat", 20, "#b07850", 3), ("pistol", 10, "#404040", 3), ("shotgun", 22, "#404040", 3)):
        im = Image.new("RGBA", (length + 4, 8), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
        d.rectangle((1, 4 - width // 2 - 1, length + 2, 4 + (width + 1) // 2), fill=K)
        d.rectangle((2, 4 - width // 2, length + 1, 4 + (width - 1) // 2), fill=C(col))
        if name == "shotgun":
            d.rectangle((2, 3, 7, 5), fill=C("#8a5a36"))
        if name == "bat":
            d.rectangle((2, 3, 7, 5), fill=C("#6b3e2a"))
        out["w_" + name] = im
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (T * len(TILES), T), (0, 0, 0, 0))
    meta = {"tile": T, "tiles": []}
    for i, (ch, name, fn, solid) in enumerate(TILES):
        sheet.alpha_composite(tile(fn), (i * T, 0))
        meta["tiles"].append({"char": ch, "name": name, "x": i, "solid": solid})
    sheet.save(OUT / "tiles.png")
    (OUT / "tiles.json").write_text(json.dumps(meta, indent=1) + "\n")
    ps = props()
    x = 0
    pmeta = {}
    height = max(im.height for im in ps.values())
    psheet = Image.new("RGBA", (sum(im.width + 1 for im in ps.values()), height), (0, 0, 0, 0))
    for name, im in ps.items():
        psheet.alpha_composite(im, (x, 0))
        pmeta[name] = [x, 0, im.width, im.height]
        x += im.width + 1
    psheet.save(OUT / "props.png")
    (OUT / "props.json").write_text(json.dumps(pmeta, indent=1) + "\n")
    print(f"tiles {len(TILES)}, props {len(ps)}")


if __name__ == "__main__":
    main()
