#!/usr/bin/env python3
"""Draw the 3/4-view character sheet with Atelier.

    python3 tools/draw_characters.py

Figures are posed skeletons (hips, jointed legs and arms, torso, head)
rendered as lit, outlined forms and then given per-character detail: jacket
seams, torn cloth, wounds, armour plates. An animation is a list of poses.

Output: assets/sprites/chars/sheet_characters_v2.png, 64x64 cells. Figures
face right with their feet on row 60, centred on column 32; the game flips
them for left and draws them at Fx.ART_SCALE.

  row 0  player    idle 0-3, run 4-9, kick 10-11, death 12-14
  row 1  shambler  walk 0-3, lunge 4, corpse 5     (motel zombie)
  row 2  horde     same                            (club zombie, shirt + jeans)
  row 3  runner    same
  row 4  bloater   same (5 = acid pool and gibs)
  row 5  riot      same                            (armoured guard)

The player has no front arm: the game draws the weapon arm on top. Keep the
layout in step with ANIMS in scripts/fx.gd. Exits 0 if Atelier is missing.
"""
from __future__ import annotations

import math
import sys

from _atelier import K, ROOT, Canvas, atelier_binary, paint, ramp, rng_for

CELL = 64
FEET = 60
OUT = ROOT / "assets" / "sprites" / "chars" / "sheet_characters_v2.png"
BLOOD = ramp("#b3122a", 4, 0.4, 1.1)
WHITE = "#fff4e0"

LOOKS = {
    "player": dict(skin=ramp("#e6b088"), hair=ramp("#5a3418", 4), top=ramp("#f0b820"),
                   pants=ramp("#3f62ad"), shoe=ramp("#6a4226", 3)),
    "shambler": dict(skin=ramp("#93a472"), hair=ramp("#3c3a30", 4), top=ramp("#8a4a44"),
                     pants=ramp("#4c4640"), shoe=ramp("#2c2420", 3)),
    "horde": dict(skin=ramp("#a8b49a"), hair=ramp("#2e2a36", 4), top=ramp("#c9cfd6"),
                  pants=ramp("#3f5a8c"), shoe=ramp("#33291f", 3)),
    "runner": dict(skin=ramp("#d8685c"), hair=ramp("#5c1c22", 4), top=ramp("#7a2a36"),
                   pants=ramp("#3a3044"), shoe=ramp("#2a1c20", 3)),
    "riot": dict(skin=ramp("#8c9a6c"), hair=ramp("#3a4234", 4), top=ramp("#586044"),
                 pants=ramp("#4a503a"), shoe=ramp("#22241c", 3)),
}


def polar(x, y, angle, length):
    """Point `length` away from (x, y); angle in degrees from straight down, positive = forward."""
    a = math.radians(angle)
    return x + math.sin(a) * length, y + math.cos(a) * length


def figure(cv, ox, look, bob=0.0, lean=0.0, hip=0.0, legs=((0, 0), (0, 0)), arms=((8, 10), None),
           head=(0, 0), bulk=0.0, head_r=8.0, hair=True):
    """Draws one figure and returns its joints. legs/arms are (upper angle,
    bend) for the back then the front limb; None skips that arm."""
    hx, hy = ox + 32 + hip, FEET - 16 + bob
    chest = (hx + lean, hy - 11)
    j = {"hip": (hx, hy), "chest": chest, "feet": []}
    sx = 7 + bulk * 0.5
    shoulders = ((chest[0] - sx + 2, chest[1] - 5), (chest[0] + sx - 1, chest[1] - 5))

    def leg(i):
        up, bend = legs[i]
        x0 = hx - 3.5 + i * 6
        kx, ky = polar(x0, hy, up, 8)
        fx, fy = polar(kx, ky, up - bend, 8)
        shade = look["pants"][:-1] if i == 0 else look["pants"]
        cv.limb(x0, hy, kx, ky, 3.6 + bulk * 0.3, shade)
        cv.limb(kx, ky, fx, fy, 3.2 + bulk * 0.3, shade, r1=2.6 + bulk * 0.2)
        cv.ball(fx + 1.8, fy + 0.6, 4.4, 2.6, look["shoe"])
        j["feet"].append((fx, fy))

    def arm(i):
        if arms[i] is None:
            return
        up, bend = arms[i]
        x0, y0 = shoulders[i]
        ex, ey = polar(x0, y0, up, 7)
        wx, wy = polar(ex, ey, up + bend, 7)
        shade = look["top"][:-1] if i == 0 else look["top"]
        cv.limb(x0, y0, ex, ey, 3.3 + bulk * 0.3, shade)
        cv.limb(ex, ey, wx, wy, 2.9 + bulk * 0.3, shade, r1=2.5)
        cv.ball(wx, wy, 2.7, 2.7, look["skin"][:-1] if i == 0 else look["skin"])
        j["hand%d" % i] = (wx, wy)

    arm(0)
    leg(0)
    leg(1)
    cv.ball(chest[0], chest[1] + 1.5, 9.2 + bulk, 11.5, look["top"])
    j["torso"] = (chest[0], chest[1] + 1.5, 9.2 + bulk, 11.5)
    hcx, hcy = chest[0] + lean * 0.4 + head[0], chest[1] - 16 + head[1]
    j["head"] = (hcx, hcy)
    cv.limb(chest[0] + 1, chest[1] - 9, hcx, hcy + 5, 3.0, look["skin"][:-1])  # neck
    cv.ball(hcx, hcy, head_r, head_r, look["skin"])
    if hair:
        cv.ball(hcx - 1.2, hcy - 4.8, head_r + 0.4, head_r - 3.9, look["hair"])
        cv.limb(hcx - head_r + 1, hcy - 2, hcx - head_r + 1.5, hcy + 4, 2.2, look["hair"])
    arm(1)
    return j


