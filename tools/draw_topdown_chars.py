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
import numpy as np

from pixelkit import Canvas, hexc

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/sprites/chars"
CELL = 48          # torso and legs cells
DEAD = 64          # corpse cells: bodies lie wider than they stand
ANCHOR = (22, 24)  # the head centre in a CELL; the actor's origin
K = (0, 0, 0, 255)

SKINS = {
    # the player: the only warm jacket on the floor
    "player": {"jacket": "#d9a52b", "jacket_shade": "#9c7214", "jacket_light": "#f2c85a", "hair": "#8a6a44",
               "hair_light": "#c9a46e", "hair_dark": "#5e4630", "skin": "#e8b48a", "skin_shade": "#b8805a",
               "trousers": "#3c4a5a", "trousers_light": "#56667a", "shoes": "#241c1c", "shirt": "#d9a52b"},
    # the same character as an enemy, for testing: a cream suit
    "guard": {"jacket": "#d8cfb8", "jacket_shade": "#9a9078", "jacket_light": "#f0ead8", "hair": "#3a2418",
              "hair_light": "#5a3c28", "hair_dark": "#24160e", "skin": "#e0a882", "skin_shade": "#b07856",
              "trousers": "#b8ae96", "trousers_light": "#d8cfb8", "shoes": "#2a1a12", "shirt": "#d8cfb8"},
    # infected: olive-grey skin, faded clothes
    "infected": {"jacket": "#5e7a78", "jacket_shade": "#3c5050", "jacket_light": "#7e9a96", "hair": "#5a6448",
                 "hair_light": "#8a9a6a", "hair_dark": "#3e4632", "skin": "#8a9a6a", "skin_shade": "#66764e",
                 "trousers": "#4a3a2a", "trousers_light": "#62503a", "shoes": "#1a1414", "shirt": "#5e7a78"},
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
    cv = Canvas(CELL, CELL)
    if f == 0:
        return cv.finish()  # standing: legs hidden under the body
    cx, cy = ANCHOR
    stride = math.sin((f - 1) / 7 * math.tau) * 8
    for side, st in ((-1, stride), (1, -stride)):
        hip = (cx - 1, cy + side * 4.5)
        foot = (cx + st, cy + side * 5)
        cv.add(cv.seg(hip, foot, 2.2), hexc(p["trousers"]))
        cv.add(cv.ellipse(foot[0] + (1.2 if st > 0 else -0.6), foot[1], 2.4, 2.0), hexc(p["shoes"]))
    return cv.finish()


# ---------------------------------------------------------------- torso

def weapon_part(cv, grip, ang, kind):
    if kind == "pipe":
        cv.add(cv.seg(grip, polar(grip, ang, 18), 1.1), hexc(STEEL))
    elif kind == "bat":
        cv.add(cv.seg(grip, polar(grip, ang, 8), 1.0), hexc(WOOD_DARK))
        cv.add(cv.seg(polar(grip, ang, 7), polar(grip, ang, 19), 1.6), hexc(WOOD))
    elif kind == "pistol":
        cv.add(cv.seg(grip, polar(grip, ang, 8), 1.2), hexc(GUNMETAL))
    elif kind == "shotgun":
        cv.add(cv.seg(polar(grip, ang, -4), grip, 1.6), hexc(WOOD))
        cv.add(cv.seg(grip, polar(grip, ang, 15), 1.1), hexc(GUNMETAL))


SWING_CELL = 64  # a swing reaches past the walk cell: its own bigger cell, the head on the same pixel offset
PIVOT_DY = 5     # the swing turns about the leading shoulder, this far toward +y from the head
SWING_R = 12     # the leading hand's distance from that pivot


def torso_frame(p: dict, weapon: str, sway: float = 0.0, arm_l: float = 0.0, arm_r: float = 0.0,
                swing: float | None = None, lunge: float = 0.0, recoil: float = 0.0, smear: list | None = None,
                turn: float = 0.0, cell: int = CELL) -> Image.Image:
    """sway: shoulder lean in px (walk); arm_*: hand forward offset in px; swing: the melee weapon's
    angle off the aim (degrees), the leading hand follows it; lunge: the punching arm's reach in px;
    recoil: the body pushed back by a shot, px; smear: past weapon angles drawn as a white trail;
    turn: the torso turning a little with the stride (px the shoulders shift); cell: the frame size."""
    cv = Canvas(cell, cell)
    off = (cell - CELL) // 2
    cx, cy = ANCHOR[0] + off - recoil, ANCHOR[1] + off
    pivot = (cx, cy + PIVOT_DY)
    gun = weapon in ("pistol", "shotgun")
    melee = weapon in ("pipe", "bat")
    if swing is not None:
        hand_r = polar(pivot, swing, SWING_R)
    elif gun:
        hand_r = (cx + 9, cy + 3)
    else:
        hand_r = (cx + 7 + arm_r + lunge, cy + 9)
    hand_l = (cx + 9, cy - 2) if weapon == "shotgun" else (cx + 7 + arm_l, cy - 9)
    # back to front: weapon, arms, shoulders, head, hands (a hand grips over the weapon)
    if melee:
        weapon_part(cv, hand_r, swing if swing is not None else 35, weapon)
    elif gun:
        weapon_part(cv, (cx + 8, cy + 1), 0, weapon)
    for side, hand in ((-1, hand_l), (1, hand_r)):
        sh = (cx - 1, cy + side * (8.5 + sway * side * 0.5))
        cv.add(cv.seg(sh, hand, 1.6), hexc(p["jacket_shade"]))
    oy = sway * 0.5
    sx = cx - 1 + turn
    crest = lambda c, r2: (r2 > 0.30) & (r2 < 0.62) & (c.xx + 0.5 < sx + 2)
    cv.add(cv.ellipse(sx, cy + oy, 6.5, 11.5),
           cv.shade(p["jacket"], p["jacket_shade"], p["jacket_light"], sx, cy + oy, 6.5, 11.5, 0.72, crest),
           heavy=(cv.xx + 0.5 < cx - 3) & (np.abs(cv.yy + 0.5 - cy - oy) < 8.5))  # 2 px outline on the back, not round the tips
    hair = cv.shade(p["hair"], p["hair_dark"], p["hair_light"], cx + 0.5, cy, 4.8, 4.8, 0.62,
                    lambda c, r2: ((c.xx + 0.5 - (cx - 0.5)) ** 2 + (c.yy + 0.5 - cy) ** 2) < 2.6)
    def head_col(c, mask):
        out = hair(c, mask)
        face = (c.xx + 0.5 > cx + 3.2) & (np.abs(c.yy + 0.5 - cy) < 2.6)
        out[face & mask] = hexc(p["skin"])
        return out
    cv.add(cv.ellipse(cx + 0.5, cy, 4.8, 4.8), head_col)
    for hand in (hand_l, hand_r):
        cv.add(cv.ellipse(hand[0], hand[1], 1.8, 1.8), hexc(p["skin"]))
    img = cv.finish()
    if smear:
        # the arc the weapon tip just swept, as a broken trail of white pixels (drawn after the line art,
        # only on empty pixels): dense near the tip, thinning toward the start of the swing
        d = ImageDraw.Draw(img)
        a0, a1 = smear
        n = max(2, int(abs(a1 - a0) / 5))
        for i in range(n):
            a = a0 + (a1 - a0) * i / (n - 1)
            for k, r in enumerate((SWING_R + 13, SWING_R + 17, SWING_R + 20)):
                if (i + k) % 2 or (i < n * 0.4 and k != 1):
                    continue
                x, y = (int(round(v)) for v in polar(pivot, a, r))
                if 0 <= x < cell and 0 <= y < cell and img.getpixel((x, y))[3] == 0:
                    d.point((x, y), fill=(255, 255, 255, 255))
    return img


def walk_frames(p, weapon):
    out = []
    for f in range(8):
        ph = f / 8 * math.tau
        out.append(torso_frame(p, weapon, sway=math.sin(ph) * 1.5, turn=round(math.sin(ph)),
                               arm_l=math.sin(ph) * 3.0, arm_r=-math.sin(ph) * 3.0))
    return out


def attack_frames(p, weapon):
    if weapon in ("pipe", "bat"):
        # ready, wind-up (2), strike with a smear (2), follow-through, recover: the hit holds on frame 3
        angs = [-20, -60, -80, 40, 68, 52, 10]
        out = []
        for i, a in enumerate(angs):
            smear = (-80, a - 12) if i in (3, 4) else None
            out.append(torso_frame(p, weapon, swing=a, smear=smear, cell=SWING_CELL))
        return out
    if weapon == "unarmed":
        return [torso_frame(p, weapon, lunge=v) for v in (0, 4, 9, 9, 5, 1)]
    return [torso_frame(p, weapon, recoil=v) for v in (0, 2, 1)]


# ---------------------------------------------------------------- corpses

def corpse(p: dict, seed: int, cause: str) -> Image.Image:
    """A body on its back, head toward +x: legs, torso, arms flung out, face up, eyes shut."""
    rng = random.Random(seed)
    cv = Canvas(DEAD, DEAD)
    hx, hy = 24, 32
    for side in (-1, 1):
        a = 180 + side * rng.randint(14, 30)
        knee = polar((hx, hy + side * 4), a, 10)
        foot = polar(knee, a + side * rng.randint(-8, 12), 9)
        cv.add(cv.seg((hx, hy + side * 4), knee, 2.2) | cv.seg(knee, foot, 2.2), hexc(p["trousers"]))
        cv.add(cv.ellipse(foot[0], foot[1], 2.2, 2.2), hexc(p["shoes"]))
    sx = 38
    spread = (60, 130) if cause != "shot" else (30, 80)
    hands = []
    for side in (-1, 1):
        a = side * rng.randint(*spread)
        elbow = polar((sx, hy + side * 6), a, 7)
        hand = polar(elbow, a + side * rng.randint(-50, 40), 7)
        cv.add(cv.seg((sx, hy + side * 6), elbow, 1.6) | cv.seg(elbow, hand, 1.6), hexc(p["jacket_shade"]))
        hands.append(hand)
    def torso_col(c, mask):
        out = np.zeros((c.h, c.w, 4), np.uint8)
        out[:] = hexc(p["jacket"])
        out[(np.abs(c.yy + 0.5 - hy) > 5.5)] = hexc(p["jacket_shade"])
        out[(np.abs(c.yy + 0.5 - hy) < 0.6) & (c.xx > hx + 1) & (c.xx < sx - 1)] = hexc(p["jacket_shade"])
        if cause == "shot":
            for _ in range(3):
                x, y = rng.randint(hx + 3, sx - 3), rng.randint(hy - 4, hy + 4)
                out[y:y + 2, x:x + 2] = hexc("#8a1018")
        if cause == "cut":
            cut = np.abs((c.yy - hy) - (c.xx - (hx + sx) / 2) * 0.8) < 0.8
            out[cut & (np.abs(c.yy - hy) < 5)] = hexc("#b8141e")
        return out
    cv.add(cv.ellipse((hx + sx) / 2, hy, (sx - hx) / 2 + 2, 7.5), torso_col)
    for hand in hands:
        cv.add(cv.ellipse(hand[0], hand[1], 1.8, 1.8), hexc(p["skin"]))
    def head_col(c, mask):
        out = np.zeros((c.h, c.w, 4), np.uint8)
        out[:] = hexc(p["hair"])
        face = ((c.xx + 0.5 - (sx + 6.5)) ** 2 + (c.yy + 0.5 - hy) ** 2) < 9.5
        out[face] = hexc(p["skin"])
        out[(c.xx.astype(int) == int(sx + 7)) & ((c.yy.astype(int) == hy - 2) | (c.yy.astype(int) == hy + 1))] = hexc(p["hair_dark"])
        return out
    cv.add(cv.ellipse(sx + 6, hy, 5, 5), head_col)
    return cv.finish()


# ---------------------------------------------------------------- sheet

def build(skin: str) -> None:
    p = SKINS[skin]
    rows: list[tuple[str, list[Image.Image], int, int, bool]] = []  # name, frames, cell, fps, loop
    rows.append(("legs_walk", [legs_frame(p, f) for f in range(8)], CELL, 12, True))
    for w in WEAPONS:
        rows.append((f"{w}_walk", walk_frames(p, w), CELL, 10, True))
        rows.append((f"{w}_attack", attack_frames(p, w), SWING_CELL if w in ("pipe", "bat") else CELL,
                     24 if w in ("pipe", "bat", "unarmed") else 30, False))
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
        off = (cell - CELL) // 2
        anchor = [32, 32] if name.startswith("dead_") else [ANCHOR[0] + off, ANCHOR[1] + off]
        meta["anims"][name] = {"y": y, "cell": cell, "frames": len(frames), "fps": fps, "loop": loop, "anchor": anchor}
        y += cell
    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / f"{skin}.png")
    (OUT / f"{skin}.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"{skin}: {sheet.size[0]}x{sheet.size[1]}, {len(rows)} animations")


if __name__ == "__main__":
    for s in SKINS:
        build(s)
