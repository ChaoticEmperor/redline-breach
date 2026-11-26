# Done so far

Newest first. One line per piece of work that reached `develop`; `git log` has the detail.

## 2026-11-26

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
