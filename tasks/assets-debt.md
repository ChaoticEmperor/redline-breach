# Asset debt

What art REDLINE // 1989 has, what it will need, and where each piece should come from.
This is a long-term list. It covers more than the current floor, and every row says which
feature or level needs the asset. Keep it current: when an asset lands, move its row to
`done.md`.

## Rules (read before using any row)

1. **No raw packs in this repo.** Third-party packs stay outside git (locally they're in
   `~/Downloads/assets_clean.zip`). Commit only what the game uses: the converted sprite, its
   tool or script, and its `.pixelgen.json` sidecar if pixelgen made it. A pack sprite we
   don't use never goes into `assets/`.
2. **No licence, no ship.** The zip holds no licence files, so every pack below is marked
   *unconfirmed* except the two CraftPix zombie families the infected already use. A pack can be a **reference** now (for proportions, the list of
   items, and how its animations are staged), but none of its pixels go into a build until its
   row says where it came from and gives a licence that allows commercial use. Fill in the
   **Source / licence** column when you find the itch.io / CraftPix page or the receipt.
3. **assets-mapped.zip is study-only, forever.** Those are ripped sprites from a commercial
   game (four VHS sprites matched pixel for pixel). We may look at them to learn how the
   animations are staged (frame counts, what each death shows, how a get-up reads). We never
   trace, convert, use them as an img2img base, or commit them. What we learned from them is in
   *Animation targets* below, written as our own numbers.
4. **Everything is redrawn in REDLINE's style.** That style is a 3/4 oblique view, 2 sheet
   pixels per world pixel (a map cell is 32 sheet px), clean cel shading with 4-step ramps and
   coloured outlines inside a dark contour, and the locked palette (`sheet_player_v3`, 42
   colours plus the neon/UI colours). A pack sprite or a pixelgen output is only a
   **reference**. It goes through the reference-conversion method (`atelier-pixel-art` section
   3, `pixel-art-engineer` section 8) and passes its gates before it ships.
5. Lighting, glow, gore particles and all audio stay procedural (`fx.gd`). They are not on this
   list as art.

## The view decision (long term)

**Keep the 3/4 oblique view.** Most of the useful material in `assets_clean` is in that view or
close to it. The interior sets (office, shelter, messy, bathroom, workshop, modern interior)
use the RPG "top face plus front face" convention, which is our prop convention. The pure
overhead packs (`topdown_*`) and the side-view packs (zombie man/woman/wild, urban zombie,
weapons) are references only: they inform the item list and the poses, not the sprites. A move
to pure top-down would throw away the converted player, the held-weapon system (16
directions, back arc) and every prop. Nothing in the packs is worth that.

Scale: the 16 px-per-tile sets would need 2x to reach our 32 px cell, and the 32 px sets are
1:1. Neither drops in directly, because rule 4 still applies.

## What we have now

| Area | Assets | Made by |
|---|---|---|
| Player | `sheet_player_v3` (96 px cells: idle 4, run 6, kick 2, death 3) + front fist | `convert_reference.py` from `assets/raw/player_reference.png` |
| Infected | shambler, horde, runner, bloater (112 px cells: walk 7–12, lunge 4–7, down 1 = corpse; heads doubled to match the player) | `import_infected.py` from CraftPix free sheets in `assets/raw/infected/` (see `CREDITS.md`) |
| Infected (riot) | riot guard (64 px cells: walk 4, lunge 1, down 1) | `draw_characters.py`, code-drawn, coarser pixel size |
| Weapons | pipe, pistol, shotgun: `held_*` (16 dirs), `hud_*`, `top_*` | `draw_weapons.py` |
| Props | 27 nightclub props (`scripts/prop_atlas.gd`), normal map prototype | `draw_props.py` |
| Floors | bar planks, concrete, corridor carpet, dancefloor, elevator steel, kitchen/restroom tile, VIP carpet | `slice_sheets.py` from `assets/raw/` |
| Unused | Kenney top-down shooter (CC0), old sliced top-down chars | remove when nothing points at them |

## `assets_clean.zip`: what each pack is good for

About 2,700 files, flat-named `<pack>_<part>`. "Fit" is the fit with our view and scale:
**high** = same view, convert directly; **ref** = right subject, wrong view (redraw from it);
**low** = not for this game.

