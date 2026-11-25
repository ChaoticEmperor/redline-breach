---
name: atelier-pixel-art
description: Draw or change pixel art for REDLINE // 1989 with the Atelier CLI - characters and their animations, 3/4 props, weapons, HUD icons, signs. Use when asked to draw, redraw, add detail to, restyle or animate a character, enemy, prop, weapon or icon, or when a texture is still a plain placeholder. Not for the floor textures (tools/slice_sheets.py) or for lighting and effects (procedural in fx.gd).
---

# Drawing pixel art with Atelier

**Before drawing or reviewing anything, load the `pixel-art-engineer` skill.** It holds the craft rules (clean
lines, outline style, shading pitfalls, material texture, colour ramps, dithering, animation, export) that every
sprite in this game is judged against. This skill covers the other half: which script draws what, the scale and
layout the game expects, and how to wire art in. Where the two disagree on project specifics (view, scale, sheet
layout), this skill wins; where they disagree on craft, `pixel-art-engineer` wins and the art should be fixed.

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
- To refresh the vendored Atelier guides after an upgrade: `tools/refresh_atelier_skills.sh`.
- To remove it: `atelier uninstall` (it asks first).
- Atelier is version 0.2 and its README says the code has had no line-by-line human review. On a user's own
  machine, ask before installing.

## 2. Where drawings live

| Script | Draws | How |
| --- | --- | --- |
| `tools/draw_characters.py` | player and infected animation sheet (64x64 cells) | posed skeletons rendered as lit forms |
| `tools/draw_props.py` | 3/4 props, glass, signs, alarm lamp, packed into one atlas | one function per prop |
| `tools/draw_weapons.py` | weapons: `held_*` (in the player's fist, at the player sheet's pixel size and palette; grip pixel in `Fx.HELD_GRIP`), `hud_*` side views, `top_*` top-down views | character grids, one character per pixel |
| `tools/convert_reference.py` | the player sheet (96x96 cells) and its front fist alone (`hand` layer, drawn over the held weapon), converted from `assets/raw/player_reference.png` | recovers the reference's pixels and rebuilds them in Atelier with gates |

`tools/_atelier.py` is shared: `Canvas` (lit `ball`, `limb`, `slab`, `disc`, plus `rect`, `line`, `speckle`),
`ramp()` for dark-to-light colour ramps, and `paint()` which sends a canvas through Atelier. Output goes to
`assets/sprites/`. Never hand-edit files there. Every script exits 0 when Atelier is missing.

## 3. The Atelier toolbox: what to reach for

Atelier has 27 tools. Until the player pilot we used three (`doc_new`, `doc_paint_grid`, `doc_export`) and
bypassed everything that makes it an art tool. Use this table to pick the tool; `atelier tools --schema NAME`
gives the arguments. Every call is `atelier call TOOL --stdin` with the JSON on stdin (or as one quoted
argument); the reply is one JSON object after any log lines. Set `ATELIER_HOME` to a folder you keep, so the
document, its checkpoints and its recipe survive between calls.

| When you need to | Tool | Notes |
| --- | --- | --- |
| start a sprite | `doc_new` | returns `doc_id`; pass it to every later call |
| fix the colours before drawing | `doc_palette op=set` | locks the palette; `op=generate` builds ramps, `op=snap` forces pixels onto it, `op=swap` recolours, `op=report` counts usage |
| split the subject into parts | `doc_layer` | ops: `add`, `rename`, `set`, `move`, `insert`, `delete`, `duplicate`, `merge_down` (there is no `edit`) |
| place authored pixels | `doc_paint_grid` | rows of characters plus a legend; send only the rows that hold pixels and position with `x`/`y` |
| draw a shape | `doc_draw` | ops: `pencil`, `line`, `rect`, `ellipse`, `polyline`, `polygon`, `stroke`, `curve`, `stamp`, `fill`, `gradient`, `scatter`, `noise`, `text`, `fill_cel`, `clear_cel`; `erase: true` cuts pixels out. No `noise` or `scatter` on character sprites |
| apply an effect or transform | `doc_fx` | ops: `outline`, `symmetry`, `pixel_perfect`, `shade`, `form`, `bevel`, `dither`, `quantize`, `replace_color`, `adjust`, `gradient_map`, `flip`, `shift`, `rotate`, `scale`, `blur`, `drop_shadow` |
| blend two ramp steps | `doc_dither_ramp` | for backgrounds and large surfaces, not small animated sprites |
| clear or move a patch | `doc_region` | `op=clear` with `rect=[x, y, w, h]`; the way to do a region fix |
| read exact pixels before a fix | `doc_dump_region` | returns the grid and its legend; diagnose with this, then edit |
| see the frame | `doc_look` | `out_path` writes a PNG; `bg=checker|dark|white`; `mode=notan|value` for the squint test; `onion` for neighbours |
| check the silhouette | `doc_silhouette` | bounding box, fill ratio and a black grid |
| find specks and separate islands | `doc_components` | `specks_total` must be 0 on a character |
| audit craft | `doc_critique` | orphans, palette adherence, contrast, light direction, pillow shading, value masses, jaggies |
| work from a reference image | `doc_ref` | `op=set` attaches it, `op=analyze` gives its palette and silhouette plan, `op=compare` scores a frame (silhouette IoU, colour delta), `op=diff` lists the worst pixels |
| animate | `doc_frame`, `doc_add_tag` | `doc_frame op=add copy_from=N`; tag a loop so the audit and the export know it |
| check an animation | `doc_contact_sheet`, `doc_frame_diff`, `doc_anim_audit` | audit modes: `seam`, `spacing`, `arc`, `timing` |
| save before a risky step, undo | `doc_checkpoint` | `action=save|list|restore|prune`; restore takes the `checkpoint_id` from `list` |
| change resolution | `doc_rescale` | whole-number `factor`; `op=down` needs both sides to divide evenly; adds no colours |
| check a floor tile repeats | `doc_seam_report`, `doc_look tile=N` | for the floor textures |
| make a pixel font | `doc_font`, `doc_export op=font` | exports a TrueType font; a candidate for the HUD |
| export | `doc_export` | `op=sheet` (PNG, pass `scale: 1`), `op=anim` (GIF/APNG), `op=font` |
| housekeeping | `doc_info`, `list_docs`, `delete_doc` | `doc_info` shows layers, frames, tags and palette size |
| rebuild or inspect a drawing | `atelier replay <recipe|id> [--show]` | every document journals its calls as a recipe |

