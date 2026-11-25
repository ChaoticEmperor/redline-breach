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
* **Perceptually Uniform Ramps (`OKLCH` / `Oklab`)**: HSL lightness is not perceptual: at the same `L`, yellow looks far brighter than blue, so equal HSL steps give uneven contrast across hues. When building or generating a ramp, step lightness in `OKLCH` / `Oklab` (even `L` steps, hue and chroma shifted deliberately), then convert to sRGB hex, clamp anything out of gamut by lowering chroma rather than clipping channels, and check the steps in greyscale.
* **Eastern Hue-Shifting vs. Western Value Ramps**: Use **Eastern hue-shifting** (shifting shadows cooler/purple-blue and highlights warmer/yellow with smooth saturation and monotonic Xenodrogen ramp steps) for painterly/vibrant mood, or **Western value shifting** (holding hue steady while stepping value) when cleaner/simpler ramps fit the style. Prefer tinted darks over harsh `#000000` in shadows and use neutral grays to unify palettes under colored lighting.
* **Palette Swapping & Reuse**: Organize ramps cleanly so a single sprite or background can be re-paletted for time-of-day shifts, biomes, factions, or character/equipment variants, or fuse/share swatches to stretch tight color budgets.
* **Atmospheric & Linear Perspective**: Layer depth using overlapping, object size, **atmospheric perspective** (farther elements appear lighter, cooler/bluer, lower contrast, lower saturation, and less detailed so interactive foreground elements pop), and **linear perspective** (horizon line + vanishing point convergence for depth scale). Avoid perspective clashes such as the "Zelda perspective problem".

## 5. Tilesets & Dithering
* **Power-of-Two Tile Math & Layout**: Use power-of-two tile sizes (`8x8`, `16x16`, `32x32`)—remembering that doubling tile dimensions quadruples pixel area—and organize tile libraries cleanly by type and layer priority. Align visual tile edges closely with rectangular collision bounds where gameplay expects crisp contact.
* **Seamless Repeating & Transitions**: For infinitely tiling ground/wall textures, avoid centered focal blobs, harsh contrast, gradients, or strong edge lines that reveal the grid; use uniform quasi-random scatter (avoiding obvious rows/columns/clumps), odd-numbered organic clusters, multi-tile variants, wrapped edge elements, and `3`-tile vs. `9`-slice transitions depending on lighting vs. speed needs.
* **Wang Tiles & Autotiling Discipline**: Break up uniform terrain with 2-state edge Wang tiles: each of the four edges is one of two types, giving `16` tiles, and any two neighbours must agree on their shared edge. Use them for variation inside one terrain and autotile/bitmask sets (`16` edge or `47` blob) for transitions between terrains; do not mix the two jobs in one set. Derive edge assignments from a hash of the edge's world coordinates and the level seed, never from a running random generator, so the map is identical across saves, reloads and partial rebuilds.
* **Organic vs. Patterned Dithering**: Use **organic (quasi-random)** dithering for skies, shadows, and natural blends, and **patterned dithering** (checkerboards, lines, dents, weaves) for man-made surfaces or controlled gradients—keeping contrast moderate and avoiding heavy dithering on small or animated sprites where it causes grit and frame flicker.