| Pack (prefix) | Files | What it is | View / scale | Fit | Use in REDLINE | Source / licence |
|---|---|---|---|---|---|---|
| `office_16x16`, `office_32x32` | 10+10 | office building: walls, terrain, furniture, exterior, icons, ruined variants | 3/4 RPG, 16/32 px | high | **office / police-HQ floor** props and wall set; ruined variants for later floors | unconfirmed |
| `shelter_16x16`, `shelter_32x32` | 9+9 | survivor shelter: Quonset huts, fences, crates, beds, supplies, loot icons | 3/4 RPG | high | storage room, **safe-room** between floors, loot icons | unconfirmed |
| `messy_16x16`, `messy_32x32` | 9+9 | suburban houses, fences, garden, clutter, furniture | 3/4 RPG | high | **motel** rooms and exterior, clutter | unconfirmed |
| `public_bathroom` | 6 | stalls, sinks, urinals, mirrors, doors | 3/4 RPG | high | restroom zone (now code-drawn): more variety | unconfirmed |
| `workshop*`, `misc_makeshift`, `misc_canned` | 5 | benches, tools, machines; crafting material icons (tools, cloth, wood, glass, paper, plastic, electric, metal, glue) | 3/4 RPG | high | storage/maintenance rooms; material icons if crafting ever comes | unconfirmed |
| `modern_interior` | 64 | interior sheets + 32x64 RPG characters (walk/idle, 4 directions) | 3/4 RPG | high (props), ref (people) | living rooms, kitchens; civilian/NPC **proportion reference** | unconfirmed (looks like a well-known paid interiors pack: check its terms, which usually forbid redistribution) |
| `garden_planter` | 7 | planters, barrels, crops, potted plants | 3/4 RPG | high | lobby/VIP plants, rooftop | unconfirmed |
| `gas_station` | 72 | 16 px tiles, canopy, 24-7 mart front, 4-dir civilians + zombies, blood decals | 3/4 RPG, 16 px | high | **street / gas-station exterior** level; mart interior | unconfirmed |
| `zombie_apoc` | 533 | big 16 px city tileset: roads, cars, buildings, fences, debris, many tiny zombie/survivor heads | 3/4-ish, 16 px | ref | **street level** layout and car/debris list; too small to convert 1:1 | unconfirmed |
| `postapoc_objects/buildings/background/…` | ~780 | 16 px props (barrels, benches, hydrants, containers, garbage), building tiles, backgrounds | mixed, 16 px | ref | rubble, street furniture list | unconfirmed |
| `postapoc_character`, `postapoc_enemies` | 505 | tiny (~16 px) side/top character frames: bat, guns, helmet; zombie walk, attack, shot, gore | mixed, 16 px | ref | animation *timing* reference only (too small) | unconfirmed |
| `postapoc_ui` | 100 | bullets/shells, HP/hunger bars, inventory, crafting, menu frames | UI | ref | ammo counter glyphs (shell/bullet), menu frame ideas | unconfirmed |
| `topdown_player`, `topdown_enemy`, `topdown_blood`, `topdown_*` | ~45 | pure overhead survivor (head/body/legs split), overhead deaths with gore, cars, corpses | overhead | low/ref | gore *staging* (head/chest death variants); cars as reference | unconfirmed |
| `topdown_future` | 135 | sci-fi overhead: creatures, roach, HUD, lights, particles, gore | overhead | low | not on theme (sci-fi). Skip | unconfirmed |
| `zombie_man`, `zombie_woman`, `zombie_wild` | 30 | side-view 96 px strips: idle, walk, run, attack, bite, scream, eating, hurt, jump, dead | side | **in use** | the runner already comes from this family; its unused strips (hurt, scream, eating, jump) are the source for C2 / C3 | CraftPix "Free Zombie Sprite Sheet Pack" (likely; compare with `assets/raw/infected/`): CraftPix free licence, see below |
| `urban_zombie` | 20 | side-view 128 px strips: suit zombie, walk/attack/fall/dead | side | **in use** | shambler, horde, bloater already come from this family | CraftPix "Free Urban Zombie Sprite Sheet Pixel Art Pack" (likely): CraftPix free licence |
| `zombie_minigame` | 77 | small top-down shooter: characters, enemies, city tiles, explosion/smoke FX, UI | overhead, small | ref | explosion and smoke *timing* (our FX stay procedural) | unconfirmed |
| `gun_guns`, `gun.png` | 51 | 50 side-view firearms, 64x32 (pistols, revolvers, SMGs, rifles, shotguns) | side | ref | **HUD icons** and the gun roster; `held_*` are redrawn in 16 dirs | unconfirmed |
| `melee_weapon` | 51 | 50 side-view melee: bats, pipes, knives, machete, axe, crowbar, wrench, saw, chainsaw… | side | ref | **melee roster** and HUD icons | unconfirmed |
| `fantasy_weapon` | 51 | swords, staffs | side | low | off theme. Skip | unconfirmed |
| `survival_items` | 101 | 100 32x32 item icons: food, meds, tools, radio, walkie, floppy, clothes, keys | icon | high | **pickups, HUD icons, grade-screen badges** | unconfirmed |
| `wasteland_tileset*` | 6 | small desert tileset (.aseprite included) | 3/4, 8 px | low | skip | unconfirmed |
| `environment.png` | 1 | 512x384 sample scene | — | low | skip | unconfirmed |

