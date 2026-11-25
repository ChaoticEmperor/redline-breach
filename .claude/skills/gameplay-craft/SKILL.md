---
name: gameplay-craft
description: >
  Design principles for fast top-down action games, learned from studying how
  a successful game in the genre is built, written as our own rules (no code or
  assets from it). Covers game feel, fair enemy perception, noise, weapons,
  scoring and grades, animation, menus and typography, and chapter structure,
  each with REDLINE's current status and how to measure a change. Load this
  before changing combat, enemies, scoring, the HUD or menus, camera, or level
  pacing in this project.
---

# Gameplay craft

These are principles, not a recipe. Each one says what it is for, so you can
judge when it applies. They were learned by reading how a celebrated game in
this genre is put together, then rewritten in our own words. A second study
(an MIT-licensed Godot action RPG) added the rules marked *(study 2)*. A third
measured a reference sprite set (sizes, frame counts, how much each frame
changes) and added section 9 *(study 3)*. **Never copy another game's code,
numbers-as-a-set, art, sound, text or levels.** Take the idea, rebuild it for
REDLINE, then measure it.

**Reference art is for measuring, not for making.** A sprite set from another
game may be opened to count frames, measure sizes against a tile or a body, and
see how a motion is split into frames. Its pixels are never traced, recoloured,
converted, cropped into ours or committed to the repo, renamed or not. What
goes into REDLINE is drawn for REDLINE (our tools, our references, or packs
whose licence allows it), built to the ratios and budgets in section 9.

## 0. How to work

1. Pick one principle. Say what player problem it fixes in REDLINE (a death
   that felt unfair, a floor that drags, a weapon that feels weak).
2. Build it on its own `feature/*` branch, with constants named after what they
   mean (`NOISE_DRAWS`, not `3`).
3. Prove it twice:
   - **Smoke test** (`tests/smoke_test.gd`): an assertion of the rule itself
     ("a shot draws at most N infected"). Break the code on purpose once and
     watch the assertion go red before you trust it green *(study 2)*.
   - **Play-test bot** (`tools/playbot.gd`, needs a display, `xvfb-run -a` in
     the cloud): play 150s on seed 1989 before and after; compare deaths,
     causes of death, kills and floor time from `playbot_log.txt`. Save the
     logs and screenshots under the recordings folder with a README.
4. Look at it: Movie Maker (`--write-movie out.png --fixed-fps 60`) for
   anything that moves.

A change that the numbers call better but looks or feels worse is not better.

## 1. Game feel

- **Responsive movement first.** Full speed and full stop in about a tenth of
  a second; slide the player round corners they clip. *REDLINE: done (`ACCEL`,
  `_round_corner`, asserted).*
- **Weight comes from the world reacting, not from the game stopping.** Screen
  shake sized per weapon, a flash of light at the muzzle, bodies thrown by the
  blow, casings, blood that stays. A whole-game freeze (hit-stop) is optional
  seasoning; in long kill chains it stacks into sluggishness, so ease it off as
  the chain grows. *REDLINE: shake, punch, kick and flash per weapon done;
  hit-stop on every kill (35ms) — easing it in chains is open.*
- **Shake fades at a steady rate**, not as a fraction of itself: big hits feel
  big, and the screen settles at a predictable time. *Done.*
- **The camera leads toward the aim**, and a hold-to-look key lets the player
  scout far ahead. Seeing a threat before it sees you is what makes a hard game
  fair. *Lead done; look-far key open.*
- **Restart is instant and the same floor.** Death is cheap, so the player
  learns the room. *Done, under 0.2s, asserted.*

## 2. Fair enemies

The player must always be able to say why they died.

- **Sight is a plain line of sight within range**, checked every few frames
  per enemy, with the checks spread out so they do not all fire on one frame.
  *Done (`think_t` starts random).*
- **A reaction beat before attacking.** When an enemy spots you it pauses
  (about a quarter second, with a visible cue) before it comes. Ranged enemies
  also wait a random moment before their first shot. *Done (`NOTICE`, "!").*
- **Danger must be readable before it lands.** Anything that kills in an area
  (an explosion, a burst) shows its reach and its timer while there is still
  time to step out. *REDLINE: done — the bloater's fuse draws a ring at the
  exact blast reach plus a ring closing on the centre (`Fx.warn`).*
