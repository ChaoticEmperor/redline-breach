# Asset debt

What art REDLINE // 1989 has, what it will need, and how we will make each piece. This is a
long-term list: it covers more than the current floor, and every row says which feature or
level needs it. Keep it current: when an asset lands, move its row to `done.md`.

## Rules

1. **All art is our own.** Every sprite, tile, icon and sheet is drawn by our `tools/draw_*`
   scripts or Atelier, or generated with pixelgen from our own prompts (Apache-2.0 models only)
   and then converted. We never use third-party packs, free or paid (itch.io, CraftPix,
   Kenney, `~/Downloads/assets_clean.zip`): no pixels from them, no conversion, no tracing, no
   recolouring, no img2img base. Their terms (no AI use, no redistribution, no modification)
   would bind the game, and our own art carries no such limits.
2. **Learning is allowed, copying isn't.** We may look at games and packs to learn a principle,
   such as how a get-up reads or how big a door is next to a body. We write the principle down
   in our own words and numbers (`gameplay-craft` section 9, *Animation targets* below) and
   then make the asset from scratch. `assets-mapped.zip` (ripped sprites from a commercial
   game) is that kind of study material and nothing more.
3. **One style.** That style is a 3/4 oblique view, 2 sheet pixels per world pixel (a map cell
   is 32 sheet px), clean cel shading with 4-step ramps and coloured outlines inside a dark
   contour, and the locked palette (`sheet_player_v3`, 42 colours plus the neon/UI colours). A
   pixelgen output is a **reference**. It goes through the reference-conversion method
   (`atelier-pixel-art` section 3, `pixel-art-engineer` section 8) and passes its gates before
   it ships.
4. **Provenance travels with the file.** Every pixelgen output has a `.pixelgen.json` sidecar
   (prompt, model, licence, seed); commit it beside the reference in `assets/raw/`. The
   pixelgen `redline` profile refuses third-party files as edit inputs (`denied_inputs`).
5. Lighting, glow, gore particles and all audio stay procedural (`fx.gd`). They are not on this
   list as art.

## View: keep the 3/4 oblique view

The converted player, the held-weapon system (16 directions, back arc), the props and the
lighting are all built for it. Pure top-down would throw that away for nothing.

## What we have now

| Area | Assets | Made by | Ours? |
|---|---|---|---|
| Player | `sheet_player_v3` (96 px cells: idle 4, run 6, kick 2, death 3) + front fist | `convert_reference.py` from `assets/raw/player_reference.png` (AI-generated reference) | yes, but no sidecar (I2) |
| Infected | shambler, horde, runner, bloater (112 px cells: walk 7–12, lunge 4–7, down 1 = corpse) | `import_infected.py` from `assets/raw/infected/` | **no: CraftPix free art, to replace (I1)** |
| Infected (riot) | riot guard (64 px cells: walk 4, lunge 1, down 1) | `draw_characters.py` | yes |
| Weapons | pipe, pistol, shotgun: `held_*` (16 dirs), `hud_*`, `top_*` | `draw_weapons.py` | yes |
| Props | 27 nightclub props (`scripts/prop_atlas.gd`), normal map prototype | `draw_props.py` | yes |
| Floors | bar planks, concrete, corridor carpet, dancefloor, elevator steel, kitchen/restroom tile, VIP carpet | `slice_sheets.py` from `assets/raw/floors.png` (AI-generated) | yes, but no sidecar (I2) |
| Concept art | `tools/ref/ref_nightclub/motel/subway.png` | AI-generated | yes, but no sidecar (I2) |
| Unused | old sliced top-down chars/props from `slice_sheets.py` | — | remove when nothing points at them |

## Debt we must clear first

| # | Task | Pri | How |
|---|---|---|---|
| I1 | **Replace the CraftPix infected** with our own sheets, then delete `assets/raw/infected/`, `import_infected.py`, the `infected_*` sprites and `scripts/infected_atlas.gd` (or keep the packer if our sheets use the same layout) | P1 | pixelgen references per type (prompts in C1), converted at the same scale and frame counts (walk 8–12, lunge 4–7, down → get-up). The packer's head-matching step isn't needed when we draw to the player's proportions from the start |
| I2 | **Record where the AI references came from**: `player_reference.png`, `floors.png`, `characters.png`, `props.png`, the concept art. The model wasn't recorded | P2 | regenerate through pixelgen (an Apache-2.0 model and a sidecar) the next time each is reworked; until then they're noted here as AI-generated, model unknown |
| I3 | Public history still holds the CraftPix originals (from 2026-11-25) | P1, after I1 | **Decided (Paul, 2026-11-26): rewrite history.** Once our own infected have replaced them, strip `assets/raw/infected/` and the CraftPix-derived `infected_*` sprites from every commit (`git filter-repo`), then force-push `develop` and `main` and tell every clone to re-clone |

## Asset debt: what the game needs that it does not have

Priority: **P1** = needed by the next features (see `future-tasks.md`), **P2** = the next
level, **P3** = later. Source: **pixelgen** = generate a reference with profile `redline`, then
convert (prompt given); **draw** = paint with the project's `draw_*` scripts or Atelier (small
or geometric things); **proc** = procedural in `fx.gd`.

### Characters

