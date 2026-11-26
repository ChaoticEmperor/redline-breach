"""Put a sprite sheet into a Tandem sprite, one cell per frame, so it can be played, linted and
hand-painted there (Tandem: ~/PersonalProjects/tandem, http://localhost:7480).

    python3 tools/tandem_push.py sheet.png <sprite-id> --cell 112 [--ms 125,125,...] [--lint]

Makes the sprite if it is missing, replaces its palette with the sheet's colours (locked),
gives it as many frames as the sheet has cells, and paints every frame. With --lint it prints
Tandem's lint per frame. Paints only sprites this tool made or that you name: never "main".
"""
from __future__ import annotations

import argparse
import json
import os
import urllib.request
from collections import Counter

from PIL import Image

URL = os.environ.get("TANDEM_URL", "http://localhost:7480")
AUTHOR = os.environ.get("TANDEM_AUTHOR", "flora")
LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


def call(path, body=None):
    req = urllib.request.Request(URL + path, method="POST" if body is not None else "GET")
    data = None
    if body is not None:
        body = dict(body, author=AUTHOR)
        data = json.dumps(body).encode()
        req.add_header("content-type", "application/json")
    with urllib.request.urlopen(req, data, timeout=30) as r:
        return json.loads(r.read() or b"{}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("sprite")
    ap.add_argument("--cell", type=int, required=True)
    ap.add_argument("--ms", default="", help="comma-separated frame times; default 100 ms each")
    ap.add_argument("--lint", action="store_true")
    a = ap.parse_args()
    if a.sprite in ("main", "courier-walk"):
        raise SystemExit("not painting a sprite someone else made")
    sheet = Image.open(a.sheet).convert("RGBA")
    n = sheet.width // a.cell
    cols = [c for c, _ in Counter("#%02x%02x%02x" % p[:3] for p in sheet.getdata() if p[3]).most_common()]
    if len(cols) > len(LETTERS):
        raise SystemExit(f"{len(cols)} colours: more than the text format's {len(LETTERS)} letters")
    ids = [d["id"] for d in call("/api/docs")]
    if a.sprite not in ids:
        call("/api/docs", {"name": a.sprite, "width": a.cell, "height": a.cell})
    d = f"/api/d/{a.sprite}"
    call(f"{d}/palette", {"locked": False})
    call(f"{d}/palette", {"colors": cols})
    call(f"{d}/palette", {"locked": True})
    have = len(call(f"{d}/canvas").get("frames", [None]))
    for _ in range(have, n):
        call(f"{d}/frames", {"add": {}})
    ms = [int(v) for v in a.ms.split(",") if v]
    idx = {c: LETTERS[i] for i, c in enumerate(cols)}
    for f in range(n):
        cell = sheet.crop((f * a.cell, 0, (f + 1) * a.cell, a.cell))
        px = cell.load()
        rows = ["".join(idx["#%02x%02x%02x" % px[x, y][:3]] if px[x, y][3] else "_" for x in range(a.cell))
                for y in range(a.cell)]
        call(f"{d}/rows", {"x": 0, "y": 0, "rows": rows, "frame": f})
        if f < len(ms):
            call(f"{d}/frames", {"set": {"index": f, "duration": ms[f]}})
        if a.lint:
            r = call(f"{d}/lint?frame={f}")
            c = r.get("counts", {})
            print(f"frame {f:2}: " + ", ".join(f"{k} {v}" for k, v in sorted(c.items())) + f", strayShare {r.get('strayShare')}")
    print(f"{a.sprite}: {n} frames, {len(cols)} colours")


if __name__ == "__main__":
    main()
