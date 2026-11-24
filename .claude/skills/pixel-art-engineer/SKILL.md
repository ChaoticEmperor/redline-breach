---
name: pixel-art-engineer
description: >
  Pixel-art craft rules for designing, constructing, animating, auditing, tiling,
  and exporting sprites, tilesets, backgrounds, VFX, palettes, and engine-ready
  assets: silhouettes, clean lines and outlines, shading and material texture,
  colour ramps, dithering, animation and export. Load this FIRST whenever
  creating, redrawing, animating, reviewing or exporting any pixel art in this
  project, then follow atelier-pixel-art for how art is built and wired in this repo.
---

# Pixel Art Engineer

## 1. Artistic Foundations & Game-Dev Scope
* **Intentional Pixels & Iconic Readability**: Treat pixel art as intentional pixel placement—not raw 3D renders, vector shapes, or blurred downscaled scans. Use clear silhouettes, distinct feature exaggeration, and controlled abstraction so players read forms immediately and fill in details naturally.
* **Scope, Palette Budget & Iteration Speed**: Keep palettes and detail density aligned with animation and level-design scope—extra shades and micro-details compound across multi-frame cycles and variants. Reserve a dedicated transparency color (such as magenta) early, use neutral/placeholder colors during blocking for fast swapping, and favor simple, reusable structures over over-engineered one-offs.
* **Workflow & Continuous Verification**:
  * Start with thumbnails, references, or low-poly mockups; sculpt rough shapes/sketches and chisel down rather than chasing single-stroke perfection or blind auto-filters.
  * Keep a **1x (100%)** preview open, test on **neutral gray or muddy brown** backgrounds to catch contrast drops, **flip horizontally** to check balance and shadow consistency, and zoom out or blur to catch banding and readability flaws.

## 2. Line Art, Staircases & Outline Architecture
* **Clean Lines & Zero Jaggies**: Keep straight lines crisp (using axis-lock where appropriate), maintain consistent step lengths along diagonals (`0:1`, `1:2`, `1:1`, `2:1`, `1:0`), and vary segment lengths progressively along curves (`4-3-2-1-1-1-2-3-4`) while avoiding "lone wolf" pixels, abrupt right angles, mixed staircase steps, and unedited circle/curve tool artifacts. Clean jagged color boundaries on lineless and cel-shaded art as well.
* **2:1 Dimetric Grid vs. True Isometric**: Standard `2:1` pixel art (`2` across per `1` vertical step, `arctan(0.5) ≈ 26.565°`) is a **dimetric** projection rather than true isometric (`30°` axes / `≈35.264°` pitch / `√3:1` ratio). Use `2:1` dimetric for clean integer steps and consistent grid-to-screen mapping (`screen_x = (x - y) * tile_w / 2`, `screen_y = (x + y) * tile_h / 2`), and record `"2:1 dimetric (26.57°)"` explicitly in specs so true-30° assets aren't mixed in.
* **Line Weight & Outline Archetypes**: Favor `1px` lines for classic crispness or deliberate line-weight contrast (thicker outer contours vs. thinner interior lines, or value-weighted line thickness). Select outline style intentionally:
  * **No Outline**: Solid/shaded shapes or broken contours (strong for backgrounds and lineless styles—requires careful value/color separation from surroundings).
  * **Black Inline**: Black lines inside and outside (use carefully; can look muddy on small sprites).
  * **Black Contour**: Black silhouette outline with colored interior lines to separate sprites cleanly.
  * **Coloured Outline**: Darkened hues matching each adjacent region/part.
  * **Selective Outline**: Light-aware shaded outlines that adapt to the light source and work across light and dark backgrounds.