def face(cv, j, eye=K, glint=None, mouth=None, brow=True):
    x, y = j["head"]
    skin = None
    for dx in (1.5, 5.5):
        cv.rect(x + dx, y + 1.5, 1, 2, eye)
        if glint:
            cv.set(x + dx, y + 1.5, glint)
    if brow:
        cv.rect(x + 1, y, 2, 1, K)
        cv.rect(x + 5, y, 2, 1, K)
    if mouth:
        cv.rect(x + 3, y + 5.5, 3, 1, mouth)


def on_torso(j, u, v):
    """Point on the torso: u, v in -1..1 across its width and height."""
    cx, cy, rx, ry = j["torso"]
    return cx + u * rx, cy + v * ry


# ------------------------------------------------------------------ player

def jacket(cv, j, sway=0.0):
    top = LOOKS["player"]["top"]
    cx, cy, rx, ry = j["torso"]
    cv.limb(cx - 5 + sway, cy + ry - 2, cx + 6 + sway, cy + ry - 2, 2.2, top[:3])       # ribbed hem
    for x in range(int(cx - 6 + sway), int(cx + 7 + sway), 2):
        cv.set(x, cy + ry - 2, top[0])
    cv.line(cx + 3, cy - ry + 3, cx + 3 + sway * 0.5, cy + ry - 4, top[0])              # zip
    cv.line(cx + 4, cy - ry + 3, cx + 4 + sway * 0.5, cy + ry - 4, top[4])
    cv.limb(cx - 2, cy - ry + 2, cx + 6, cy - ry + 2, 1.8, ramp("#f4ead2", 3))          # collar
    cv.line(cx - 5, cy + 2, cx - 1, cy + 3, top[1])                                     # pocket
    cv.rect(cx - 7, cy - 4, 2, 1, top[4])                                               # shoulder shine
    cv.rect(cx - 6, cy - 5, 3, 1, WHITE)
    cv.line(cx - 8, cy - 1, cx - 8, cy + 5, top[0])                                     # sleeve seam


def player(cv, ox, **pose):
    sway = pose.pop("sway", 0.0)
    j = figure(cv, ox, LOOKS["player"], **pose)
    jacket(cv, j, sway)
    face(cv, j, mouth=LOOKS["player"]["skin"][0])
    x, y = j["head"]
    cv.set(x + 7.5, y + 3.5, LOOKS["player"]["skin"][1])     # nose shadow
    cv.rect(x - 5, y - 7, 5, 1, LOOKS["player"]["hair"][3])  # hair shine
    return j


RUN = ((38, 6), (18, 26), (-4, 14), (-30, 34), (-12, 78), (24, 66))


