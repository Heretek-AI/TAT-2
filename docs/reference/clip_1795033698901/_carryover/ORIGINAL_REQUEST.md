# Original User Request
## Initial Request — 2026-11-18T20:38:50Z
Break down the recorded gameplay footage of the official Thick As Thieves (`/home/john/Videos/clip_1,795,033,698,901.mp4`), grounded in `docs/HANDOFF_NEXT_SESSION.md`, into an exhaustive visual and audio reference baseline with extracted/annotated frames, text descriptions, and TAT-2 subsystem cross-references so it serves as the comparison target for our Godot port.

Working directory: /home/john/Projects/TAT-2
Integrity mode: development

Reference material:
- `docs/HANDOFF_NEXT_SESSION.md` (and the repository documentation it references)
- `/home/john/Videos/clip_1,795,033,698,901.mp4`

## Requirements

### R1. Exhaustive Visual and Audio Breakdown
Produce an exhaustive, timestamped text breakdown of everything seen and heard in `/home/john/Videos/clip_1,795,033,698,901.mp4`. Cover all visible elements (environment, lighting, sky/atmosphere, materials/shaders, character/NPC animations, VFX, HUD/UI layout and state, camera/framing, and gameplay interactions/timings) as well as audible cues, sound effects, UI audio, and music.

### R2. Extracted References, Annotations, and Comparison Structure
Extract clean keyframe reference images from the footage and create annotated versions with visual callouts and labels tied to the timestamped descriptions. Structure all observations and reference artifacts so a future recording from the TAT-2 Godot port can be compared directly side-by-side against this baseline.

### R3. TAT-2 Subsystem Cross-References
Read `docs/HANDOFF_NEXT_SESSION.md` and the relevant repository docs it points to, and cross-reference observed elements in the official footage against the corresponding TAT-2 port subsystems, known parity gaps, and hard limits.

### R4. Repository Output Location
Save all breakdown documents and extracted/annotated reference images under `docs/` in `/home/john/Projects/TAT-2` so they are tracked in git, without making unintended changes to game code or gitignored directories (`build/`, `game/.godot/`, `game/data/generated/`).

## Verification Resources
- `/home/john/Videos/clip_1,795,033,698,901.mp4`
- `docs/HANDOFF_NEXT_SESSION.md` and the repository docs it references

## Acceptance Criteria

### Timeline and Modality Completeness
- [ ] Timestamped entries cover `/home/john/Videos/clip_1,795,033,698,901.mp4` continuously from `00:00` to the end of the clip with no unexplained gaps.
- [ ] Every segment documents both visual observations (environment, lighting, materials, animations, VFX, HUD/UI, interactions) and audio observations (sound effects, UI audio, music/ambience, or explicit absence).

### Reference Images and Factual Accuracy
- [ ] All referenced clean and annotated keyframe images exist under `docs/`, are valid non-empty image files, and match the file paths and timestamps cited in the breakdown text.
- [ ] An independent reviewer spot-checking descriptions, timestamps, and annotated callouts against `/home/john/Videos/clip_1,795,033,698,901.mp4` confirms they accurately reflect directly observable visual and audio details with no fabricated claims.

### Comparison Readiness and Subsystem Mapping
- [ ] The breakdown includes a structured, repeatable comparison format/checklist covering visual, audio, UI, and gameplay criteria for 1:1 comparison with future port footage.
- [ ] Observed elements include cross-references to the relevant TAT-2 port subsystems, parity gaps, or hard limits documented via `docs/HANDOFF_NEXT_SESSION.md`.

### Output Hygiene
- [ ] All deliverables are saved under `docs/` in `/home/john/Projects/TAT-2`, with no unintended edits to game source code or gitignored build/generated directories.
