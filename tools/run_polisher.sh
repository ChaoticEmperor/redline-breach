#!/usr/bin/env bash
# Visual polisher loop: capture the game, audit the sprites, diff the captures
# against the concept references and write a brief of the largest gaps.
#
#   tools/run_polisher.sh [label] [view ...]
#
#   label   keeps a copy of this run in tools/out/<label>/ (e.g. `baseline`).
#           Any later run with another label gets a Before column from
#           tools/out/baseline/ in the brief.
#   views   default: entry dancefloor (see tools/capture_views.gd)
#
# Outputs (git-ignored) in tools/out/: actual_<view>.png + .json,
# sprites_contact.png, asset_report.json, diff_report.png, diff_summary.json,
# polish_brief.md. Acting on the brief is left to whoever runs this.
set -u
cd "$(dirname "$0")/.."

LABEL="${1:-}"
[ $# -gt 0 ] && shift
VIEWS=("$@")
[ ${#VIEWS[@]} -eq 0 ] && VIEWS=(entry dancefloor)
OUT=tools/out
SIZE="${POLISHER_SIZE:-1920x1080}"
GODOT="${GODOT:-godot}"

mkdir -p "$OUT"
touch "$OUT/.gdignore" # Godot must not import the captures

# 1. Frame capture: the real renderer on a virtual display.
if ! command -v xvfb-run >/dev/null 2>&1; then
	echo "run_polisher: xvfb-run not found (apt-get install xvfb); capture skipped, existing actual_*.png are reused."
elif ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "run_polisher: $GODOT not found; capture skipped, existing actual_*.png are reused."
else
	[ -d .godot ] || "$GODOT" --headless --import >/dev/null 2>&1
	rm -f "$OUT"/actual_*.png "$OUT"/actual_*.json
	xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT" --path . --rendering-driver opengl3 --resolution "$SIZE" \
		-s tools/capture_views.gd -- "$OUT" "${VIEWS[@]}" "$SIZE" 2>&1 \
		| grep -E "capture_views|SCRIPT ERROR|Parse Error" || echo "run_polisher: the capture printed nothing; check godot and xvfb."
fi

# 2. Asset audit, visual diff and brief.
BASE=()
[ -n "$LABEL" ] && [ "$LABEL" != baseline ] && [ -d "$OUT/baseline" ] && BASE=(--baseline "$OUT/baseline")
python3 tools/asset_slicer_diff.py all --out "$OUT" "${BASE[@]}"

# 3. Keep this run under its label.
if [ -n "$LABEL" ]; then
	rm -rf "${OUT:?}/$LABEL"
	mkdir -p "$OUT/$LABEL"
	find "$OUT" -maxdepth 1 -type f ! -name .gdignore -exec cp {} "$OUT/$LABEL/" \;
	echo "run_polisher: kept a copy in $OUT/$LABEL/"
fi
echo "run_polisher: brief at $OUT/polish_brief.md"