| # | Asset | Why / which feature | Pri | Source | Notes / pixelgen prompt |
|---|---|---|---|---|---|
| C1 | **Infected, one reference per type** at the player's scale and proportions | I1; riot is also at a coarser pixel size | P1 | pixelgen `-k infected` | "shambling infected in a torn 1989 club outfit, grey-green skin, slack jaw", "infected clubber in a sequin dress, tangled hair, arms reaching", "lean sprinting infected in a tracksuit, hunched forward", "swollen bloated infected, glowing acid-green veins, bursting shirt", "infected in riot police armour, cracked visor, heavy stance" |
| C2 | Infected **knockdown → floor → get-up** (down about 3 + get-up 7) | feature 5 (random knockdown length) needs a readable get-up | P1 | pixelgen edit of our C1 pick + draw | currently a single `down` frame, which is also the corpse |
| C3 | Infected **directional deaths**: front/back × blunt, cut, shot, blast | gore feedback; matches weapon type | P2 | draw | 1–4 frames each plus a corpse frame |
| C4 | Player **melee swing** body frames per melee weapon (7–9) | the swing timing is done; the body doesn't move | P1 | draw / edit of the player reference | swing arc drawn as an effect on `Fx._dot` |
| C5 | Player **shoot/recoil** (2–3 frames), shotgun pump (about 5) | weapon feel | P2 | draw | |
| C6 | Player **throw** (about 5 frames) | feature 3 (throwable empty guns) | P1 | draw | |
| C7 | Player **ground finisher** on a downed infected (about 4–6 frames per weapon class) | combo/knockdown loop (feature 5) | P2 | draw | |
| C8 | Player **8-frame walk** | `gameplay-craft` section 9 | P2 | pixelgen edit of the player reference | |
| C9 | Boss / special infected per floor | later levels | P3 | pixelgen | design first |
| C10 | Civilians / survivors (rescue or ambience) | motel/street levels | P3 | pixelgen `-k character` | |

### Weapons

| # | Asset | Why | Pri | Source | Notes |
|---|---|---|---|---|---|
| W1 | Empty-gun **thrown** sprite (spin frames, 8 dirs) for pistol and shotgun | feature 3 | P1 | draw (`draw_weapons.py`) | can reuse the `held_*` directions as spin frames |
| W2 | Melee roster: bat, knife, machete, crowbar, fire axe, bottle (breaks) | weapon variety | P2 | draw | `held_*` 16 dirs + `hud_*` + `top_*` each |
| W3 | Gun roster: revolver, SMG, assault rifle, double-barrel | weapon variety | P2 | draw | same three files each |
| W4 | Throwables: molotov, pipe bomb | crowd control | P3 | draw | fire stays procedural |

### Props and tiles (per level)

| # | Asset | Level | Pri | Source |
|---|---|---|---|---|
| P1 | Nightclub extras: coat check, cigarette machine, neon tubes, pool table, broken booth | nightclub (now) | P2 | draw / pixelgen `-k prop` |
| P2 | Knocked-down prop states (table on its side, toppled stool, smashed arcade) | physics feel, cover | P2 | draw |
| P3 | Motel: beds, TV on dresser, ice machine, reception desk, numbered room doors, pool, neon vacancy sign | **motel** (`tools/ref/ref_motel.png`) | P2 | pixelgen `-k prop` + draw |
| P4 | Subway: turnstiles, benches, platform edge, train car interior, tiled walls, ad posters (made-up brands) | **subway** (`tools/ref/ref_subway.png`) | P2 | pixelgen `-k prop` |
| P5 | Office / police HQ: desks, filing cabinets, cell bars, evidence lockers | office level | P3 | pixelgen + draw |
| P6 | Street / gas station: pumps, canopy, wrecked cars, hydrants, dumpsters, 24-hour mart front | exterior level | P3 | pixelgen + draw |
| P7 | Safe room between floors: cots, supply crates, weapon rack, radio | safe room | P3 | pixelgen + draw |
| P8 | Floors and walls for each new level (carpet, tile, platform concrete, asphalt) | each level | P2 | `slice_sheets.py` pipeline from a pixelgen reference (with sidecar) |

### UI / HUD

| # | Asset | Why | Pri | Source |
|---|---|---|---|---|
| U1 | **Grade screen**: letter grades (S/A/B/C/D) in the neon type, stat icons (time, kills, combo, accuracy) | feature 4 | P1 | draw |
| U2 | Ammo glyphs: pistol round, shotgun shell | HUD clarity | P2 | draw |
| U3 | Pickup icons: medkit, ammo box, keycard, cassette (collectible) | pickups | P2 | draw / pixelgen `-k icon` |
| U4 | Title / logo art, floor-intro cards | presentation | P3 | pixelgen reference + hand pass |

### FX (procedural; listed so we can plan their timing)

| # | Effect | Pri | Notes |
|---|---|---|---|
| F1 | Blood squirt on hit (about 7 frames), splat decal (3–8), slowly spreading pool | P2 | `Fx._dot` path, dithered; the pool grows for several seconds |
| F2 | Throw spin trail and impact sparks | P1 | feature 3 |
| F3 | Knockdown dust puff | P1 | feature 5 |

## Animation targets

Frame budgets (walk 8, swing 7–9 with a held frame, gunshot 2–3, get-up 7, deaths sized by the
blow, effects 7–9) are in **`gameplay-craft` section 9**. Measure a new animation against it.
The study adds three points that section 9 doesn't spell out:

- **The death is picked from hit direction × damage type** (front/back × blunt, cut, shot,
  blast), so one blow reads differently from another. Most deaths are short and end on a corpse
  frame; a few long showpiece deaths are kept for finishers.
- **Knockdown is a state, not a death.** While an enemy is down, the player can finish it with
  a ground finisher per weapon class (C7). This is the loop of feature 5.
- **Furniture has a knocked-down state** (1–3 frames), and a blood pool keeps spreading under a
  corpse for several seconds.

## Open questions for Paul

- Which levels come after the nightclub, and in what order? The concept art suggests motel,
  then subway; the office, street and safe-room rows assume more.
