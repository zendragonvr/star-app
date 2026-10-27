# Headless acceptance check, written 2026-10-26.
# Run: godot --headless --path project -s tests/acceptance_test.gd
# Inputs from the validated spec: 2026-10-24 04:45:00 UTC,
# Clermont lat 28.5496, lon -81.7729, JD(TT) 2461337.69872,
# JD(UT1) 2461337.69792. Expected alt/az are the spec's OURS values.
# Tolerance 0.05 degrees here (looser than the spec's 0.01, because
# this v1 omits proper motion — see astro_math.gd note).
extends SceneTree

const AstroMathScript = preload("res://scripts/astro_math.gd")

func _initialize() -> void:
	var jd_tt: float = 2461337.69872
	var jd_ut1: float = 2461337.69792
	var lat: float = 28.5496
	var lon: float = -81.7729
	var cases: Array = [
		["Sirius", 6.752481, -16.716116, 0.8907, 109.6748],
		["Betelgeuse", 5.919529, 7.407063, 23.6403, 94.4673],
		["Vega", 18.61564, 38.783692, 8.6237, 309.7280],
		["Polaris", 2.52975, 89.264109, 29.1175, 0.2989],
		["Rigel", 5.242298, -8.20164, 24.0318, 114.8216],
	]
	var all_pass: bool = true
	for c: Array in cases:
		var aa: Dictionary = AstroMathScript.star_alt_az(c[1], c[2], jd_tt, jd_ut1, lat, lon)
		var dalt: float = abs(aa["alt"] - c[3])
		var daz: float = abs(AstroMathScript.fmod360(aa["az"] - c[4] + 180.0) - 180.0)
		var ok: bool = dalt < 0.05 and daz < 0.05
		if not ok:
			all_pass = false
		print("Star App acceptance: ", c[0], " alt ", aa["alt"], " (exp ", c[3], ", diff ", dalt, ") az ", aa["az"], " (exp ", c[4], ", diff ", daz, ") ", "PASS" if ok else "FAIL")
	print("Star App acceptance: ", "ALL PASS" if all_pass else "SOME FAILED")
	quit()
