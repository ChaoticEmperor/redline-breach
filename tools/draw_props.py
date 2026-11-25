#!/usr/bin/env python3
"""Draw the 3/4-view props sheet with Atelier.

    python3 tools/draw_props.py

Every prop is drawn as a solid object seen from above and in front: its top
face first, then its front face below, so it has visible height. A prop that
stands on the floor covers `fw` x `fh` map cells (32 pixels per cell at 2
pixels per world pixel); its sprite is fw*32 wide and fh*32 + height tall and
is placed with its bottom edge on the bottom of its footprint.

Outputs:
  assets/sprites/props/sheet_props_v2.png   all props packed into one atlas
  scripts/prop_atlas.gd                     generated table of where each is

Exits 0 if Atelier is missing (the game falls back to flat blocks).
"""
from __future__ import annotations

import math
import sys

from _atelier import K, ROOT, Canvas, atelier_binary, paint, ramp, rng_for
from _deps import skip

OUT = ROOT / "assets" / "sprites" / "props" / "sheet_props_v2.png"
TABLE = ROOT / "scripts" / "prop_atlas.gd"
C = 32
WHITE = "#fff4e0"
STEEL, DARK, WOOD = ramp("#8e98ae"), ramp("#34343f"), ramp("#93602f")
VELVET, PORC = ramp("#cc2f80"), ramp("#d9e0e6")
NEON = {"pink": "#ff2a6d", "cyan": "#05d9e8", "purple": "#c060ff", "yellow": "#f9f002", "green": "#30ff70"}


def grit(cv, shades, amount=0.05, name="g"):
    cv.speckle(0, 0, cv.w, cv.h, [shades[0], shades[1]], amount, rng_for(name), only=set(shades[1:]))


def booth():
    cv = Canvas(C, C + 16)
    cv.slab(0, 0, C, 11, VELVET, curve=0.0)                 # backrest
    cv.rect(1, 1, C - 2, 2, VELVET[4])
    cv.rect(3, 2, 8, 1, WHITE)
    cv.slab(0, 10, C, 22, VELVET[1:])                       # seat cushion
    for x, y in ((8, 17), (24, 17), (16, 25)):              # tufting
        cv.rect(x - 1, y - 1, 3, 3, VELVET[2])
        cv.rect(x, y, 1, 1, VELVET[0])
        cv.rect(x - 1, y - 1, 1, 1, VELVET[4])
    cv.line(2, 13, 12, 13, VELVET[4])
    cv.slab(0, C, C, 16, VELVET[:3])                        # front
    cv.rect(1, C + 1, C - 2, 1, VELVET[4])                  # piping
    cv.rect(2, C + 12, 4, 3, DARK[0])
    cv.rect(C - 6, C + 12, 4, 3, DARK[0])
    grit(cv, VELVET, 0.04, "booth")
    return cv, 1, 1


def bar(bottles):
    cv = Canvas(C, C + 18)
    cv.slab(0, 0, C, C, WOOD)
    for y in (8, 16, 24):
        cv.line(1, y, C - 2, y, WOOD[1])
    cv.line(3, 4, 13, 2, WOOD[4])                           # varnish shine
    cv.line(5, 6, 20, 3, WHITE)
    cv.rect(18, 20, 6, 4, WOOD[1])                          # glass ring
    cv.rect(19, 21, 4, 2, WOOD[3])
    if bottles:
        for i, col in enumerate(("green", "cyan", "pink")):
            x, shades = 5 + i * 9, ramp(NEON[col], 4, 0.4, 1.1)
            cv.slab(x, 10, 5, 12, shades, curve=0.7)
            cv.slab(x + 1, 5, 3, 6, shades[1:], curve=0.5)
            cv.rect(x + 1, 12, 1, 7, WHITE)
            cv.rect(x + 1, 16, 3, 3, WHITE)                 # label
    else:
        cv.slab(22, 4, 6, 8, ramp("#9ad8e8", 4), curve=0.6)  # tumbler
        cv.rect(23, 5, 4, 1, WHITE)
    cv.slab(0, C, C, 18, WOOD[:4])
    for x in (10, 21):
        cv.line(x, C + 2, x, C + 15, WOOD[0])
    cv.rect(1, C + 4, C - 2, 2, NEON["pink"])               # underglow strip
    cv.rect(1, C + 4, C - 2, 1, "#ffb0c8")
    cv.rect(1, C + 6, C - 2, 1, "#7a1038")
    cv.rect(0, C + 14, C, 1, ramp("#c8a040", 3)[2])         # brass foot rail
    grit(cv, WOOD, 0.05, "bar")
    return cv, 1, 1


