---
name: atelier-pixel-art
description: Draw or change pixel art for REDLINE // 1989 with the Atelier CLI - characters and their animations, 3/4 props, weapons, HUD icons, signs. Use when asked to draw, redraw, add detail to, restyle or animate a character, enemy, prop, weapon or icon, or when a texture is still a plain placeholder. Not for the floor textures (tools/slice_sheets.py) or for lighting and effects (procedural in fx.gd).
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

| Script | Draws | How |
| --- | --- | --- |
| `tools/draw_characters.py` | player and infected animation sheet (64x64 cells) | posed skeletons rendered as lit forms |
| `tools/draw_props.py` | 3/4 props, glass, signs, alarm lamp, packed into one atlas | one function per prop |
| `tools/draw_weapons.py` | weapons: side views and top-down views | character grids, one character per pixel |

`tools/_atelier.py` is shared: `Canvas` (lit `ball`, `limb`, `slab`, `disc`, plus `rect`, `line`, `speckle`),
`ramp()` for dark-to-light colour ramps, and `paint()` which sends a canvas through Atelier. Output goes to
`assets/sprites/`. Never hand-edit files there. Every script exits 0 when Atelier is missing.

## 3. Drawing rules

- **View:** 3/4 oblique. Characters show face, body and legs and face right (the game flips them). A prop shows
  its top face and, below it, its front face.
- **Scale:** character and prop sheets hold 2 pixels per world pixel, so one map cell is 32 pixels. A prop
  covering `fw` x `fh` cells is `fw*32` wide and `fh*32 + height` tall and stands on its bottom edge. Characters
  stand with their feet on row 60 of a 64x64 cell, centred on column 32. Weapons hold 4 pixels per world pixel.
- **Form before detail:** build shapes from the lit primitives with a 4-5 step `ramp()`, then add detail
  (seams, tears, wounds, labels, glints) on top. Flat `rect` fills on their own read as blocky; that is what
  got the first version of these sheets rejected.
- **Animation:** change the pose arguments of `figure()` (leg and arm angles, bob, lean), not pixels.
- **Layout is a contract.** Character rows and frame ranges must match `ANIMS` in `scripts/fx.gd`. Adding a prop
  means adding it to `PROPS` in `draw_props.py`; the script regenerates `scripts/prop_atlas.gd`.

## 4. Draw, look, repeat

```sh
python3 tools/draw_characters.py   # or draw_props.py / draw_weapons.py
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

- **New prop:** choose where it appears in `_prop_for()` in `scripts/world.gd` (by room type and the shape of
  the furniture piece). Single-cell props are repeated across a piece; a larger prop is used when its footprint
  matches the piece exactly.
- **New animation or character:** add the row or frame range to `ANIMS` in `scripts/fx.gd` and play it from
  `player.gd` / `enemy.gd`.
- **New standalone texture:** map its name to the file in `SPRITES` in `scripts/fx.gd`.
- Always keep a procedural fallback in `Fx._make()` (the sheets have `_fallback_chars()` / `_fallback_props()`):
  CI does not run these tools and the game must work with any sprite missing.
- Run `godot --headless --import` and commit new `.png` files together with their `.png.import` files.

## 6. Finish

Follow the git workflow and run the checks in `CLAUDE.md`. Then export the web build, open it in a browser and
confirm the sprite shows where intended. A sprite that exists but is hidden by other art (for example a held
weapon under a body sprite that already has one painted in) is not done: say so.