## 6. Game Animation & VFX
* **In-Place Cycles, State Snapping & Pixel Flashing**: Author game character cycles in place and drive movement via code, accepting crisp state snaps rather than authoring excessive pairwise transitions. Prevent **pixel flashing** (sudden single-pixel pops/disappearances) and add motion trails/smears when fast movement would skip across frames.
* **Sub-Pixel Animation & Smearing**: A form cannot move less than one pixel, but it can look as if it does. On in-between frames, move only part of it: add a pixel on the leading edge and remove one on the trailing edge, or shift an interior shade boundary or highlight by one pixel while the outline stays put, so the eye reads a fraction of a pixel of travel (breathing, idle sway, slow drifts). For fast motion, smear instead: stretch or repeat the form's pixels along the motion vector for one or two frames, in its own colours, then snap back to the clean shape. In both cases protect high-priority details (eyes, face, silhouette landmarks, hands on a grip): they move whole pixels or not at all, and never flicker.
* **Keyframes, Arcs, Squash/Stretch & Chunking**: Block keyframes, arcs of motion, anticipation wind-ups, follow-through/secondary motion, and squash-and-stretch first. To keep animation manageable, simplify detail/ramps where appropriate or move/layer coherent body chunks and modular parts/damage states rather than redrawing intricate textures from scratch every frame.
* **VFX & Material Physics**: Build flames from shifting inner/outer shapes, lasers/trip wires from core/border contrast or pulsing semi-transparent beams, glows from concentric/dithered rings, and explosions across **flash → force (shaped by obstacles) → fire/rising smoke → residue/secondary impact**. Match damage states and fall/impact behavior to material rigidity and air drag.
* **Runtime Effects on the Art Grid**: Effects drawn by code must use the sprites' pixel size: snap every draw to that grid, pick colours by hard steps down a ramp from heat or remaining life (never interpolate), and fade with an ordered (`4x4` Bayer) dither test per pixel instead of alpha. Open a hit or shot with a one or two frame white-hot frame, then shrink and cool. Keep true blending for the glow or light layer only.
* **Timing in Ticks, Holds as Durations**: Author frame times in whole display ticks (`4` ticks = 15 fps, `5` = 12 fps, `6` = 10 fps at 60 Hz) so frames do not stutter. Hold a key pose by giving it a longer duration, not duplicate frames. Idle may loop or ping-pong; walks loop and never ping-pong; attack, hurt and death are one-shots that hold their last frame. Lock every frame to one ground line (the lowest row with a few body pixels) with whole-pixel shifts so feet do not swim.

## 7. Export & Engine Integration
* **Lossless Masters & Integer Scaling**: Store editable masters in layered project formats (`.ase`/`.aseprite`/`.gal`) and export lossless `.png` sprite sheets/tilesets—never `.jpg`/`.jpeg` for working pixel art. Always scale pixel art using **nearest-neighbor** at **whole-number** multipliers (`1x`, `2x`, `3x`), never mix pixel sizes in a scene, and upscale standalone social/web previews to at least `512x512` via nearest-neighbor to resist platform re-encoding blur.
* **Engine Rendering Setup (Godot 4)**: Set default texture filtering to **Nearest** (`Rendering > Textures > Default Texture Filter` = `Nearest`), and choose `viewport` + `integer` stretch mode for uniform low-res pixel scaling or `canvas_items` when mixing smooth cameras/tweens/shaders with pixel assets.
* **Atlas Extrusion, `Filter Clip` & Mipmap Safety**: With linear filtering, a fractional camera position or a non-integer scale, the sampler reads slightly outside a sprite's rectangle. Empty padding stops a neighbouring sprite showing but lets transparent or dark texels blend into the edge; extrusion (repeating each cell's border pixels outward by `1-2px`) gives the sampler the right colour to read, so export sheets and tilesets extruded, not just padded. Where the engine has it, also turn on clipping to the region (Godot: `Filter Clip` on `Sprite2D` / `AtlasTexture`). Keep mipmaps off for pixel art: lower mip levels average across cells and bleed or blur when zoomed out.
* **Snapping & Camera Trade-Offs**: Decide per project and test in motion, not on a still frame. Snapping sprites and camera to whole pixels keeps the grid stable but turns slow or diagonal movement into visible steps, and objects snapped separately from the camera jitter against each other. Unsnapped motion is smooth but lets art pixels shimmer unless the scale is a whole number and filtering is nearest. Rendering to a low-resolution viewport (or a pixelating post pass) snaps everything together at the cost of sub-pixel camera motion. Check each choice with a slow diagonal pan, a slow-moving sprite and camera smoothing on; pick the one with no unintended stepping or jitter, and keep authored sub-pixel animation out of whatever rounds positions.

