# Done so far

Newest first. One line per piece of work that reached `develop`; `git log` has the detail.

## 2026-11-26

- Git history holds no CraftPix art: rewritten with `git filter-repo` from the import commit on
  (I3); every rewritten commit verified to equal the old one minus the removed files.
- No CraftPix art left in the tree: the runner and bloater sheets and their importer are removed;
  both use the code-drawn sheet. `animate_infected.py` writes the infected atlas.
- Our horde is in the game (CraftPix horde removed): a clubber in a teal sequin dress, built the
  shambler's way. The animator now takes a spec per kind (her own lunge, an arm drawn in front,
  reach by stretching so the arm stays on the shoulder).
- Shambler death: a backwards fall onto its back (eyes shut, arms splayed), posed before shading so
  the light stays right; the corpse decal is the last "down" frame. Frames cleaned with Tandem's
  lint (one near-black, small pockets closed, pixel-perfect outline turns).
- Our shambler is in the game (CraftPix shambler removed): walk 8, lunge 5, down 1, built by
  `tools/animate_infected.py` from the Tandem still, every frame re-shaded and checked by the critic.
- Our shambler, still pose: a pixelgen reference for layout, rebuilt on our ramps by
  `tools/draw_infected.py` at the player's height, hand-painted in Tandem. `tools/critique_sprite.py`
  checks size, key leftovers, contour, noise, flat fills and palette (it found holes in the
  player's run frames: I4). pixelgen now keys backdrop trapped inside a figure.
- Decision: the CraftPix originals are removed from git history after I1 (no private repo).
- Own art only: no third-party packs. Removed the unused Kenney CC0 pack and its importer (no
  texture ever loaded from it); pixelgen refuses third-party files as edit inputs. The CraftPix
  infected are listed for replacement (`assets-debt.md` I1).
- `tasks/` folder: `assets-debt.md` (the asset inventory, the asset debt and animation
  targets), `future-tasks.md`, and this file.
- pixelgen (separate repo, `~/GameProjects/pixelgen`): a CLI that generates reference images on
  studio's mflux, then chroma-keys them, recovers the pixel grid, palette-locks them and writes
  a provenance sidecar. Profile `redline`. It refuses prompts that name other games or brands,
  edit inputs that aren't ours, and non-commercial models.

## 2026-11-25

- Infected (shambler, horde, runner, bloater) from CraftPix free sheets, packed by
  `import_infected.py` at the player's pixel size with full walk and attack cycles; heads
  doubled to match the player's proportions (the smoke test keeps them within 12% of the
  player's height).
- `gameplay-craft` section 9: a scale and animation baseline as ratios. Floor weapons moved to
  the player's pixel size; the pipe swing strikes, holds, then returns.
- Bloater fuse warning: a dashed ring that marks the blast zone where it was lit, and a fuse
  long enough to escape (`FUSE_TIME >= REACTION + BLAST / SPEED`, asserted in the smoke test).
- `gameplay-craft` skill (game feel, fair enemies, weapons, scoring, animation, menus) and
  `tools/playbot.gd`, the play-test bot; Elusion study folded in.
- Normal-mapped props prototype (normals from the forms).
- Physics interpolation, so movement stays smooth above 60 Hz.
- Movement ramp and corner rounding; a notice beat for the infected.
- Held weapon: 16 pre-drawn directions, gripped in the player's fist, drawn behind the body when
  aiming up-screen; the muzzle flash starts at the barrel tip.
- Transient effects drawn on the art pixel grid with dithered fades.
- Reference converter follows the reference's own pixel grid.
- Cloud tooling: numpy/Pillow in the session hook, one Godot pin (`.godot-version`).

## 2026-11-24

- Player converted from a generated reference (`convert_reference.py`, 96 px cells, 42-colour
  palette), with gates.
- `pixel-art-engineer` skill, Atelier toolbox and the reference-conversion method.
- 3/4 oblique art pass: animated characters, props with depth.
- Visual polisher: asset slicer, xvfb frame capture, visual diff against the concept art; look
  tuned toward the nightclub concept.
- Weapon pixel art for HUD, pickups and the held weapon.
- Responsive HUD and touch controls for portrait and landscape.
- SessionStart hook that installs Godot and Atelier in cloud sessions.

## 2026-11-23

- Playable one-floor prototype, CI to Firebase (`develop` preview, `main` live).
- Full HD responsive canvas, fullscreen web shell.
- First visual pass: lighting and room props.