## 3. Shading, Material Texture & Anti-Aliasing (AA)
* **Light Direction, Surface Angles & Cast Shadows**: Lock a primary light direction and intensity early. Surfaces angled more perpendicular to the light receive stronger illumination while surfaces turning away darken; curved forms transition across ramps, and secondary/bounced or rim light is added selectively once primary volume is clear. Map cast shadows along light rays from blocking edges, darkening near contact and softening/fading with distance.
* **Material Texture Over Flat Shading**: Convey surface properties—roughness, grain, wood/brick/stone patterns, metallic highlights, translucent refraction, and water/glass reflections—rather than leaving surfaces as generic shaded blobs.
* **Shading Pitfalls & Banding Prevention**:
  * Avoid **pillow shading** ("flash shading") and false corner-to-corner gradients on flat sun-lit planes.
  * Avoid **banding** and **"super pixels"**—do not let parallel bands, outline-hugging shade rows, or aligned diagonal shade steps lock together into chunky pseudo-pixels.
* **Contextual Anti-Aliasing**: Use `1–2` buffer shades in interior corners or high-contrast transitions to smooth curves and eyes without blurring sprites into mush. **Never** AA outer edges against a fixed color if the sprite moves across unpredictable backgrounds.

## 4. Color Ramps, Palette Swapping & Scene Depth
* **HSL / HSV Control & Contrast Calibration**: Work in Hue, Saturation, and Lightness/Value rather than unshifted RGB sliders. Tune contrast and saturation to scale and purpose: smaller sprites generally need clearer contrast so details don't mash together, while excessive saturation or extreme contrast across everything creates visual fatigue.
* **Eastern Hue-Shifting vs. Western Value Ramps**: Use **Eastern hue-shifting** (shifting shadows cooler/purple-blue and highlights warmer/yellow with smooth saturation and monotonic Xenodrogen ramp steps) for painterly/vibrant mood, or **Western value shifting** (holding hue steady while stepping value) when cleaner/simpler ramps fit the style. Prefer tinted darks over harsh `#000000` in shadows and use neutral grays to unify palettes under colored lighting.
* **Palette Swapping & Reuse**: Organize ramps cleanly so a single sprite or background can be re-paletted for time-of-day shifts, biomes, factions, or character/equipment variants, or fuse/share swatches to stretch tight color budgets.
* **Atmospheric & Linear Perspective**: Layer depth using overlapping, object size, **atmospheric perspective** (farther elements appear lighter, cooler/bluer, lower contrast, lower saturation, and less detailed so interactive foreground elements pop), and **linear perspective** (horizon line + vanishing point convergence for depth scale). Avoid perspective clashes such as the "Zelda perspective problem".

## 5. Tilesets & Dithering
* **Power-of-Two Tile Math & Layout**: Use power-of-two tile sizes (`8x8`, `16x16`, `32x32`)—remembering that doubling tile dimensions quadruples pixel area—and organize tile libraries cleanly by type and layer priority. Align visual tile edges closely with rectangular collision bounds where gameplay expects crisp contact.
* **Seamless Repeating & Transitions**: For infinitely tiling ground/wall textures, avoid centered focal blobs, harsh contrast, gradients, or strong edge lines that reveal the grid; use uniform quasi-random scatter (avoiding obvious rows/columns/clumps), odd-numbered organic clusters, multi-tile variants, wrapped edge elements, and `3`-tile vs. `9`-slice transitions depending on lighting vs. speed needs.
* **Organic vs. Patterned Dithering**: Use **organic (quasi-random)** dithering for skies, shadows, and natural blends, and **patterned dithering** (checkerboards, lines, dents, weaves) for man-made surfaces or controlled gradients—keeping contrast moderate and avoiding heavy dithering on small or animated sprites where it causes grit and frame flicker.

