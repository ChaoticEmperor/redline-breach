# Asset debt

What art REDLINE // 1989 has and what the top-down rewrite needs. Keep it current: when an asset lands, move its
row to `done.md`.

## Rules

1. **All art is our own**, drawn in Tandem for REDLINE, or generated with pixelgen from our own prompts
   (Apache-2.0 models only, `.pixelgen.json` sidecar committed beside it) and used only as a reference. Never
   third-party packs, free or paid: no pixels, no conversion, no tracing, no recolouring, no img2img base.
2. **Measure, don't copy.** Group B and C packs (tandem skill, `references/topdown/sources.md`) may be measured for
   proportions and timing; the principle is written down in our own words and numbers.
3. **One style** (tandem skill, `references/topdown/core.md`): top-down, black outline and inner contours, short
   ramps, a locked neutral ramp for the whole game, a short hue ramp per character family, no partial alpha.
   Floors are not outlined. A tile is 32 art px; a character is a ~24x24 box in a 32 px cell.
4. **Gates:** Tandem `lint` (outlined, strays, doubles) and the `compare` style stats (dark share 0.35–0.50,
   8–14 colours, fill 0.55–0.75) before a sprite is wired in.
5. **A warm colour marks the player.** Enemies, floors and props stay in other hues, so the player is never lost.
6. Lighting, glow, gore particles and all audio stay procedural.

## What we have

Nothing yet: the 3/4 art was removed in M0 (it is in git history). Placeholders are drawn in code.

## Needed for the first playable slice (M6)

| # | Asset | Frames | Notes |
|---|---|---|---|
| A1 | Player legs strip | walk 8 | turned to the movement direction; frame 0 legs hidden |
| A2 | Player torso: unarmed, pipe, pistol | walk 8 + attack 7–9 (melee) / 4–5 (gun) each | head pinned to one pixel; melee cell 48 px; smear frame |
| A3 | Infected rusher | walk 8 (shamble, arms forward), attack 5, deaths per cause, corpse | muted, grey-green skin |
| A4 | Armed guard | legs + torso as the player, shoot 4–5, deaths per cause, corpse | a distinct hue family |
| A5 | Nightclub floor tiles | 32x32, variants | not outlined, ~5 colours; dancefloor cycles colour, not shape |
| A6 | Walls, doors (open, kicked), glass (whole, broken) | — | outlined |
| A7 | Floor weapons: pipe, pistol, shotgun | 1 + thrown spin | 0.4–1 tile long, lighter outline |
| A8 | Props: bar, booth, table, stool, DJ booth | 1–3 knocked-down states | real widths, not one tile each |