def stool():
    cv = Canvas(C, C + 14)
    cv.disc(16, 41, 8, 3, STEEL)                            # base
    cv.slab(14, 22, 4, 19, STEEL, curve=0.8)                # stem
    cv.slab(6, 18, 20, 6, VELVET[:3], curve=0.7)            # cushion side
    cv.disc(16, 17, 10.5, 6, VELVET[1:], rim=VELVET[2])
    cv.rect(10, 14, 6, 1, VELVET[4])
    cv.rect(11, 13, 3, 1, WHITE)
    return cv, 1, 1


def table():
    cv = Canvas(C, C + 12)
    purple = ramp("#6a44b0")
    cv.disc(16, 40, 7, 2.6, DARK)
    cv.slab(14, 24, 4, 16, DARK, curve=0.8)
    cv.slab(3, 16, 26, 5, purple[:3], curve=0.7)
    cv.disc(16, 14, 14, 9, purple, rim=purple[2])
    cv.rect(7, 9, 8, 1, purple[4])
    for x, y, col in ((9, 10, "cyan"), (19, 8, "pink"), (16, 15, "yellow")):   # cocktails
        shades = ramp(NEON[col], 3, 0.5, 1.1)
        cv.slab(x, y, 5, 6, shades, curve=0.6)
        cv.rect(x + 1, y + 1, 3, 1, WHITE)
        cv.rect(x + 3, y - 3, 1, 3, WHITE)                  # straw
    return cv, 1, 1


def dj():
    cv = Canvas(C * 4, C * 2 + 22)
    deck = ramp("#3a2c66")
    cv.slab(0, 0, 128, 64, deck, bevel=2)
    cv.rect(2, 2, 124, 1, NEON["cyan"])
    for cx, label in ((30, "pink"), (98, "cyan")):          # turntables
        cv.slab(cx - 26, 8, 52, 48, DARK[1:], bevel=1)
        cv.disc(cx, 31, 22, 17, ramp("#16161e", 4), rim="#3c3c52")
        for r in (0.78, 0.6, 0.42):                         # grooves
            for a in range(0, 360, 3):
                cv.set(cx + math.cos(math.radians(a)) * 22 * r, 31 + math.sin(math.radians(a)) * 17 * r, "#2a2a38")
        cv.line(cx - 14, 22, cx - 4, 27, "#5a5a78")         # light catching the vinyl
        cv.disc(cx, 31, 6.5, 5, ramp(NEON[label], 3, 0.5, 1.1))
        cv.rect(cx - 1, 30, 2, 2, WHITE)
        cv.limb(cx + 20, 12, cx + 9, 27, 1.3, STEEL)        # tone arm
        cv.ball(cx + 21, 11, 3, 3, STEEL, spec=WHITE)
    cv.slab(57, 6, 14, 52, DARK[1:], bevel=1)               # mixer
    for i, y in enumerate(range(10, 30, 5)):
        for x in (60, 65):
            cv.ball(x + 1, y + 1, 1.6, 1.6, ramp(("#ff2a6d", "#05d9e8", "#f9f002", "#30ff70")[i], 3, 0.5, 1.1),
                    outline=None)
    for x in (59, 63, 67):                                  # faders
        cv.rect(x, 33, 1, 20, K)
        cv.rect(x - 1, 38 + (x * 7) % 11, 3, 3, STEEL[4])
    cv.slab(0, 64, 128, 22, deck[:3], bevel=1)              # front
    rng = rng_for("vu")
    for i, x in enumerate(range(6, 122, 4)):                # VU meters
        h = rng.randint(2, 7)
        for k in range(h):
            col = NEON["green"] if k < 4 else NEON["yellow"] if k < 6 else NEON["pink"]
            cv.rect(x, 80 - k * 2, 2, 1, col)
    cv.rect(1, 68, 126, 2, NEON["purple"])
    cv.rect(1, 68, 126, 1, "#f0c8ff")
    cv.rect(0, 84, 128, 2, K)
    return cv, 4, 2


