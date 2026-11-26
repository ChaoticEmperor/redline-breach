# Future tasks

Work that is agreed or proposed but not started. Each feature gets its own `feature/*` branch,
merged to `develop` with `--no-ff` once CI is green (see `CLAUDE.md`). Load `gameplay-craft`
for gameplay work and `pixel-art-engineer` → `atelier-pixel-art` for art. Move a row to
`done.md` when it merges.

## Gameplay (agreed, in this order)

| # | Task | Notes | Art it needs (`assets-debt.md`) |
|---|---|---|---|
| G2 | **Noise draws only the 3–4 nearest infected**, each to a scattered spot near the source, not all to the exact point | stops the conga-line of the whole floor; smoke test: a shot draws at most N, and their targets are spread | — |
| G3 | **Throwable empty guns**: an empty gun can be thrown; it spins, stuns or knocks down on hit, and drops | gives an empty gun a last use; smoke test on knockdown and drop | C6, W1, F2 |
| G4 | **Floor-clear grade screen**: time, kills, best combo, accuracy, then a letter grade | the score has a payoff; deterministic for the same seed and inputs | U1 |
| G5 | **Longer combo window, extended by knockdowns; random knockdown length** | knockdown → finisher loop; seeded randomness so a restart replays the same | C2, C7, F3 |
| G6 | **SCRIPT ERROR logger**: make any `SCRIPT ERROR` / `Parse Error` fail the smoke test and the playbot | from the Elusion study; CI already treats them as failures, this makes it local and in-game | — |
| G7 | White hit flash plus shader warm-up; stagger the bloater fuses | Elusion follow-ups in `gameplay-craft` | — |

## Art (from `assets-debt.md`, P1 first)

- C2: infected get-up (7 frames) for feature 5.
- C4 / C6: player melee-swing body frames (the swing timing is done) and throw frames.
- An 8-frame player walk (needs a new reference; `gameplay-craft` section 9).
- Grade-screen type and icons (U1).
- Remove the old sliced top-down sprites once nothing points at them.

## Levels (proposed)

- **Motel** floor (`tools/ref/ref_motel.png`): props P3, floors P7.
- **Subway** floor (`tools/ref/ref_subway.png`): props P4 (no pack covers it, so pixelgen).
- Later: office / police HQ (P5), street / gas station (P6).
- Safe room between floors (P7): weapon pick, grade recap.

## Tooling

- pixelgen: tune the `redline` prompt prefix for the 3/4 view; add a fixed-grid size for
  sprites meant to drop straight into a sheet; compare qwen-image-2512-turbo with z-image-turbo
  for drafts.
- I2: regenerate the AI references (player, floors, concept art) through pixelgen when each is
  next reworked, so each has a sidecar.
