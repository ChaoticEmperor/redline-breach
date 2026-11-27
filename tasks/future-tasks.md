# Future tasks

The top-down rewrite (Paul, via donna, 2026-11-27). Each milestone gets its own `feature/*` branch, merged to
`develop` with `--no-ff` once CI is green (see `CLAUDE.md`); Paul approved pushing M0–M5 as they land. `main` is
untouched until Paul asks for a release. Load `gameplay-craft` for gameplay work and the `tandem` skill (its
`references/topdown/` and `engineer.md`) for art. Move a row to `done.md` when it merges.

## Decisions (Paul, 2026-11-27)

| Question | Answer |
|---|---|
| Camera | Overhead, one sprite per actor rotated to the aim (legs strip to the movement direction, torso per weapon), isolated in one `Look` node |
| Enemies | Keep the 1989 nightclub infection setting; armed humans beside the infected |
| Levels | Hand-made floors (ASCII map files loaded into a `TileMapLayer`), not seeded chunks |
| Dash | Dropped (the genre has none), unless Paul says otherwise |
| Render size | M1: whole-number scale bringing the short side closest to 330 art px, long side expands (no bars). 16:9 desktops all get 640x360 (20x11.2 tiles); iPhone 2556x1179 x4 = 639x294; Android 2400x1080 x3 = 800x360. A genre-close 480x270 would give 720p x2.67 and 1440p x5.33 (not whole numbers). One constant (`SHORT_TARGET`) if Paul wants it closer |

## Milestones

| # | Branch | Scope | Smoke-test rules it brings back |
|---|---|---|---|
| M0 | `feature/topdown-m0` | Delete the 3/4 game; keep CI, web shell, controls, procedural sound; empty placeholder room | physics interpolation, sounds, controls on screen |
| M1 | `feature/topdown-m1` | Pixel-true viewport (size measured, see above), player movement (0.1 s accel, corner rounding), aim (mouse; right stick on touch), camera lead + look-far, `Look` node with placeholder art; controls remapped (no dash; THROW, KICK/EXEC, LOOK) | accel, corner rounding, viewport scale is a whole number |
| M2 | `feature/topdown-m2` | Melee (silent, one-hit arc, held hit frame), pistol and shotgun (own ammo only, loud), throw anything (knockdown, lands as pickup), pickups | one hit kills, ammo, throw knockdown |
| M3 | `feature/topdown-m3` | Enemies: infected rusher and armed guard; cone sight on staggered frames, 0.25 s notice, A* chase, search last seen, noise draws the nearest 3–4 to scattered spots, first-shot delay, knockdown → execute, varied seeded get-up | notice beat, noise draw count and spread |
| M4 | `feature/topdown-m4` | Level loader (ASCII → `TileMapLayer` with collision and navigation; scenes for doors, glass, props, pickups, spawns); kicked doors knock down whoever is behind | every spawn reachable, doors knock down |
| M5 | `feature/topdown-m5` | Death → instant restart of the same floor, floor clear → exit, score, ~4 s combo refreshed by knockdowns, HUD. **First playable slice:** one nightclub floor, ~6 rooms, ~12 enemies | restart < 0.2 s, same floor on restart |
| M6 | — | Tandem art pass: player legs strip, pipe and pistol torsos, the two enemies (deaths per cause), tiles | lint + style stats per sprite |
| M7 | — | Floor-clear grade screen (count-up per category, letter grade) | deterministic grade |

## Later

- More weapons (bat, knife, SMG), more enemy types (by behaviour, not stats), more floors.
- A play-test bot for the new game (the old `tools/playbot.gd` was removed with the 3/4 game).
- Chapter frame (a quiet place, title card, floors, walk back, score), menus with moving type.