def player_row(cv):
    for i, bob in enumerate((0, 0.4, 1, 0.4)):                                   # idle 0-3
        player(cv, i * CELL, bob=bob, arms=((6 + i % 2 * 2, 12), None))
    for i in range(6):                                                           # run 4-9
        front, back = RUN[i], RUN[(i + 3) % 6]
        player(cv, (4 + i) * CELL, bob=(1, 0, -1, 1, 0, -1)[i], lean=3, legs=(back, front),
               arms=((-front[0] * 0.9, 35), None), sway=(-1.5, -0.5, 1, 1.5, 0.5, -1)[i], head=(1, 0))
    player(cv, 10 * CELL, lean=-2, hip=-2, legs=((-8, 10), (70, 95)), arms=((-25, 30), None))   # kick wind-up
    ox = 11 * CELL                                                               # kick: full extension
    j = player(cv, ox, lean=-6, hip=-4, bob=1, legs=((-14, 6), (88, 2)), arms=((-55, 20), None), head=(-1, 1))
    fx, fy = j["feet"][1]
    for k in range(7):                                                           # impact streaks
        a = -0.9 + k * 0.3
        cv.line(fx + 6 + math.cos(a) * 3, fy + math.sin(a) * 9, fx + 9 + math.cos(a) * 5, fy + math.sin(a) * 12,
                WHITE if k % 2 else "#7fe8f0")
    ox = 12 * CELL                                                               # death: hit
    j = player(cv, ox, lean=-5, hip=-1, bob=1, legs=((-18, 12), (16, 20)), arms=((-70, -30), None), head=(-2, -1))
    rng = rng_for("hit")
    tx, ty = on_torso(j, 0.2, -0.2)
    cv.ball(tx, ty, 3.2, 2.6, BLOOD, outline=None)
    for _ in range(14):
        a, d = rng.uniform(-1.2, 0.9), rng.uniform(5, 15)
        cv.rect(tx + math.cos(a) * d, ty + math.sin(a) * d, rng.choice((1, 2)), 1, rng.choice(BLOOD[1:]))
    ox = 13 * CELL                                                               # death: knees give way
    cv.ball(ox + 31, FEET - 1, 15, 3.5, BLOOD[:2], outline=None)
    j = player(cv, ox, lean=-8, hip=1, bob=9, legs=((62, 118), (80, 140)), arms=((-95, -20), None), head=(-4, 3))
    tx, ty = on_torso(j, 0.1, 0.0)
    cv.ball(tx, ty, 3.6, 3, BLOOD, outline=None)
    corpse(cv, 14 * CELL, LOOKS["player"], "player")


def corpse(cv, ox, look, name, helmet=False):
    """Sprawled on its back, head to the left, in a spreading pool."""
    rng = rng_for("corpse" + name)
    cx, cy = ox + 32, FEET - 9
    cv.ball(cx, cy + 1, 27, 9.5, BLOOD[:1], outline=None)
    cv.ball(cx - 2, cy + 1, 22, 7, BLOOD[:2], outline=None)
    cv.ball(cx - 5, cy, 12, 3.5, BLOOD[1:3], outline=None)
    for _ in range(16):
        a, d = rng.uniform(0, 6.28), rng.uniform(0.85, 1.25)
        cv.rect(cx + math.cos(a) * 27 * d, cy + 1 + math.sin(a) * 9.5 * d, rng.choice((1, 2, 3)), rng.choice((1, 2)),
                rng.choice(BLOOD[:2]))
    hip = (cx + 9, cy - 1)
    for knee, foot, shade in (((cx + 17, cy - 8), (cx + 24, cy - 5), look["pants"][:-1]),
                              ((cx + 18, cy + 4), (cx + 26, cy + 6), look["pants"])):
        cv.limb(*hip, *knee, 3.5, shade)
        cv.limb(*knee, *foot, 3.1, shade, r1=2.6)
        cv.ball(foot[0] + 1.5, foot[1] - 1.5, 2.8, 4.0, look["shoe"])
    cv.limb(cx - 6, cy - 5, cx - 13, cy - 13, 3.0, look["top"][:-1])                      # arm thrown up
    cv.ball(cx - 14.5, cy - 14.5, 2.7, 2.7, look["skin"][:-1])
    cv.ball(cx, cy - 1, 11.5, 7.8, look["top"])
    cv.limb(cx - 2, cy + 5, cx - 8, cy + 10, 3.0, look["top"])                            # arm out
    cv.ball(cx - 9.5, cy + 11, 2.7, 2.7, look["skin"])
    cv.ball(cx - 17, cy - 2, 7.6, 7.6, look["skin"])
    if helmet:
        cv.ball(cx - 18.5, cy - 2.5, 8.6, 8.4, look["hair"])
        cv.slab(cx - 15, cy - 5, 4, 7, ramp("#3c6c7c", 4), bevel=1)
    else:
        cv.ball(cx - 20.5, cy - 3, 5.2, 7.4, look["hair"])
        cv.rect(cx - 14, cy - 4, 2, 1, K)
        cv.rect(cx - 14, cy, 2, 1, K)
    cv.ball(cx + 1, cy - 2, 4.5, 3.4, BLOOD, outline=None)                                # wound
    cv.rect(cx, cy - 3, 3, 2, BLOOD[0])
    for _ in range(9):
        cv.rect(cx + rng.randint(-9, 10), cy + rng.randint(-7, 5), rng.choice((1, 2)), 1, rng.choice(BLOOD[1:]))