**CraftPix free licence** (https://craftpix.net/file-licenses/, read 2026-11-26): commercial use is
allowed and attribution is not required. You may not resell the source files, or redistribute
the art (modified or not) so that another person can use the files. Using the art inside the game
is fine. **Using the assets for AI training is banned**, so a CraftPix sprite is never a pixelgen
`edit` input or an img2img base. Consequence: the original sheets now in
`assets/raw/infected/` are downloadable from this public repo. That is a decision for Paul (see
*Open questions*).

**Most valuable, in order:** `survival_items` (icons, nearly 1:1), the office / shelter / messy /
bathroom interiors (the next floors' props), `gas_station` + `zombie_apoc` (an exterior level),
the two weapon sets (the roster and HUD icons), and the side-view zombies (the infected action
list).

## Asset debt: what the game needs that it does not have

Priority: **P1** = needed by the next features (see `future-tasks.md`), **P2** = the next
level, **P3** = later. Source: **pack** = convert from a pack once its licence is confirmed;
**pixelgen** = generate a reference, then convert (prompt given; profile `redline`);
**draw** = paint with the project's `draw_*` scripts or Atelier (small or geometric things);
**proc** = procedural in `fx.gd`.

### Characters

| # | Asset | Why / which feature | Pri | Source | Notes / pixelgen prompt |
|---|---|---|---|---|---|
| C1 | **Riot guard** at the new infected scale; infected bodies a little wider (they are thinner than the player) | riot is still code-drawn at a coarser pixel size | P1 | pixelgen reference + convert | `-k infected`: "infected in riot police armour, cracked visor, baton, heavy stance" |
| C1b | A bloater that reads as a bloater: acid-green glow, swollen torso | its fuse warning is acid green and the body should match | P2 | edit of our converted sheet (not of the CraftPix PNG) | |
| C2 | Infected **knockdown → floor → get-up** (down 1 → about 3 + get-up 7) | feature 5 (random knockdown length) needs a readable get-up | P1 | draw, or the `hurt` strips of the CraftPix family | currently a single `down` frame, which is also the corpse |
| C3 | Infected **directional deaths**: front/back × blunt, cut, shot, blast | gore feedback; matches weapon type | P2 | draw | 1–4 frames each plus a corpse frame |
| C4 | Player **melee swing** per melee weapon (about 7–9 frames) | the pipe currently has no swing body animation | P1 | draw/convert | swing arc drawn as an effect on `Fx._dot` |
| C5 | Player **shoot/recoil** (2–3 frames), shotgun pump (about 5) | weapon feel | P2 | draw | |
| C6 | Player **throw** (about 5 frames) | feature 3 (throwable empty guns) | P1 | draw | |
| C7 | Player **ground finisher** on a downed infected (about 4–6 frames per weapon class) | combo/knockdown loop (feature 5) | P2 | draw | |
| C8 | Boss / special infected per floor | later levels | P3 | pixelgen | design first |
| C9 | Civilians / survivors (rescue or ambience) | motel/street levels | P3 | pack ref (`modern_interior`, `gas_station`) + pixelgen | |

### Weapons

| # | Asset | Why | Pri | Source | Notes |
|---|---|---|---|---|---|
| W1 | Empty-gun **thrown** sprite (spin frames, 8 dirs) for pistol and shotgun | feature 3 | P1 | draw (`draw_weapons.py`) | can reuse `held_*` directions as spin frames |
| W2 | Melee roster: bat, knife, machete, crowbar, fire axe, bottle (breaks) | weapon variety | P2 | draw, ref `melee_weapon` | `held_*` 16 dirs + `hud_*` + `top_*` each |
| W3 | Gun roster: revolver, SMG, assault rifle, double-barrel | weapon variety | P2 | draw, ref `gun_guns` | same three files each |
| W4 | Throwables: molotov, pipe bomb | crowd control | P3 | draw | fire stays procedural |

### Props and tiles (per level)

| # | Asset | Level | Pri | Source |
|---|---|---|---|---|
| P1 | Nightclub extras: coat check, cigarette machine, neon tubes, pool table, broken booth | nightclub (now) | P2 | draw / pixelgen `-k prop` |
| P2 | Knocked-down prop states (table on its side, toppled stool, smashed arcade) | physics feel, cover | P2 | draw |
| P3 | Motel: beds, TV on dresser, ice machine, reception desk, room doors with numbers, pool | **motel** (`tools/ref/ref_motel.png`) | P2 | pack `messy_*`, `modern_interior` |
| P4 | Subway: turnstiles, benches, platform edge, train car interior, tiled walls, ad posters (made-up brands) | **subway** (`tools/ref/ref_subway.png`) | P2 | pixelgen (no pack covers it) |
| P5 | Office / police HQ: desks, filing cabinets, cell bars, evidence lockers | office level | P3 | pack `office_*` |
| P6 | Street / gas station: pumps, canopy, wrecked cars, hydrants, dumpsters | exterior level | P3 | pack `gas_station`, `zombie_apoc` |
| P7 | Floors and walls for each new level (carpet, tile, platform concrete, asphalt) | each level | P2 | `slice_sheets.py` pipeline from a reference |

### UI / HUD

| # | Asset | Why | Pri | Source |
|---|---|---|---|---|
| U1 | **Grade screen**: letter grades (S/A/B/C/D) in the neon type, stat icons (time, kills, combo, accuracy) | feature 4 | P1 | draw (type) + `survival_items` ref (icons) |
| U2 | Ammo glyphs: pistol round, shotgun shell | HUD clarity | P2 | draw, ref `postapoc_ui` |
| U3 | Pickup icons: medkit, ammo box, keycard, cassette (collectible) | pickups | P2 | pack `survival_items` |
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
The study of the reference pack adds three points that section 9 doesn't spell out:

- **The death is picked from hit direction × damage type** (front/back × blunt, cut, shot,
  blast), so one blow reads differently from another. Most deaths are short and end on a corpse
  frame; a few long showpiece deaths are kept for finishers.
- **Knockdown is a state, not a death.** While an enemy is down, the player can finish it with
  a ground finisher per weapon class (C7). This is the loop of feature 5.
- **Furniture has a knocked-down state** (1–3 frames), and a blood pool keeps spreading under a
  corpse for several seconds.

## Open questions for Paul

- Where did each `assets_clean` pack come from (itch.io / CraftPix page or receipt)? That fills
  the licence column and unlocks the **high**-fit packs.
- Which levels come after the nightclub, and in what order? The concept art suggests motel,
  then subway. The office/police-HQ and street rows above assume more.
- **The CraftPix originals in `assets/raw/infected/` are public.** The free licence forbids
  redistributing the art so others can use the files. Options: (a) make the repo private;
  (b) keep the originals outside git (gitignored, fetched by hand) and commit only the packed
  `infected_*.png`. Removing them from history too would mean rewriting it, which is your call.
- Should the repo go private before converted pack art lands? Converted art is still derived
  from the pack, so the pack's licence decides whether a public repo is allowed.
