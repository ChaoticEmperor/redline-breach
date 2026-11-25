#!/bin/bash
# SessionStart hook for Claude Code cloud sessions: installs the tools this
# project needs that a fresh container does not have.
#   - Godot 4.7.2 (headless checks: import, parse check, smoke test)
#   - Atelier (pixel-art CLI used by tools/draw_*.py and the atelier-* skills)
#   - numpy + Pillow (tools/convert_reference.py, draw_weapons.py, slice_sheets.py, the polisher)
# Each tool is installed only when missing, so later starts cost nothing.
# A failed download warns and carries on: a session without a tool is still
# usable, a session that never starts is not.
set -uo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="$(tr -d '[:space:]' < "${CLAUDE_PROJECT_DIR:-.}/.godot-version")-stable"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
warn() { echo "session-start: $*" >&2; }

# --- Godot engine (export templates are 1.2 GB and are left out; see CLAUDE.md)
if ! command -v godot >/dev/null 2>&1 && [ ! -x "$BIN/godot" ]; then
  tmp="$(mktemp -d)"
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  if curl -fsSL --retry 2 -o "$tmp/godot.zip" "$url" && unzip -oq "$tmp/godot.zip" -d "$tmp"; then
    mv "$tmp/Godot_v${GODOT_VERSION}_linux.x86_64" "$BIN/godot"
    chmod +x "$BIN/godot"
  else
    warn "could not install Godot ${GODOT_VERSION}; the checks in CLAUDE.md will not run"
  fi
  rm -rf "$tmp"
fi

# --- Atelier. Its installer verifies the download against the release checksums.
# The options keep it from editing shell profiles or registering itself with agents.
if ! command -v atelier >/dev/null 2>&1 && [ ! -x "$BIN/atelier" ]; then
  tmp="$(mktemp -d)"
  if curl -fsSL --retry 2 -o "$tmp/install.sh" \
      "https://github.com/marmikshah/atelier/releases/latest/download/install.sh" \
      && ATELIER_NO_MODIFY_PATH=1 ATELIER_NO_CONNECT=1 sh "$tmp/install.sh" >/dev/null 2>&1; then
    :
  else
    warn "could not install Atelier; tools/draw_*.py will skip drawing"
  fi
  rm -rf "$tmp"
fi

# --- Python libraries for the art tools. Without them the tools exit 1 in a
# cloud session (tools/_deps.py), so a failure here shows up when they run.
if ! python3 -c "import numpy, PIL" >/dev/null 2>&1; then
  python3 -m pip install --quiet --user numpy Pillow >/dev/null 2>&1 \
    || python3 -m pip install --quiet --user --break-system-packages numpy Pillow >/dev/null 2>&1 \
    || warn "could not install numpy/Pillow; the art tools will refuse to run"
fi

# Put the tools on PATH for the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
exit 0
