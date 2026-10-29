# Message for Claude — Evochi facial expression correction

I'm providing two distinct sets of references:

1. `references/00_Original_Character_Models.png` is the existing actual character design. This is authoritative for stage body shapes and materials. NEVER redesign the body or invent details.
2. `references/01_Expression_Style_Anchor.png` plus `references/02-07` personality sheets show the TARGET facial expression style. The visual language is: voxel/pixel-like soft 3D creature, cream/gold skin, restrained dark eyes and brows with bright glossy highlights, small pink blush rectangles, expressive rounded open mouth with small fangs and tongue, subtle tension for strain, controlled focused face for fierce.
3. `references/08_Claude_Current_Output_To_Correct.png` is the output to fix; do NOT treat it as the design reference.

## What is specifically wrong with your output

- You turned almost every expression into the same harsh angry face. Shout should be a battle cry, NOT just angry eyebrows. Fierce should convey determined focus; the Elder should be controlled, not furious.
- Your eyebrows are too heavy, too dark, too similar across all stages and emotions. Reduce thickness and vary curvature, position and tilt in a personality-aware way.
- Eyes and pupils look too generic and angry. Use the target's rounded, glossy dark eyes with small white highlights where open; retain expressive eye shapes instead of moving V-shaped bars around.
- Your mouth silhouettes are too uniform. Use the soft rounded red mouth, pale teeth/fangs and pink tongue of the target. Some Shout mouths need joyful courage, not aggression; some strain mouths should be asymmetric clenched teeth rather than a pasted grin.
- Large blue cartoon sweat drops and orange blast marks have been introduced into what should be face studies. Reduce or omit these; put actual FX in separate cinematic layers, not the face texture.
- Silhouettes, limb/foot structure, gold patch placement, elder horns, and tails must match the user-supplied existing 3D models. The face is the only change; do not change anatomy/age progression.
- You lost the differences between evolution stages and personalities. Eggling should be adorable and emotionally exaggerated, Juvenile energetic and brave, Elder restrained and authoritative. Brave ≠ Stubborn ≠ Timid ≠ Playful ≠ Curious ≠ Calm.
- The decorative paper layout is fine, but style fidelity matters more than poster aesthetics. Do not repaint the creatures into a different illustration or shaded-cartoon style.

## New task

Modify ONLY facial-expression assets (eyes, brows, cheeks, mouth; optional subtle strain accent) and their timing / placement for the existing model and Wilds boss entrance. Use the supplied SVG/PNG facial prototype components if practical, but FIRST inspect the in-game character mesh, current face texture / atlas, UVs and animation controls to determine the correct integration method. Do NOT rebuild or substitute the creature meshes.

Give me side-by-side model screenshots for one Eggling, one Juvenile, and one Elder with Shout, Strain and Fierce. Keep the same camera, scale, materials and lighting in each comparison.

Expression targets:
- SHOUT: open rounded red mouth, one or two subtle fang teeth, tiny tongue, clear glossy eyes or intentionally closed smiling eyes for playful.
- STRAIN: eyes squeezed with believable tension; teeth clenched or mouth compressed; facial squash and animation can reinforce pressure. Sweat accents only when personality/style justifies them.
- FIERCE: narrowed but readable eyes, small composed mouth and intentional brow tilt; not an indiscriminate angry V.

Personality notes:
- Brave: protective and eager, confident roar, determined gaze.
- Timid: worried, startled, then gathers courage; worried brows, slightly smaller mouth.
- Stubborn: defiant, persistent; stronger brow tension without constant snarling.
- Playful: joy, cheekiness, wink/smile possible even in danger.
- Curious: surprised or observant, eye-brow asymmetry, alert gaze.
- Calm: composed, controlled mouth, less exaggerated brows and strain.

Acceptance criteria:
1. Existing character stage meshes, proportions, golden patches, and model material are unchanged.
2. Expressions visually match the softer original reference sheets, not the previous angry cartoon output.
3. Nine base expression renders (3 stages × 3 states) can be compared at fixed camera, plus six clearly distinguishable personality variants.
4. Face assets are reusable, transparent, appropriately UV-aligned, and not baked into a new creature render.
5. No added particle effects / text in actual face textures.
6. If exact texture matching requires the original face atlas or UV map, state what you need rather than claiming pixel-perfect extraction from concept art.
