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
  assets/sprites/weapons/held_<name>.png  the weapon in the player's fist, at
                                          the player sheet's pixel size and in its
                                          colours: 16 cells of 64x64, one per aim
                                          direction (cell i points i x 22.5 degrees
                                          clockwise from right), the grip pixel at
                                          (32, 32) of every cell. The game shows the
                                          cell nearest the aim instead of rotating a
                                          sprite, so the weapon stays on the body's
                                          pixel grid (pixel-art-engineer section 9).
                                          Keep in step with HELD_* in scripts/fx.gd.

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

HELD_GRIP = {"held_pipe": (4, 3), "held_pistol": (3, 6), "held_shotgun": (10, 6)}  # pixel held in the fist
HELD_DIRS = 16
HELD_CELL = 64


def turned(rows: list[str], grip: tuple[int, int], step: int) -> list[str]:
    """The weapon grid turned to direction `step`, as HELD_CELL rows with the grip at the centre.
    Turned at 8x size and voted back down per pixel, so colours stay on the palette and edges
    stay whole; aims to the left use the mirrored drawing so the lit side stays on top."""
    import numpy as np
    angle = step * 2 * np.pi / HELD_DIRS
    h, w = len(rows), len(rows[0])
    gx, gy = grip
    if np.cos(angle) < -1e-6:
        rows, gy = rows[::-1], h - 1 - gy
    chars = sorted(set("".join(rows)))
    src = np.array([[chars.index(c) for c in r] for r in rows])
    k, c = 8, HELD_CELL
    half = c // 2
    ys, xs = np.mgrid[0:c * k, 0:c * k]
    dx, dy = (xs + 0.5) / k - (half + 0.5), (ys + 0.5) / k - (half + 0.5)
    sx = np.floor(dx * np.cos(angle) + dy * np.sin(angle) + gx + 0.5).astype(int)
    sy = np.floor(-dx * np.sin(angle) + dy * np.cos(angle) + gy + 0.5).astype(int)
    inside = (sx >= 0) & (sx < w) & (sy >= 0) & (sy < h)
    big = np.where(inside, src[np.clip(sy, 0, h - 1), np.clip(sx, 0, w - 1)], chars.index("."))
    blocks = big.reshape(c, k, c, k).transpose(0, 2, 1, 3).reshape(c, c, k * k)
    empty, ink = chars.index("."), chars.index("k")
    out = np.full((c, c), empty)
    for y in range(c):
        for x in range(c):
            b = blocks[y, x]
            solid = b[b != empty]
            if len(solid) * 2 < len(b):
                continue
            counts = np.bincount(solid, minlength=len(chars))
            # the outline is one pixel wide, so it wins a cell it shares rather than breaking up
            out[y, x] = ink if counts[ink] >= 0.4 * len(solid) else int(np.argmax(counts))
    for y in range(c):                               # no lone pixels
        for x in range(c):
            if out[y, x] != empty and all(out[yy, xx] == empty for yy, xx in
                                         ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)) if 0 <= yy < c and 0 <= xx < c):
                out[y, x] = empty
    return ["".join(chars[v] for v in row) for row in out]


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
            target = OUT / f"{name}.png"
            if name in HELD:
                # one frame per aim direction, on a locked palette, checked for stray pixels
                doc = call(binary, env, "doc_new", {"name": name, "width": HELD_CELL, "height": HELD_CELL})
                call(binary, env, "doc_palette", {"op": "set", "doc_id": doc["doc_id"], "colors": list(legend.values())})
                stray = 0
                for step in range(HELD_DIRS):
                    if step:
                        call(binary, env, "doc_frame", {"op": "add", "doc_id": doc["doc_id"]})
                    frame = turned(rows, HELD_GRIP[name], step)
                    if frame[HELD_CELL // 2][HELD_CELL // 2] == ".":
                        raise SystemExit(f"{name}: direction {step} has no pixel at the grip")
                    call(binary, env, "doc_paint_grid", {"doc_id": doc["doc_id"], "layer": 0, "frame": step,
                                                         "legend": legend, "rows": frame})
                    checks = call(binary, env, "doc_critique", {"doc_id": doc["doc_id"], "frame": step})["checks"]
                    stray += checks["orphans"]["count"] + (checks["palette_adherence"]["verdict"] != "ok")
                call(binary, env, "doc_export", {"doc_id": doc["doc_id"], "op": "sheet", "scale": 1,
                                                 "out_path": str(target)})
                target.with_suffix(".json").unlink(missing_ok=True)
                print(f"  weapons/{name}.png  {HELD_DIRS} directions of {HELD_CELL}x{HELD_CELL}"
                      + (f"  <- {stray} stray-pixel or palette findings" if stray else "  (no stray pixels, on palette)"))
                continue
            doc = call(binary, env, "doc_new", {"name": name, "width": width, "height": len(rows)})
            call(binary, env, "doc_paint_grid", {"doc_id": doc["doc_id"], "layer": 0, "frame": 0,
                                                 "legend": legend, "rows": rows})
            call(binary, env, "doc_export", {"doc_id": doc["doc_id"], "op": "sheet", "scale": 1,
                                             "out_path": str(target)})
            target.with_suffix(".json").unlink(missing_ok=True)  # sheet metadata is not needed
            print(f"  weapons/{name}.png  {width}x{len(rows)}")
    print(f"draw_weapons: wrote {len(SPRITES) + len(HELD)} sprites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