### Gates: do not move on until these pass

Run them per frame, after each stage (silhouette, colour, shading, animation), and look at a `doc_look` render
each time. A sprite is not finished because the numbers pass, and it is not finished while they fail.

| Check | Tool | Pass |
| --- | --- | --- |
| stray pixels | `doc_critique` orphans, `doc_components` specks | 0 |
| palette | `doc_critique` palette adherence, `doc_info` | 0% off-palette; palette locked, sized by the definition test below |
| definition | compare the face at the same scale as the reference | eye highlights, iris, brow and the shading steps on the face all present |
| structure | `doc_info` | parts on separate layers, loop tagged |
| reads at all | `doc_silhouette`, `doc_look mode=notan` | recognisable in flat black |
| matches the reference | `doc_ref op=compare` | silhouette IoU 0.80 or more, colour delta 0.06 or less |
| shading | `doc_critique` | no pillow shading, one light direction, contrast ok |
| loop | `doc_anim_audit mode=seam` and `timing` | wrap about as large as a normal step; hold key poses longer |

`jaggies` is information, not a gate: small curves always keep some step corners, so judge them by eye.

### Working from a reference image (the method that produced the best art so far)

When there is a generated or hand-made reference in the target style, convert it; do not redraw it.
`tools/convert_reference.py` does all of this for the player: copy it (or add a second spec) for another
character. Its `SPEC` holds what is particular to a sheet: the source rows and columns of each pose, the
backdrop colour, the frame order, the palette size and the hand patches. It keeps the Atelier document in
`tools/out/atelier/`, so fixes can be made by region and then recorded in the spec's `patches`.

1. **Measure its pixel grid.** Sum the absolute luminance differences along x and along y to get two edge
   profiles, then find the pitch (try 4.0 to 12.0 in steps of 0.25) whose sample points land on the most edge
   energy. The Gemini player sheet was 5.75 screen pixels per art pixel.
2. **Recover the native pixels.** For each pose, find the grid phase the same way and take the median colour of
   the middle of each cell. Drop the backdrop and any ground shadow, keep dark outline cells that touch
   colour, close one-pixel gaps in the outline and fill what is sealed inside it.
3. **Lock the palette from the reference, sized to keep its definition.** One ink colour for all near-black
   outline pixels, N colours quantised from the rest, plus a few accent slots for colours that are rare but far
   from everything else (eye whites, an iris, a mouth); plain quantising drops those first. Choose N by test:
   for each candidate size, measure the mean distance from the reference's pixels to their nearest palette
   colour, over the whole figure and over the face alone, and take the smallest size where no face pixel is
   badly off. The Gemini player needed 42 (39 + accents); at 16 the eyes, brow and face shading were lost and
   the sprite read as "too pixelated" although every pixel was in the right place. A generic "8-16 colours"
   cap suits art drawn for it, not art converted from a painted reference. `doc_palette op=set`.
4. **Build it in one document:** a layer per part, one frame per pose, `doc_paint_grid` per layer and frame,
   `doc_add_tag` for each loop, `doc_checkpoint action=save`.
