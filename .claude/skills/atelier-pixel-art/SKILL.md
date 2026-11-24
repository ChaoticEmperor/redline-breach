---
name: atelier-pixel-art
description: Draw or change pixel art for REDLINE // 1989 with the Atelier CLI - characters and their animations, 3/4 props, weapons, HUD icons, signs. Use when asked to draw, redraw, add detail to, restyle or animate a character, enemy, prop, weapon or icon, or when a texture is still a plain placeholder. Not for the floor textures (tools/slice_sheets.py) or for lighting and effects (procedural in fx.gd).
---

# Drawing pixel art with Atelier

Atelier (https://github.com/marmikshah/atelier) is an offline pixel-art editor with no GUI. You draw by
calling its tools from the shell; it does not generate art, you place the pixels. In this project every
drawing lives as a character grid in a Python script, so it is reviewable and can be regenerated.

## 1. Make sure Atelier is installed

```sh
command -v atelier || ls ~/.local/bin/atelier
```

In Claude Code cloud sessions the repo's SessionStart hook (`.claude/hooks/session-start.sh`) installs Atelier
(and Godot) automatically when they are missing, so it should already be there. If it is not (the hook warned
that a download failed, or you are on a local machine), install it by hand:

```sh
curl -fsSL -o /tmp/atelier-install.sh https://github.com/marmikshah/atelier/releases/latest/download/install.sh
ATELIER_NO_MODIFY_PATH=1 ATELIER_NO_CONNECT=1 sh /tmp/atelier-install.sh   # installs ~/.local/bin/atelier
~/.local/bin/atelier --version
```

- macOS and Linux only. The installer downloads a prebuilt binary and checks it against the release checksums.
- The two options keep it from editing shell profiles and from registering itself with coding agents. Do not
  run `atelier connect`: this project drives Atelier through its command line only.
- The scripts in `tools/` find the binary on PATH or in `~/.local/bin`.
- To refresh the vendored Atelier guides after an upgrade: `atelier skills install --dir .claude/skills`.
- To remove it: `atelier uninstall` (it asks first).
- Atelier is version 0.2 and its README says the code has had no line-by-line human review. On a user's own
  machine, ask before installing.

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

## 4. Craft order (adapted from Atelier's own sprite, scene and review guides)

Atelier's own three guides are installed next to this skill as `atelier-sprite`, `atelier-scene` and
`atelier-review` (copied verbatim by `atelier skills install --dir .claude/skills`; re-run that to update them,
never edit them by hand; Atelier is MIT licensed). They are written for drawing layer by layer inside Atelier.
**For anything that ships in this game, this skill wins**: our sheets are drawn by code through `tools/draw_*.py`,
with the scale, layout and wiring rules above. Use the bundled guides for technique, and for one-off art drawn
directly in Atelier. These are the parts that carry over to our scripts, in the order to apply them. Each level
invalidates the ones below it.

1. **Silhouette.** Before any detail, check that the figure or prop reads as itself in flat black (the preview
   snippet below has a `--silhouette` variant). If it does not, change the pose or proportions in `figure()` or
   the prop's big forms. Detail on a shape that does not read is wasted.
2. **Value.** Squint, or view it in greyscale. The focal area (a character's head and chest, the face of a
   prop the player looks at) must hold the strongest light-dark contrast. Two neighbouring masses in the same
   value merge into one.
3. **One light.** Everything is lit from the upper left (`LIGHT` in `tools/_atelier.py`). A highlight on the
   wrong side, or a lamp that lights nothing, is the loudest sign of assembled art. If you draw a light source,
   something must be lit by it.
4. **Colour.** Stay on the ramps from `ramp()`. Do not invent in-between colours; mix two ramp steps with the
   built-in dithering instead.
5. **Detail, only where it earns attention.** Detail everywhere is detail nowhere. Put it on the focal area
   and leave the rest in clean forms.

Rules that apply at every level:

- **Texture follows form.** Random speckle is noise, not texture. `Canvas.speckle()` is for wear on a surface
  (rust on a drum, stains on cloth), at a few percent; cloth folds, wood grain and brushed metal are drawn as
  lines that follow the shape.
- **Name the problem before changing anything.** Look at the render and say in words what is wrong and where.
  If you cannot name it, you are guessing.
- **Fix the part, never the sheet.** One problem per pass: change the one function, pose argument or detail
  call responsible, regenerate, look again. Rewriting a character to fix its hands throws away what was right,
  and two fixes at once hide which one worked.
- **Carry motion in shape, not opacity.** A pulse or impact is drawn as bigger or brighter pixels; soft alpha
  fades die at this size.
- **Keep a pose inside its cell.** `python3 tools/asset_slicer_diff.py audit` flags poses that touch a cell
  edge (a clipped corpse or lunge) and stray pixels in unused cells.

### Reviewing art (when asked to judge, not to fix)

Look first, measure second, report third. Report the most severe finding first, ranked silhouette, then value,
then light, then colour, then detail: a colour note on a figure whose silhouette fails is noise. Every finding
has three parts:

```
<what is wrong>  -  <where: sheet, row/frame or prop name, and the region>
fix: <the one localised change, naming the function or pose argument>
```

"Redraw it" is not a finding unless the silhouette itself is wrong; then say exactly that. Separate what the
art was asked to be from what you would prefer, and say so when it is fine: an empty report is a real result.
For screen-level judgement (brightness, contrast, colour balance, character size against the concept art) use
`tools/run_polisher.sh`, described in `CLAUDE.md`.

## 5. Draw, look, repeat

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

For the silhouette check, fill every opaque pixel with black before enlarging:

```sh
python3 - <<'PY'
from PIL import Image
im = Image.open("assets/sprites/chars/sheet_characters_v2.png").convert("RGBA")
black = Image.new("RGBA", im.size, (0, 0, 0, 255))
out = Image.new("RGBA", im.size, (230, 230, 230, 255))
out.paste(black, (0, 0), im.getchannel("A").point(lambda v: 255 if v > 127 else 0))
out.resize((im.width * 2, im.height * 2), Image.NEAREST).save("/tmp/silhouette.png")
PY
```

Check it at game size too, not only enlarged. Expect two or three rounds.

For work the grid approach does not cover (animation frames, effects, fonts), list the tools with
`atelier tools --markdown` and read one with `atelier tools --schema NAME`. Calls are
`atelier call TOOL '<json>'`; the reply is one JSON object after any log lines. Useful ones: `doc_new`,
`doc_paint_grid`, `doc_frame`, `doc_look`, `doc_contact_sheet`, `doc_export` (`op`: `sheet`, `anim`, `font`).

## 6. Wire it into the game

- **New prop:** choose where it appears in `_prop_for()` in `scripts/world.gd` (by room type and the shape of
  the furniture piece). Single-cell props are repeated across a piece; a larger prop is used when its footprint
  matches the piece exactly.
- **New animation or character:** add the row or frame range to `ANIMS` in `scripts/fx.gd` and play it from
  `player.gd` / `enemy.gd`.
- **New standalone texture:** map its name to the file in `SPRITES` in `scripts/fx.gd`.
- Always keep a procedural fallback in `Fx._make()` (the sheets have `_fallback_chars()` / `_fallback_props()`):
  CI does not run these tools and the game must work with any sprite missing.
- Run `godot --headless --import` and commit new `.png` files together with their `.png.import` files.

## 7. Finish

Follow the git workflow and run the checks in `CLAUDE.md`. Then export the web build, open it in a browser and
confirm the sprite shows where intended. A sprite that exists but is hidden by other art (for example a held
weapon under a body sprite that already has one painted in) is not done: say so.
