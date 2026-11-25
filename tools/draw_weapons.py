#!/usr/bin/env python3
"""Draw the weapon pixel art with Atelier and export it into assets/sprites.

    python3 tools/draw_weapons.py

Each weapon is a character grid below (one character = one pixel, see
LEGEND). The script paints them through the `atelier` CLI
(https://github.com/marmikshah/atelier) and exports:

  assets/sprites/weapons/hud_<name>.png   side view, for the HUD weapon box
  assets/sprites/weapons/top_<name>.png   top-down, facing right: floor
                                          pickups, and the held weapon when the
                                          body sprite has no weapon of its own
  assets/sprites/weapons/held_<name>.png  side view at the player sheet's pixel
                                          size, in the player's own colours; held
                                          in the fist (grip pixels: HELD_GRIP in
                                          scripts/fx.gd), see pixel-art-engineer
                                          section 9

Deterministic and safe to re-run. If `atelier` is not installed nothing is
written and the exit code is 0 (the game falls back to procedural weapons).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "weapons"

LEGEND = {
    "k": "#120a1a",  # outline
    "d": "#3a3f55",  # steel, shadow
    "m": "#6b7390",  # steel
    "l": "#aab4d0",  # steel, light
    "w": "#e8f0ff",  # highlight
    "b": "#5a2e1a",  # wood, shadow
    "o": "#9a5a2c",  # wood
    "y": "#c88a4a",  # wood, light
    "c": "#05d9e8",  # neon sight
    "p": "#ff2a6d",  # neon accent
}

# Held weapons share the player sheet's palette (tools/convert_reference.py): its ink, steel
# on its jeans blues plus two lights, wood on its hair browns. Lit from the upper left.
HELD_LEGEND = {
    "k": "#030102",  # ink
    "d": "#293042",  # steel, shadow
    "m": "#465165",  # steel
    "l": "#7c879c",  # steel, light
    "h": "#b9c2d0",  # steel, highlight
    "v": "#452014",  # wood, shadow
    "w": "#6c3a1c",  # wood
    "y": "#865512",  # wood, light
    "t": "#413b3f",  # grip tape
    "u": "#2c202e",  # grip tape, shadow
}

HELD = {
    "held_pipe": [
        ".........................kkkkkk",
        ".kkkkkkkkkkkkkkkkkkkkkkkkkhlllk",
        "kttuttuthllllllllllllllllkllllk",
        "ktuttuttmmmmmmmmmmmmmmmmmkmmmmk",
        "kuuuuuuuddddddddddddddddkkmmmdk",
        ".kkkkkkkkkkkkkkkkkkkkkkkkkddddk",
        ".........................kkkkkk",
    ],
    "held_pistol": [
        ".kkkkkkkkkkkkk.",
        "khlllllllllllmk",
        "kmmmmmmmkkmmmdk",
        "kdddddddddddkk.",
        ".kwwwkkkkkkk...",
        ".kywwk.k.......",
        ".kwwvkkk.......",
        "kywwvk.........",
        "kwvvvk.........",
        "kkkkkk.........",
    ],
    "held_shotgun": [
        "..........kkkkkkkkkkkkkkkkkkkkkkkk",
        "..kkkkkkkkkhlllllllllllllllllllllk",
        ".kyyyyyyykkmmmmmmmmmmmmmmmmmmmmmdk",
        "kywwwwwwwkmmmkkkkkkkkkkkkkkkkkkkk.",
        "kwwwwwwvvkdddkyyyyyyyykdddk.......",
        "kvwwwvvkkkkkkkwwwwwwwwkkkkk.......",
        ".kvvvkk.kywk.kvvvvvvvvk...........",
        "..kkk...kwvk..kkkkkkkk............",
        "........kkkk......................",
    ],
}

SPRITES = {
    # ---------------------------------------------------------------- HUD
    "hud_pistol": [
        "...kkkkkkkkkkkkkkkkkkkkkkkk...",
        "..kwwwwwwwwwwwwwwwwwwwwwwwck..",
        "..kllllllllllllllllllllllllkk.",
        "..kmdmdmdmmmmmmmmkkkkkmmmmmdk.",
        "..kmdmdmdmmmmmmmmkddkkmmmmmdk.",
        "..kddddddddddddddddddddddddkk.",
        "..kkmmmmmmmmmmmmmmmmmmkkkkk...",
        "...kmmmmmmmkkkkkkkkkmmk.......",
        "...kboooobk.k......kkk........",
        "...kbooyobk.kk....kk..........",
        "..kboooyobk..kkkkkk...........",
        "..kbooyobk....................",
        "..kboooobk....................",
        ".kboooyobk....................",
        ".kbooooobk....................",
        ".kbbbbbbbk....................",
        ".kkkkkkkkk....................",
    ],
    "hud_shotgun": [
        "...........kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
        "..kkkkkkkkklllllllllwwwwwwwwwwwwwwwwwwwwwwwwck",
        ".kyyyyyyyykmmmmmmmmkmmmmmmmmmmmmmmmmmmmmmmmmmk",
        "kyooooooookmmmpmmmmkkkkkkkkkkkkkkkkkkkkkkkkkk.",
        "koooooooookmmmmmmmmklllllkyyyyyyyyyklllllk....",
        "kooooooobbkddddddddkmmmmmkoooooooookmmmmmk....",
        "kboooobbkkkkmk.k...kkkkkkkbbbbbbbbbkkkkkkk....",
        ".kbbbbkk..kook.kk.kk",
        "..kkkk....kook..kkk",
        "..........kbbk",
        "..........kkkk",
    ],
    "hud_pipe": [
        ".kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk.kkkkkkk.",
        "kwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwkwwwwwwwk",
        "kllllllllllllllllllllllllllllllllkklllllllk",
        "kmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmkkmmmmmmmk",
        "kdddddddddddddddddddddddddddddddddkmmmkkkkk",
        ".kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkmmmk....",
        "..................................kdddk....",
        "..................................kkkkk....",
    ],
    # ----------------------------------------------------------- top-down
    "top_pistol": [
        "..kkkkkkkkkkkkkkkkkkkkkkk.",
        ".kookmmllllllllllllllllmk.",
        "kooookmdwwwwwwwwwwwwwkkmck",
        "kooookmdllllllllllllldkmck",
        ".kookmmmmmmmmmmmmmmmmmmmk.",
        "..kkkkkkkkkkkkkkkkkkkkkkk.",
    ],
    "top_shotgun": [
        ".kkkkkkkkkkkkk.......................................",
        "kyyyyyyyyyyyyykkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk.",
        "kooooooooooooookmmmmmmmkyyyyyyyyyyklllllllllllllllllk",
        "kooooooooooooookmlpllmmkooooooooookwwwwwwwwwwwwwwwwck",
        "kooooooooooooookmmmmmmmkooooooooookmmmmmmmmmmmmmmmmmk",
        "kbbbbbbbbbbbbbkkdddddddkbbbbbbbbbbkdddddddddddddddddk",
        ".kkkkkkkkkkkkk.kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk.",
    ],
    "top_pipe": [
        ".kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk.kkkkkkk.",
        "kwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwkwwwwwwwk",
        "kllllllllllllllllllllllllllllllllkklllllllk",
        "kmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmkkmmmmmmmk",
        "kdddddddddddddddddddddddddddddddddkdddddddk",
        ".kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk.kkkkkkk.",
    ],
}


def call(binary: str, env: dict, tool: str, args: dict) -> dict:
    done = subprocess.run([binary, "call", tool, json.dumps(args)], env=env, capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"atelier {tool} failed:\n{done.stdout}\n{done.stderr}")
    # stdout carries one JSON object; log lines go before it
    return json.loads(done.stdout[done.stdout.index("{"):])


def main() -> int:
    binary = shutil.which("atelier") or str(Path.home() / ".local" / "bin" / "atelier")
    if not Path(binary).exists():
        print("draw_weapons: atelier is not installed; nothing drawn, game falls back")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, ATELIER_HOME=home)  # keep the user's own library untouched
        for name, rows in {**SPRITES, **HELD}.items():
            legend = HELD_LEGEND if name in HELD else LEGEND
            width = max(len(r) for r in rows)
            rows = [r.ljust(width, ".") for r in rows]
            unknown = set("".join(rows)) - set(legend) - {"."}
            if unknown:
                raise SystemExit(f"{name}: characters not in LEGEND: {sorted(unknown)}")
            doc = call(binary, env, "doc_new", {"name": name, "width": width, "height": len(rows)})
            call(binary, env, "doc_paint_grid", {"doc_id": doc["doc_id"], "layer": 0, "frame": 0,
                                                 "legend": legend, "rows": rows})
            target = OUT / f"{name}.png"
            call(binary, env, "doc_export", {"doc_id": doc["doc_id"], "op": "sheet", "scale": 1,
                                             "out_path": str(target)})
            target.with_suffix(".json").unlink(missing_ok=True)  # sheet metadata is not needed
            print(f"  weapons/{name}.png  {width}x{len(rows)}")
    print(f"draw_weapons: wrote {len(SPRITES) + len(HELD)} sprites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