- **Warning time is a budget, not a feel:** reaction time (about 0.25s) plus
  the time to walk from the worst spot to safety. If a danger needs more
  travel, give it a longer warning, not a smaller area *(study 2)*. *REDLINE:
  `FUSE_TIME >= REACTION + BLAST / SPEED`, asserted.*
- **The warning stays where it was painted.** A marker that follows its source
  is a delayed guaranteed hit *(study 2)*.
- **One warning at a time near the player.** Overlapping telegraphs are
  unreadable; stagger chain reactions so each one reads *(study 2)*. Open.
- **Noise draws a few, not all.** A gunshot alerts only the nearest few
  enemies in earshot, and sends each to a scattered spot near the sound, not
  the exact pixel. One shot should not pull the whole floor into one doorway.
  *REDLINE: `world.noise` sends every enemy in range to the exact point. Open
  (feature 2).*
- **Variety through behaviour, not stats.** Types differ in what they do (one
  grabs, one rushes, one bursts, one is armoured from the front), not in bigger
  numbers. *Done in spirit.*

## 3. Weapons and resources

- **Ammo is what the gun came with.** No reloads, no ammo pickups; you trade
  guns. Scarcity makes the silent melee weapon the main tool and the gun a
  decision.
- **Everything can be thrown.** An empty gun is a missile: it knocks the target
  down and lands as a pickup again. This keeps an empty weapon useful and gives
  melee a ranged opener. *REDLINE: an empty gun just switches back to the pipe.
  Open (feature 3).*
- **Silent melee, loud guns.** Noise is the cost of a gun. *Done.*

## 4. Scoring and grades

- **Reward boldness.** A kill is worth more the more armed, alerted enemies
  are around you at that moment. It pays the player for taking the risk the
  game is about.
- **A combo window long enough to plan in** (around four seconds), which
  knockdowns refresh. Too short and chains are luck. *REDLINE: 2.5s, refreshed
  by knockdowns. Lengthening is open (feature 5).*
- **The end-of-floor screen teaches.** Count categories up one by one (kills,
  chain bonus, variety of kill methods, time against a par), then show a letter
  grade. The player sees what they could do better. *Open (feature 4).*
- **Score pop-ups move and stack**: they rise, they are coloured by kind, the
  total rolls up instead of jumping.

## 5. Animation

- **Walk cycles of about 8 frames, attacks 7–12**, and playback speed scaled by
  how fast the body actually moves, so feet never skate.
- **Knockdowns vary in length** (a range, not one fixed time), so a floor of
  downed enemies does not all stand up together. *REDLINE: fixed 1.8s. Open
  (feature 5).*
- **Corpses are a handful of still poses chosen by how the enemy died** (shot,
  blunt, burst, executed), slid a little by the blow, and they stay for the
  whole floor. The floor becomes the record of the fight.

## 6. Menus and typography

- **Nothing on a menu sits still.** Title text is extruded (the glyph drawn
  several times, offset, darker behind) and each letter bobs on a sine wave
  offset from its neighbour. Background colours drift on slow sine waves at
  mismatched speeds, so the screen breathes.
- **One display font, big, with heavy shadows**, and a small clean font for
  numbers.
- **Every screen fits the fiction.** Pause, death and score screens use the
  same neon-and-noise language as the world.

## 7. Structure and story

- **A chapter is a loop with a quiet frame round the violence:** a calm place,
  a message that sends you out, a title card, the floors, a quiet walk back
  through what you did, the score, then a short scene. The quiet parts make
  the loud parts land and carry the story without cutscenes.
- **Show the aftermath.** Walking back past your own mess is storytelling the
  player wrote.

## 9. Scale and animation baseline *(study 3)*

