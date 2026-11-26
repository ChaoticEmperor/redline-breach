#!/usr/bin/env python3
"""Asset slicer + visual differ for the polisher loop (tools/run_polisher.sh).

    python3 tools/asset_slicer_diff.py            # audit + diff + brief
    python3 tools/asset_slicer_diff.py audit      # sprites only
    python3 tools/asset_slicer_diff.py diff       # captures vs references only
    python3 tools/asset_slicer_diff.py brief      # polish_brief.md from the two JSON files

audit  Slices every sprite and sheet in assets/sprites/ and assets/raw/ into
       cells (64x64 grid for the character sheet, the rectangles listed in
       scripts/prop_atlas.gd for the props sheet, green-screen blobs for the
       raw sheets), measures each one and flags the empty, tiny and clipped.
       -> tools/out/sprites_contact.png, tools/out/asset_report.json
diff   Compares tools/out/actual_*.png (tools/capture_views.gd) with
       tools/ref/ref_*.png on brightness, contrast, edges and colour balance.
       -> tools/out/diff_report.png, tools/out/diff_summary.json
brief  Ranks the largest gaps into tools/out/polish_brief.md.

Needs Pillow and numpy only. Deterministic. Anything missing is skipped with a
message and the exit code stays 0.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import deque
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    from _deps import skip
    sys.exit(skip("asset_slicer_diff: Pillow and numpy are needed (pip install Pillow numpy); nothing done."))

ROOT = Path(__file__).resolve().parent.parent
CHAR_SHEET = "assets/sprites/chars/sheet_characters_v2.png"
PROP_SHEET = "assets/sprites/props/sheet_props_v2.png"
CELL = 64                   # one pose in the character sheet
TINY_PX = 4                 # a bounding box narrower or shorter than this is "tiny"
TINY_COVERAGE = 0.01        # ... as is a cell with less than 1% of its pixels opaque
COMMON = (480, 270)         # every screenshot is measured at this size
BLOCK = 16                  # local contrast block, in pixels of the common size

# Player figure height as a share of the image height in each reference.
# Estimated by eye from the concept art, not measured.
REF_CHAR_RATIO = {"ref_nightclub": 0.12, "ref_motel": 0.11, "ref_subway": 0.10}
# View name -> reference it is like for like with. Anything else, unless a
# reference carries the view's own name, is compared with DEFAULT_REF.
PAIRS = {"dancefloor": "ref_nightclub"}
DEFAULT_REF = "ref_nightclub"

# metric key -> (label, is a percentage, what to turn when the game is under / over the reference)
METRICS = {
    "brightness": ("average brightness", False, "raise AMBIENT and room light energy", "lower AMBIENT or light energy"),
    "near_black_pct": ("near-black % (lum < 0.10)", True, "less light spill: smaller pools, darker ambient", "raise AMBIENT, widen room light pools"),
    "bright_pct": ("bright highlight % (lum > 0.6)", True, "stronger self-lit accents: dancefloor tiles, neon, prop glows", "tone down light energy and over-bright modulates"),
    "edge_density_pct": ("strong-edge density %", True, "more light on detail, larger on-screen sprites (zoom), busier floors", "less zoom or flatter lighting"),
    "local_contrast": ("local contrast (16 px block std)", False, "more light on detail, larger on-screen sprites (zoom)", "flatter lighting"),
    "vivid_pct": ("vivid pixels % (sat > 0.35, val > 0.25)", True, "more saturated light colours and tile pulses", "desaturate light colours"),
    "purple_magenta_pct": ("purple/magenta share of vivid %", True, "shift light tints toward magenta/purple", "shift light tints away from magenta"),
    "pink_red_pct": ("pink/red share of vivid %", True, "more pink/red in lights and dance tiles", "less pink/red in lights"),
    "cyan_blue_pct": ("cyan/blue share of vivid %", True, "more cyan/blue accents", "shift cyan/blue lights toward magenta"),
    "char_height_ratio": ("character height / viewport height", False, "raise the camera ZOOM", "lower the camera ZOOM"),
}


def say(msg: str) -> None:
    print("asset_slicer_diff: " + msg)


def font() -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default(11)
    except TypeError:  # older Pillow
        return ImageFont.load_default()


# ---------------------------------------------------------------- audit

def key_green(im: Image.Image) -> np.ndarray:
    """RGBA array of a raw sheet with the #00FF00 screen made transparent."""
    a = np.asarray(im.convert("RGB")).astype(np.int16)
    green = a[..., 1] - np.maximum(a[..., 0], a[..., 2])
    out = np.dstack([a, np.where(green > 90, 0, 255)]).astype(np.uint8)
    return out


