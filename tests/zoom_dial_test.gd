# Zoom dial + focus/back check, headless.
# Run: godot --headless --path project -s tests/zoom_dial_test.gd
# Covers the v22 UI primitives main.gd relies on: zoom clamp 1x-10x,
# step cycle, new-selection zoom reset, telescope + back-to-sky reset,
# real-scan flags. Local only, no API, no lock/calibration code.
# No scene/rendering needed: seeds body keys so focus APIs work headless.
extends SceneTree

const PlanetsCore = preload("res://scripts/planets_core.gd")

var _fail: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("ZoomDial: ", label, " PASS")
	else:
		_fail += 1
		print("ZoomDial: ", label, " FAIL")

func _initialize() -> void:
	var p: Node3D = PlanetsCore.new()
	p._bodies = {"Mars": true, "Jupiter": true}
	_check(absf(p.zoom_factor() - 1.0) < 0.001, "starts at 1x")
	p.set_zoom(0.5)
	_check(absf(p.zoom_factor() - 1.0) < 0.001, "clamps low to 1x")
	p.set_zoom(20.0)
	_check(absf(p.zoom_factor() - 10.0) < 0.001, "clamps high to 10x")
	p.set_zoom(1.0)
	p.step_zoom()
	_check(absf(p.zoom_factor() - 2.0) < 0.001, "steps 1->2")
	p.step_zoom()
	_check(absf(p.zoom_factor() - 4.0) < 0.001, "steps 2->4")
	p.step_zoom()
	_check(absf(p.zoom_factor() - 7.0) < 0.001, "steps 4->7")
	p.step_zoom()
	_check(absf(p.zoom_factor() - 10.0) < 0.001, "steps 7->10")
	p.step_zoom()
	_check(absf(p.zoom_factor() - 1.0) < 0.001, "steps 10->1")
	p.set_zoom(4.0)
	_check(absf(p.zoom_factor() - 4.0) < 0.001, "zoom sets level")
	p.select_body("Mars")
	_check(p.focused_body() == "Mars", "highlight follows pick")
	p.set_zoom(5.0)
	p.select_body("Jupiter")
	_check(p.focused_body() == "Jupiter" and absf(p.zoom_factor() - 1.0) < 0.001, "new pick resets zoom")
	_check(not p.is_real_scan("Pluto") and p.is_real_scan("Mars"), "real texture flags")
	_check(p.has_travel("Mars") and not p.has_travel("Jupiter"), "travel flags")
	p.select_body("Mars")
	p.set_telescope("Mars")
	_check(p.telescope_body() == "Mars" and p.focused_body() == "Mars", "telescope keeps highlight")
	p.clear_focus()
	_check(p.focused_body() == "" and p.telescope_body() == "" and absf(p.zoom_factor() - 1.0) < 0.001, "back clears highlight+zoom")
	p.free()
	print("ZoomDial: ", "ALL PASS" if _fail == 0 else "SOME FAILED")
	quit(_fail)
