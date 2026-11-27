"""A small pixel-art renderer for code-drawn sprites that must pass Tandem's craft lint.

Parts are boolean masks painted back to front, each with its own colouring (shade by form).
`finish()` then draws the line art the way the top-down rules ask for it:
  * an outer contour one pixel outside the silhouette, 2 px on the heavy side of chosen parts;
  * inner contours where a part lies over another (head over shoulders, arm over body);
  * "pixel-perfect" thinning, so a contour never doubles at a turn (no L corners);
  * a tinted near-black instead of #000000.
"""
from __future__ import annotations

import numpy as np
from PIL import Image

INK = (28, 18, 24, 255)  # tinted near-black: dark plum-brown


def hexc(h: str) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


class Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.yy, self.xx = np.mgrid[0:h, 0:w].astype(float)
        self.col = np.zeros((h, w, 4), np.uint8)
        self.part = np.full((h, w), -1, np.int16)
        self.meta: list[dict] = []

    # ---- masks
    def ellipse(self, cx, cy, rx, ry):
        return ((self.xx + 0.5 - cx) / rx) ** 2 + ((self.yy + 0.5 - cy) / ry) ** 2 <= 1.0

    def seg(self, a, b, r):
        ax, ay = a
        bx, by = b
        px, py = self.xx + 0.5 - ax, self.yy + 0.5 - ay
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy or 1e-9
        t = np.clip((px * dx + py * dy) / ll, 0, 1)
        return (px - t * dx) ** 2 + (py - t * dy) ** 2 <= r * r

    def rect(self, x0, y0, x1, y1):
        return (self.xx >= x0) & (self.xx <= x1) & (self.yy >= y0) & (self.yy <= y1)

    # ---- painting
    def add(self, mask, colour, outline=True, heavy=None):
        """colour: an RGBA tuple, or fn(canvas, mask) -> HxWx4 array. heavy: a mask of pixels
        where this part's outer contour goes 2 px thick (its heavy side)."""
        idx = len(self.meta)
        self.meta.append({"outline": outline, "heavy": heavy})
        if callable(colour):
            arr = colour(self, mask)
            self.col[mask] = arr[mask]
        else:
            self.col[mask] = colour
        self.part[mask] = idx
        return idx

    def shade(self, base, dark, light=None, cx=0.0, cy=0.0, rx=1.0, ry=1.0, rim=0.68, crest=None):
        """Shade by form for an ellipse-like part: the rim darker, an optional crest lighter."""
        def fn(c, mask):
            out = np.zeros((c.h, c.w, 4), np.uint8)
            r2 = ((c.xx + 0.5 - cx) / rx) ** 2 + ((c.yy + 0.5 - cy) / ry) ** 2
            out[:] = hexc(base)
            out[r2 > rim] = hexc(dark)
            if light and crest is not None:
                out[crest(c, r2)] = hexc(light)
            return out
        return fn

    # ---- line art
    def finish(self, thin=True) -> Image.Image:
        part = self.part
        h, w = part.shape
        ink = np.zeros((h, w), bool)
        filled = part >= 0
        pad = np.pad(part, 1, constant_values=-1)
        n4 = [pad[0:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, 0:-2], pad[1:-1, 2:]]
        # outer contour: empty pixels touching the silhouette
        outer = (~filled) & np.any([n >= 0 for n in n4], axis=0)
        # inner contours: a part's own pixels where it touches a lower part
        inner = np.zeros((h, w), bool)
        for i, m in enumerate(self.meta):
            if not m["outline"]:
                continue
            mine = part == i
            touches_lower = np.any([(n >= 0) & (n < i) for n in n4], axis=0)
            inner |= mine & touches_lower
        # parts drawn without outline get none on their outer edge either
        no_line = np.zeros((h, w), bool)
        for i, m in enumerate(self.meta):
            if not m["outline"]:
                no_line |= np.any([n == i for n in n4], axis=0) & ~np.any([(n >= 0) & (n != i) & self._lined(n) for n in n4], axis=0)
        outer &= ~no_line
        ink = outer | inner
        # the heavy side: a second outer ring
        heavy = np.zeros((h, w), bool)
        for i, m in enumerate(self.meta):
            if m["heavy"] is not None:
                heavy |= m["heavy"]
        if heavy.any():
            pi = np.pad(outer, 1)
            touch = pi[0:-2, 1:-1] | pi[2:, 1:-1] | pi[1:-1, 0:-2] | pi[1:-1, 2:]
            ink |= (~filled) & (~outer) & touch & heavy
        if thin:
            ink = self._thin(ink, filled)
        img = self.col.copy()
        img[ink] = INK
        return Image.fromarray(img, "RGBA")

    def _lined(self, n):
        out = np.zeros(n.shape, bool)
        for i, m in enumerate(self.meta):
            if m["outline"]:
                out |= n == i
        return out

    @staticmethod
    def _thin(ink, filled):
        """Removes the corner pixel of every L turn in the contour (pixel-perfect), when the
        diagonal pixel across the turn is ink too or the pixel is outside the shape."""
        ink = ink.copy()
        h, w = ink.shape
        changed = True
        while changed:
            changed = False
            p = np.pad(ink, 1)
            up, dn, lf, rt = p[0:-2, 1:-1], p[2:, 1:-1], p[1:-1, 0:-2], p[1:-1, 2:]
            ul, ur, dl, dr = p[0:-2, 0:-2], p[0:-2, 2:], p[2:, 0:-2], p[2:, 2:]
            n = up.astype(int) + dn + lf + rt
            corner = ink & (n == 2) & (
                (up & rt & ~ur & ~dn & ~lf) | (up & lf & ~ul & ~dn & ~rt) |
                (dn & rt & ~dr & ~up & ~lf) | (dn & lf & ~dl & ~up & ~rt))
            # only thin outside the shape, and only a pixel that touches the fill diagonally:
            # removing one that sits beside the fill would open a gap in the contour
            fp = np.pad(filled, 1)
            side_fill = fp[0:-2, 1:-1] | fp[2:, 1:-1] | fp[1:-1, 0:-2] | fp[1:-1, 2:]
            corner &= ~filled & ~side_fill
            ys, xs = np.nonzero(corner)
            for y, x in zip(ys, xs):
                if not ink[y, x]:
                    continue
                # keep 8-connectivity: the two neighbours stay linked through the diagonal
                ink[y, x] = False
                changed = True
        return ink
