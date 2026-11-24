#!/usr/bin/env python3
"""Draw the 3/4-view character sheet with Atelier.

    python3 tools/draw_characters.py

Figures are posed skeletons (hips, jointed legs and arms, torso, head)
rendered as lit forms and then given deliberate, hand-placed detail. An
animation is a list of poses. Craft rules (see the pixel-art-engineer skill):

  - clean cel shading: 4-step hue-shifted ramps, no dithering, no noise
  - coloured outlines between parts, one dark contour around the silhouette
  - materials differ: cloth has seams and hems, skin is smooth, armour is
    plates with hard highlights
  - detail is anchored to joints, so nothing flickers between frames
  - one pixel size: the sheet is drawn at 2 pixels per world pixel, the same
    as the props, and shown at Fx.ART_SCALE = 0.5

Output: assets/sprites/chars/sheet_characters_v2.png, 64x64 cells. Figures
are about 42 pixels tall, face right with their feet on row 60, centred on
column 32; the game flips them for left.

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

from _atelier import K, ROOT, Canvas, atelier_binary, ink, paint, ramp

CELL = 64
FEET = 60
OUT = ROOT / "assets" / "sprites" / "chars" / "sheet_characters_v2.png"
WHITE = "#fff4e0"
BLOOD = ["#5c0a1c", "#8e0b1c", "#c4162e", "#f04a5a"]


def mat(base, lo=0.42, hi=1.12):
    return ramp(base, 4, lo, hi, warm=0.5)


LOOKS = {
    "player": dict(skin=mat("#e8ae84"), hair=mat("#6a3c1c"), top=mat("#f2bc1e"), pants=mat("#3f66b4"),
                   shoe=mat("#d8d2c4")),
    "shambler": dict(skin=mat("#8fa26e"), hair=mat("#3e3a34"), top=mat("#93504a"), pants=mat("#55504a"),
                     shoe=mat("#3a302a")),
    "horde": dict(skin=mat("#a2b094"), hair=mat("#2f2a3a"), top=mat("#c6ccd6"), pants=mat("#41609a"),
                  shoe=mat("#3c3028")),
    "runner": dict(skin=mat("#d4665a"), hair=mat("#5c1c22"), top=mat("#6e2634"), pants=mat("#40344e"),
                   shoe=mat("#2e2026")),
    "riot": dict(skin=mat("#8a986a"), hair=mat("#3a4234"), top=mat("#5c6648"), pants=mat("#4e563c"),
                 shoe=mat("#26281e")),
}


def polar(x, y, angle, length):
    """Point `length` away from (x, y); angle in degrees from straight down, positive = forward."""
    a = math.radians(angle)
    return x + math.sin(a) * length, y + math.cos(a) * length


def figure(cv, ox, look, bob=0.0, lean=0.0, hip=0.0, legs=((0, 0), (0, 0)), arms=((8, 10), None),
           head=(0, 0), bulk=0.0, head_r=6.5, bare=(False, False), stub=False):
    """Draws the body forms and returns the joints. legs/arms are (upper
    angle, bend) for the back then the front limb; None skips that arm.
    `bare` draws that arm in skin (a torn-off sleeve). `stub` draws only the
    near upper arm, for the player, whose weapon arm the game draws."""
    hx, hy = ox + 32 + hip, FEET - 14 + bob
    chest = (hx + lean, hy - 8)
    j = {"hip": (hx, hy), "chest": chest}
    shoulders = ((chest[0] - 4.5 - bulk * 0.4, chest[1] - 4), (chest[0] + 4.5 + bulk * 0.4, chest[1] - 4))

    def leg(i):
        up, bend = legs[i]
        x0 = hx - 2.5 + i * 5
        kx, ky = polar(x0, hy, up, 7)
        fx, fy = polar(kx, ky, up - bend, 7)
        shade = look["pants"][:3] if i == 0 else look["pants"]
        line = ink(look["pants"])
        cv.limb(x0, hy, kx, ky, 2.9 + bulk * 0.3, shade, outline=line)
        cv.limb(kx, ky, fx, fy, 2.6 + bulk * 0.3, shade, outline=line, r1=2.2 + bulk * 0.2)
        cv.ball(fx + 1.6, fy + 0.4, 3.7, 2.3, look["shoe"][:3] if i == 0 else look["shoe"], outline=ink(look["shoe"]))
        j["knee%d" % i], j["foot%d" % i] = (kx, ky), (fx, fy)

    def arm(i):
        if arms[i] is None:
            return
        up, bend = arms[i]
        x0, y0 = shoulders[i]
        ex, ey = polar(x0, y0, up, 6)
        wx, wy = polar(ex, ey, up + bend, 6)
        cloth = look["skin"] if bare[i] else look["top"]
        shade = cloth[:3] if i == 0 else cloth
        cv.limb(x0, y0, ex, ey, 2.6 + bulk * 0.3, shade, outline=ink(cloth))
        cv.limb(ex, ey, wx, wy, 2.3 + bulk * 0.3, shade, outline=ink(cloth), r1=2.0)
        cv.ball(wx, wy, 2.2, 2.2, look["skin"][:3] if i == 0 else look["skin"], outline=ink(look["skin"]))
        j["elbow%d" % i], j["hand%d" % i] = (ex, ey), (wx, wy)

    arm(0)
    leg(0)
    leg(1)
    j["torso"] = (chest[0], chest[1] + 1, 6.8 + bulk, 8.8)
    # a capsule, not an egg: straight sides read as a jacket or a shirt
    cv.limb(chest[0], chest[1] - 1.6, chest[0], chest[1] + 3.6, 6.6 + bulk, look["top"], outline=ink(look["top"]))
    hcx, hcy = chest[0] + lean * 0.3 + head[0] + 1, chest[1] - 13.5 + head[1]
    j["head"] = (hcx, hcy)
    j["head_r"] = head_r
    cv.limb(chest[0] + 0.5, chest[1] - 7, hcx - 0.5, hcy + 4, 2.2, look["skin"][:3], outline=ink(look["skin"]))
    cv.ball(hcx, hcy, head_r, head_r, look["skin"], outline=ink(look["skin"]))
    arm(1)
    if stub:
        x0, y0 = shoulders[1]
        ex, ey = polar(x0 - 0.5, y0 + 0.5, 28, 4.5)
        cv.limb(x0 - 0.5, y0 + 0.5, ex, ey, 2.7, look["top"], outline=ink(look["top"]))
        j["sleeve"] = (ex, ey)
    cv.despeckle(ox, 0, ox + CELL, CELL)
    return j


def at(j, u, v):
    """Point on the torso: u, v in -1..1 across its width and height."""
    cx, cy, rx, ry = j["torso"]
    return cx + u * rx, cy + v * ry


def finish(cv, ox, skip=()):
    cv.contour(K, ox, 0, ox + CELL, CELL, skip=skip)


# ------------------------------------------------------------------ player

def player(cv, ox, sway=0.0, **pose):
    look = LOOKS["player"]
    top, skin, hair = look["top"], look["skin"], look["hair"]
    j = figure(cv, ox, look, stub=True, **pose)
    cx, cy, rx, ry = j["torso"]
    hx, hy = j["head"]
    # hair: a cap that stops above the brow, a quiff, one highlight along its curve
    cv.ball(hx - 1.4, hy - 4.8, 6.8, 3.5, hair, outline=ink(hair))
    cv.ball(hx + 3.2, hy - 6.6, 2.9, 2.0, hair, outline=ink(hair))
    cv.rect(hx - 6.5, hy - 2.5, 2, 5, hair[1])                  # hair over the ear
    cv.line(hx - 4, hy - 7.5, hx + 1, hy - 8.5, hair[3])
    # face: eyes are the focal point, so they get the strongest contrast
    for dx in (1.5, 4.5):
        cv.rect(hx + dx, hy, 1, 3, K)
        cv.set(hx + dx - 1, hy, WHITE)
    cv.rect(hx + 1, hy - 1.5, 2, 1, hair[0])                    # brows
    cv.rect(hx + 4, hy - 1.5, 2, 1, hair[0])
    cv.set(hx + 6, hy + 2.5, skin[1])                           # nose
    cv.rect(hx + 3, hy + 4.5, 2, 1, skin[0])                    # mouth
    cv.set(hx - 3.5, hy + 1.5, skin[1])                         # ear
    # jacket: collar, zip, ribbed hem that lags behind the run, pocket, fold
    cv.limb(cx - 2.5, cy - ry + 1.5, cx + 4, cy - ry + 1.5, 1.4, mat("#f2e8d0"), outline=ink(top))
    cv.rect(cx + 2, cy - ry + 4, 1, ry * 2 - 7, top[0])         # zip: one unbroken line
    hem = int(cy + ry - 2)                                      # hem band: solid, shifts with the stride
    cv.rect(cx - 5 + sway, hem, 11, 2, top[0])
    cv.rect(cx - 5 + sway, hem, 5, 1, top[1])
    cv.rect(cx - 4, cy + 2, 4, 1, top[1])                       # pocket
    cv.rect(cx - 4, cy - 6, 3, 1, WHITE)                        # shoulder shine
    if "hand0" in j:
        ex, ey = j["elbow0"]
        wx, wy = j["hand0"]
        cv.set((ex + wx * 2) / 3, (ey + wy * 2) / 3, top[0])    # cuff
    # jeans seam and trainers
    kx, ky = j["knee1"]
    fx, fy = j["foot1"]
    cv.line(kx + 1, ky + 1, fx + 1, fy - 2, look["pants"][3])
    for i in (0, 1):
        sx, sy = j["foot%d" % i]
        cv.rect(sx - 1, sy + 2, 6, 1, "#f4eee0" if i else "#b8b0a0")   # sole
    return j


RUN = ((38, 6), (18, 26), (-4, 14), (-30, 34), (-12, 78), (24, 66))


def player_row(cv):
    for i, bob in enumerate((0, 0.5, 1, 0.5)):                                   # idle 0-3: breathing
        player(cv, i * CELL, bob=bob, arms=((6 + (i % 2) * 3, 12), None))
        finish(cv, i * CELL)
    for i in range(6):                                                           # run 4-9
        front, back = RUN[i], RUN[(i + 3) % 6]
        player(cv, (4 + i) * CELL, bob=(1, 0, -1, 1, 0, -1)[i], lean=2.5, legs=(back, front),
               arms=((-front[0] * 0.9, 35), None), sway=(-2, -1, 1, 2, 1, -1)[i], head=(0.5, 0))
        finish(cv, (4 + i) * CELL)
    ox = 10 * CELL                                                               # kick: anticipation, coiled
    player(cv, ox, lean=-2.5, hip=-2, bob=2, legs=((-10, 22), (62, 110)), arms=((-30, 40), None), head=(-0.5, 1))
    finish(cv, ox)
    ox = 11 * CELL                                                               # kick: full extension + smear
    j = player(cv, ox, lean=-5, hip=-4, bob=0, legs=((-16, 4), (90, 0)), arms=((-60, 20), None), head=(-1, 0.5))
    fx, fy = j["foot1"]
    finish(cv, ox)
    for k, (dy, length) in enumerate(((-6, 3), (-4, 5), (-2, 7), (0, 8), (2, 7), (4, 5), (6, 3))):
        cv.rect(fx + 7, fy + dy, length, 1, WHITE if k % 2 == 0 else "#7fe8f0")   # motion smear
    ox = 12 * CELL                                                               # death: hit, thrown back
    j = player(cv, ox, lean=-5, hip=-1, bob=1, legs=((-18, 12), (16, 20)), arms=((-75, -30), None), head=(-2, -1))
    finish(cv, ox)
    tx, ty = at(j, 0.25, -0.2)
    cv.ball(tx, ty, 2.6, 2.2, BLOOD, outline=None)
    for a, d in ((-1.0, 6), (-0.6, 9), (-0.2, 12), (0.2, 8), (0.6, 11), (-0.4, 14), (0.0, 16)):
        cv.rect(tx + math.cos(a) * d, ty + math.sin(a) * d, 2 if d < 12 else 1, 1, BLOOD[2])
    ox = 13 * CELL                                                               # death: knees give way
    cv.ball(ox + 31, FEET - 1, 13, 3, BLOOD[:2], outline=None)
    j = player(cv, ox, lean=-7, hip=1, bob=8, legs=((62, 118), (80, 140)), arms=((-95, -20), None), head=(-3, 3))
    finish(cv, ox, skip=BLOOD)
    tx, ty = at(j, 0.1, 0.0)
    cv.ball(tx, ty, 3.0, 2.6, BLOOD, outline=None)
    corpse(cv, 14 * CELL, LOOKS["player"], hair=True)


def corpse(cv, ox, look, hair=False, helmet=False):
    """Sprawled on its back, head to the left, in a pool of blood."""
    cx, cy = ox + 32, FEET - 8
    cv.ball(cx, cy + 1, 22, 8, BLOOD[:1], outline=None)                          # pool: dark rim, wet core
    cv.ball(cx - 1, cy + 1, 18, 6, BLOOD[1:2], outline=None)
    cv.ball(cx - 5, cy, 9, 2.4, BLOOD[2:3], outline=None)
    for dx, dy, w in ((-24, -3, 3), (-21, 6, 2), (20, -6, 3), (23, 3, 2), (10, 9, 3), (-8, -9, 2)):
        cv.rect(cx + dx, cy + dy, w, 1, BLOOD[0])                                # spatter, placed by hand
    body = Canvas(cv.w, cv.h)
    hip = (cx + 7, cy - 1)
    for i, (knee, foot) in enumerate((((cx + 13, cy - 6), (cx + 19, cy - 4)), ((cx + 14, cy + 3), (cx + 20, cy + 5)))):
        shade = look["pants"][:3] if i == 0 else look["pants"]
        body.limb(*hip, *knee, 2.9, shade, outline=ink(look["pants"]))
        body.limb(*knee, *foot, 2.5, shade, outline=ink(look["pants"]), r1=2.2)
        body.ball(foot[0] + 1.2, foot[1] - 1.2, 2.3, 3.4, look["shoe"], outline=ink(look["shoe"]))
    body.limb(cx - 5, cy - 4, cx - 10, cy - 10, 2.4, look["top"][:3], outline=ink(look["top"]))   # arm thrown up
    body.ball(cx - 11, cy - 11.5, 2.2, 2.2, look["skin"][:3], outline=ink(look["skin"]))
    body.ball(cx, cy - 1, 9.2, 6.2, look["top"], outline=ink(look["top"]))
    body.limb(cx - 2, cy + 4, cx - 7, cy + 8, 2.4, look["top"], outline=ink(look["top"]))         # arm out
    body.ball(cx - 8.5, cy + 9, 2.2, 2.2, look["skin"], outline=ink(look["skin"]))
    body.ball(cx - 14, cy - 2, 6.2, 6.2, look["skin"], outline=ink(look["skin"]))
    if helmet:
        body.ball(cx - 15.5, cy - 2.5, 7.2, 7.0, look["hair"], outline=ink(look["hair"]))
        body.rect(cx - 12, cy - 5, 3, 6, "#2a4c5a")
        body.rect(cx - 12, cy - 5, 1, 3, "#bff4ff")
    else:
        if hair:
            body.ball(cx - 17.5, cy - 3, 4.2, 6.0, look["hair"], outline=ink(look["hair"]))
        body.rect(cx - 12, cy - 4, 2, 1, K)                                      # closed eyes
        body.rect(cx - 12, cy - 1, 2, 1, K)
    body.ball(cx + 1, cy - 2, 3.4, 2.6, BLOOD[1:], outline=BLOOD[0])              # wound
    body.rect(cx, cy - 3, 2, 2, BLOOD[0])
    body.despeckle(ox, 0, ox + CELL, CELL)
    body.contour(K, ox, 0, ox + CELL, CELL)
    cv.blit(body, 0, 0)


# ------------------------------------------------------------------ infected

def decay(cv, j, look, wound=(0.25, -0.15), patch=(-0.4, 0.3), bald=False, tie=False):
    """What makes it a zombie, placed by hand and anchored to the joints so
    it does not crawl between frames: a torn hem, an open wound that drips,
    bare ribs, sunken eyes, a slack bloody jaw, clawed hands."""
    top, skin, hair = look["top"], look["skin"], look["hair"]
    cx, cy, rx, ry = j["torso"]
    hx, hy = j["head"]
    if not bald:                                                 # thin, matted hair
        cv.ball(hx - 1.5, hy - 4.2, 6.4, 3.4, hair, outline=ink(hair))
        cv.rect(hx - 6.5, hy - 2, 2, 4, hair[1])
        cv.rect(hx + 2, hy - 3, 1, 2, hair[1])                   # a strand over the brow
    else:
        cv.line(hx - 4, hy - 4, hx - 1, hy - 5.5, skin[0])       # a vein
        cv.line(hx - 1, hy - 5.5, hx + 1, hy - 3.5, skin[0])
    for dx in (1, 4.5):                                          # sunken sockets, one live glint each
        cv.rect(hx + dx, hy, 2, 2, K)
        cv.set(hx + dx + 1, hy, "#e8ff5a")
    cv.rect(hx + 1.5, hy + 3.5, 5, 3, "#3a0c16")                 # slack jaw
    cv.set(hx + 2.5, hy + 3.5, WHITE)
    cv.set(hx + 4.5, hy + 3.5, WHITE)
    cv.rect(hx + 3, hy + 6.5, 1, 3, BLOOD[2])                    # blood down the chin
    cv.rect(hx - 4, hy + 1, 2, 2, skin[0])                       # a bruise
    tx, ty = at(j, *patch)                                       # shirt torn open over the ribs
    cv.ball(tx, ty, 2.6, 2.9, skin[:3], outline=ink(top))
    cv.rect(tx - 1.5, ty - 1, 3, 1, skin[0])
    cv.rect(tx - 1.5, ty + 1, 3, 1, skin[0])
    wx, wy = at(j, *wound)                                       # the bite
    cv.ball(wx, wy, 2.0, 1.7, BLOOD[1:], outline=BLOOD[0])
    cv.set(wx, wy, BLOOD[0])
    cv.rect(wx, wy + 2, 1, 3, BLOOD[2])
    if tie:
        cv.line(cx + 1, cy - ry + 3, cx + 2, cy + 1, "#7a1c2c")
        cv.rect(cx, cy - ry + 2, 3, 2, "#a8283c")
    hem = int(cy + ry - 1)                                       # ragged hem: a fixed zigzag, not noise
    for k, x in enumerate(range(int(cx - 5), int(cx + 6))):
        for d in range((0, 2, 1, 3, 1, 0, 2)[k % 7]):
            if cv.get(x, hem - d) in top:
                cv.set(x, hem - d, look["pants"][1])
    for name in ("hand0", "hand1"):                              # claws
        if name in j:
            x, y = j[name]
            cv.rect(x + 2, y - 1, 2, 1, skin[3])
            cv.rect(x + 2, y + 1, 2, 1, skin[1])


SHUFFLE = (((-14, 8), (14, 6)), ((-4, 14), (4, 22)), ((14, 6), (-14, 8)), ((4, 22), (-4, 14)))
SPRINT = (((-34, 40), (40, 8)), ((-8, 70), (12, 30)), ((40, 8), (-34, 40)), ((12, 30), (-8, 70)))


def zombie_row(cv, name, cycle, lean, head, sag, bulk=0.0, bare=(False, True), **look_args):
    look = LOOKS[name]
    for i in range(5):
        lunge = i == 4
        legs = ((-26, 10), (22, 14)) if lunge else cycle[i]
        up = 80 + (8 if lunge else (i % 2) * 5)
        j = figure(cv, i * CELL, look, bob=0 if lunge else i % 2, lean=lean + (3.5 if lunge else 0), legs=legs,
                   arms=((up - 14, -sag), (up, -sag + 4)), head=(head[0] + (1.5 if lunge else 0), head[1]),
                   bulk=bulk, bare=bare)
        decay(cv, j, look, **look_args)
        finish(cv, i * CELL)
    corpse(cv, 5 * CELL, look, hair=not look_args.get("bald", False))


PUSTULES = ((-0.55, -0.2), (-0.2, -0.5), (0.3, -0.35), (0.6, 0.05), (-0.65, 0.35), (-0.15, 0.25), (0.25, 0.5),
            (0.05, -0.1), (-0.4, 0.65), (0.5, 0.6))


def bloater_row(cv):
    flesh, bile, shirt = mat("#c88a76"), mat("#a6b83a"), mat("#44608c")
    legs_m, boot = mat("#5c5c46"), mat("#2c2620")
    for i in range(5):
        swell = (0, 1, 2, 1, 3)[i]
        ox = i * CELL
        cx, fy = ox + 31, FEET
        bx, by, brx, bry = cx - 1, fy - 23, 19.5 + swell, 16.5 + swell
        for dx, ang in ((-8, -8), (7, 10)):                                               # stubby legs
            kx, ky = polar(cx + dx, fy - 12, ang + (i % 2) * 6 * (1 if dx > 0 else -1), 9)
            cv.limb(cx + dx, fy - 13, kx, ky, 4.6, legs_m, outline=ink(legs_m))
            cv.ball(kx + 1.5, fy - 1.6, 5.0, 2.5, boot, outline=ink(boot))
        cv.limb(cx - 12, fy - 36, cx - 20 - swell, fy - 26, 4.2, flesh[:3], outline=ink(flesh))   # back arm
        cv.ball(bx, by, brx, bry, bile, outline=ink(bile))                                # belly
        cv.ball(cx, fy - 38, 14 + swell * 0.6, 10.5, flesh, outline=ink(flesh))           # chest
        cv.despeckle(ox, 0, ox + CELL, CELL)
        for k, (drop, yy) in enumerate(((4.5, fy - 29), (5.0, fy - 20), (4.0, fy - 12))):   # rolls of fat
            w = brx - 3 - k * 2
            for x in range(int(bx - w), int(bx + w)):
                t = (x - bx) / w
                y = yy + (1 - t * t) * drop * 0.7
                cv.set(x, y, bile[0])
                if t < 0.3:
                    cv.set(x, y - 1, bile[3])
        for u, v in PUSTULES:                                                             # boils, each with a glint
            x, y = bx + u * brx * 0.85, by + v * bry * 0.85
            cv.rect(x, y, 2, 2, "#e6f24a")
            cv.set(x, y, WHITE)
            cv.set(x + 2, y + 1, bile[0])
            cv.set(x + 1, y + 2, bile[0])
        cv.limb(cx - 11, fy - 46, cx + 11, fy - 37, 2.2, shirt, outline=ink(shirt))        # what is left of a shirt
        cv.limb(cx + 9, fy - 45, cx + 14, fy - 32, 2.0, shirt[:3], outline=ink(shirt))
        for x in range(int(cx - 10), int(cx + 12), 4):
            cv.rect(x, fy - 39, 1, 3, shirt[1])                                           # torn threads
        cv.limb(cx + 12, fy - 37, cx + 21 + swell, fy - 30, 4.2, flesh, outline=ink(flesh))   # front arm
        cv.ball(cx + 23 + swell, fy - 28, 3.2, 3.0, flesh, outline=ink(flesh))
        cv.ball(cx + 4, fy - 50, 6.4, 5.8, flesh, outline=ink(flesh))                     # small head, sunk in
        cv.ball(cx + 3, fy - 53.4, 5.8, 2.6, mat("#4a3a30"), outline=ink(mat("#4a3a30")))
        for dx in (5, 8.5):
            cv.rect(cx + dx, fy - 51, 2, 2, K)
            cv.set(cx + dx + 1, fy - 51, "#e8ff5a")
        cv.rect(cx + 5, fy - 47, 5, 2, "#3a0c16")
        cv.set(cx + 6, fy - 47, WHITE)
        cv.rect(cx + 7, fy - 45, 1, 4 + i % 2, "#b8ff40")                                 # bile drool
        cv.rect(cx - 6, fy - 41, 3, 2, BLOOD[2])                                          # sores on the chest
        cv.rect(cx + 2, fy - 34, 2, 2, BLOOD[2])
        finish(cv, ox)
    ox = 5 * CELL                                                                         # burst: acid pool, gibs
    acid = ["#3c6410", "#6ea818", "#a8e02c", "#e0ff6a"]
    cx, cy = ox + 32, FEET - 8
    cv.ball(cx, cy, 24, 8.5, acid[:1], outline=None)
    cv.ball(cx - 1, cy, 20, 6.5, acid[1:2], outline=None)
    cv.ball(cx - 4, cy - 1, 12, 3.4, acid[2:3], outline=None)
    cv.rect(cx - 10, cy - 2, 6, 1, acid[3])
    for dx, dy, w in ((-26, -2, 3), (-22, 6, 2), (22, -5, 3), (25, 2, 2), (8, 9, 3), (-6, -10, 2), (14, -9, 2)):
        cv.rect(cx + dx, cy + dy, w, 1, acid[1])
    for dx, dy, r, shade in ((-11, 2, 3.0, flesh), (9, -3, 3.4, bile), (2, 3, 2.4, BLOOD), (-3, -4, 2.2, flesh),
                             (15, 2, 2.0, BLOOD)):
        cv.ball(cx + dx, cy + dy, r, r * 0.8, shade, outline=ink(shade))
    for dx, dy in ((-16, -1), (5, -5), (12, 5)):
        cv.rect(cx + dx, cy + dy, 2, 2, "#e6f24a")
        cv.set(cx + dx, cy + dy, WHITE)


def riot_row(cv):
    look = LOOKS["riot"]
    plate, glass, baton = mat("#3e4636", 0.5, 1.25), ["#16303a", "#2a4c5a", "#3c6c7c", "#7fe8f0"], mat("#30303a")
    for i in range(5):
        lunge = i == 4
        legs = ((-24, 10), (20, 12)) if lunge else SHUFFLE[i]
        ox = i * CELL
        j = figure(cv, ox, look, bob=0 if lunge else i % 2, lean=3 if lunge else 0.5, legs=legs,
                   arms=((60 if lunge else 14, 20), (84 if lunge else 40, 28 if not lunge else 6)), bulk=2.2,
                   head_r=6.2)
        cx, cy, rx, ry = j["torso"]
        for px, py, w, h in ((-6, 3, 3, 2), (2, 5, 4, 2)):                                # camouflage: a few
            cv.rect(cx + px, cy + ry + py, w, h, look["pants"][1])                        # deliberate patches
        for name, (px, py) in (("knee1", (0, 2)), ("knee0", (-1, 3))):
            kx, ky = j[name]
            cv.rect(kx + px, ky + py, 3, 2, look["pants"][3])
        cv.slab(cx - 6, cy - 7, 13, 10, plate, outline=ink(plate), bevel=1, grit=0)       # chest plate
        cv.line(cx - 5, cy - 2, cx + 5, cy - 2, plate[0])
        cv.rect(cx - 5, cy - 6, 5, 1, WHITE)                                              # hard-edged shine
        cv.slab(cx - 5, cy + 4, 5, 4, plate[:3], outline=ink(plate), bevel=1, grit=0)     # pouches
        cv.slab(cx + 1, cy + 4, 5, 4, plate[:3], outline=ink(plate), bevel=1, grit=0)
        cv.rect(cx + 2, cy - 5, 3, 2, "#f9f002")                                          # badge
        cv.ball(cx - 8, cy - 7, 3.8, 3.2, plate, outline=ink(plate))                      # shoulder pads
        cv.ball(cx + 8, cy - 7, 3.8, 3.2, plate, outline=ink(plate), spec=WHITE)
        for name in ("knee0", "knee1"):                                                   # knee pads
            kx, ky = j[name]
            cv.ball(kx + 0.5, ky, 2.7, 2.3, plate[:3], outline=ink(plate))
        hx, hy = j["head"]
        cv.ball(hx - 0.5, hy - 1.5, 8.0, 7.6, plate, outline=ink(plate), spec=WHITE)      # helmet
        cv.despeckle(ox, 0, ox + CELL, CELL)
        cv.rect(hx - 1, hy - 3, 9, 6, glass[1])                                           # visor
        cv.rect(hx - 1, hy - 3, 9, 1, glass[2])
        cv.rect(hx - 1, hy + 2, 9, 1, glass[0])
        cv.line(hx + 1, hy + 1, hx + 4, hy - 2, glass[3])                                 # reflection
        cv.line(hx + 4, hy + 1, hx + 6, hy - 1, glass[2])
        cv.rect(hx - 7, hy + 4, 13, 2, plate[1])                                          # neck guard
        cv.rect(hx - 7, hy + 4, 13, 1, plate[3])
        cv.rect(hx + 3, hy + 3, 2, 1, BLOOD[2])                                           # blood under the visor
        cv.rect(hx + 3, hy + 6, 1, 3, BLOOD[2])
        x, y = j["hand1"]
        bx, by = polar(x, y, 150 if not lunge else 60, 12 if not lunge else 7)
        cv.limb(x, y, bx, by, 1.4, baton, outline=ink(baton))                             # baton
        tx, ty = at(j, -0.35, 0.35)
        cv.rect(tx, ty, 2, 2, BLOOD[2])
        finish(cv, ox)
    corpse(cv, 5 * CELL, look, helmet=True)


def main() -> int:
    binary = atelier_binary()
    if binary is None:
        print("draw_characters: atelier is not installed; nothing drawn, game falls back")
        return 0
    sheet = Canvas(CELL * 15, CELL * 6)
    rows = [player_row,
            lambda cv: zombie_row(cv, "shambler", SHUFFLE, 2, (1.5, 1.5), 14),
            lambda cv: zombie_row(cv, "horde", SHUFFLE, 1, (1, 1), 6, bare=(False, False), tie=True,
                                  wound=(-0.2, 0.1), patch=(0.35, 0.45)),
            lambda cv: zombie_row(cv, "runner", SPRINT, 6, (3, 3), 22, bulk=-1.0, bare=(True, True), bald=True,
                                  wound=(0.1, 0.3), patch=(-0.3, -0.2)),
            bloater_row, riot_row]
    for r, draw in enumerate(rows):
        strip = Canvas(CELL * 15, CELL)
        strip.grit = 0.0   # clean cel bands: dithering flickers on small animated sprites
        draw(strip)
        sheet.blit(strip, 0, r * CELL)
    paint(binary, sheet, OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