def speaker():
    cv = Canvas(C * 2, C * 2 + 44)
    cv.slab(0, 0, 64, 64, DARK[1:], bevel=2)
    cv.slab(22, 26, 20, 6, DARK[:3], bevel=1)               # handle recess
    cv.slab(0, 64, 64, 44, DARK[:4], bevel=2)
    cv.rect(2, 66, 60, 1, NEON["cyan"])
    for cx in (18, 46):
        cv.disc(cx, 88, 13, 13, ramp("#4a4a60", 4), rim="#20202a")
        cv.disc(cx, 88, 9, 9, ramp("#14141c", 3))
        cv.ball(cx, 88, 4.5, 4.5, ramp("#6a6a88", 4), spec=WHITE)
        cv.disc(cx, 72, 3.2, 3.2, ramp("#4a4a60", 3))
    for x in range(6, 60, 3):                               # grille
        cv.rect(x, 104, 1, 3, DARK[0])
    grit(cv, DARK, 0.04, "spk")
    return cv, 2, 2


def arcade():
    cv = Canvas(C, C + 38)
    body = ramp("#27345e")
    cv.slab(0, 0, C, C, body)
    cv.slab(3, 3, 26, 20, body[1:], bevel=1)
    y = C
    cv.slab(0, y, C, 38, body[:4], bevel=1)
    cv.slab(2, y + 1, 28, 7, ramp("#d300c5", 4), bevel=1)   # lit marquee
    for x in range(5, 27, 4):
        cv.rect(x, y + 3, 2, 3, WHITE)
    cv.slab(3, y + 9, 26, 15, DARK[:2], bevel=1)            # bezel
    cv.slab(5, y + 11, 22, 11, ramp("#0a7a94", 4), bevel=0, grit=1.4)
    rng = rng_for("arcade")
    for row in range(2):                                    # invaders
        for col in range(4):
            cv.rect(7 + col * 5, y + 12 + row * 3, 3, 2, (NEON["green"], NEON["pink"])[row])
    cv.rect(15, y + 20, 3, 1, WHITE)                        # player ship
    cv.rect(16, y + 17, 1, 2, NEON["yellow"])
    cv.rect(5, y + 11, 22, 1, "#bff4ff")
    cv.slab(1, y + 25, 30, 5, body[2:], bevel=1)            # control panel
    cv.ball(8, y + 26, 2.2, 2.2, ramp("#ff2a6d", 3, 0.5, 1.1), spec=WHITE)
    cv.rect(7, y + 27, 2, 2, K)
    for i, col in enumerate(("yellow", "cyan", "green")):
        cv.rect(16 + i * 4, y + 26, 2, 2, NEON[col])
    cv.slab(10, y + 31, 12, 6, DARK[:3], bevel=1)           # coin door
    cv.rect(13, y + 33, 2, 2, NEON["yellow"])
    cv.rect(17, y + 33, 2, 2, NEON["yellow"])
    return cv, 1, 1