# ------------------------------------------------------------------ infected

def rot(cv, j, look, name, holes=4, stains=10, hem=True):
    """Decay pass: torn cloth showing skin, wounds, stains, a ragged hem."""
    rng = rng_for(name)
    for _ in range(holes):
        x, y = on_torso(j, rng.uniform(-0.6, 0.6), rng.uniform(-0.5, 0.6))
        cv.ball(x, y, rng.uniform(1.6, 2.8), rng.uniform(1.4, 2.4), look["skin"][:4], outline=look["top"][0])
    x, y = on_torso(j, 0.25, -0.1)
    cv.ball(x, y, 3.0, 2.4, BLOOD, outline=look["top"][0])                                # open wound
    cv.rect(x - 1, y - 1, 2, 2, BLOOD[0])
    cv.rect(x - 1, y + 2, 1, 4, BLOOD[1])                                                 # drip
    cx, cy, rx, ry = j["torso"]
    cv.speckle(cx - rx, cy - ry, rx * 2, ry * 2, [BLOOD[0], BLOOD[1], look["top"][0]], 0.012 * stains, rng,
               only=set(look["top"]))
    if hem:
        for x in range(int(cx - rx + 2), int(cx + rx - 1)):                               # ragged hem
            if rng.random() < 0.5:
                for d in range(rng.randint(1, 3)):
                    y = int(cy + ry) - d
                    if cv.get(x, y) in look["top"]:
                        cv.set(x, y, look["pants"][2])
    hx, hy = j["head"]
    cv.rect(hx + 1, hy + 0.5, 3, 3, K)                                                    # sunken sockets
    cv.rect(hx + 5, hy + 0.5, 3, 3, K)
    cv.set(hx + 2, hy + 1.5, "#f2ff7a")
    cv.set(hx + 6, hy + 1.5, "#f2ff7a")
    cv.rect(hx + 2, hy + 4, 5, 3, "#3a1018")                                              # slack jaw
    cv.rect(hx + 3, hy + 4, 1, 1, WHITE)
    cv.rect(hx + 5, hy + 4, 1, 1, WHITE)
    cv.rect(hx - 2, hy + 3, 2, 2, BLOOD[1])
    cv.speckle(hx - 8, hy - 8, 16, 16, [look["skin"][0], look["skin"][1]], 0.07, rng, only=set(look["skin"]))


SHUFFLE = (((-14, 8), (14, 6)), ((-4, 14), (4, 22)), ((14, 6), (-14, 8)), ((4, 22), (-4, 14)))
SPRINT = (((-34, 40), (40, 8)), ((-8, 70), (12, 30)), ((40, 8), (-34, 40)), ((12, 30), (-8, 70)))


def zombie_row(cv, name, legs_cycle, lean, reach, head, arm_sag, bulk=0.0):
    look = LOOKS[name]
    for i in range(5):
        lunge = i == 4
        legs = ((-26, 10), (22, 14)) if lunge else legs_cycle[i]
        up = 78 + (10 if lunge else (i % 2) * 5)
        j = figure(cv, i * CELL, look, bob=0 if lunge else i % 2, lean=lean + (4 if lunge else 0), legs=legs,
                   arms=((up - 14, -arm_sag), (up, -arm_sag + 4)), head=(head[0] + (2 if lunge else 0), head[1]),
                   bulk=bulk)
        rot(cv, j, look, name + str(i % 2))
        for hand in ("hand0", "hand1"):                                                   # clawed fingers
            x, y = j[hand]
            cv.rect(x + 2, y - 1, 2, 1, look["skin"][3])
            cv.rect(x + 2, y + 1, 2, 1, look["skin"][1])
    corpse(cv, 5 * CELL, look, name)


