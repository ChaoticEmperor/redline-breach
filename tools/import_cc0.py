#!/usr/bin/env python3
"""Fetch Kenney's CC0 "Topdown Shooter" pack and map it into game sprites.

    python3 tools/import_cc0.py

Downloads and extracts the pack into assets/cc0/kenney_topdown_shooter/ (only
if it is not already there), then writes the mapped sprites to
assets/sprites/cc0/. Deterministic and safe to re-run. Needs Pillow.

The game looks a sprite up as assets/sprites/<name>.png first (AI sheets, see
slice_sheets.py), then assets/sprites/cc0/<name>.png, then draws it
procedurally - so these fill in for any character the AI sheets do not cover.
Offline, or if the download fails, nothing is written and the exit code is 0.
"""
from __future__ import annotations

import io
import sys
import urllib.request
import zipfile
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    from _deps import skip
    sys.exit(skip("import_cc0: Pillow is not installed (pip install Pillow); nothing imported."))

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "assets" / "cc0" / "kenney_topdown_shooter"
OUT = ROOT / "assets" / "sprites" / "cc0"
# kenney.nl changes its download hash over time; OpenGameArt mirrors the pack.
URLS = [
    "https://kenney.nl/media/pages/assets/top-down-shooter/2380501d5e-1677586675/kenney_top-down-shooter.zip",
    "https://opengameart.org/sites/default/files/topdown-shooter.zip",
]
PX_PER_UNIT = 4  # sprite pixels per world pixel (the game draws sprites at 1/4 scale)

# game sprite -> (file in the pack, shoulder width in world pixels, RGB tint)
# The pack has one zombie and no pipe/shotgun poses, so the nearest pose is used.
CHARS = {
    "chars/player_pipe": ("PNG/Survivor 1/survivor1_hold.png", 17, None),
    "chars/player_pistol": ("PNG/Survivor 1/survivor1_gun.png", 17, None),
    "chars/player_shotgun": ("PNG/Survivor 1/survivor1_machine.png", 17, None),
    "chars/zombie_shambler": ("PNG/Zombie 1/zoimbie1_hold.png", 17, None),
    "chars/zombie_runner": ("PNG/Zombie 1/zoimbie1_hold.png", 15, (1.0, 0.55, 0.55)),
    "chars/zombie_bloater": ("PNG/Zombie 1/zoimbie1_stand.png", 30, (1.0, 1.0, 0.45)),
}


def fetch() -> bool:
    if (PACK / "PNG").is_dir():
        return True
    for url in URLS:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            data = urllib.request.urlopen(req, timeout=60).read()
            archive = zipfile.ZipFile(io.BytesIO(data))
        except Exception as err:  # offline, 403, not a zip...
            print(f"  {url}: {err}")
            continue
        PACK.mkdir(parents=True, exist_ok=True)
        for info in archive.infolist():
            name = info.filename
            if info.is_dir() or name.endswith("Thumbs.db") or name.startswith("Vector/"):
                continue
            target = (PACK / name).resolve()
            if not str(target).startswith(str(PACK.resolve())):
                continue  # never write outside the pack folder
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(info))
        # keep Godot from importing the whole pack
        (ROOT / "assets" / "cc0" / ".gdignore").touch()
        print(f"  downloaded {url}")
        return True
    return False


def centre_on_mass(sprite: Image.Image) -> Image.Image:
    alpha = sprite.getchannel("A").load()
    total = sum_x = sum_y = 0
    for y in range(sprite.height):
        for x in range(sprite.width):
            if alpha[x, y] > 127:
                total += 1
                sum_x += x
                sum_y += y
    cx, cy = sum_x / total + 0.5, sum_y / total + 0.5
    half_w = int(max(cx, sprite.width - cx) + 0.999)
    half_h = int(max(cy, sprite.height - cy) + 0.999)
    out = Image.new("RGBA", (half_w * 2, half_h * 2), (0, 0, 0, 0))
    out.paste(sprite, (round(half_w - cx), round(half_h - cy)))
    return out


def apply() -> int:
    done = 0
    for name, (source, width, tint) in CHARS.items():
        path = PACK / source
        if not path.exists():
            print(f"  {source}: missing from the pack, skipped")
            continue
        im = Image.open(path).convert("RGBA")
        im = im.crop(im.getchannel("A").getbbox())
        scale = width * PX_PER_UNIT / im.height  # characters face right: height = shoulders
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        if tint:
            r, g, b, a = im.split()
            im = Image.merge("RGBA", (r.point(lambda v: int(v * tint[0])), g.point(lambda v: int(v * tint[1])),
                                      b.point(lambda v: int(v * tint[2])), a))
        im = centre_on_mass(im)
        target = OUT / f"{name}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        im.save(target)
        print(f"  cc0/{name}.png  {im.width}x{im.height}")
        done += 1
    return done


def main() -> int:
    print("import_cc0: Kenney Topdown Shooter (CC0) -> assets/sprites/cc0")
    if not fetch():
        print("import_cc0: pack unavailable (offline?); nothing imported, game falls back")
        return 0
    print(f"import_cc0: wrote {apply()} sprites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