def vending():
    cv = Canvas(C, C + 38)
    body = ramp("#a83248")
    cv.slab(0, 0, C, C, body)
    cv.slab(3, 3, 26, 22, body[1:], bevel=1)
    y = C
    cv.slab(0, y, C, 38, body[:4], bevel=1)
    cv.slab(2, y + 2, 19, 26, ramp("#1c2c3c", 3), bevel=1)  # window
    rng = rng_for("cans")
    for row in range(4):
        cv.rect(3, y + 8 + row * 6, 17, 1, STEEL[1])        # shelf
        for col in range(4):
            shades = ramp(rng.choice(list(NEON.values())), 3, 0.5, 1.1)
            cv.slab(4 + col * 4, y + 3 + row * 6, 3, 5, shades, outline=None, bevel=0, curve=0.7)
    cv.line(4, y + 4, 9, y + 24, "#5a7a94")                 # glass glint
    cv.slab(22, y + 3, 8, 12, DARK[1:], bevel=1)            # keypad
    for i in range(6):
        cv.rect(24 + (i % 2) * 3, y + 5 + (i // 2) * 3, 2, 2, STEEL[3])
    cv.rect(24, y + 17, 4, 2, NEON["green"])
    cv.rect(25, y + 21, 2, 4, K)                            # coin slot
    cv.slab(3, y + 30, 18, 6, DARK[:2], bevel=1)            # hatch
    cv.rect(1, y + 36, 30, 1, body[0])
    return cv, 1, 1


def counter():
    cv = Canvas(C, C + 16)
    cv.slab(0, 0, C, C, STEEL)
    for i in (-14, -2, 10, 22):                             # brushed-metal glints
        cv.line(max(i, 1), max(-i, 1) + 2, min(i + 14, 30), 16 + min(-i, 0) + (14 if i < 0 else 14), STEEL[4])
    cv.line(4, 8, 12, 3, WHITE)
    cv.slab(0, C, C, 16, STEEL[:4])
    cv.slab(2, C + 2, 13, 10, STEEL[1:4], bevel=1)
    cv.slab(17, C + 2, 13, 10, STEEL[1:4], bevel=1)
    cv.rect(11, C + 5, 2, 4, WHITE)
    cv.rect(19, C + 5, 2, 4, WHITE)
    cv.rect(0, C + 13, C, 3, DARK[0])                       # kick plate
    grit(cv, STEEL, 0.03, "counter")
    return cv, 1, 1


def stove():
    cv = Canvas(C, C + 16)
    cv.slab(0, 0, C, C, STEEL)
    for i, (x, y) in enumerate(((9, 9), (23, 9), (9, 22), (23, 22))):
        cv.disc(x, y, 6, 5, ramp("#2a2038", 3), rim="#5a4a80")
        cv.disc(x, y, 3, 2.4, ramp("#ff7a2a" if i == 2 else "#3a3048", 3, 0.5, 1.2))
    cv.slab(0, C, C, 16, STEEL[:4])
    cv.slab(3, C + 5, 26, 9, DARK[:3], bevel=1)             # oven window
    cv.line(6, C + 7, 12, C + 12, "#5a5a78")
    cv.rect(4, C + 4, 24, 1, WHITE)                         # handle
    for x in (5, 11, 17, 23):
        cv.ball(x + 1, C + 2, 1.4, 1.4, DARK[1:], outline=None)
    return cv, 1, 1


def sink():
    cv = Canvas(C, C + 16)
    cv.slab(0, 0, C, C, PORC)
    cv.disc(16, 18, 11, 9, ramp("#6a8ca8", 4), rim=PORC[1])
    cv.rect(15, 20, 3, 2, K)                                # drain
    cv.limb(16, 4, 16, 12, 1.6, STEEL)                      # tap
    cv.ball(16, 4, 2.4, 2.0, STEEL, spec=WHITE)
    cv.slab(25, 4, 4, 5, ramp("#ff7ab8", 3), bevel=1)       # soap
    cv.slab(0, C, C, 16, PORC[:4])
    cv.slab(12, C + 6, 8, 9, STEEL[:3], curve=0.7)          # trap
    cv.rect(2, C + 11, 5, 4, ramp("#4a5a2a", 3)[1])         # grime
    grit(cv, PORC, 0.04, "sink")
    return cv, 1, 1


def toilet():
    cv = Canvas(C, C + 14)
    cv.slab(8, 30, 16, 14, PORC[:4], curve=0.8)             # pedestal
    cv.slab(7, 4, 18, 13, PORC, bevel=1)                    # tank
    cv.rect(21, 7, 3, 2, STEEL[4])
    cv.disc(16, 25, 11, 9, PORC, rim=PORC[3])
    cv.disc(16, 26, 7, 5.5, ramp("#3c5c7c", 4))
    cv.rect(13, 24, 3, 1, WHITE)
    grit(cv, PORC, 0.05, "toilet")
    return cv, 1, 1


def crate():
    cv = Canvas(C, C + 18)
    cv.slab(0, 0, C, C, WOOD, bevel=2)
    cv.slab(4, 4, 24, 24, WOOD[1:], bevel=1)
    cv.line(5, 5, 26, 26, WOOD[0])
    cv.line(6, 5, 27, 26, WOOD[3])
    cv.slab(0, C, C, 18, WOOD[:4], bevel=2)
    for x in (10, 21):
        cv.line(x, C + 2, x, C + 15, WOOD[0])
    cv.rect(12, C + 6, 8, 6, NEON["yellow"])                # stencil
    cv.rect(14, C + 8, 4, 2, K)
    for x, y in ((2, 2), (29, 2), (2, 29), (29, 29), (2, C + 2), (29, C + 2)):
        cv.set(x, y, STEEL[4])                              # nails
    grit(cv, WOOD, 0.07, "crate")
    return cv, 1, 1


def barrel(cv, x, y, shades, name):
    """One upright drum, 26 wide; (x, y) is the top-left of its lid."""
    cv.slab(x, y + 6, 26, 32, shades, curve=0.85)
    for band in (12, 22, 32):
        cv.rect(x + 1, y + band, 24, 1, shades[0])
        cv.rect(x + 2, y + band + 1, 8, 1, shades[4])
    cv.slab(x + 7, y + 15, 12, 6, ramp("#f9d020", 3), outline=None, bevel=0)   # hazard label
    cv.rect(x + 11, y + 16, 4, 4, K)
    cv.rect(x + 12, y + 17, 2, 2, NEON["yellow"])
    cv.disc(x + 13, y + 6, 13, 6, shades[1:], rim=shades[1])
    cv.rect(x + 8, y + 3, 3, 2, DARK[0])                    # bung
    cv.speckle(x, y, 27, 40, ["#6a3a1c", "#4a2a14"], 0.07, rng_for(name), only=set(shades[1:]))


def barrels():
    cv = Canvas(C * 2, C * 2 + 28)
    barrel(cv, 3, 8, ramp("#6c7a2c"), "b1")
    barrel(cv, 35, 4, ramp("#8a5a24"), "b2")
    barrel(cv, 19, 50, ramp("#7a8630"), "b3")
    cv.rect(30, 80, 2, 9, NEON["green"])                    # leak
    cv.rect(26, 88, 9, 2, "#8ad022")
    return cv, 2, 2


def vat():
    cv = Canvas(C * 2, C * 2 + 46)
    liquid, glow = ramp("#2fae4c"), ramp("#8affa0", 4, 0.5, 1.1)
    rng = rng_for("vat")
    cv.limb(6, 30, 6, 96, 2.2, STEEL)                       # feed pipes
    cv.limb(58, 40, 58, 96, 2.2, STEEL[:4])
    cv.slab(2, 92, 60, 16, STEEL[:4], curve=0.6)            # plinth
    cv.rect(4, 96, 56, 2, NEON["yellow"])
    for x in range(4, 60, 8):
        cv.rect(x, 96, 4, 2, K)
    cv.slab(8, 24, 48, 70, liquid, curve=0.9, grit=1.6)     # tank
    for s in range(5):                                      # swirling fluid
        for t in range(40):
            y = 30 + t * 1.5
            x = 32 + math.sin(t * 0.32 + s * 1.3) * (16 - s * 2)
            if 10 < x < 54:
                cv.set(x, y, glow[min(3, s % 3 + 1)])
    cv.ball(31, 62, 8, 13, ramp("#1a5a2a", 4), outline=None)            # something in there
    cv.ball(31, 48, 5, 5, ramp("#1a5a2a", 4), outline=None)
    for _ in range(18):
        cv.ball(rng.randint(12, 52), rng.randint(28, 88), 1.2, 1.2, glow[2:], outline=None)
    cv.rect(11, 28, 2, 60, "#d8ffe0")                       # glass reflections
    cv.rect(14, 30, 1, 40, "#a8ffb8")
    cv.rect(51, 30, 2, 58, liquid[0])
    cv.slab(36, 70, 14, 12, ramp("#f9d020", 3), bevel=1)    # biohazard plate
    cv.disc(43, 76, 3.5, 3.5, [K, K])
    cv.rect(42, 75, 2, 2, NEON["yellow"])
    cv.slab(5, 12, 54, 14, STEEL, curve=0.6)                # collar
    cv.disc(32, 12, 27, 9, STEEL, rim=STEEL[1])
    cv.disc(32, 12, 19, 5.5, glow)
    for x in (10, 24, 40, 54):
        cv.ball(x, 20, 1.5, 1.5, STEEL[2:], outline=None, spec=WHITE)   # bolts
    return cv, 2, 2


def rack():
    cv = Canvas(C, C + 40)
    cv.slab(0, 0, C, C, DARK[1:], bevel=2)
    for y in range(6, 26, 4):
        cv.rect(5, y, 22, 1, DARK[0])                       # top vent
    y0 = C
    cv.slab(0, y0, C, 40, DARK[:4], bevel=1)
    rng = rng_for("rack")
    for u in range(6):
        y = y0 + 2 + u * 6
        cv.slab(2, y, 28, 5, DARK[1:], bevel=1)
        if u in (1, 4):                                     # status screens
            cv.slab(4, y + 1, 12, 3, ramp(NEON["cyan"] if u == 1 else NEON["green"], 3, 0.4, 1.0), outline=None, bevel=0)
            cv.rect(5, y + 2, 6, 1, WHITE)
            cv.rect(18, y + 1, 10, 3, ramp("#ff8a2a", 3)[1])
            cv.rect(19, y + 2, 5, 1, WHITE)
        else:
            for x in range(4, 16, 2):
                cv.rect(x, y + 2, 1, 1, rng.choice([NEON["green"], NEON["green"], NEON["yellow"], NEON["pink"], K]))
            for x in range(18, 28, 2):
                cv.rect(x, y + 1, 1, 3, DARK[0])
    cv.line(30, y0 + 4, 31, y0 + 36, NEON["cyan"])          # patch cable
    return cv, 1, 1


def chairs():
    cv = Canvas(C, C + 12)
    teal = ramp("#2c8f96")
    cv.rect(2, 36, 28, 2, STEEL[1])                         # beam
    for x in (4, 26):
        cv.slab(x, 36, 2, 8, STEEL[:3], outline=None, bevel=0)
    for x in (1, 17):
        cv.slab(x, 2, 14, 13, teal, curve=0.5)              # back
        cv.rect(x + 2, 4, 6, 1, teal[4])
        cv.slab(x, 16, 14, 16, teal[1:])                    # seat
        cv.slab(x, 32, 14, 5, teal[:3], bevel=1)
    cv.rect(20, 20, 6, 4, "#8e0b1c")                        # stain
    grit(cv, teal, 0.06, "chairs")
    return cv, 1, 1


def tape():
    cv = Canvas(C, C + 16)
    for x in (5, 27):
        cv.disc(x, 44, 4.5, 2.2, DARK)
        cv.slab(x - 1, 12, 3, 32, ramp("#e86a1c", 4), curve=0.8)
        cv.ball(x, 11, 2.6, 2.4, ramp("#ffb040", 3), spec=WHITE)
        for y in range(18, 42, 8):
            cv.rect(x - 1, y, 3, 3, WHITE)
    for x in range(7, 26):                                  # sagging tape
        y = 17 + round(2 * math.sin((x - 7) / 18 * math.pi))
        for k in range(5):
            cv.set(x, y + k, K if (x + k) // 3 % 2 else NEON["yellow"])
        cv.set(x, y - 1, K)
        cv.set(x, y + 5, K)
    return cv, 1, 1


def glass(broken):
    cv = Canvas(C, C + 20)
    rng = rng_for("glass")
    cv.slab(0, C + 16, C, 4, STEEL[:4], bevel=1)            # sill
    if not broken:
        cv.rect(0, 0, C, C, "#7fe8f030")                    # top of the pane
        cv.rect(0, C, C, 16, "#7fe8f066")
        cv.rect(0, C, C, 1, "#d8ffffcc")
        cv.rect(0, 0, 1, C + 16, "#bff4ffaa")
        cv.rect(C - 1, 0, 1, C + 16, "#3a8a9aaa")
        for i in (4, 9, 20):                                # reflections
            cv.line(i, C + 14, i + 8, C + 2, "#ffffffcc")
        cv.line(22, 20, 28, 8, "#ffffff66")
    else:
        for x0, w, h in ((0, 5, 13), (4, 4, 6), (25, 7, 14), (22, 4, 5), (12, 5, 4)):   # shards left in the frame
            for x in range(x0, x0 + w):
                top = h - abs(x - x0 - w // 2) * 2 - rng.randint(0, 2)
                for y in range(max(top, 1)):
                    cv.set(x, C + 15 - y, "#9af0f8b0" if (x + y) % 3 else "#ffffffd0")
        for _ in range(26):                                 # sparkling debris
            x, y = rng.randint(1, 30), rng.randint(6, C + 14)
            cv.set(x, y, rng.choice(("#ffffffff", "#bff4ffe0", "#7fe8f0c0")))
            if rng.random() < 0.3:
                cv.set(x + 1, y, "#7fe8f0a0")
    return cv, 1, 1


def hazard_light():
    cv = Canvas(20, 20)
    cv.slab(3, 12, 14, 6, DARK[1:], bevel=1)
    cv.ball(10, 9, 6, 6, ramp("#ff5a1c", 5, 0.45, 1.2), spec=WHITE)
    for x in (6, 10, 14):
        cv.line(x, 4, x, 13, K)                             # cage
    cv.line(4, 9, 16, 9, K)
    return cv, 0, 0


FONT = {
    "M": ("X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X"),
    "O": (".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."),
    "T": ("XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."),
    "E": ("XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"),
    "L": ("X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"),
    "U": ("X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."),
    "N": ("X...X", "XX..X", "X.X.X", "X.X.X", "X..XX", "X...X", "X...X"),
    "G": (".XXX.", "X...X", "X....", "X.XXX", "X...X", "X...X", ".XXX."),
    "R": ("XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"),
    "D": ("XXXX.", "X...X", "X...X", "X...X", "X...X", "X...X", "XXXX."),
    "I": ("XXX", ".X.", ".X.", ".X.", ".X.", ".X.", "XXX"),
}


def sign(text, colour):
    """Neon tube lettering on a backing board."""
    width = sum(len(FONT[ch][0]) * 2 + 3 for ch in text) + 9
    cv = Canvas(width, 26)
    cv.slab(0, 2, width, 22, DARK[:3], bevel=1)
    for x in (4, width - 6):
        cv.rect(x, 0, 2, 3, STEEL[2])                       # hangers
    shades = ramp(NEON[colour], 4, 0.35, 1.0)
    x = 6
    tubes = set()
    for ch in text:
        for r, row in enumerate(FONT[ch]):
            for c, bit in enumerate(row):
                if bit == "X":
                    for dy in range(2):
                        for dx in range(2):
                            tubes.add((x + c * 2 + dx, 6 + r * 2 + dy))
        x += len(FONT[ch][0]) * 2 + 3
    for (px, py) in tubes:                                  # glow bleeding onto the board
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                if (px + dx, py + dy) not in tubes and 1 <= px + dx < width - 1 and 3 <= py + dy < 23:
                    cv.set(px + dx, py + dy, shades[1] if abs(dx) + abs(dy) > 2 else shades[2])
    for (px, py) in tubes:
        cv.set(px, py, NEON[colour])
    for (px, py) in tubes:                                  # hot core
        if (px - 1, py) in tubes and (px, py - 1) in tubes and (px - 1, py - 1) in tubes and (px + py) % 2 == 0:
            cv.set(px - 1, py - 1, WHITE)
    return cv, 0, 0


PROPS = {
    "booth": booth, "bar": lambda: bar(False), "bar_bottles": lambda: bar(True), "stool": stool, "table": table,
    "dj": dj, "speaker": speaker, "arcade": arcade, "vending": vending, "counter": counter, "stove": stove,
    "sink": sink, "toilet": toilet, "crate": crate, "barrels": barrels, "vat": vat, "rack": rack,
    "chairs": chairs, "tape": tape, "glass": lambda: glass(False), "glass_broken": lambda: glass(True),
    "hazard_light": hazard_light, "sign_motel": lambda: sign("MOTEL", "pink"),
    "sign_lounge": lambda: sign("LOUNGE", "purple"), "sign_redline": lambda: sign("REDLINE", "cyan"),
}


def main() -> int:
    binary = atelier_binary()
    if binary is None:
        return skip("draw_props: atelier is not installed; nothing drawn, game falls back")
    drawn = {name: make() for name, make in PROPS.items()}
    width, pad = 512, 2
    x = y = shelf = 0
    places = {}
    for name, (cv, fw, fh) in sorted(drawn.items(), key=lambda kv: -kv[1][0].h):   # shelf packing, tallest first
        if x + cv.w > width:
            x, y, shelf = 0, y + shelf + pad, 0
        places[name] = (x, y, cv.w, cv.h, fw, fh)
        x += cv.w + pad
        shelf = max(shelf, cv.h)
    atlas = Canvas(width, y + shelf)
    for name, (cv, _, _) in drawn.items():
        atlas.blit(cv, places[name][0], places[name][1])
    paint(binary, atlas, OUT)
    lines = ["extends RefCounted", "## Generated by tools/draw_props.py - do not edit by hand.",
             "## Where each prop sits in assets/sprites/props/sheet_props_v2.png.", "",
             "const SIZE := Vector2i(%d, %d)" % (atlas.w, atlas.h),
             "# name: [x, y, width, height, footprint width, footprint height] (pixels; footprint in map cells)",
             "const PROPS := {"]
    lines += ['\t"%s": [%s],' % (name, ", ".join(str(v) for v in places[name])) for name in PROPS]
    lines.append("}")
    TABLE.write_text("\n".join(lines) + "\n")
    print(f"  scripts/prop_atlas.gd  {len(PROPS)} props")
    return 0


if __name__ == "__main__":
    sys.exit(main())
