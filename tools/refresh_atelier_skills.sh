#!/bin/bash
# Refreshes Atelier's own skills (atelier-sprite, atelier-scene, atelier-review)
# in .claude/skills/ from the installed Atelier, then re-adds this project's
# note to each so they keep pointing at our craft and project skills.
set -euo pipefail
cd "$(dirname "$0")/.."

atelier="$(command -v atelier || echo "$HOME/.local/bin/atelier")"
if [ ! -x "$atelier" ]; then
  echo "refresh_atelier_skills: atelier is not installed; nothing refreshed" >&2
  exit 0
fi
"$atelier" skills install --dir "$PWD/.claude/skills"

marker="## In this repository (REDLINE // 1989)"
for name in atelier-sprite atelier-scene atelier-review; do
  file=".claude/skills/$name/SKILL.md"
  [ -f "$file" ] || continue
  grep -qF "$marker" "$file" && continue
  cat >> "$file" <<EOF

$marker

This guide is Atelier's own and is generic. In this repository:

- Load the \`pixel-art-engineer\` skill first: it holds the craft rules all pixel art here is judged against.
- Then follow \`atelier-pixel-art\`: art that ships in the game is drawn by the scripts in \`tools/\`, at the
  scale and sheet layout the game expects. Its project rules take precedence over this guide.
- Use this guide for technique, and for one-off art drawn directly in Atelier.

(This section is added by \`tools/refresh_atelier_skills.sh\`.)
EOF
done
echo "refresh_atelier_skills: done"
