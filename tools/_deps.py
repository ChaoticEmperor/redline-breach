"""What an art tool does when a tool or library it needs is missing.

Locally a missing dependency is a skip: the tool says so and exits 0, and the game falls back to
its stand-in textures. In a Claude Code cloud session (CLAUDE_CODE_REMOTE=true) the session-start
hook installs everything, so a missing dependency is a broken setup: the tool exits 1, and the agent
cannot mistake "nothing drawn" for "redrawn".
"""
from __future__ import annotations

import os
import sys


def skip(message: str) -> int:
    """Reports a missing dependency; returns the exit code to use."""
    if os.environ.get("CLAUDE_CODE_REMOTE") == "true":
        print(f"{message} (cloud session: this is a setup error, see .claude/hooks/session-start.sh)",
              file=sys.stderr)
        return 1
    print(message)
    return 0
