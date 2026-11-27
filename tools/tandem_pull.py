"""Brings art and levels edited in Tandem (http://localhost:7480) back into the game, in the
layouts the game reads, so hand-painted frames replace the code-drawn ones with no code change.

    python3 tools/tandem_pull.py            # every skin with Tandem sprites, the club tiles, the club map
    python3 tools/tandem_pull.py --skin player --no-map

Sprites are named redline-<skin>-<anim> (anim with dashes, e.g. redline-player-pipe-attack): each
one's frames replace that row of assets/sprites/chars/<skin>.png. Rows with no Tandem sprite keep
their code-drawn frames (tools/draw_topdown_chars.py). The tileset sprite redline-club-tiles gives
assets/sprites/world/tiles.png (one tile per frame, in tiles.json order); the map club-floor-1 is
exported to levels/club.txt.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
URL = os.environ.get("TANDEM_URL", "http://localhost:7480")
# Where the head centre is in a hand-moved animation's cells (the swing was shifted in Tandem to keep
# 1 px clear of the cell border), for every skin that has that animation in Tandem.
ANCHORS = {"pipe_attack": [28, 29]}


def get(path: str) -> bytes:
    with urllib.request.urlopen(URL + path, timeout=30) as r:
        return r.read()


def docs() -> set[str]:
    return {d["id"] for d in json.loads(get("/api/docs"))}


def frames_of(doc: str, cell: int) -> list[Image.Image]:
    """Every frame of a sprite, read through its sheet's JSON rects (whatever the sheet's layout)."""
    return frames_and_ticks(doc)[0]


def frames_and_ticks(doc: str) -> tuple[list[Image.Image], list]:
    """The frames and each one's duration in 60 Hz ticks (None when not a whole tick)."""
    sheet = Image.open(io.BytesIO(get(f"/api/d/{doc}/sheet.png"))).convert("RGBA")
    data = json.loads(get(f"/api/d/{doc}/sheet.json"))["frames"]
    frames = [sheet.crop((f["frame"]["x"], f["frame"]["y"], f["frame"]["x"] + f["frame"]["w"], f["frame"]["y"] + f["frame"]["h"])) for f in data]
    return frames, [f.get("ticks") for f in data]


def pull_skin(skin: str, have: set[str]) -> int:
    png = ROOT / f"assets/sprites/chars/{skin}.png"
    meta = json.loads((ROOT / f"assets/sprites/chars/{skin}.json").read_text())
    sheet = Image.open(png).convert("RGBA")
    pulled = 0
    for name, a in meta["anims"].items():
        doc = f"redline-{skin}-{name.replace('_', '-')}"
        if doc not in have:
            continue
        fr, ticks = frames_and_ticks(doc)
        if len(fr) != a["frames"]:
            print(f"  {doc}: {len(fr)} frames in Tandem, the layout has {a['frames']}: skipped")
            continue
        sheet.paste(Image.new("RGBA", (a["cell"] * a["frames"], a["cell"])), (0, a["y"]))
        for i, f in enumerate(fr):
            sheet.alpha_composite(f, (i * a["cell"], a["y"]))
        if name in ANCHORS:
            a["anchor"] = ANCHORS[name]
        if all(t for t in ticks):
            a["ticks"] = ticks  # per-frame timing, so a held pose plays as drawn
        pulled += 1
    sheet.save(png)
    (ROOT / f"assets/sprites/chars/{skin}.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"{skin}: {pulled} animations from Tandem")
    return pulled


def pull_tiles(have: set[str]) -> None:
    if "redline-club-tiles" not in have:
        return
    meta = json.loads((ROOT / "assets/sprites/world/tiles.json").read_text())
    fr = frames_of("redline-club-tiles", meta["tile"])
    out = Image.new("RGBA", (meta["tile"] * len(meta["tiles"]), meta["tile"]))
    for t in meta["tiles"]:
        if t["x"] < len(fr):
            out.alpha_composite(fr[t["x"]], (t["x"] * meta["tile"], 0))
    out.save(ROOT / "assets/sprites/world/tiles.png")
    print(f"tiles: {len(fr)} from Tandem")


def pull_props(have: set[str]) -> None:
    """Each prop or floor weapon is a Tandem sprite redline-prop-<name>; frame 0 replaces its rect."""
    meta = json.loads((ROOT / "assets/sprites/world/props.json").read_text())
    png = ROOT / "assets/sprites/world/props.png"
    sheet = Image.open(png).convert("RGBA")
    pulled = 0
    for name, (x, y, w, h) in meta.items():
        doc = f"redline-prop-{name.replace('_', '-')}"
        if doc not in have:
            continue
        fr = frames_of(doc, 0)[0]
        if fr.size != (w, h):
            print(f"  {doc}: {fr.size} in Tandem, the layout has {(w, h)}: skipped")
            continue
        sheet.paste(Image.new("RGBA", (w, h)), (x, y))
        sheet.alpha_composite(fr, (x, y))
        pulled += 1
    sheet.save(png)
    print(f"props: {pulled} from Tandem")


def pull_map(map_id: str, out: Path) -> None:
    text = get(f"/api/m/{map_id}/redline.txt").decode()
    out.write_text(text if text.endswith("\n") else text + "\n")
    print(f"map {map_id} -> {out.relative_to(ROOT)}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skin", action="append")
    ap.add_argument("--no-map", action="store_true")
    a = ap.parse_args()
    have = docs()
    for skin in a.skin or ["player", "guard", "infected", "runner", "bloater", "riot"]:
        pull_skin(skin, have)
    pull_tiles(have)
    pull_props(have)
    if not a.no_map:
        pull_map("club-floor-1", ROOT / "levels/club.txt")


if __name__ == "__main__":
    main()