def bloater_row(cv):
    flesh, bile, shirt = ramp("#c98a78"), ramp("#a8b83a"), ramp("#44608c", 4)
    for i in range(5):
        swell = (0, 1, 2, 1, 3.5)[i]
        ox = i * CELL
        rng = rng_for("bloat")
        cx, fy = ox + 31, FEET
        for dx, ang in ((-9, -8), (7, 10)):                                               # stubby legs
            kx, ky = polar(cx + dx, fy - 12, ang + (i % 2) * 6 * (1 if dx > 0 else -1), 9)
            cv.limb(cx + dx, fy - 13, kx, ky, 5.0, ramp("#5a5a44", 4))
            cv.ball(kx + 1.5, fy - 1.5, 5.2, 2.6, ramp("#2c2420", 3))
        cv.limb(cx - 13, fy - 34, cx - 21 - swell, fy - 24, 4.6, flesh[:-1])              # back arm
        cv.ball(cx - 1, fy - 24, 20 + swell, 17 + swell, bile)                            # belly
        cv.ball(cx, fy - 37, 15 + swell * 0.6, 11.5, flesh)                               # chest
        for k, (ry_, yy) in enumerate(((5.0, fy - 28), (5.5, fy - 19), (4.5, fy - 11))):  # rolls of fat
            w = 17 + swell - k * 2
            for x in range(int(cx - 1 - w), int(cx - 1 + w)):
                t = (x - (cx - 1)) / w
                y = yy + (1 - t * t) * ry_ * 0.7
                cv.set(x, y, bile[0])
                cv.set(x, y - 1, bile[4] if t < 0.2 else bile[3])
        for _ in range(13):                                                               # pustules
            a, d = rng.uniform(0, 6.28), rng.uniform(0.15, 0.85)
            x, y = cx - 1 + math.cos(a) * (19 + swell) * d, fy - 23 + math.sin(a) * (15 + swell) * d
            cv.ball(x, y, rng.uniform(1.5, 2.6), rng.uniform(1.4, 2.2), ramp("#e6f24a", 3), outline=bile[0],
                    spec=WHITE)
        cv.limb(cx - 12, fy - 45, cx + 12, fy - 36, 2.4, shirt)                           # shreds of shirt
        cv.limb(cx + 10, fy - 44, cx + 15, fy - 31, 2.2, shirt[:-1])
        for x in range(int(cx - 12), int(cx + 13), 3):
            cv.rect(x, fy - 38 + rng.randint(-1, 2), 1, rng.randint(2, 4), shirt[1])
        cv.limb(cx + 13, fy - 36, cx + 22 + swell, fy - 29, 4.6, flesh)                   # front arm
        cv.ball(cx + 24 + swell, fy - 27, 3.4, 3.2, flesh)
        cv.ball(cx + 4, fy - 49, 7, 6.2, flesh)                                           # head, sunk in
        cv.ball(cx + 3, fy - 52.5, 6.4, 3.0, ramp("#4a3a30", 3))
        cv.rect(cx + 5, fy - 50, 2, 2, K)
        cv.rect(cx + 9, fy - 50, 2, 2, K)
        cv.set(cx + 5, fy - 50, "#f2ff7a")
        cv.set(cx + 9, fy - 50, "#f2ff7a")
        cv.rect(cx + 5, fy - 46, 5, 2, "#3a1018")
        cv.rect(cx + 7, fy - 44, 1, 4 + i % 2, "#b8ff40")                                 # bile drool
        cv.speckle(ox, 0, CELL, CELL, [bile[0], "#7a8a22"], 0.035, rng, only=set(bile[1:]))
        cv.speckle(ox, 0, CELL, CELL, [flesh[0], BLOOD[1]], 0.03, rng, only=set(flesh[1:]))
    ox = 5 * CELL                                                                         # burst: acid and gibs
    rng = rng_for("burst")
    acid = ramp("#8ad022", 5)
    cx, cy = ox + 32, FEET - 9
    cv.ball(cx, cy, 28, 10, acid[:2], outline=None)
    cv.ball(cx - 2, cy, 23, 7.5, acid[1:4], outline=None)
    cv.ball(cx - 7, cy - 1, 11, 3.2, acid[3:], outline=None)
    for _ in range(18):
        a, d = rng.uniform(0, 6.28), rng.uniform(0.8, 1.3)
        cv.rect(cx + math.cos(a) * 28 * d, cy + math.sin(a) * 10 * d, rng.choice((1, 2, 3)), rng.choice((1, 2)), acid[1])
    for _ in range(7):
        x, y = cx + rng.randint(-20, 18), cy + rng.randint(-7, 5)
        cv.ball(x, y, rng.uniform(2, 4), rng.uniform(1.6, 3), rng.choice((flesh, BLOOD, bile)))
    for _ in range(5):
        x, y = cx + rng.randint(-18, 16), cy + rng.randint(-5, 4)
        cv.ball(x, y, 1.6, 1.6, ramp("#e6f24a", 3), outline=None, spec=WHITE)


