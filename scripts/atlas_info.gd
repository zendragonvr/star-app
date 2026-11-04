# Info panel + AI guide context for 3I/ATLAS — added 2026-11-01.
# Facts are the user's own words, not invented, and the live distances
# come from ephemeris.gd at the time the panel is shown.
# The same text is given to the AI guide (see worker.js ATLAS_CONTEXT),
# so the panel and the teacher cannot disagree.
extends RefCounted
class_name AtlasInfo

const FACTS: String = """Third confirmed interstellar object (after 'Oumuamua in 2017 and Borisov in 2019).
Discovered 1 July 2025 by the ATLAS survey telescope in Chile.
Closest to the Sun 29 Oct 2025 at 1.36 AU.
Closest to Earth 19 Dec 2025 at 1.80 AU.
Passed Jupiter 16 Mar 2026 at 0.36 AU.
Moving about 58 km/s relative to the Sun far away.
Nucleus likely under 1 km (estimates vary and are uncertain).
Leaving the solar system for good."""

const TEACHER_CONTEXT: String = """3I/ATLAS facts, use these and do not invent other numbers:
Third confirmed interstellar object (after 'Oumuamua in 2017 and Borisov in 2019).
Discovered 1 July 2025 by the ATLAS survey telescope in Chile.
Closest to the Sun 29 Oct 2025 at 1.36 AU.
Closest to Earth 19 Dec 2025 at 1.80 AU.
Passed Jupiter 16 Mar 2026 at 0.36 AU.
Moving about 58 km/s relative to the Sun far away.
Nucleus likely under 1 km (estimates vary and are uncertain).
Leaving the solar system for good.
It is a comet: a small nucleus inside a coma, with a tail pointing away from the Sun.
Not 'Oumuamua: do not describe it as a rock/cigar, and do not use an 'Oumuamua artist concept."""

static func panel_text(jd: float) -> String:
	var sky := Ephemeris.atlas_sky(jd)
	return "3I/ATLAS, interstellar comet. Too faint to see by eye, shown enlarged.\n" + FACTS + "\nToday: %.2f AU from the Sun, %.2f AU from Earth, %.1f km/s.\nOrbit data: NASA JPL Small-Body Database." % [sky["helio_au"], sky["dist_au"], Ephemeris.atlas_speed_kms(jd)]

# vc118 SHORT panel (user 2026-11-01 22:02 EST: panel must be sideways, not
# up-and-down). Same live numbers, no long facts list — that list is what
# made the vc117 panel a 20-line tall column. Full facts stay in panel_text
# for the teacher / system view, not on the pinch panel.
static func short_panel_text(jd: float) -> String:
	var sky := Ephemeris.atlas_sky(jd)
	return "Interstellar comet. Too faint to see by eye, shown enlarged.\nToday: %.2f AU from the Sun, %.2f AU from Earth, %.1f km/s.\nOrbit data: NASA JPL Small-Body Database." % [sky["helio_au"], sky["dist_au"], Ephemeris.atlas_speed_kms(jd)]