## 8. Converting a Painted or Generated Reference (findings from the REDLINE player)
These were learned by converting a generated reference sheet into the game's player, after three code-drawn character sheets were rejected. Method and tooling: `atelier-pixel-art` section 3 and `tools/convert_reference.py`.
* **Convert, Don't Redraw**: When a reference in the target style exists, recover its own pixels. Shapes computed by code (lit spheres and capsules, however well shaded) read as rendered blobs with too many colours; redrawing a good reference by hand or by maths always lost to converting it.
* **Find the Grid First**: Generated "pixel art" is an upscaled grid. Measure its pitch from the edge profiles (the reference player was `5.75` source pixels per art pixel) and take the smallest strong pitch, because multiples of the true pitch score just as well. Then check the grid is real: the colour spread inside cells should be small (the reference's median was about `1.4` on a 0-255 scale). If cells are flat, sampling at a finer grid adds nothing.
* **Follow the Grid, and Read Whole Cells**: A generated grid drifts, so a uniform pitch slowly slides off it. Start from the uniform grid, then move each cut to the strongest edge within a third of a cell (never closer than `0.6` of a cell to the previous cut, and leave it where there is no edge). Take a cell's colour from all of its pixels, not a point at its centre: split them into a dark and a light group and keep the larger, or the dark one when it is a strong minority (`>= 40%`, clearly darker), which is what saves one-pixel eyes and outlines. On the player this lowered the colour difference to the reference on every frame.
* **Size the Palette by a Definition Test, Not a Fixed Cap**: A cap of `8-16` colours suits art authored for that budget. A converted figure with soft shading needed `42`: at `16` the eye highlights, iris, brow and the shading steps on the face were merged away and the sprite read as "too pixelated" although every pixel was in the right place. Raise the palette until no face pixel is badly off its nearest palette colour, and reserve a few slots for colours that are rare but distinct, since ordinary quantising drops those first.
* **Judge at the Same Scale as the Reference**: Upscale the sprite by the pitch and put it beside the source with the face enlarged. A sprite that looks coarser than its reference has lost colours or is being shown smaller; it has not lost pixels.
* **Never Halve a Detailed Figure**: Reducing the `78px` figure to `39px` destroyed the face. Keep the native resolution and choose the in-game scale to suit it.
* **Whole Screen Pixels per Art Pixel**: Pick the sprite's scale so each art pixel covers a whole number of screen pixels at the target resolution (`2` for the player at 1080p). A ratio like `1.6` makes neighbouring art pixels alternate between one and two screen pixels wide, which wrecks outlines and faces.
* **Strip What the Engine Draws**: Remove a baked ground shadow and backdrop. Keep dark outline pixels that touch colour, close one-pixel gaps in the outline, and fill whatever is sealed inside it. Expect to rebuild by hand the parts that fade into the shadow (a far foot, a trailing hand).
* **Passing Checks Is Not Approval**: Automated critique measures hygiene (stray pixels, palette discipline, contrast, light direction). A sheet passed every one of those and was still rejected. Show the result to the person and compare it with the reference before calling it done.

## 9. Clean Asset Merging & Compositing
For fusing two or more sprites, props, characters or backgrounds into one image or one on-screen object (a weapon in a hand, a rider on a mount, a prop on a table, a character on a background). A merge is finished when the parts read as one drawing, not as one drawing laid over another. Work through the four checks in order; a failure in an earlier one makes the later ones pointless.

### 9.1 Pixel-Grid & Scale Alignment
* **One pixel size**: Before compositing, compute each asset's on-screen pixel size (`sheet pixels per world pixel` x `draw scale` x `camera zoom`). They must be equal. If they differ, re-export or redraw the smaller-budget asset at the shared resolution; do not scale one to fit.
* **Integer scaling only**: Any resize is nearest-neighbour at a whole-number factor. A non-integer factor makes neighbouring art pixels alternate widths and breaks every outline it touches.
* **Same grid**: Place parts at integer pixel offsets on a shared 1x grid. A half-pixel offset shows as a doubled or missing row at the join.
* **Rotation**: Free rotation of a part (a weapon arm) leaves the grid by definition. Either author the needed angles (8 or 16 directions) on the grid, or accept runtime rotation only for parts drawn at the same pixel size as the body and keep them small.
* **Check**: Zoom to 1x and count: a one-pixel line in each asset must be the same number of screen pixels wide.

### 9.2 Depth Ordering, Occlusion & Contact
* **State the order first**: Write the front-to-back stack before drawing, part by part (for a held item: far arm, body, item, near hand and sleeve). Decide what changes with facing or aim (an item passes behind the body when aimed away from the viewer).
* **Grip, do not overlay**: Whatever holds something is drawn over it. A hand or sleeve must cover part of the grip; an item drawn wholly on top of the body reads as floating. If the body art has no gripping hand, add one (a pose, or a separate hand layer drawn above the item).
* **Erase what is hidden**: Where one shape covers another, remove the covered shape's outline and interior lines inside the overlap. Outlines showing through are the clearest sign of a paste.
* **Anchor it**: Give each join a contact cue: a one or two pixel contact shadow in the darker ramp step of the surface underneath, a pressed or overlapped pixel where a hand closes, feet that share a ground line and a shadow. Darken the shadow nearest the contact and let it fade with distance.
* **Background occlusion**: Terrain and props in front of a character cover it up to their own outline; keep the sort line at the object's base so the overlap is consistent while it moves.
* **Check**: Hide each part in turn. If nothing about the neighbouring parts changes, that part is pasted on, not integrated.

### 9.3 Unified Light, Ambient & Palette Harmony
* **One light direction**: All merged parts are lit from the same side. Flip or re-shade any part whose highlight sits on the other side; a mirrored sprite carries its lighting with it.
* **One set of ramps**: Re-map each part onto the shared palette. The same material uses the same ramp everywhere, shadows shift hue the same way in every part, and no part keeps a private near-duplicate of a colour that already exists.
* **Shared ambient**: Apply coloured or ambient light to every part of the merged object equally. If a light cone, neon wash or tint reaches the body, it reaches what the body holds; mismatched brightness or tint between a character and its item separates them at once.
* **One outline style**: Pick no outline, black inline, black contour, coloured outline or selective outline for the whole composite and convert the odd part out. Match outline weight too: a one-pixel contour next to a two-pixel one never reads as one object.
* **Matched contrast and detail**: Bring value range and detail density into line. A flat, low-detail item on a richly shaded body (or the reverse) looks like a different drawing regardless of colour.
* **Check**: View the composite in greyscale and as a palette list. Parts should not be separable by overall brightness, and the colour count should not have grown by the full palette of the added part.

### 9.4 Seam, Staircase & Edge Cleanup
* **No double borders**: Where two outlined shapes meet, keep one outline, not two side by side. Decide which shape owns the edge (normally the one in front).
* **No gaps**: Fill transparent slivers between parts that should touch, and remove stray background pixels trapped at the join.
* **Repair the lines**: Re-step any diagonal or curve the merge cut across so its staircase is regular again, and delete lone pixels left at the seam.
* **No banding at the join**: Shading rows from two parts must not line up into parallel bands along the seam; break them by shifting one ramp step.
* **Animation**: Check the join on every frame. An item must keep its offset to the hand through the cycle, or it will swim against the body.
* **Verify four ways**: at 1x (100%), flipped horizontally, on a neutral grey background, and zoomed out or blurred. The join should not be findable in any of them.

### 9.5 Merge Checklist
1. Same on-screen pixel size, integer scale, shared grid.
2. Draw order written down; holder overlaps held; hidden lines erased; contact shadow or anchor pixels present.
3. Same light direction, shared ramps and ambient, one outline style and weight, matched contrast.
4. No double borders, gaps, lone pixels, broken staircases or banding at the seam; passes 1x, flipped, neutral background and zoomed out; holds on every animation frame.

