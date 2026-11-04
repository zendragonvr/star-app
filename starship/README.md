# Starship-style launch — Star Bridge feature

Unofficial; not affiliated with SpaceX. Starship is a trademark of its owner.

No SpaceX logos, lettering or branding anywhere in this feature. All meshes
are simple procedural shapes, all sounds are synthesized in code, no recorded
audio, no TTS, no AI models in this feature.

Phases: 1 placement at true size, 2 ignition/liftoff/ascent, 3 hot staging
and boostback, 4 booster return, 5 tower catch (two parallel beams, vc180 — not a single centred beam, which passed through the booster), 6 synthesized sound,
7 minimal UI, Reduce effects, Indoor 1:10 demo mode.

Entry: say "spawn starship" to the teacher (Talk to Teacher, or spoken without Talk pinch; "launch starship" is an alias), then aim at the real
ground and pinch to place, or pinch PLACE. Then pinch LAUNCH.
Modes: HIGHLIGHTS (150 s total, catch at 150 s) and REAL TIME (catch at 420 s).
Reset returns to the normal app. After the catch, the scene holds, then
returns to the normal app on its own.

Limits, honest: frame rate and a test video need a headset run. Floor height (vc180) comes from the aim angle at the chosen distance, so a slope is handled if you aim at the real ground spot. It still fails if that spot is hidden behind a fence/trees, or if you aim at nearer ground — UP/DOWN still corrects it. Sound delay is distance / 343 m/s.

vc180 fixes (Claude report, checked against real code): placement buttons work (button_at checked before place, head must look at button); INDOOR rebuilds at 1:10; steam sphere 8x4 segments (~19k tris, was ~1.2M); tile/steel/dark materials cached (was 9 tile images on spawn); sunlight + surroundings hidden on RESET; floor height from aim angle, not flat Y=0; ground shadow catcher (unproven on Quest GL Compatibility, fixed sun angle, not real Sun); orange figure outdoors + car for scale; steel tone bands (simulated); plume inner cone; steam billows along ground (simulated).
Corrections to Claude's numbers: weld-ring segments were swapped — ring_segments is the main circle (24), rings is the tube (4), not the reverse. Cylinder rings stays 1, not 0.
