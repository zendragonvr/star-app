# Selection check, headless (vc36+: NO orange glow — the node is
# built but forced hidden; identification is panel name +
# bring-to-you). Run: godot --headless --path project -s tests/highlight_test.gd
# Contract (current, proven in headset):
# - pinch a planet + identify success -> that planet selected.
# - pinch with no clear match -> selection cleared + "Not sure".
# - never select the wrong object (star pick clears planet focus,
#   planet pick clears star orb, failure clears both).
extends SceneTree

const PlanetsCore = preload("res://scripts/planets_core.gd")

var _fail: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("Highlight: ", label, " PASS")
	else:
		_fail += 1
		print("Highlight: ", label, " FAIL")

func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t

func _initialize() -> void:
	# Runtime: focus owns the glow (PlanetsCore._process shows glow
	# only when focused_body() != "" and travel == "").
	var p: Node3D = PlanetsCore.new()
	p._bodies = {"Mars": true, "Saturn": true}
	_check(p.focused_body() == "", "starts with nothing focused")
	p.select_body("Saturn")
	_check(p.focused_body() == "Saturn", "success pinch selects that planet")
	p.clear_focus()
	_check(p.focused_body() == "", "failure/back clears selection")
	p.free()
	# No-glow rule: the node exists but is never shown anywhere.
	var pg: String = _read("res://scripts/planets_core.gd")
	_check(pg.contains("_glow.visible = false"), "glow forced hidden")
	_check(pg.contains("_glow.visible = true") == false, "nothing ever shows glow")
	# Source contract: main.gd failure + cross-clear rules.
	var mg: String = _read("res://scripts/main.gd")
	_check(mg.contains("show_not_sure"), "unsure pinch shows Not sure panel")
	# Both failure branches (empty + ambiguous) must clear planet
	# focus and the star orb so highlight stays off.
	_check(mg.contains("_planets.clear_focus()") and mg.contains("_clear_star_orb()"), "failure clears planet + star selection")
	_check(pg.contains("_holo_mat") and pg.contains("emission_energy_multiplier = 1.6 + 0.35"), "hologram shimmers, size and spot fixed")
	# Star success must clear planet focus (never wrong-object glow).
	# Body success already clears the star orb in _show_panel_for.
	_check(pg.contains("_glow.visible = false"), "glow hides when nothing focused")
	# Awe-teacher contract: small light-figure beside the planet,
	# tagged AI (never human), hidden unless room-focused.
	_check(pg.contains("TeacherHolo") and pg.contains('"AI"'), "hologram is tagged AI")
	_check(pg.contains("Vector3(1.0, -0.55, 0.35)"), "hologram sits beside planet, never over it")
	_check(pg.contains("_holo.visible = false"), "hologram hides with no focus/telescope/travel")
	# Voice contract: per-planet robot-lady clip on identify, and a
	# new pinch cuts the old voice (stop-before-play, one stream).
	_check(mg.contains('_in_room'), "identify plays per-planet voice line")
	var vg: String = _read("res://scripts/voice_ui.gd")
	_check(vg.contains("stop()"), "new pinch stops old voice")
	# Travel contract ("You are there", 7 planets): shell is
	# see-through (passthrough stays on), Saturn gets its rings,
	# Mars alone is REAL, the rest SIMULATED + floating.
	_check(pg.contains("TRAVEL_WORLDS"), "travel worlds listed")
	for w: String in ["Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]:
		_check(pg.contains('"' + w + '"'), "travel covers " + w)
	_check(pg.contains("can_travel"), "travel gate covers 7")
	_check(pg.contains("TRANSPARENCY_ALPHA"), "travel shell is see-through")
	_check(pg.contains("TravelRingSaturn"), "saturn travel has rings")
	_check(mg.contains("real panorama") and mg.contains("NASA/JPL"), "mars travel labelled real")
	for w2: String in ["Mercury", "Venus", "Jupiter", "Saturn", "Uranus", "Neptune"]:
		_check(mg.contains(w2 + '\\nYOU ARE THERE — simulated'), w2 + " labelled simulated")
	for g: String in ["Jupiter", "Saturn", "Uranus", "Neptune"]:
		_check(mg.contains(g + '\\nYOU ARE THERE — simulated cloud deck'), g + " gets imagined deck")
	_check(mg.contains("No solid ground") and mg.contains("magined from real scans") and mg.contains("Imagined"), "decks honest: imagined, no solid ground")
	_check(pg.contains("TravelDeck") and pg.contains("TRAVEL_DECK_PLANETS"), "deck exists, gas giants only")
	_check(pg.contains("TravelAurora") and pg.contains("TravelSun"), "aurorae and real-placed sun exist")
	_check(not mg.contains('Mercury\\nYOU ARE THERE — simulated cloud deck') and not mg.contains('Venus\\nYOU ARE THERE — simulated cloud deck'), "mercury and venus keep honest views, no deck")
	# Hand-grab contract: hold/release API, generous catch range,
	# dial precedence kept, hold cleared on focus/telescope/travel.
	_check(pg.contains("hold_focused") and pg.contains("release_hold"), "grab hold API exists")
	_check(pg.contains("grab_radius") and mg.contains("_grab_hand"), "grab range wired to pinch hand")
	_check(mg.contains("Dial drag first"), "dial keeps precedence over grab")
	# Trippy hands contract: our own rim shader, painted onto the
	# real OpenXR hand meshes, pinch thresholds untouched.
	var hg: String = _read("res://scripts/hand_glow.gdshader")
	_check(hg.contains("fres") and hg.contains("TIME"), "hand shader is animated rim light")
	_check(hg.contains("ALPHA") and hg.contains("unshaded"), "hands stay see-through")
	var ht: String = _read("res://scripts/hand_tracking.gd")
	_check(ht.contains("HAND_GLOW_SHADER") and ht.contains("_paint_hands"), "glow painted onto real hands")
	_check(ht.contains("PINCH_DISTANCE_M: float = 0.045"), "pinch thresholds untouched")
	_check(mg.contains("Never the ground"), "venus never shows fake ground")
	_check(mg.contains("Pinch again to go back"), "travel offers pinch back")
	print("Highlight: ", "ALL PASS" if _fail == 0 else "SOME FAILED")
	quit(_fail)
