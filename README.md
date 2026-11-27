# REDLINE // 1989

A fast, lethal top-down action game: one hit kills, restart is instant, and every floor is cleared room by room.
1989, a nightclub, an infection outbreak: infected and armed humans. Godot 4.7.2 (GDScript), exported for Web,
hosted on Firebase.

- Live: https://redline-1989.web.app (deploys from `main`)
- Preview: the `develop` channel, linked from each `develop` run of the GitHub Actions workflow

**Being rebuilt from scratch** as a true top-down game (2026-11-27). The earlier 3/4-view game is in git history
before `feature/topdown-m0`. The milestones are in `tasks/future-tasks.md`.

## Working on it

`CLAUDE.md` is the source of truth for the branching rules (`feature/*` -> `develop` -> `main`), the checks
that must pass, and how the project is laid out. In short:

```sh
godot --headless --import
godot --headless --quit
godot --headless -s tests/smoke_test.gd
mkdir -p web && godot --headless --export-release "Web" web/index.html
```

## Art

Drawn in Tandem (a live pixel editor) and exported to Godot SpriteFrames; until then, placeholders drawn in code.
Sound is synthesised in code (`scripts/sfx.gd`).

## Licences

All art and sound in REDLINE is made for it. No third-party art is used.
