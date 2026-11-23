# REDLINE // 1989

Fast-paced 2D top-down zombie action game. Godot **4.7.2** (GDScript, `gl_compatibility`), exported for Web,
hosted on Firebase Hosting (project `project-dweller`, site `redline-1989`, live at https://redline-1989.web.app).

## Git workflow (strict — follow in every session)

| Branch | Purpose | Rules |
| --- | --- | --- |
| `main` | Production. Mirrors the live site. | **Never commit directly.** Only merge tested releases from `develop`. |
| `develop` | Integration. Everything developed and verified so far. | **Never build features directly on it.** Only receives merges from `feature/*`. |
| `feature/<feature_name>` | All new features, fixes and experiments. | Always branch off `develop`. |

Procedure for any change:

1. `git fetch origin && git checkout develop && git pull origin develop`
2. `git checkout -b feature/<feature_name>`
3. Do the work; run all checks below locally until they pass. Push the feature branch (CI runs checks only, no deploy).
4. `git checkout develop && git merge --no-ff feature/<feature_name>` — resolve any conflicts cleanly, re-run the checks.
5. `git push origin develop` (CI deploys to the `develop` preview channel).
6. `main` is only updated by merging `develop` after the `develop` preview has been verified by the user. Do not
   touch `main` unless the user explicitly asks for a release.

## Checks (must pass before merging into `develop`; CI runs the same on every branch/PR)

```sh
godot --headless --import
godot --headless --quit                       # script parse/load check
godot --headless -s tests/smoke_test.gd       # headless simulation test
mkdir -p web && godot --headless --export-release "Web" web/index.html && test -f web/index.wasm
```

If a sheet in `assets/raw/` changed, run `python3 tools/slice_sheets.py` first.

Treat any `SCRIPT ERROR` / `Parse Error` in the output as a failure even when the exit code is 0.

## CI / deploy (`.github/workflows/deploy.yml`)

- Checks run on pushes to `main`, `develop`, `feature/**`, on PRs targeting `develop`/`main`, and on manual dispatch.
- Push to `develop` → Firebase preview channel `develop`. Push to `main` → `live`. Feature branches never deploy.
- Requires the repo secret `FIREBASE_SERVICE_ACCOUNT`.
- `web/` and `.godot/` are build output and git-ignored. Never commit them.

## Art pipeline: AI sprite sheets + procedural lighting/FX

- **Raw sheets** live in `assets/raw/` (`characters.png` 4x2, `props.png` 4x4, `floors.png` 4x2) on a flat `#00FF00`
  chroma-key background. `assets/raw/.gdignore` keeps Godot from importing them.
- **Processed sprites** are generated into `assets/sprites/{chars,props,floors}/` by `python3 tools/slice_sheets.py`
  (needs Pillow). It keys out the green and its fringe, finds each drawing, drops the watermark, trims and
  downscales with nearest-neighbour. It is deterministic: re-run it whenever a raw sheet changes and commit the
  output (and the `.png.import` files Godot creates). Never hand-edit files in `assets/sprites/`.
- The cell order of each sheet is fixed by the name lists at the top of `tools/slice_sheets.py`.
- **Fallback:** every sprite is optional. `Fx.tex()` / `Fx.img()` load `assets/sprites/...` when the file exists and
  otherwise generate a procedural stand-in, so the game and CI work with any subset of sprites (CI does not run the
  slicer). New art must keep a procedural fallback.
- Characters are drawn strictly top-down, facing right; the game rotates them to the aim/move direction.
- **Lighting, glow, gore, particles and all audio stay procedural** (`fx.gd`, `world.gd`): dark `CanvasModulate`
  ambient (`#1e182e`), `PointLight2D` room lights / flashlight / muzzle flash, and an unlit glow canvas for neon.

## Project layout

- `project.godot`, `export_presets.cfg` (preset `Web`, no threads), `main.tscn` (root node + `scripts/main.gd`).
- `scripts/main.gd` — run lifecycle: floor build, restart (same seed), score/combo, win/lose state.
- `scripts/layout.gd` — pure data: hand-made room chunks stitched into a tile grid from a seed (deterministic).
- `scripts/world.gd` — bakes floors + room props into one texture, lights, wall collision, doors, glass, pickups,
  A* grid, raycasts, noise propagation.
- `scripts/player.gd`, `scripts/enemy.gd` — actors. `scripts/controls.gd` — touch sticks/buttons + keyboard/mouse.
- `scripts/fx.gd` — sprite loading with procedural fallbacks, `AudioStreamWAV` sounds, decals, particles.
  `scripts/hud.gd` — HUD.
- `tools/slice_sheets.py` — sprite sheet slicer (see above). `assets/` — raw sheets and sliced sprites.
- `tests/smoke_test.gd` — headless test; drives the game through `controls.override`.

## Conventions

- Scripts reference each other with `preload` constants, not `class_name` or autoloads (keeps `-s` test runs working).
- 640x360 viewport, 16px tiles, nearest filtering, camera zoom 1.5. Mobile-first: every action must be reachable
  by touch.
- Restart after death must stay under 0.2s (asserted by the smoke test) — keep per-floor build work cheap and cached.
- Each room is its own floor sprite and decal canvas so no canvas item exceeds the 2D light-per-item limit; keep
  that split when adding lit content.
- New gameplay behaviour gets an assertion in `tests/smoke_test.gd`.
