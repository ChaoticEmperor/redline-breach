"""Shared helpers for the Atelier drawing scripts.

`Canvas` is a small software renderer for pixel art: rounded forms are lit
from the upper left and quantised onto a colour ramp with ordered dithering,
every form gets a dark outline, and detail is added on top. The finished
canvas is painted through the `atelier` CLI and exported as a PNG.
"""
from __future__ import annotations

import colorsys
import json
import math
import os
import random
import shutil
import string
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEYS = string.ascii_letters + string.digits + "!$%&()*+,-/:;<=>?@[]^_{|}~"
K = "#140c1c"                      # outline
LIGHT = (-0.52, -0.62, 0.59)       # towards the light: upper left, out of the screen
BAYER = ((0.0, 0.5), (0.75, 0.25))
FRONT = (0.0, 0.0, 1.0)            # normal of a surface facing the viewer (view frame: x right, y down, z out)
TOP = (0.0, -0.6, 0.8)             # normal of a horizontal surface (a table top) seen in the 3/4 view


def ink(shades: list[str], amount: float = 0.55) -> str:
    """Outline colour for a material: its darkest shade, darkened further.
    Coloured outlines inside a sprite stay readable where black turns to mud."""
    r, g, b = (int(shades[0][i:i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(int(c * amount) for c in (r, g, b))


def ramp(base: str, n: int = 5, lo: float = 0.34, hi: float = 1.18, warm: float = 0.0) -> list[str]:
    """Dark-to-light ramp around a base colour. Shadows drift towards violet
    and lose a little saturation; with `warm`, lights drift towards yellow."""
    r, g, b = (int(base[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i in range(n):
        t = i / (n - 1)
        vv = min(1.0, v * (lo + (hi - lo) * t))
        turn = ((0.75 - h + 0.5) % 1.0) - 0.5          # shortest way round the hue wheel to violet
        glow = ((0.13 - h + 0.5) % 1.0) - 0.5          # ... and to warm yellow
        if abs(glow) > 0.2:
            glow = 0.0                                  # only already-warm hues drift warmer; blue stays blue
        hh = (h + turn * 0.2 * (1 - t) ** 2 + glow * warm * t * t) % 1.0 if s > 0.05 else h
        ss = min(1.0, s * (1.15 - 0.45 * t))
        out.append("#%02x%02x%02x" % tuple(int(c * 255) for c in colorsys.hsv_to_rgb(hh, ss, vv)))
    return out


class Canvas:
    """Pixels are '#rrggbb' / '#rrggbbaa' strings or None (transparent)."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]
        # Surface normal per pixel in the view frame, kept by the lit forms for the normal map
        # (normal_image()). Detail painted on top keeps the normal of the form under it.
        self.nrm = [[None] * w for _ in range(h)]
        self.grit = 0.9  # ordered-dither strength on lit forms; 0 gives clean cel bands

    # ------------------------------------------------------------ basics
    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def set(self, x, y, c, n=None):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c
            if c is None:
                self.nrm[y][x] = None
            elif n is not None:
                self.nrm[y][x] = n

    def rect(self, x, y, w, h, c):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.set(xx, yy, c)

    def line(self, x0, y0, x1, y1, c):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) or 1
        for i in range(n + 1):
            self.set(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), c)

    def blit(self, other: "Canvas", ox: int, oy: int):
        for y in range(other.h):
            for x in range(other.w):
                if other.px[y][x] is not None:
                    self.set(ox + x, oy + y, other.px[y][x], other.nrm[y][x])

    def speckle(self, x, y, w, h, colours, chance, rng, only=None):
        """Grit: recolour scattered pixels (optionally only those in `only`)."""
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                cur = self.get(xx, yy)
                if cur is not None and cur != K and (only is None or cur in only) and rng.random() < chance:
                    self.set(xx, yy, rng.choice(colours))

    # ------------------------------------------------------------ lit forms
    @staticmethod
    def _tone(shades, light, x, y, grit=0.9):
        v = (light * 0.5 + 0.5) * len(shades) + (BAYER[y & 1][x & 1] - 0.375) * grit
        return shades[max(0, min(len(shades) - 1, int(v)))]

    def _fill(self, pts, outline, normals=None):
        """pts: {(x, y): colour}. Draws a 1px outline around the shape first.
        normals: {(x, y): view-frame normal}; an outline pixel takes the normal of the form pixel beside it."""
        normals = normals or {}
        if outline:
            for (x, y) in pts:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if (x + dx, y + dy) not in pts:
                        self.set(x + dx, y + dy, outline, normals.get((x, y), FRONT))
        for (x, y), c in pts.items():
            self.set(x, y, c, normals.get((x, y), FRONT))

    def ball(self, cx, cy, rx, ry, shades, outline=K, spec=None, flat=0.0):
        """Lit ellipsoid. `flat` (0..1) pushes it towards a disc seen from above."""
        pts, normals = {}, {}
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                d = nx * nx + ny * ny
                if d > 1.0:
                    continue
                nz = math.sqrt(1.0 - d)
                li = nx * LIGHT[0] * (1 - flat) + ny * LIGHT[1] * (1 - flat) + (nz + flat) * LIGHT[2]
                pts[(x, y)] = spec if spec and li > 0.9 else self._tone(shades, li * 1.25, x, y, self.grit)
                normals[(x, y)] = _unit(nx * (1 - flat), ny * (1 - flat), nz + flat)
        self._fill(pts, outline, normals)

    def limb(self, x0, y0, x1, y1, r, shades, outline=K, r1=None):
        """Lit capsule from (x0, y0) to (x1, y1); radius tapers from r to r1."""
        r1 = r if r1 is None else r1
        dx, dy = x1 - x0, y1 - y0
        length2 = dx * dx + dy * dy or 1e-6
        rr = max(r, r1)
        pts, normals = {}, {}
        for y in range(int(min(y0, y1) - rr - 1), int(max(y0, y1) + rr + 2)):
            for x in range(int(min(x0, x1) - rr - 1), int(max(x0, x1) + rr + 2)):
                px, py = x + 0.5 - x0, y + 0.5 - y0
                t = max(0.0, min(1.0, (px * dx + py * dy) / length2))
                ox, oy = px - dx * t, py - dy * t
                rad = r + (r1 - r) * t
                d = (ox * ox + oy * oy) / (rad * rad)
                if d > 1.0:
                    continue
                nz = math.sqrt(1.0 - d)
                li = ox / rad * LIGHT[0] + oy / rad * LIGHT[1] + nz * LIGHT[2]
                pts[(x, y)] = self._tone(shades, li * 1.25, x, y, self.grit)
                normals[(x, y)] = _unit(ox / rad, oy / rad, nz)
        self._fill(pts, outline, normals)

    def slab(self, x, y, w, h, shades, outline=K, bevel=1, curve=0.0, grit=0.9, face="front"):
        """Lit panel facing the viewer: lighter towards the top-left, with a
        bevel. `curve` > 0 shades it like a cylinder (dark at both sides).
        `face` only feeds the normal map: "front" for an upright face, "top" for a
        horizontal one (a counter top, a seat); the colours are the same."""
        base = TOP if face == "top" else FRONT
        pts, normals = {}, {}
        x, y, w, h = int(x), int(y), int(w), int(h)
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                u, v = (xx - x + 0.5) / w, (yy - y + 0.5) / h
                n = base
                if bevel and (xx - x < bevel or yy - y < bevel):
                    li = 0.75
                    n = _unit(base[0] - (0.6 if xx - x < bevel else 0.0), base[1] - (0.6 if yy - y < bevel else 0.0), base[2])
                elif bevel and (x + w - xx <= bevel or y + h - yy <= bevel):
                    li = -0.75
                    n = _unit(base[0] + (0.6 if x + w - xx <= bevel else 0.0), base[1] + (0.6 if y + h - yy <= bevel else 0.0), base[2])
                else:
                    li = 0.25 - v * 0.55 - u * 0.2
                if curve:
                    li = (1.0 - abs(u * 2 - 1.15) ** 1.6 * 1.6) * curve + li * (1 - curve)
                    side = max(-0.95, min(0.95, (u * 2 - 1) * curve))
                    n = _unit(side, n[1], math.sqrt(1 - side * side))
                pts[(xx, yy)] = self._tone(shades, li, xx, yy, grit)
                normals[(xx, yy)] = n
        self._fill(pts, outline, normals)

    def disc(self, cx, cy, rx, ry, shades, outline=K, rim=None):
        """Flat ellipse seen at an angle (a table top, a barrel lid, liquid)."""
        pts, normals = {}, {}
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                d = nx * nx + ny * ny
                if d > 1.0:
                    continue
                if rim and d > 0.72:
                    pts[(x, y)] = rim
                else:
                    pts[(x, y)] = self._tone(shades, 0.35 - nx * 0.45 - ny * 0.55, x, y, self.grit)
                normals[(x, y)] = TOP
        self._fill(pts, outline, normals)

    def contour(self, c=K, x0=0, y0=0, x1=None, y1=None, skip=()):
        """Recolours the outermost opaque pixels (the silhouette edge) to `c`,
        leaving coloured outlines between parts as they are."""
        x1 = self.w if x1 is None else x1
        y1 = self.h if y1 is None else y1
        edge = []
        for y in range(y0, y1):
            for x in range(x0, x1):
                cur = self.px[y][x]
                if cur is None or cur in skip:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = self.get(x + dx, y + dy) if (x0 <= x + dx < x1 and y0 <= y + dy < y1) else None
                    if n is None or n in skip:
                        edge.append((x, y))
                        break
        for x, y in edge:
            self.px[y][x] = c

    def despeckle(self, x0=0, y0=0, x1=None, y1=None):
        """Removes lone pixels: one that differs from all four neighbours, at
        least three of which agree, takes their colour."""
        x1 = self.w if x1 is None else x1
        y1 = self.h if y1 is None else y1
        fixes = []
        for y in range(y0 + 1, y1 - 1):
            for x in range(x0 + 1, x1 - 1):
                cur = self.px[y][x]
                if cur is None:
                    continue
                around = [self.px[y][x + 1], self.px[y][x - 1], self.px[y + 1][x], self.px[y - 1][x]]
                if cur in around:
                    continue
                for cand in set(around):
                    if cand is not None and around.count(cand) >= 3:
                        fixes.append((x, y, cand))
        for x, y, c in fixes:
            self.px[y][x] = c

    def outline(self, c=K, x0=0, y0=0, x1=None, y1=None, skip=()):
        x1 = self.w if x1 is None else x1
        y1 = self.h if y1 is None else y1
        todo = []
        for y in range(y0, y1):
            for x in range(x0, x1):
                if self.px[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = self.get(x + dx, y + dy)
                    if x0 <= x + dx < x1 and y0 <= y + dy < y1 and n is not None and n not in skip:
                        todo.append((x, y))
                        break
        for x, y in todo:
            self.px[y][x] = c


def _unit(x: float, y: float, z: float) -> tuple[float, float, float]:
    length = math.sqrt(x * x + y * y + z * z) or 1.0
    return (x / length, y / length, z / length)


# The view looks at the floor from the south and above, tilted VIEW_TILT from straight down.
VIEW_TILT = math.radians(37)


def to_floor(n: tuple[float, float, float]) -> tuple[float, float, float]:
    """A view-frame normal in Godot's 2D lighting frame: x east, y south (down the screen), z up off the floor.
    The canvas is the floor, so a table top (TOP) comes out as (0, 0, 1) and a front face leans south."""
    s, c = math.sin(VIEW_TILT), math.cos(VIEW_TILT)
    x, y, z = n
    return _unit(x, y * c + z * s, -y * s + z * c)


def normal_image(canvas: "Canvas"):
    """The canvas's normal map as a Pillow image: RGB = normal * 0.5 + 0.5 with green pointing up the
    screen (the OpenGL convention Godot reads), alpha = the colour sheet's coverage."""
    from PIL import Image
    im = Image.new("RGBA", (canvas.w, canvas.h), (128, 128, 255, 0))
    out = im.load()
    for y in range(canvas.h):
        for x in range(canvas.w):
            if canvas.px[y][x] is None:
                continue
            fx, fy, fz = to_floor(canvas.nrm[y][x] or FRONT)
            out[x, y] = (round(127.5 + fx * 127.5), round(127.5 - fy * 127.5), round(127.5 + fz * 127.5), 255)
    return im


def atelier_binary() -> str | None:
    found = shutil.which("atelier") or str(Path.home() / ".local" / "bin" / "atelier")
    return found if Path(found).exists() else None


def _call(binary, env, tool, args):
    done = subprocess.run([binary, "call", tool, "--stdin"], input=json.dumps(args), env=env,
                          capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"atelier {tool} failed:\n{done.stdout}\n{done.stderr}")
    return json.loads(done.stdout[done.stdout.index("{"):])


def paint(binary: str, canvas: Canvas, target: Path) -> None:
    """Paints the canvas into a fresh Atelier document and exports it to `target`.
    Wide sheets are painted in bands: one legend key per colour, per band."""
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, ATELIER_HOME=home)  # leave the user's own library alone
        doc = _call(binary, env, "doc_new", {"name": target.stem, "width": canvas.w, "height": canvas.h})
        y = 0
        while y < canvas.h:
            legend, rows = {}, []
            while y < canvas.h:
                row = canvas.px[y]
                fresh = {c for c in row if c is not None and c not in legend}
                if len(legend) + len(fresh) > len(KEYS):
                    break
                for c in sorted(fresh):
                    legend[c] = KEYS[len(legend)]
                rows.append("".join("." if c is None else legend[c] for c in row))
                y += 1
            if not rows:
                raise SystemExit(f"{target.name}: row {y} uses more than {len(KEYS)} colours")
            colours = {}
            for c, key in legend.items():
                rgba = [int(c[i:i + 2], 16) for i in range(1, len(c), 2)]
                colours[key] = rgba
            _call(binary, env, "doc_paint_grid", {"doc_id": doc["doc_id"], "layer": 0, "frame": 0, "x": 0,
                                                  "y": y - len(rows), "legend": colours, "rows": rows})
        _call(binary, env, "doc_export", {"doc_id": doc["doc_id"], "op": "sheet", "scale": 1,
                                          "out_path": str(target)})
    target.with_suffix(".json").unlink(missing_ok=True)
    print(f"  {target.relative_to(ROOT / 'assets' / 'sprites')}  {canvas.w}x{canvas.h}")


def rng_for(name: str) -> random.Random:
    return random.Random(name)
