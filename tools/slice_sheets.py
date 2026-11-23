#!/usr/bin/env python3
"""Slice the AI-generated sprite sheets in assets/raw/ into game sprites.

    python3 tools/slice_sheets.py

Deterministic and safe to re-run whenever a raw sheet changes. Needs Pillow.
A missing sheet is skipped (exit code 0): the game falls back to its
procedural textures for any sprite that is not in assets/sprites/.

Pipeline per sheet:
  1. chroma-key the flat #00FF00 background and its anti-aliased green fringe
  2. find each drawing as a connected blob and assign it to its grid cell by
     centroid (drawings may spill over the cell lines)
  3. drop stray specks and the corner watermark
  4. trim, downscale with nearest-neighbour, write the PNG
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageFilter
except ImportError:  # pragma: no cover
    print("slice_sheets: Pillow is not installed (pip install Pillow); nothing sliced.")
    sys.exit(0)

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets" / "raw"
OUT = ROOT / "assets" / "sprites"

CHARS = ["player_pipe", "player_pistol", "player_shotgun", "zombie_shambler",
         "zombie_runner", "zombie_bloater", "corpse_zombie", "corpse_player"]
PROPS = ["sofa_pink", "table_cocktail", "bar_counter", "bar_stool",
         "dj_booth", "speaker", "potted_palm", "kitchen_counter",
         "stove", "toilet_stall", "sink", "crate",
         "metal_shelf", "booth_seat", "elevator_panel", "wooden_door"]
FLOORS = ["concrete", "dancefloor", "vip_carpet", "kitchen_tile",
          "bar_planks", "restroom_tile", "corridor_carpet", "elevator_steel"]

CHAR_MAX = 32   # longest side of the largest character, in game pixels
PROP_MAX = 32   # longest side of the largest prop
FLOOR_SIZE = 32  # floor tiles are square and cover 2x2 map cells
GRID = 8        # blob detection runs on a mask reduced by this factor


def key_green(im: Image.Image) -> Image.Image:
    """Returns RGBA with the green screen (and its fringe) made transparent."""
    im = im.convert("RGB")
    r, g, b = im.split()
    # "greenness": how far green exceeds the stronger of red and blue
    green = ImageChops.subtract(g, ImageChops.lighter(r, b))
    background = green.point(lambda v: 255 if v > 90 else 0)
    # Fringe: weaker green, but only directly next to keyed background.
    for _ in range(2):
        near = background.filter(ImageFilter.MaxFilter(3))
        fringe = ImageChops.multiply(near, green.point(lambda v: 255 if v > 36 else 0))
        background = ImageChops.lighter(background, fringe)
    out = im.convert("RGBA")
    out.putalpha(ImageChops.invert(background))
    return out


def blobs(alpha: Image.Image) -> list[dict]:
    """Connected opaque regions, measured on a reduced mask."""
    w, h = alpha.size
    gw, gh = w // GRID, h // GRID
    small = alpha.resize((gw, gh), Image.BOX).point(lambda v: 255 if v > 24 else 0)
    px = small.load()
    seen = [[False] * gw for _ in range(gh)]
    found = []
    for sy in range(gh):
        for sx in range(gw):
            if seen[sy][sx] or not px[sx, sy]:
                continue
            queue = deque([(sx, sy)])
            seen[sy][sx] = True
            x0 = x1 = sx
            y0 = y1 = sy
            area = sum_x = sum_y = 0
            while queue:
                x, y = queue.popleft()
                area += 1
                sum_x += x
                sum_y += y
                x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
                for nx in (x - 1, x, x + 1):
                    for ny in (y - 1, y, y + 1):
                        if 0 <= nx < gw and 0 <= ny < gh and not seen[ny][nx] and px[nx, ny]:
                            seen[ny][nx] = True
                            queue.append((nx, ny))
            found.append({
                "box": (x0 * GRID, y0 * GRID, (x1 + 1) * GRID, (y1 + 1) * GRID),
                "area": area * GRID * GRID,
                "cx": (sum_x / area + 0.5) * GRID,
                "cy": (sum_y / area + 0.5) * GRID,
            })
    return found


def cells(im: Image.Image, cols: int, rows: int) -> list[Image.Image | None]:
    """One trimmed RGBA image per grid cell (None if the cell is empty)."""
    w, h = im.size
    found = blobs(im.getchannel("A"))
    biggest = max((b["area"] for b in found), default=0)
    boxes: list[tuple | None] = [None] * (cols * rows)
    for b in found:
        speck = b["area"] < biggest * 0.01
        watermark = b["cx"] > w * 0.9 and b["cy"] > h * 0.86 and b["area"] < biggest * 0.15
        if speck or watermark:
            continue
        i = min(int(b["cy"] * rows / h), rows - 1) * cols + min(int(b["cx"] * cols / w), cols - 1)
        x0, y0, x1, y1 = b["box"]
        if boxes[i]:
            x0, y0 = min(x0, boxes[i][0]), min(y0, boxes[i][1])
            x1, y1 = max(x1, boxes[i][2]), max(y1, boxes[i][3])
        boxes[i] = (x0, y0, x1, y1)
    out = []
    for box in boxes:
        if box is None:
            out.append(None)
            continue
        part = im.crop(box)
        out.append(part.crop(part.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()))
    return out


def shrink(part: Image.Image, scale: float) -> Image.Image:
    size = (max(1, round(part.width * scale)), max(1, round(part.height * scale)))
    small = part.resize(size, Image.NEAREST)
    # hard alpha: pixel art has no soft edges
    small.putalpha(small.getchannel("A").point(lambda v: 255 if v > 127 else 0))
    return small


def centre_on_mass(sprite: Image.Image) -> Image.Image:
    """Pads so the visual centre of mass is the image centre. Characters are
    rotated around their centre in game, so a long weapon must not shift it."""
    alpha = sprite.getchannel("A").load()
    total = sum_x = sum_y = 0
    for y in range(sprite.height):
        for x in range(sprite.width):
            if alpha[x, y]:
                total += 1
                sum_x += x
                sum_y += y
    cx, cy = sum_x / total + 0.5, sum_y / total + 0.5
    half_w = int(max(cx, sprite.width - cx) + 0.999)
    half_h = int(max(cy, sprite.height - cy) + 0.999)
    out = Image.new("RGBA", (half_w * 2, half_h * 2), (0, 0, 0, 0))
    out.paste(sprite, (round(half_w - cx), round(half_h - cy)))
    return out


def slice_objects(sheet: str, names: list[str], cols: int, rows: int, folder: str, longest: int, centre: bool) -> int:
    path = RAW / sheet
    if not path.exists():
        print(f"  {sheet}: not found, skipped (game uses procedural fallback)")
        return 0
    parts = cells(key_green(Image.open(path)), cols, rows)
    scale = longest / max(max(p.size) for p in parts if p)
    (OUT / folder).mkdir(parents=True, exist_ok=True)
    done = 0
    for name, part in zip(names, parts):
        if part is None:
            print(f"  {sheet}: cell for {name} is empty, skipped")
            continue
        sprite = shrink(part, scale)
        if centre:
            sprite = centre_on_mass(sprite)
        sprite.save(OUT / folder / f"{name}.png")
        print(f"  {folder}/{name}.png  {sprite.width}x{sprite.height}")
        done += 1
    return done


def slice_floors(sheet: str, names: list[str], cols: int, rows: int) -> int:
    path = RAW / sheet
    if not path.exists():
        print(f"  {sheet}: not found, skipped (game uses procedural fallback)")
        return 0
    parts = cells(key_green(Image.open(path)), cols, rows)
    (OUT / "floors").mkdir(parents=True, exist_ok=True)
    done = 0
    for i, (name, part) in enumerate(zip(names, parts)):
        if part is None:
            print(f"  {sheet}: cell for {name} is empty, skipped")
            continue
        # Cut the dark frame drawn around each swatch so the tile can repeat.
        inset = round(min(part.size) * 0.035)
        part = part.crop((inset, inset, part.width - inset, part.height - inset)).convert("RGB")
        if i == len(names) - 1:
            # The generator's watermark sits on the last swatch's bottom-right
            # corner: replace that quarter with a mirror of the bottom-left.
            w, h = part.size
            patch = part.crop((0, h // 2, w - w // 2, h)).transpose(Image.FLIP_LEFT_RIGHT)
            part.paste(patch, (w // 2, h // 2))
        part.resize((FLOOR_SIZE, FLOOR_SIZE), Image.NEAREST).save(OUT / "floors" / f"{name}.png")
        print(f"  floors/{name}.png  {FLOOR_SIZE}x{FLOOR_SIZE}")
        done += 1
    return done


def main() -> int:
    print("slice_sheets: assets/raw -> assets/sprites")
    total = slice_objects("characters.png", CHARS, 4, 2, "chars", CHAR_MAX, True)
    total += slice_objects("props.png", PROPS, 4, 4, "props", PROP_MAX, False)
    total += slice_floors("floors.png", FLOORS, 4, 2)
    print(f"slice_sheets: wrote {total} sprites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
