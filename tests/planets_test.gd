# Headless planets/Moon check, written 2026-10-26.
# Run: godot --headless --path project -s tests/planets_test.gd
# Expected RA/Dec are the spec's OURS values at JD(TT) 2461337.69872.
# Tolerance 0.05 degrees of arc (Moon topocentric 0.3, its series limit).
extends SceneTree

const AstroMathScript = preload("res://scripts/astro_math.gd")

func _ang_diff(a: float, b: float) -> float:
	return abs(AstroMathScript.fmod360(a - b + 180.0) - 180.0)

func _initialize() -> void:
	var jd_tt: float = 2461337.69872
	var jd_ut1: float = 2461337.69792
	var cases: Array = [
		["Mercury", 15.15375, -20.8029],
		["Venus", 13.72289, -17.6722],
		["Mars", 9.14191, 17.9392],
		["Jupiter", 9.70173, 14.4899],
		["Saturn", 0.65331, 1.2844],
		["Uranus", 4.17538, 20.8998],
		["Neptune", 0.15183, -0.5576],
		["Sun", 13.88740, -11.6171],
	]
	var all_pass: bool = true
	for c: Array in cases:
		var rd: Dictionary = AstroMathScript.planet_radec_j2000(c[0], jd_tt)
		var dra: float = _ang_diff(rd["ra_h"] * 15.0, c[1] * 15.0)
		var ddec: float = abs(rd["dec_deg"] - c[2])
		var ok: bool = dra < 0.05 and ddec < 0.05
		if not ok:
			all_pass = false
		print("Planets: ", c[0], " RA ", rd["ra_h"], " (exp ", c[1], ") Dec ", rd["dec_deg"], " (exp ", c[2], ") ", "PASS" if ok else "FAIL")
	var moon_geo: Dictionary = AstroMathScript.moon_radec_j2000(jd_tt, jd_ut1, 28.5496, -81.7729, false)
	var moon_topo: Dictionary = AstroMathScript.moon_radec_j2000(jd_tt, jd_ut1, 28.5496, -81.7729, true)
	print("Moon geocentric RA ", moon_geo["ra_h"], " (exp 0.22115) Dec ", moon_geo["dec_deg"], " (exp 4.7355)")
	print("Moon topocentric RA ", moon_topo["ra_h"], " (exp 0.20261) Dec ", moon_topo["dec_deg"], " (exp 4.3385)")
	var moon_ok: bool = _ang_diff(moon_topo["ra_h"] * 15.0, 0.20261 * 15.0) < 0.3 and abs(moon_topo["dec_deg"] - 4.3385) < 0.3
	if not moon_ok:
		all_pass = false
	print("Planets: ", "ALL PASS" if all_pass else "SOME FAILED (see Moon tolerance note)")
	quit()
