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

Treat any `SCRIPT ERROR` / `Parse Error` in the output as a failure even when the exit code is 0.

## CI / deploy (`.github/workflows/deploy.yml`)

- Checks run on pushes to `main`, `develop`, `feature/**`, on PRs targeting `develop`/`main`, and on manual dispatch.
- Push to `develop` → Firebase preview channel `develop`. Push to `main` → `live`. Feature branches never deploy.
- Requires the repo secret `FIREBASE_SERVICE_ACCOUNT`.
- `web/` and `.godot/` are build output and git-ignored. Never commit them.

## Project layout

- `project.godot`, `export_presets.cfg` (preset `Web`, no threads), `main.tscn` (root node + `scripts/main.gd`).
- `scripts/main.gd` — run lifecycle: floor build, restart (same seed), score/combo, win/lose state.
- `scripts/layout.gd` — pure data: hand-made room chunks stitched into a tile grid from a seed (deterministic).
- `scripts/world.gd` — floor texture, wall collision, doors, glass, pickups, A* grid, raycasts, noise propagation.
- `scripts/player.gd`, `scripts/enemy.gd` — actors. `scripts/controls.gd` — touch sticks/buttons + keyboard/mouse.
- `scripts/fx.gd` — all generated textures and `AudioStreamWAV` sounds, decals, particles. `scripts/hud.gd` — HUD.
- `tests/smoke_test.gd` — headless test; drives the game through `controls.override`.

## Conventions

- All art and audio are generated in code (`fx.gd`). Do not add image or audio asset files.
- Scripts reference each other with `preload` constants, not `class_name` or autoloads (keeps `-s` test runs working).
- 640x360 viewport, 16px tiles, nearest filtering. Mobile-first: every action must be reachable by touch.
- Restart after death must stay under 0.2s (asserted by the smoke test) — keep per-floor build work cheap and cached.
- New gameplay behaviour gets an assertion in `tests/smoke_test.gd`.
