"""Draws REDLINE's prototype top-down character sheets: one character, several skins
(colourways), every animation the game plays. Placeholder art drawn in code to the tandem
skill's references/topdown rules, until the Tandem-drawn sheets replace it (same layout).

    python3 tools/draw_topdown_chars.py            # writes assets/sprites/chars/<skin>.png + .json

The JSON is the contract with the game (scripts/art/char_art.gd): per animation its row,
frame count, cell size, fps and loop. Swap the art by writing a new sheet with the same JSON
shape; nothing in the game changes.

Construction (facing +x, head centre at ANCHOR): a big central head with the shoulders as a
crescent round it, arms along the top and bottom edges ending in hands, black outline and
inner contours, 2-3 tone ramps, vintage 1980s palette. Legs are their own 8-frame strip
(frame 0 hidden) under the torso; the torso has a set per weapon.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/sprites/chars"
CELL = 48          # torso and legs cells
DEAD = 64          # corpse cells: bodies lie wider than they stand
ANCHOR = (22, 24)  # the head centre in a CELL; the actor's origin
K = (0, 0, 0, 255)

SKINS = {
    # the player: the only warm jacket on the floor
    "player": {"jacket": "#d9a52b", "jacket_shade": "#9c7214", "hair": "#8a6a44", "hair_light": "#c9a46e",
               "skin": "#e8b48a", "trousers": "#3c4a5a", "shoes": "#1a1a1a", "shirt": "#d9a52b"},
    # the same character as an enemy, for testing: a cream suit
    "guard": {"jacket": "#d8cfb8", "jacket_shade": "#9a9078", "hair": "#2a1a12", "hair_light": "#4a3424",
              "skin": "#e0a882", "trousers": "#d8cfb8", "shoes": "#2a1a12", "shirt": "#d8cfb8"},
    # infected: olive-grey skin, faded clothes
    "infected": {"jacket": "#5e7a78", "jacket_shade": "#3c5050", "hair": "#5a6448", "hair_light": "#8a9a6a",
                 "skin": "#8a9a6a", "trousers": "#4a3a2a", "shoes": "#1a1a1a", "shirt": "#5e7a78"},
}
WEAPONS = ["unarmed", "pipe", "bat", "pistol", "shotgun"]
STEEL, STEEL_DARK, WOOD, WOOD_DARK, GUNMETAL = "#bfbfbf", "#808080", "#b07850", "#6b3e2a", "#404040"


def C(h: str) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def ell(d, cx, cy, rx, ry, fill, outline=True):
    if outline:
        d.ellipse((cx - rx - 1, cy - ry - 1, cx + rx + 1, cy + ry + 1), fill=K)
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=fill)


def seg(d, a, b, col, width):
    d.line((a[0], a[1], b[0], b[1]), fill=K, width=width + 2)
    d.line((a[0], a[1], b[0], b[1]), fill=col, width=width)


def polar(o, ang, r):
    return (o[0] + math.cos(math.radians(ang)) * r, o[1] + math.sin(math.radians(ang)) * r)


# ---------------------------------------------------------------- legs

def legs_frame(p: dict, f: int) -> Image.Image:
    im = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    if f == 0:
        return im  # standing: legs hidden under the body
    d = ImageDraw.Draw(im)
    cx, cy = ANCHOR
    stride = math.sin((f - 1) / 7 * math.tau) * 8
    for side, s in ((-1, stride), (1, -stride)):
        hip = (cx - 2, cy + side * 4)
        foot = (cx + s, cy + side * 5)
        seg(d, hip, foot, C(p["trousers"]), 4)
        ell(d, foot[0] + (1.5 if s > 0 else -0.5), foot[1], 2, 2, C(p["shoes"]))
    return im


# ---------------------------------------------------------------- torso

def weapon_line(d, grip, ang, kind):
    if kind == "pipe":
        seg(d, grip, polar(grip, ang, 18), C(STEEL), 2)
    elif kind == "bat":
        tip = polar(grip, ang, 19)
        seg(d, grip, polar(grip, ang, 8), C(WOOD_DARK), 2)
        seg(d, polar(grip, ang, 8), tip, C(WOOD), 3)
    elif kind == "pistol":
        seg(d, grip, polar(grip, ang, 8), C(GUNMETAL), 2)
    elif kind == "shotgun":
        seg(d, polar(grip, ang, -4), grip, C(WOOD), 3)
        seg(d, grip, polar(grip, ang, 15), C(GUNMETAL), 2)


def torso_frame(p: dict, weapon: str, sway: float = 0.0, arm_l: float = 0.0, arm_r: float = 0.0,
                swing: float | None = None, lunge: float = 0.0, recoil: float = 0.0, smear: list | None = None) -> Image.Image:
    """sway: shoulder lean in px (walk); arm_*: hand forward offset in px; swing: the melee weapon's
    angle off the aim (degrees), the leading hand follows it; lunge: the punching arm's reach in px;
    recoil: the body pushed back by a shot, px; smear: past weapon angles drawn as a white trail."""
    im = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = ANCHOR[0] - recoil, ANCHOR[1]
    jacket, shade, skin = C(p["jacket"]), C(p["jacket_shade"]), C(p["skin"])
    gun = weapon in ("pistol", "shotgun")
    melee = weapon in ("pipe", "bat")

    # the leading (right, +y) hand position
    if swing is not None:
        hand_r = polar((cx, cy + 4), swing, 11)
    elif gun:
        hand_r = (cx + 9, cy + 3)
    else:
        hand_r = (cx + 7 + arm_r + lunge, cy + 9)
    hand_l = (cx + 9, cy - 2) if weapon == "shotgun" else (cx + 7 + arm_l, cy - 9)

    if smear:
        for i, a in enumerate(smear):  # the arc the weapon just swept, as white dots
            r0 = polar((cx, cy + 4), a, 11)
            for k in range(4, 20, 3):
                x, y = polar(r0, a, k)
                if (i + k) % 2 == 0:
                    d.point((x, y), fill=(255, 255, 255, 255))
    # weapon under the hand
    if melee:
        ang = swing if swing is not None else 25
        weapon_line(d, hand_r, ang, weapon)
    elif gun:
        weapon_line(d, (cx + 8, cy + 1), 0, weapon)

    # arms along the edges: shoulder to hand
    for side, hand in ((-1, hand_l), (1, hand_r)):
        sh = (cx - 1, cy + side * (9 + sway * side * 0.5))
        seg(d, sh, hand, shade, 3)
        ell(d, hand[0], hand[1], 1.5, 1.5, skin)
    # shoulders: a crescent round the head, light on top, swaying
    oy = sway
    ell(d, cx - 1, cy + oy * 0.5, 6, 11, shade)
    d.ellipse((cx - 5, cy - 9 + oy * 0.5, cx + 2, cy + 9 + oy * 0.5), fill=jacket)
    # the head: big and central, hair round the back, a face edge toward the aim
    ell(d, cx + 1, cy, 4.5, 4.5, C(p["hair"]))
    d.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=C(p["hair_light"]))
    d.rectangle((cx + 4, cy - 2, cx + 5, cy + 2), fill=skin)
    return im


def walk_frames(p, weapon):
    out = []
    for f in range(8):
        ph = f / 8 * math.tau
        out.append(torso_frame(p, weapon, sway=math.sin(ph) * 1.0,
                               arm_l=math.sin(ph) * 2.0, arm_r=-math.sin(ph) * 2.0))
    return out


def attack_frames(p, weapon):
    if weapon in ("pipe", "bat"):
        # ready, wind-up (2), strike with a smear (2), follow-through, recover: the hit holds on frame 3
        angs = [-40, -95, -110, 35, 75, 55, -10]
        out = []
        for i, a in enumerate(angs):
            smear = list(range(-110, a, 22)) if i in (3, 4) else None
            out.append(torso_frame(p, weapon, swing=a, smear=smear))
        return out
    if weapon == "unarmed":
        return [torso_frame(p, weapon, lunge=v) for v in (0, 4, 9, 9, 5, 1)]
    return [torso_frame(p, weapon, recoil=v) for v in (0, 2, 1)]


# ---------------------------------------------------------------- corpses

def corpse(p: dict, seed: int, cause: str) -> Image.Image:
    """A body on its back, head toward +x: legs, torso, arms flung out, face up, eyes shut."""
    rng = random.Random(seed)
    im = Image.new("RGBA", (DEAD, DEAD), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    hx, hy = 24, 32
    for side in (-1, 1):
        a = 180 + side * rng.randint(14, 30)
        knee = polar((hx, hy + side * 4), a, 10)
        foot = polar(knee, a + side * rng.randint(-8, 12), 9)
        seg(d, (hx, hy + side * 4), knee, C(p["trousers"]), 4)
        seg(d, knee, foot, C(p["trousers"]), 4)
        ell(d, foot[0], foot[1], 2, 2, C(p["shoes"]))
    sx = 38
    spread = (60, 130) if cause != "shot" else (30, 80)
    for side in (-1, 1):
        a = side * rng.randint(*spread)
        elbow = polar((sx, hy + side * 6), a, 7)
        hand = polar(elbow, a + side * rng.randint(-50, 40), 7)
        seg(d, (sx, hy + side * 6), elbow, C(p["jacket"]), 3)
        seg(d, elbow, hand, C(p["jacket"]), 3)
        ell(d, hand[0], hand[1], 1.5, 1.5, C(p["skin"]))
    d.rounded_rectangle((hx - 2, hy - 8, sx + 2, hy + 8), 4, fill=K)
    d.rounded_rectangle((hx - 1, hy - 7, sx + 1, hy + 7), 3, fill=C(p["jacket_shade"]))
    d.rounded_rectangle((hx + 1, hy - 5, sx - 1, hy + 5), 3, fill=C(p["jacket"]))
    d.line((hx + 2, hy, sx - 2, hy), fill=C(p["jacket_shade"]), width=1)
    if cause == "shot":  # wounds on the chest
        for _ in range(3):
            x, y = rng.randint(hx + 3, sx - 3), rng.randint(hy - 4, hy + 4)
            d.rectangle((x, y, x + 1, y + 1), fill=C("#8a1018"))
    if cause == "cut":
        d.line((hx + 4, hy - 5, sx - 3, hy + 5), fill=C("#b8141e"), width=2)
    ell(d, sx + 6, hy, 5, 5, C(p["hair"]))
    d.ellipse((sx + 3, hy - 3, sx + 9, hy + 3), fill=C(p["skin"]))
    d.point([(sx + 7, hy - 1), (sx + 7, hy + 1)], fill=K)
    return im


# ---------------------------------------------------------------- sheet

def build(skin: str) -> None:
    p = SKINS[skin]
    rows: list[tuple[str, list[Image.Image], int, int, bool]] = []  # name, frames, cell, fps, loop
    rows.append(("legs_walk", [legs_frame(p, f) for f in range(8)], CELL, 12, True))
    for w in WEAPONS:
        rows.append((f"{w}_walk", walk_frames(p, w), CELL, 10, True))
        rows.append((f"{w}_attack", attack_frames(p, w), CELL, 24 if w in ("pipe", "bat", "unarmed") else 30, False))
    for cause in ("blunt", "shot", "cut"):
        rows.append((f"dead_{cause}", [corpse(p, 11 * i + len(cause), cause) for i in range(3)], DEAD, 1, False))
    width = max(len(fr) * cell for _, fr, cell, _, _ in rows)
    height = sum(cell for _, _, cell, _, _ in rows)
    sheet = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    meta = {"anchor": list(ANCHOR), "dead_anchor": [32, 32], "anims": {}}
    y = 0
    for name, frames, cell, fps, loop in rows:
        for i, fr in enumerate(frames):
            sheet.alpha_composite(fr, (i * cell, y))
        meta["anims"][name] = {"y": y, "cell": cell, "frames": len(frames), "fps": fps, "loop": loop}
        y += cell
    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / f"{skin}.png")
    (OUT / f"{skin}.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"{skin}: {sheet.size[0]}x{sheet.size[1]}, {len(rows)} animations")


if __name__ == "__main__":
    for s in SKINS:
        build(s)