Ratios, not pixels: everything is given against a **tile** (a door's width) or
a **body** (shoulder width), so it carries over to our 3/4 view and pixel size.
Measure a new asset against these before wiring it.

### Scale

- **A door is one tile and a body is about three quarters of it.** The gap
  either side of a body in a doorway is what makes doors a choke point without
  making them a snag. *REDLINE: door 1 tile; player about 0.55 tile wide and
  1.6 tall in 3/4 view, collision 0.6 tile. Fine; corner rounding covers the
  rest.*
- **The screen shows about 15 x 8 tiles.** Close enough that a body is a real
  shape, far enough to see the next room's door. *REDLINE: 20 x 11 tiles
  (`ZOOM` 6). Wider than the baseline; the look-far key (section 1) would let
  us zoom in. Open.*
- **Furniture is not tile-sized.** Stools and chairs are about half a tile,
  armchairs three quarters, tables one to two tiles long and under a tile
  deep, beds and pool tables about two, a car over three. Mixed sizes are what
  make a room read as a place and give cover of different widths. *REDLINE:
  every small prop is exactly one tile wide (stool, table, chairs, toilet,
  crate). Open: redraw the small props to their real widths.*
- **A weapon on the floor is half a tile to one tile long:** knives and
  pistols about 0.4-0.5, long guns and clubs 0.8-1.0, roughly a body's width.
  Big enough to find at a glance, small enough not to read as furniture.
  *REDLINE: done (`PICKUP_SCALE`: pistol 0.54, pipe 0.9, shotgun 1.1, at whole
  screen pixels; asserted).*
- **Small things are small:** a casing is a tenth of a tile, a bullet streak
  about half a tile.
- **Pieces of one actor share one pixel size** (see `pixel-art-engineer`
  section 9). Scale changes the on-screen size of a pixel, never the art.

### How an animation is built

Count frames by what the motion needs, and spend them unevenly.

- **Walk: 8 frames**, with the two foot-plants the biggest changes and the
  frames between them even. Legs can run on their own longer cycle. *REDLINE:
  infected 7-12 frames, done; player 4. Open: an 8-frame player walk needs a
  new reference.*
- **A melee swing is ready, strike, hold, recover** in 7-9 frames (heavy
  weapons up to 13): one or two very different frames carry the weapon to full
  extension, **one frame is held there** (nothing moves: that is where the hit
  reads), three or four frames bring it back, and a last near-identical frame
  settles. Never an even sweep. *REDLINE: the pipe has no body frames, but its
  sweep follows this shape (`Player.swing_angle`: strike in the first third,
  hold, slower return; asserted). Body frames are open.*
- **A gunshot is 2-3 frames** (flash, kick, back). **A slow gun shows its
  recovery:** the pump shotgun kicks for three frames, then holds almost still
  for eight. The fire-rate lock is something you see, not just a timer.
  *REDLINE: recoil slide only; the shotgun's 0.75s lock is invisible. Open.*
- **Getting up is 7 frames with the biggest change first** (the body leaves
  the floor at once, then rights itself evenly). **Crawling stops and starts:**
  a few moving frames, then two or three held. *REDLINE: none; a downed
  infected snaps upright. Open.*
- **Deaths are sized by the blow.** A gunshot drop is about 4 frames. A blunt
  kill is 10-15: big changes as the body goes, then small "settling" frames,
  often a late twitch. One still pose per kind of death stays as the corpse.
  *REDLINE: one downed pose per skin. Open (section 5).*
- **Breaking things decay:** a door or window shatters over about 10 frames,
  each changing less than the last.
- **Effects are short:** sparks and blood bursts 7-8 frames, smoke 9, a bullet
  hit 11. Ambient loops are long (a dance floor about 35) so the repeat is not
  seen.
- **Variety is counted in sprites, not recolours:** dozens of distinct floor
  weapons and death poses. Add a new one only with its own silhouette.

### How to measure

For a sheet of frames, compare each frame with the one before: the share of
pixels that changed is its "weight". Strikes and foot-plants should be the
heavy frames, holds should be zero, settles a few percent. A cycle whose
frames all weigh the same reads as floaty.

## 8. Build order for REDLINE

1. Bloater fuse warning (readable danger, section 2). *Done.*
2. Noise draws the nearest few, to scattered spots (section 2).
3. Throwable empty guns (section 3).
4. Floor-clear grade screen (section 4).
5. Longer combo window and varied knockdown time (sections 4 and 5).

Then: fail the smoke test on any runtime SCRIPT ERROR (a logger that counts
them; today a runtime error prints and the test still passes) *(study 2)*,
a white hit flash on the infected (a flash shader on the body; `modulate` can
only darken) and warm that shader at floor build so the web build does not
stall on the first hit *(study 2)*, staggered chain-reaction fuses,
boldness bonus, easing hit-stop in chains, look-far key, corpse poses
by kill type, animation speed from velocity, menu text effects, chapter frame.
From section 9: small props at their real widths, a visible shotgun recovery,
a get-up for downed infected, death sequences sized by the blow, body frames
for the swing, an 8-frame player walk, a closer camera.
Update the status lines above when one lands.
