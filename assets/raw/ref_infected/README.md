# Our infected: references and drawn sprites

Everything here is ours (assets-debt I1). Nothing comes from a third-party pack.

| File | What it is |
|---|---|
| `shambling_…_s1941657839.png` and `_lock` (the cleaned copy used; the `_key` and `_px` steps are in the recordings folder) | pixelgen reference, z-image-turbo (Apache-2.0), our prompt; the `.pixelgen.json` sidecars hold the prompt, seed and every clean-up step. Used for layout only |
| `shambling_…_contact.png` | the four seeds we picked from (the other three are in `~/Hive/recordings/redline/2026-11-26-shambler/`) |
| `shambler_tandem_v2.png` | **the shambler**: built by `tools/draw_infected.py shambler <…_lock.png>` (our ramps, shading and contour, cut to the player's 78 px), then hand-painted in Tandem by flora, 2026-11-26, sprite id `redline-infected-shambler` (eyes, tongue, shirt rip, blood, sole line). Checked with `tools/critique_sprite.py` |

| `infected_clubber_…_s1986989899.png` and `_lock` | the horde's pixelgen reference (z-image-turbo, our prompt), cleaned at `--pixel-width 11` so she stands at the player's height. Layout only |
| `infected_clubber_…_contact.png` | the four horde seeds (the other three in `~/Hive/recordings/redline/2026-11-26-horde/`) |
| `<kind>_handpass.json` | the hand pass painted in Tandem by flora, 2026-11-26 (sprites `redline-infected-<kind>`): eyes, mouth, wounds, as pixels in material-map coordinates |

The game sheets are built by `tools/animate_infected.py <kind> <…_lock.png> <kind>_handpass.json` (walk 8, lunge 5, down 4).
