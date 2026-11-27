# REDLINE // 1989

Fast, lethal top-down action game: one hit kills, restart is instant, floors are cleared room by room. Set in a 1989 nightclub during an infection outbreak, with infected and armed humans. Godot **4.7.2** (pinned in `.godot-version`, read by CI and the session-start hook; GDScript, `gl_compatibility`), exported for Web,
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
   **Wait for that CI run to pass before merging** (`gh run watch` where `gh` works, otherwise the run on GitHub):
   the Web export check only runs in CI, so a local pass does not cover it.
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
cp web_template/manifest.webmanifest web_template/icon-192.png web_template/icon-512.png web/
```

Treat any `SCRIPT ERROR` / `Parse Error` in the output as a failure even when the exit code is 0.

## Cloud session setup

`.claude/hooks/session-start.sh` (registered in `.claude/settings.json`) runs at the start of Claude Code cloud
sessions and installs what a fresh container lacks, only when missing: Godot (the version in `.godot-version`) into `~/.local/bin`
and Pillow (`tools/tandem_push.py`). It still also installs the Atelier CLI and numpy, which the rewrite no longer uses (removing
them from the hook is pending Paul's OK, since the hook is permissions-sensitive). It runs synchronously, does nothing outside cloud sessions, and only warns if a download fails.
It does not install the Web export templates (1.2 GB): without them the export check cannot run locally, so rely
on CI for that step or install them by hand into `~/.local/share/godot/export_templates/4.7.2.stable/`.

## CI / deploy (`.github/workflows/deploy.yml`)

- Checks run on pushes to `main`, `develop`, `feature/**`, on PRs targeting `develop`/`main`, and on manual dispatch.
- Push to `develop` → Firebase preview channel `develop`. Push to `main` → `live`. Feature branches never deploy.
- Requires the repo secret `FIREBASE_SERVICE_ACCOUNT`.
- `web/` and `.godot/` are build output and git-ignored. Never commit them.

## Rewrite status (2026-11-27)

The game is being rebuilt from scratch as a true top-down game; the 3/4-view game (oblique art, Atelier tools,
the polisher) was removed in M0 and lives in git history before `feature/topdown-m0`. Milestones, one
`feature/*` branch each: M0 skeleton → M1 movement, aim, camera, viewport → M2 melee, guns, throw, pickups →
M3 enemies → M4 level loader, doors, glass → M5 death/restart, score, combo, HUD (first playable slice) →
M6 Tandem art pass → M7 grade screen. The plan and Paul's answers are in `tasks/future-tasks.md`.

## View and art (top-down)

- **Overhead camera, one sprite per actor, turned by the engine to the aim** (Paul, 2026-11-27). Legs are their
  own 8-frame strip turned to the movement direction; the torso is one set per weapon. Every actor draws through
  one `Look` node (`set_aim`, `set_move`, `play`), so a switch to 4-direction sprites would replace only that node.
- A tile is 32 art pixels; a door is one tile; a character is a ~24x24 box in a 32 px cell (bigger cells only for
  reach, head pinned to the same pixel). The world is rendered pixel-true (resolution chosen and measured in M1).
- **Art is drawn in Tandem** (Paul's live editor, http://localhost:7480) with the `tandem` skill: read its
  `references/topdown/` (core rules, characters, animation, environment, ...) and `references/engineer.md` (the
  pixel-art rules and which Tandem check enforces each). Export with `bin/tandem export godot <dir>` (SpriteFrames
  `.tres` plus an extruded sheet) into `assets/sprites/`; never hand-edit exported files. A sprite passes Tandem
  `lint` and the style stats (`compare`: dark share 0.35–0.50, 8–14 colours, outlined) before it is wired in.
- Style: black carries the drawing (outline plus 1 px inner contours), short ramps, one locked neutral ramp for the
  whole game and a short hue ramp per character family. Bodies, props and walls are outlined; floors, light,
  effects and UI are not. No partial transparency.
- Until real art exists, actors and tiles are simple outlined placeholders drawn in code at the real cell sizes.
- Lighting, glow, gore, particles and all audio stay procedural. Sound is `scripts/sfx.gd`.
- `.claude/skills/pixel-art-engineer` holds the general craft rules; its sections 8–9 describe the removed 3/4
  pipeline and are superseded by the Tandem references.

## Display and web shell

- **Pixel-true view** (`main.gd`): the world is drawn into a `SubViewport` and shown by a `SubViewportContainer`
  at a whole-number scale (`stretch_shrink`), so rotated sprites land on the same art-pixel grid as everything
  else. The window stretch mode is `disabled`: one canvas unit is one window pixel, and the UI is drawn at full
  resolution on top. `Main.scale_for(size)` picks the whole number that brings the short side closest to
  `SHORT_TARGET` (330 art px); the long side expands with the window (no black bars), and the leftover, always
  fewer pixels than the scale, shows `BORDER`. Measured (M1): 1280x720 x2, 1920x1080 x3, 2560x1440 x4 (all
  640x360 art px, 20x11.2 tiles), iPhone 2556x1179 x4 (639x294), Android 2400x1080 x3 (800x360), 3840x2160 x7
  (548x308). The short side stays 9.2–11.2 tiles. Asserted by the smoke test.
- Mouse aim needs the player's window position: `Main.to_window()` (canvas transform x scale), passed to
  `controls.gd` as `aim_origin`.
- Portrait and landscape are both supported. HUD and touch controls are laid out in units (the SHORT screen side
  is 360 units; `W` x `H` units overall) by `Controls.layout()` and anchored to the corners; never use fixed pixel
  positions there. The smoke test checks the controls stay on screen and do not overlap on several screen shapes.
- Touch: MOVE stick (left); HIT/FIRE (hold to attack, drag to aim), THROW, KICK/EXEC, LOOK (hold). Keyboard and
  mouse: WASD, mouse aim, left click attack, right click or Q throw, E pick up, Space kick/execute, Shift look far,
  R restart. No dash. Presses are buffered for 100ms in `controls.gd`; gameplay must only `take()` a press when it
  can act on it.
- `web_template/custom_shell.html` is the export shell (Godot's default plus the fullscreen toggle, and PWA tags).
  `manifest.webmanifest` and the icons are copied into `web/` by CI after the export; do the same locally.

## Project layout

- `project.godot`, `export_presets.cfg` (preset `Web`, no threads), `main.tscn` (root node + `scripts/main.gd`).
- `scripts/main.gd` — the pixel-true view, floor build, camera (leads toward the aim; LOOK pushes it far).
- `scripts/level.gd` — ASCII floor map → `TileMapLayer` (placeholder tileset with wall collision).
- `scripts/player.gd` — movement (0.1 s acceleration, corner rounding) and aim. `scripts/look.gd` — how an actor
  is drawn (legs turned to the movement, torso to the aim); the only file that knows the view.
- `scripts/controls.gd` — touch sticks/buttons + keyboard/mouse. `scripts/sfx.gd` — synthesised sound and music.
- `tools/tandem_push.py` — put a sheet into a Tandem sprite to play, lint or hand-paint it.
- `web_template/` — HTML shell, PWA manifest, icons.
- `tests/smoke_test.gd` — headless test; drives the game through `controls.override`.

## Gameplay design

Load the `gameplay-craft` skill before changing combat, enemies, noise, weapons, scoring, the HUD or menus, the
camera or level pacing, and before sizing or animating a new asset: its section 9 is the scale and animation
baseline. Its "REDLINE status" lines describe the removed 3/4 game; update them as each milestone lands. Rebuild
ideas in our own way; never copy another game's code, art, sound, text or levels. Another game's sprites may be
measured, never traced, recoloured or committed.

## Tasks

`tasks/` tracks the plan: `future-tasks.md` (the rewrite milestones and later work), `assets-debt.md` (what art
exists and what is still needed) and `done.md`. Update them in the same branch as the work.

**All art is our own.** Every sprite, tile, icon and sheet is drawn for REDLINE in Tandem, or generated with
pixelgen from our own prompts (Apache-2.0 models only, with a `.pixelgen.json` sidecar) and used as a reference.
Third-party packs, free or paid (itch.io, CraftPix, Kenney, the zips in `~/Downloads`), are never used: no pixels,
no conversion, no tracing, no img2img base. The measure-only packs (groups B and C in the tandem skill's
`references/topdown/sources.md`) are for measuring proportions and timing only.

## Conventions

- Scripts reference each other with `preload` constants, not `class_name` or autoloads (keeps `-s` test runs working).
- Nearest filtering. Mobile-first: every action must be reachable by touch.
- Feel rules, re-asserted in the smoke test as each milestone brings them back: the player reaches and leaves
  walking speed in 0.1s and is slid round a wall corner it walks straight into; an enemy that spots the player
  waits a 0.25s notice beat (a "!" pops) before coming; restart after death stays under 0.2s.
- Physics interpolation is on (`project.godot`, asserted by the smoke test): actors move in 60 Hz physics ticks and
  are drawn between ticks. Anything that teleports an actor mid-play must call `reset_physics_interpolation()` on it.
- New gameplay behaviour gets an assertion in `tests/smoke_test.gd`.