## 6. Game Animation & VFX
* **In-Place Cycles, State Snapping & Pixel Flashing**: Author game character cycles in place and drive movement via code, accepting crisp state snaps rather than authoring excessive pairwise transitions. Prevent **pixel flashing** (sudden single-pixel pops/disappearances) and add motion trails/smears when fast movement would skip across frames.
* **Keyframes, Arcs, Squash/Stretch & Chunking**: Block keyframes, arcs of motion, anticipation wind-ups, follow-through/secondary motion, and squash-and-stretch first. To keep animation manageable, simplify detail/ramps where appropriate or move/layer coherent body chunks and modular parts/damage states rather than redrawing intricate textures from scratch every frame.
* **VFX & Material Physics**: Build flames from shifting inner/outer shapes, lasers/trip wires from core/border contrast or pulsing semi-transparent beams, glows from concentric/dithered rings, and explosions across **flash → force (shaped by obstacles) → fire/rising smoke → residue/secondary impact**. Match damage states and fall/impact behavior to material rigidity and air drag.

## 7. Export & Engine Integration
* **Lossless Masters & Integer Scaling**: Store editable masters in layered project formats (`.ase`/`.aseprite`/`.gal`) and export lossless `.png` sprite sheets/tilesets—never `.jpg`/`.jpeg` for working pixel art. Always scale pixel art using **nearest-neighbor** at **whole-number** multipliers (`1x`, `2x`, `3x`), never mix pixel sizes in a scene, and upscale standalone social/web previews to at least `512x512` via nearest-neighbor to resist platform re-encoding blur.
* **Engine Rendering Setup (Godot 4)**: Set default texture filtering to **Nearest** (`Rendering > Textures > Default Texture Filter` = `Nearest`), and choose `viewport` + `integer` stretch mode for uniform low-res pixel scaling or `canvas_items` when mixing smooth cameras/tweens/shaders with pixel assets.

## 8. Converting a Painted or Generated Reference (findings from the REDLINE player)
These were learned by converting a generated reference sheet into the game's player, after three code-drawn character sheets were rejected. Method and tooling: `atelier-pixel-art` section 3 and `tools/convert_reference.py`.
* **Convert, Don't Redraw**: When a reference in the target style exists, recover its own pixels. Shapes computed by code (lit spheres and capsules, however well shaded) read as rendered blobs with too many colours; redrawing a good reference by hand or by maths always lost to converting it.
* **Find the Grid First**: Generated "pixel art" is an upscaled grid. Measure its pitch from the edge profiles (the reference player was `5.75` source pixels per art pixel) and take the smallest strong pitch, because multiples of the true pitch score just as well. Then check the grid is real: the colour spread inside cells should be small (the reference's median was about `1.4` on a 0-255 scale). If cells are flat, sampling at a finer grid adds nothing.
* **Size the Palette by a Definition Test, Not a Fixed Cap**: A cap of `8-16` colours suits art authored for that budget. A converted figure with soft shading needed `42`: at `16` the eye highlights, iris, brow and the shading steps on the face were merged away and the sprite read as "too pixelated" although every pixel was in the right place. Raise the palette until no face pixel is badly off its nearest palette colour, and reserve a few slots for colours that are rare but distinct, since ordinary quantising drops those first.
* **Judge at the Same Scale as the Reference**: Upscale the sprite by the pitch and put it beside the source with the face enlarged. A sprite that looks coarser than its reference has lost colours or is being shown smaller; it has not lost pixels.
* **Never Halve a Detailed Figure**: Reducing the `78px` figure to `39px` destroyed the face. Keep the native resolution and choose the in-game scale to suit it.
* **Whole Screen Pixels per Art Pixel**: Pick the sprite's scale so each art pixel covers a whole number of screen pixels at the target resolution (`2` for the player at 1080p). A ratio like `1.6` makes neighbouring art pixels alternate between one and two screen pixels wide, which wrecks outlines and faces.
* **Strip What the Engine Draws**: Remove a baked ground shadow and backdrop. Keep dark outline pixels that touch colour, close one-pixel gaps in the outline, and fill whatever is sealed inside it. Expect to rebuild by hand the parts that fade into the shadow (a far foot, a trailing hand).
* **Passing Checks Is Not Approval**: Automated critique measures hygiene (stray pixels, palette discipline, contrast, light direction). A sheet passed every one of those and was still rejected. Show the result to the person and compare it with the reference before calling it done.