def blobs(alpha: np.ndarray, grid: int = 8) -> list[tuple[int, int, int, int]]:
    """Bounding boxes (x0, y0, x1, y1) of connected opaque regions, found on a reduced mask."""
    h, w = alpha.shape
    gh, gw = h // grid, w // grid
    small = alpha[:gh * grid, :gw * grid].reshape(gh, grid, gw, grid).max(axis=(1, 3)) > 0
    seen = np.zeros_like(small)
    out = []
    for y, x in zip(*np.nonzero(small)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        queue = deque([(y, x)])
        x0 = x1 = x
        y0 = y1 = y
        while queue:
            cy, cx = queue.popleft()
            x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
            for ny in (cy - 1, cy, cy + 1):
                for nx in (cx - 1, cx, cx + 1):
                    if 0 <= ny < gh and 0 <= nx < gw and small[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
        out.append((int(x0) * grid, int(y0) * grid, int(x1 + 1) * grid, int(y1 + 1) * grid))
    out.sort(key=lambda b: (b[1] // 200, b[0]))
    return out


def dominant(rgb: np.ndarray, n: int = 4) -> list[dict]:
    """The `n` most common colours of an (N, 3) pixel array, as hex with their share."""
    if len(rgb) == 0:
        return []
    strip = Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8), "RGB")
    q = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()
    counts = sorted(q.getcolors(), reverse=True)
    return [{"hex": "#%02x%02x%02x" % tuple(pal[i * 3:i * 3 + 3]), "share": round(c / len(rgb), 3)} for c, i in counts]


def measure(cell: np.ndarray) -> dict:
    """Bounding box, alpha coverage, edge contact and dominant colours of an RGBA cell."""
    h, w = cell.shape[:2]
    mask = cell[..., 3] > 16
    out = {"size": [w, h], "coverage": round(float(mask.mean()), 4), "bbox": None, "touches": [], "colors": []}
    if not mask.any():
        return out
    ys, xs = np.nonzero(mask)
    out["bbox"] = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
    for side, line in (("left", mask[:, 0]), ("top", mask[0]), ("right", mask[:, -1]), ("bottom", mask[-1])):
        if line.any():
            out["touches"].append(side)
    out["colors"] = dominant(cell[..., :3][mask])
    return out


def char_cells(root: Path) -> dict:
    """(row, column) -> "who/animation" for every cell the game plays, from ANIMS in fx.gd."""
    used = {}
    src = root / "scripts" / "fx.gd"
    if not src.exists():
        return used
    block = re.search(r"const ANIMS := \{(.*?)\n\}", src.read_text(), re.S)
    if not block:
        return used
    for who, row, anims in re.findall(r'"(\w+)": \[(\d+), \{(.*?)\}\]', block.group(1)):
        for anim, first, count in re.findall(r'"(\w+)": \[(\d+), (\d+)', anims):
            for i in range(int(count)):
                used[(int(row), int(first) + i)] = "%s/%s" % (who, anim)
    return used


def prop_rects(root: Path) -> dict:
    """name -> (x, y, w, h) from the generated scripts/prop_atlas.gd."""
    src = root / "scripts" / "prop_atlas.gd"
    if not src.exists():
        return {}
    return {name: tuple(int(v) for v in nums.split(",")[:4])
            for name, nums in re.findall(r'"(\w+)": \[([\d, ]+)\]', src.read_text())}


def audit(root: Path, out: Path) -> dict | None:
    sprites = root / "assets" / "sprites"
    raw = root / "assets" / "raw"
    entries = []  # {id, source, kind, cell (RGBA array), severity, flags, ...measure}

    def add(ident: str, source: str, kind: str, cell: np.ndarray, clip: str, used: bool = True, note: str = "") -> None:
        m = measure(cell)
        flags = []
        severity = "ok"
        if m["bbox"] is None:
            flags.append("empty" if used else "empty (unused cell)")
            severity = "error" if used else "info"
        else:
            bw, bh = m["bbox"][2] - m["bbox"][0], m["bbox"][3] - m["bbox"][1]
            if min(bw, bh) < TINY_PX or m["coverage"] < TINY_COVERAGE:
                flags.append("tiny")
                severity = "warn"
            if m["touches"] and clip != "skip":
                # Character feet stand on the bottom row of their cell, so contact
                # there alone is only noted; the sides and top mean a cut pose.
                feet = clip == "warn" and m["touches"] == ["bottom"]
                flags.append("feet on the bottom edge" if feet else "clipped: " + "/".join(m["touches"]))
                severity = "warn" if clip == "warn" and not feet else (severity if severity != "ok" else "info")
            if not used:
                flags.append("drawn but not played by any animation")
                severity = severity if severity != "ok" else "info"
        entries.append({"id": ident, "source": source, "kind": kind, "severity": severity, "flags": flags,
                        "note": note, "_cell": cell, **m})

    if sprites.exists():
        rects = prop_rects(root)
        used = char_cells(root)
        for path in sorted(sprites.rglob("*.png")):
            rel = path.relative_to(root).as_posix()
            im = np.asarray(Image.open(path).convert("RGBA"))
            if rel == CHAR_SHEET:
                for r in range(im.shape[0] // CELL):
                    for c in range(im.shape[1] // CELL):
                        add("chars[%d,%d] %s" % (r, c, used.get((r, c), "")), rel, "character cell",
                            im[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL], "warn", (r, c) in used)
            elif rel == PROP_SHEET:
                if not rects:
                    say("scripts/prop_atlas.gd not found or empty; props sheet not sliced")
                for name, (x, y, w, h) in rects.items():
                    # Props are packed tightly and tile against their neighbours, so
                    # touching the rectangle is by design; it is reported as info only.
                    add("prop " + name, rel, "prop rect", im[y:y + h, x:x + w], "info",
                        note="atlas rectangles are tight by design")
            else:
                kind = "floor tile" if "/floors/" in rel else "sprite"
                add(path.stem, rel, kind, im, "skip", note="trimmed single sprite; edge contact is not checked")
    else:
        say("assets/sprites/ not found; sprite audit skipped")

    if raw.exists():
        for path in sorted(raw.glob("*.png")):
            rel = path.relative_to(root).as_posix()
            im = key_green(Image.open(path))
            if (im[..., 3] > 0).all():
                say("%s has no #00FF00 screen; audited as one image" % rel)
            for i, (x0, y0, x1, y1) in enumerate(blobs(im[..., 3])):
                cell = im[y0:y1, x0:x1]
                edge = x0 == 0 or y0 == 0 or x1 >= im.shape[1] - 8 or y1 >= im.shape[0] - 8
                speck = (x1 - x0) * (y1 - y0) < 48 * 48
                add("%s#%d" % (path.stem, i), rel, "raw blob", cell, "skip",
                    note="raw green-screen sheet, box %d,%d-%d,%d" % (x0, y0, x1, y1))
                e = entries[-1]
                if speck:
                    e["flags"], e["severity"] = ["speck or watermark (dropped by slice_sheets.py)"], "info"
                elif edge:
                    e["flags"].append("clipped: touches the sheet edge")
                    e["severity"] = "warn"
    else:
        say("assets/raw/ not found; raw sheets skipped")

    if not entries:
        say("no sprites found; no contact sheet or asset report written")
        return None

    # Contact sheet: every cell on a dark tile, bordered by severity.
    tile, label_h, cols = 96, 26, 12
    f = font()
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tile + 8) + 8, rows * (tile + label_h + 8) + 8), (18, 14, 26))
    draw = ImageDraw.Draw(sheet)
    border = {"ok": (60, 54, 80), "info": (70, 110, 150), "warn": (240, 200, 40), "error": (255, 50, 60)}
    for i, e in enumerate(entries):
        x = 8 + (i % cols) * (tile + 8)
        y = 8 + (i // cols) * (tile + label_h + 8)
        draw.rectangle([x, y, x + tile - 1, y + tile - 1], fill=(40, 34, 56), outline=border[e["severity"]], width=2)
        cell = Image.fromarray(e.pop("_cell"), "RGBA")
        k = min((tile - 8) / cell.width, (tile - 8) / cell.height)
        size = (max(1, int(cell.width * k)), max(1, int(cell.height * k)))
        cell = cell.resize(size, Image.NEAREST if k >= 1 else Image.LANCZOS)
        sheet.paste(cell, (x + (tile - size[0]) // 2, y + (tile - size[1]) // 2), cell)
        draw.text((x, y + tile + 1), e["id"][:17], fill=(220, 220, 235), font=f)
        tag = "; ".join(e["flags"])[:18] if e["flags"] else "%d%% opaque" % round(e["coverage"] * 100)
        draw.text((x, y + tile + 13), tag, fill=border[e["severity"]] if e["flags"] else (130, 125, 150), font=f)
    out.mkdir(parents=True, exist_ok=True)
    sheet.save(out / "sprites_contact.png")

    counts = {s: sum(1 for e in entries if e["severity"] == s) for s in ("ok", "info", "warn", "error")}
    report = {
        "counts": counts,
        "severity": {"error": "a cell the game plays is empty", "warn": "tiny, or opaque pixels touch the cell edge",
                     "info": "expected: unused cells, tight atlas rectangles, raw-sheet specks"},
        "flagged": [e for e in entries if e["severity"] in ("warn", "error")],
        "sprites": entries,
    }
    (out / "asset_report.json").write_text(json.dumps(report, indent=1) + "\n")
    say("audit: %d cells (%d ok, %d info, %d warn, %d error) -> %s, %s" % (
        len(entries), counts["ok"], counts["info"], counts["warn"], counts["error"],
        (out / "sprites_contact.png").relative_to(root), (out / "asset_report.json").relative_to(root)))
    return report


# ---------------------------------------------------------------- diff

def load_common(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB").resize(COMMON, Image.LANCZOS)).astype(np.float64) / 255.0


def metrics(a: np.ndarray) -> dict:
    """Brightness, contrast, edge and colour-balance figures of an RGB float image."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    gy, gx = np.gradient(lum)
    h, w = lum.shape
    blocks = lum[:h // BLOCK * BLOCK, :w // BLOCK * BLOCK].reshape(h // BLOCK, BLOCK, w // BLOCK, BLOCK)
    mx, mn = a.max(axis=2), a.min(axis=2)
    d = mx - mn
    sat = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0.0)
    safe = np.maximum(d, 1e-9)
    hue = np.where(mx == r, ((g - b) / safe) % 6.0, np.where(mx == g, (b - r) / safe + 2.0, (r - g) / safe + 4.0)) * 60.0
    vivid = (sat > 0.35) & (mx > 0.25)
    n = max(int(vivid.sum()), 1)
    hv = hue[vivid]
    purple = float(((hv >= 260) & (hv < 320)).sum()) / n * 100
    pink = float(((hv >= 320) | (hv < 20)).sum()) / n * 100
    cyan = float(((hv >= 170) & (hv < 260)).sum()) / n * 100
    return {
        "brightness": round(float(lum.mean()), 4),
        "near_black_pct": round(float((lum < 0.10).mean()) * 100, 2),
        "bright_pct": round(float((lum > 0.6).mean()) * 100, 2),
        "edge_density_pct": round(float((np.hypot(gx, gy) > 0.08).mean()) * 100, 2),
        "local_contrast": round(float(blocks.std(axis=(1, 3)).mean()), 4),
        "vivid_pct": round(float(vivid.mean()) * 100, 2),
        "purple_magenta_pct": round(purple, 2),
        "pink_red_pct": round(pink, 2),
        "cyan_blue_pct": round(cyan, 2),
        "other_hue_pct": round(max(0.0, 100 - purple - pink - cyan), 2),
    }


def fmt(key: str, v) -> str:
    if v is None:
        return "n/a"
    if key == "char_height_ratio":
        return "%.1f%%" % (v * 100)
    return "%.1f%%" % v if METRICS[key][1] else "%.3f" % v


def diff(root: Path, out: Path, ref_dir: Path) -> dict | None:
    actuals = sorted(out.glob("actual_*.png"))
    refs = {p.stem: p for p in sorted(ref_dir.glob("ref_*.png"))}
    if not actuals:
        say("no %s/actual_*.png (run tools/run_polisher.sh to capture); visual diff skipped" % out.relative_to(root))
        return None
    if not refs:
        say("no ref_*.png in %s; visual diff skipped" % ref_dir)
        return None
    ref_m = {}
    for name, path in refs.items():
        ref_m[name] = metrics(load_common(path))
        ref_m[name]["char_height_ratio"] = REF_CHAR_RATIO.get(name)
    fallback = DEFAULT_REF if DEFAULT_REF in refs else next(iter(refs))

    pairs = []
    for path in actuals:
        view = path.stem[len("actual_"):]
        ref = next((r for r in refs if view.startswith(r[len("ref_"):])), None)  # a reference of the same name
        if ref is None:
            ref = next((r for v, r in PAIRS.items() if view.startswith(v) and r in refs), fallback)
        img = load_common(path)
        m = metrics(img)
        side = path.with_suffix(".json")
        m["char_height_ratio"] = None
        if side.exists():
            m["char_height_ratio"] = round(float(json.loads(side.read_text()).get("char_height_ratio", 0.0)), 4) or None
        delta = {k: (round(m[k] - ref_m[ref][k], 4) if m.get(k) is not None and ref_m[ref].get(k) is not None else None)
                 for k in METRICS}
        pairs.append({"view": view, "actual": path.relative_to(root).as_posix(),
                      "reference": refs[ref].relative_to(root).as_posix(), "reference_name": ref,
                      "actual_metrics": m, "reference_metrics": ref_m[ref], "delta": delta, "_img": img})

    # Side-by-side strip per pair: reference | actual | dominant-colour bars and figures.
    f = font()
    tw, th = COMMON
    pad, text_w = 10, 430
    row_h = th + 2 * pad + 16
    strip = Image.new("RGB", (2 * tw + text_w + 4 * pad, row_h * len(pairs)), (18, 14, 26))
    draw = ImageDraw.Draw(strip)
    for i, p in enumerate(pairs):
        y = i * row_h + pad
        ref_img = load_common(refs[p["reference_name"]])
        for j, (img, label) in enumerate(((ref_img, "reference: " + p["reference_name"]), (p.pop("_img"), "actual: " + p["view"]))):
            x = pad + j * (tw + pad)
            draw.text((x, y), label, fill=(230, 230, 240), font=f)
            strip.paste(Image.fromarray((img * 255).astype(np.uint8), "RGB"), (x, y + 16))
        x = 3 * pad + 2 * tw
        for j, (img, label) in enumerate(((ref_img, "ref"), (load_common(root / p["actual"]), "act"))):
            by = y + 16 + j * 26
            draw.text((x, by + 5), label, fill=(200, 200, 215), font=f)
            bx = x + 30
            cols = dominant((img.reshape(-1, 3) * 255).astype(np.uint8), 8)
            p.setdefault("dominant_colors", {})["reference" if j == 0 else "actual"] = cols
            for c in cols:
                wpx = max(1, round(c["share"] * (text_w - 40)))
                draw.rectangle([bx, by, bx + wpx - 1, by + 20], fill=c["hex"])
                bx += wpx
        ty = y + 16 + 60
        draw.text((x, ty), "%-34s %8s %8s" % ("metric", "ref", "actual"), fill=(160, 155, 180), font=f)
        for n, key in enumerate(METRICS):
            rv, av = p["reference_metrics"].get(key), p["actual_metrics"].get(key)
            line = "%-34s %8s %8s" % (METRICS[key][0][:34], fmt(key, rv), fmt(key, av))
            draw.text((x, ty + 15 * (n + 1)), line, fill=(225, 225, 235), font=f)
    strip.save(out / "diff_report.png")

    summary = {
        "common_size": list(COMMON),
        "note": "Reference char_height_ratio values are estimates read off the concept art; "
                "actual values come from the capture sidecar JSON (52 sheet px * ART_SCALE * camera zoom / viewport height).",
        "thresholds": {"near_black": "luminance < 0.10", "bright": "luminance > 0.6",
                       "strong_edge": "luminance gradient magnitude > 0.08", "local_contrast": "mean std of luminance in 16 px blocks",
                       "vivid": "saturation > 0.35 and value > 0.25",
                       "hues": "purple/magenta 260-320, pink/red 320-20, cyan/blue 170-260 (shares of the vivid pixels)"},
        "references": ref_m,
        "pairs": pairs,
    }
    (out / "diff_summary.json").write_text(json.dumps(summary, indent=1) + "\n")
    say("diff: %d capture(s) vs %d reference(s) -> %s, %s (reference character ratios are estimates)" % (
        len(pairs), len(refs), (out / "diff_report.png").relative_to(root), (out / "diff_summary.json").relative_to(root)))
    for p in pairs:
        print("  %s vs %s" % (p["view"], p["reference_name"]))
        for key in METRICS:
            print("    %-40s ref %8s  actual %8s" % (METRICS[key][0], fmt(key, p["reference_metrics"].get(key)),
                                                      fmt(key, p["actual_metrics"].get(key))))
    return summary


# ---------------------------------------------------------------- brief

def brief(root: Path, out: Path, baseline: Path | None) -> None:
    summary_path, report_path = out / "diff_summary.json", out / "asset_report.json"
    if not summary_path.exists() and not report_path.exists():
        say("no diff_summary.json or asset_report.json in %s; brief skipped" % out)
        return
    lines = ["# Polish brief", "",
             "Generated by `tools/run_polisher.sh`. Largest gaps between the captured views and the concept",
             "references first; act on tuning values (see CLAUDE.md, *Visual polisher*), then re-run.", ""]
    before = {}
    if baseline and (baseline / "diff_summary.json").exists() and baseline.resolve() != out.resolve():
        before = {p["view"]: p["actual_metrics"] for p in json.loads((baseline / "diff_summary.json").read_text())["pairs"]}
    if summary_path.exists():
        summary = json.loads(summary_path.read_text())
        for p in summary["pairs"]:
            ref, act = p["reference_metrics"], p["actual_metrics"]
            gaps = []
            for key, (label, _pct, under, over) in METRICS.items():
                if ref.get(key) is None or act.get(key) is None:
                    continue
                d = act[key] - ref[key]
                rel = abs(d) / max(abs(ref[key]), 1e-6)
                gaps.append((rel, key, label, d, under if d < 0 else over))
            gaps.sort(reverse=True)
            lines += ["## View `%s` vs `%s`" % (p["view"], p["reference_name"]), "", "Top deltas:", ""]
            for rel, key, label, d, hint in gaps[:6]:
                if rel < 0.05:
                    continue
                lines.append("- **%s**: %s vs reference %s (%s by %.0f%%) -> %s." % (
                    label, fmt(key, act[key]), fmt(key, ref[key]), "under" if d < 0 else "over", rel * 100, hint))
            b = before.get(p["view"])
            lines += ["", "| Metric | Reference | %sActual |" % ("Before | " if b else ""),
                      "| --- | --- | %s--- |" % ("--- | " if b else "")]
            for key, (label, *_rest) in METRICS.items():
                lines.append("| %s | %s | %s%s |" % (label, fmt(key, ref.get(key)),
                                                    (fmt(key, b.get(key)) + " | ") if b else "", fmt(key, act.get(key))))
            lines.append("")
        lines += ["Reference character ratios are estimates. Captures: `%s`; strip: `%s`." % (
            ", ".join(p["actual"] for p in summary["pairs"]), (out / "diff_report.png").relative_to(root).as_posix()), ""]
    else:
        lines += ["No captures were compared (no `actual_*.png`; is `xvfb-run` installed?).", ""]
    if report_path.exists():
        report = json.loads(report_path.read_text())
        lines += ["## Flagged assets", "", "Counts: " + ", ".join("%d %s" % (v, k) for k, v in report["counts"].items()) + ".", ""]
        if report["flagged"]:
            for e in report["flagged"]:
                lines.append("- `%s` (%s, %s): %s" % (e["id"].strip(), e["source"], e["severity"], "; ".join(e["flags"])))
        else:
            lines.append("- Nothing at warn or error level.")
        lines += ["", "Contact sheet: `%s`. Fix art through its tool in `tools/`, never by hand." % (
            (out / "sprites_contact.png").relative_to(root).as_posix()), ""]
    (out / "polish_brief.md").write_text("\n".join(lines))
    say("brief -> %s" % (out / "polish_brief.md").relative_to(root))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", default="all", choices=["all", "audit", "diff", "brief"],
                    help="what to run (default: all)")
    ap.add_argument("--root", type=Path, default=ROOT, help="project root (default: the repo this file is in)")
    ap.add_argument("--out", type=Path, help="output directory, also where actual_*.png are read (default: tools/out)")
    ap.add_argument("--ref", type=Path, help="reference directory holding ref_*.png (default: tools/ref)")
    ap.add_argument("--baseline", type=Path, help="an earlier output directory, for a Before column in the brief")
    args = ap.parse_args()
    root = args.root.resolve()
    out = (args.out or root / "tools" / "out").resolve()
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").touch()  # Godot must not import anything in here
    if args.command in ("all", "audit"):
        audit(root, out)
    if args.command in ("all", "diff"):
        diff(root, out, (args.ref or root / "tools" / "ref").resolve())
    if args.command in ("all", "brief"):
        brief(root, out, args.baseline.resolve() if args.baseline else None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