5. **Attach an aligned reference per frame.** `doc_ref op=compare` stretches the reference over the canvas, so
   cut the same window out of the source that the canvas covers (canvas size times the pitch, same offset). A
   loosely cropped pose scores about 0.3 even when the sprite is right.
6. **Run the gates, fix by region.** `doc_dump_region` the failing area, then `doc_region op=clear` and
   `doc_paint_grid` exactly there. Typical damage: a far foot or hand that fades into the shadow.
7. **Check definition against the reference at the same scale** (upscale the sprite by the pitch and put it
   beside the source, face enlarged) before judging it. If it looks coarser than the reference, the cause is
   the palette or the display size, not the grid, as long as the reference's cells are flat inside (measure
   the colour spread within cells; under about 5 means the grid is right).
8. **Export at native size.** Halving a detailed 78px figure with `doc_rescale` destroys the face; pick the
   in-game scale to suit the art, not the other way round.

A reference only converts well if it has a regular pixel grid, a flat backdrop and one pose per clear gap.

## 4. Drawing rules

- **View:** 3/4 oblique. Characters show face, body and legs and face right (the game flips them). A prop shows
  its top face and, below it, its front face.
- **Scale:** character and prop sheets hold 2 pixels per world pixel, so one map cell is 32 pixels. A prop
  covering `fw` x `fh` cells is `fw*32` wide and `fh*32 + height` tall and stands on its bottom edge. Characters
  are about 42 pixels tall and stand with their feet on row 60 of a 64x64 cell, centred on column 32; both sheets
  are shown at half scale, so characters and props share one pixel size. Character canvases set `grit = 0`
  (clean cel bands, no dithering) and use `ink()` for coloured outlines, then `contour()` for the dark silhouette
  edge. Weapons hold 4 pixels per world pixel.
- **Form before detail:** build shapes from the lit primitives with a 4-5 step `ramp()`, then add detail
  (seams, tears, wounds, labels, glints) on top. Flat `rect` fills on their own read as blocky; that is what
  got the first version of these sheets rejected.
- **Animation:** change the pose arguments of `figure()` (leg and arm angles, bob, lean), not pixels.
- **Layout is a contract.** Character rows and frame ranges must match `ANIMS` in `scripts/fx.gd`. Adding a prop
  means adding it to `PROPS` in `draw_props.py`; the script regenerates `scripts/prop_atlas.gd`.

## 5. Craft order (adapted from Atelier's own sprite, scene and review guides)

Atelier's own three guides are installed next to this skill as `atelier-sprite`, `atelier-scene` and
`atelier-review` (copied verbatim by `atelier skills install --dir .claude/skills`; re-run that to update them,
refresh them with `tools/refresh_atelier_skills.sh`, which also re-adds the project note at the end of each;
Atelier is MIT licensed). They are written for drawing layer by layer inside Atelier.
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

When one asset is combined with another (a weapon in the player's hand, a prop on a counter, a character
over a floor), follow `pixel-art-engineer` section 9, "Clean Asset Merging & Compositing": same pixel size,
written draw order with the holder overlapping what it holds, shared light and outline style, clean seams.

Checklist from `pixel-art-engineer` to run on every sprite before it is wired in:

- lines: no stray single pixels, no mixed staircase steps on a diagonal or curve;
- outline: one outline style per sheet, chosen on purpose;
- shading: no pillow shading, no banding that hugs the outline;
- materials: cloth, metal, wood and skin read differently, not as the same shaded blob;
- dithering: light on small or animated sprites (it flickers between frames);
- preview at 1x on a neutral grey background and flipped horizontally;
- one pixel size across everything on screen.

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

## 6. Draw, look, repeat

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

The tools for looking, checking and fixing are in section 3; `atelier tools --markdown` lists them all.

## 7. Wire it into the game

- **New prop:** choose where it appears in `_prop_for()` in `scripts/world.gd` (by room type and the shape of
  the furniture piece). Single-cell props are repeated across a piece; a larger prop is used when its footprint
  matches the piece exactly.
- **New animation or character:** add the row or frame range to `ANIMS` in `scripts/fx.gd` and play it from
  `player.gd` / `enemy.gd`.
- **New standalone texture:** map its name to the file in `SPRITES` in `scripts/fx.gd`.
- Always keep a procedural fallback in `Fx._make()` (the sheets have `_fallback_chars()` / `_fallback_props()`):
  CI does not run these tools and the game must work with any sprite missing.
- Run `godot --headless --import` and commit new `.png` files together with their `.png.import` files.

## 8. Finish

Follow the git workflow and run the checks in `CLAUDE.md`. Then export the web build, open it in a browser and
confirm the sprite shows where intended. A sprite that exists but is hidden by other art (for example a held
weapon under a body sprite that already has one painted in) is not done: say so.
