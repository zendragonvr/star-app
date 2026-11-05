# 100% own sounds — submission build only

These three WAVs were synthesized in code on 2026-11-01, no recordings,
no downloaded samples, no third-party files. They replace, for the
submission build, the three slots that were NOT 100% ours:

- sound_pinch_click_own.wav (0.09s) — replaces sound_pinch_click.wav
  (user file soundshelfstudio, license unverified)
- sound_typing_tick_own.wav (0.03s) — replaces sound_typing_tick.wav
  (user file freesound community, license unverified)
- sound_zoom_own.wav (3.5s) — replaces sound_zoom.wav / sound_zoom_full_yle.wav
  (YleArkisto CC BY 4.0, credit required — no longer needed if this file ships)

Other app sounds (click, back, lock, travel) were already synthesized
WAVs per voice_ui.gd header: "Sounds are synthesized WAVs, no external audio."

To use in a submission build, rewire only these three load paths:
- main.gd pinch success: sound_pinch_click.wav -> data/sounds/own/sound_pinch_click_own.wav
- identify_panel.gd typing: sound_typing_tick.wav -> data/sounds/own/sound_typing_tick_own.wav
- main.gd telescope: sound_zoom.wav -> data/sounds/own/sound_zoom_own.wav

Do NOT rewire vc115 for a headset verdict — vc115 stays as-is until
the user gives a verdict. This folder is for the new submission build.
