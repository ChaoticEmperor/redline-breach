---
name: atelier-pixel-art
description: Draw or change small pixel-art sprites for REDLINE // 1989 with the Atelier CLI (weapons, HUD icons, pickups, decals, animation frames, pixel fonts). Use when asked to draw, redraw, tweak or animate a sprite or icon, when adding a new weapon or pickup, or when a texture is still a plain procedural placeholder. Not for the Gemini sprite sheets (use tools/slice_sheets.py) or for lighting and effects (procedural in fx.gd).
---

# Drawing pixel art with Atelier

Atelier (https://github.com/marmikshah/atelier) is an offline pixel-art editor with no GUI. You draw by
calling its tools from the shell; it does not generate art, you place the pixels. In this project every
drawing lives as a character grid in a Python script, so it is reviewable and can be regenerated.

## 1. Make sure Atelier is installed

It is not present in a fresh cloud session.

```sh
command -v atelier || ls ~/.local/bin/atelier
```

If it is missing, ask the user before installing (the project's README says its code has had no line-by-line
human review). Install without touching shell profiles or agent config:

```sh
curl -fsSL -o /tmp/atelier-install.sh https://github.com/marmikshah/atelier/releases/latest/download/install.sh
ATELIER_NO_MODIFY_PATH=1 ATELIER_NO_CONNECT=1 sh /tmp/atelier-install.sh   # installs ~/.local/bin/atelier
```

Do not run `atelier connect`. The scripts find the binary on PATH or in `~/.local/bin`.

## 2. Where drawings live

- `tools/draw_weapons.py` holds the weapon grids. Add related sprites to its `SPRITES` dict.
- For an unrelated set (for example HUD icons or an animation), copy that script to `tools/draw_<set>.py` and
  change `OUT` and `SPRITES`. Keep its behaviour: exit 0 when Atelier is missing, run in a temporary
  `ATELIER_HOME`, export at `scale: 1`, delete the `.json` sheet metadata.
- Output goes to `assets/sprites/<set>/`. Never hand-edit files there.

## 3. Drawing rules

- One character is one pixel. `.` is transparent. Colours come from `LEGEND`; add a key there before using a
  new character. Rows shorter than the widest row are padded with `.` on the right.
- Scale: sprite files hold **4 pixels per world pixel** (a 16px floor tile is 64 sprite pixels). A pistol in
  the hand is about 26x6; a character's shoulders are about 68 pixels across.
- Anything that rotates in the world (held weapons, characters, pickups) is drawn **top-down, facing right**.
- HUD icons are side views. The HUD scales them to fit a 32x18 unit slot, so keep them near that proportion.
- Give every sprite a 1px outline in `k` and no more than three tones per material; soft gradients turn to
  mud at this size.

## 4. Draw, look, repeat

```sh
python3 tools/draw_weapons.py
```

Then enlarge the result and look at it with the Read tool before wiring it in. Do not judge a sprite from its
grid:

```sh
python3 - <<'PY'
from PIL import Image
im = Image.open("assets/sprites/weapons/hud_pistol.png").convert("RGBA")
bg = Image.new("RGBA", (im.width * 8 + 16, im.height * 8 + 16), (45, 20, 60, 255))
big = im.resize((im.width * 8, im.height * 8), Image.NEAREST)
bg.paste(big, (8, 8), big)
bg.save("/tmp/preview.png")
PY
```

Check it at game size too, not only enlarged. Expect two or three rounds.

For work the grid approach does not cover (animation frames, effects, fonts), list the tools with
`atelier tools --markdown` and read one with `atelier tools --schema NAME`. Calls are
`atelier call TOOL '<json>'`; the reply is one JSON object after any log lines. Useful ones: `doc_new`,
`doc_paint_grid`, `doc_frame`, `doc_look`, `doc_contact_sheet`, `doc_export` (`op`: `sheet`, `anim`, `font`).

## 5. Wire it into the game

1. Map the texture name to the file in `SPRITES` at the top of `scripts/fx.gd`
   (for example `"hud_pistol": "weapons/hud_pistol"`).
2. Keep a procedural fallback for that name in `Fx._make()`. CI does not run this tool, and the game must work
   with any sprite missing.
3. Where the texture is shown in the world, multiply the node's scale by `Fx.sprite_scale(name)` (0.25 for
   sprite files, 1 for procedural art). The HUD sizes icons itself.
4. Run `godot --headless --import` and commit the new `.png` files together with their `.png.import` files.

## 6. Finish

Follow the git workflow and run the checks in `CLAUDE.md`. Then export the web build, open it in a browser and
confirm the sprite shows where intended. A sprite that exists but is hidden by other art (for example a held
weapon under a body sprite that already has one painted in) is not done: say so.