def riot_row(cv):
    look = LOOKS["riot"]
    plate, visor = ramp("#3c4434"), ramp("#2a4c5a", 4)
    for i in range(5):
        lunge = i == 4
        legs = ((-24, 10), (20, 12)) if lunge else SHUFFLE[i]
        ox = i * CELL
        rng = rng_for("riot")
        j = figure(cv, ox, look, bob=0 if lunge else i % 2, lean=3 if lunge else 0.5, legs=legs,
                   arms=((60 if lunge else 14, 20), (84 if lunge else 38, 30 if not lunge else 6)), bulk=3,
                   head_r=7.5, hair=False)
        cv.speckle(ox, 0, CELL, CELL, [look["pants"][0], "#6c7450", "#3a4030"], 0.16, rng, only=set(look["pants"][1:]))
        cx, cy, rx, ry = j["torso"]
        cv.slab(cx - 7, cy - 8, 15, 12, plate, bevel=1)                                   # chest plate
        cv.line(cx - 6, cy - 2, cx + 7, cy - 2, plate[0])
        cv.slab(cx - 6, cy + 5, 6, 5, plate[:-1], bevel=1)                                # pouches
        cv.slab(cx + 1, cy + 5, 6, 5, plate[:-1], bevel=1)
        cv.rect(cx + 2, cy - 6, 4, 2, "#f9f002")                                          # badge
        cv.ball(cx - 9, cy - 8, 4.6, 3.8, plate)                                          # shoulder pads
        cv.ball(cx + 9, cy - 8, 4.6, 3.8, plate, spec="#9aa890")
        for fx, fy in j["feet"]:                                                          # knee pads, boots
            cv.ball(fx - 1, fy - 8, 3.2, 2.6, plate[:-1])
        hx, hy = j["head"]
        cv.ball(hx - 0.5, hy - 1.5, 9.4, 9.0, plate, spec="#b8c4a8")                      # helmet
        cv.slab(hx - 1, hy - 3, 10, 7, visor, bevel=1)                                    # visor
        cv.line(hx + 1, hy + 2, hx + 5, hy - 2, "#bff4ff")
        cv.line(hx + 4, hy + 2, hx + 7, hy - 1, "#7fe8f0")
        cv.rect(hx - 8, hy + 5, 15, 3, plate[1])                                          # neck guard
        cv.rect(hx - 8, hy + 5, 15, 1, plate[3])
        cv.rect(hx + 2, hy + 4, 3, 2, BLOOD[1])                                           # blood under the visor
        cv.rect(hx + 3, hy + 6, 1, 3, BLOOD[1])
        x, y = j["hand1"]                                                                 # baton
        bx, by = polar(x, y, 150 if not lunge else 70, 13)
        cv.limb(x, y, bx, by, 1.5, ramp("#2a2a34", 3))
        tx, ty = on_torso(j, -0.3, 0.2)
        cv.ball(tx, ty, 2.4, 2.0, BLOOD, outline=None)
    corpse(cv, 5 * CELL, look, "riot", helmet=True)


def main() -> int:
    binary = atelier_binary()
    if binary is None:
        print("draw_characters: atelier is not installed; nothing drawn, game falls back")
        return 0
    sheet = Canvas(CELL * 15, CELL * 6)
    rows = [player_row,
            lambda cv: zombie_row(cv, "shambler", SHUFFLE, 2, 8, (2, 2), 14),
            lambda cv: zombie_row(cv, "horde", SHUFFLE, 1, 8, (1, 1), 6),
            lambda cv: zombie_row(cv, "runner", SPRINT, 7, 6, (4, 4), 22, bulk=-1.5),
            bloater_row, riot_row]
    for r, draw in enumerate(rows):
        strip = Canvas(CELL * 15, CELL)
        draw(strip)
        sheet.blit(strip, 0, r * CELL)
    paint(binary, sheet, OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
