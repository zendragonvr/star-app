# Launch Watch trip check, headless.
# Run: godot --headless --path project -s tests/journey_test.gd
# Contract (user Launch Watch step):
# - Artemis II REPLAY with true dates, crew, distance; flyby, NEVER
#   a landing claim. Missing data is said aloud, never invented.
# - True direction (lock), shrunk distance, true km/days on panel,
#   time scaled. Lock off -> says so, never fakes it.
# - Real footage on a flat screen (OGV), never called 3D; absent
#   footage is reported, not faked.
# - Star chart untouched: identify/calibrate paths still present,
#   journey consumes only its own presses.
extends SceneTree

const Journey = preload("res://scripts/journey.gd")

var _fail: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("Journey: ", label, " PASS")
	else:
		_fail += 1
		print("Journey: ", label, " FAIL")

func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t

func _initialize() -> void:
	var trip: Dictionary = Journey.TRIP
	_check(trip.get("name", "") == "Artemis II", "trip is Artemis II")
	_check(trip.get("kind", "") == "REPLAY", "labelled REPLAY")
	_check(trip.get("launch", "") == "Apr 1, 2026", "launch Apr 1 2026")
	_check(trip.get("splash", "") == "Apr 10, 2026", "splashdown Apr 10 2026")
	_check(float(trip.get("days", 0.0)) == 9.0, "9-day trip")
	_check(float(trip.get("one_way_km", 0.0)) == 384400.0, "true 384400 km")
	var crew: Array = trip.get("crew", [])
	_check(crew.size() == 4, "four crew")
	for surname: String in ["Wiseman", "Glover", "Koch", "Hansen"]:
		var found: bool = false
		for c: Variant in crew:
			if str(c).contains(surname):
				found = true
		_check(found, "crew has " + surname)
	_check(str(trip.get("note", "")).contains("no landing"), "flyby, no landing")
	_check(str(trip.get("note", "")).contains("Apollo 17"), "names Apollo 17 gap")
	_check(float(trip.get("mission_minutes", 99.0)) <= 5.0, "trip plays in minutes")
	var expect_scale: float = 9.0 * 24.0 * 60.0 / float(trip.get("mission_minutes", 3.0))
	_check(abs(float(trip.get("time_scale", 0.0)) - expect_scale) < 1.0, "time scale math honest")
	var jg: String = _read("res://scripts/journey.gd")
	_check(jg.contains("calibration_done") and jg.contains("No sky lock"), "lock off is said aloud")
	_check(jg.contains("touchdown") == false and jg.contains("Moon landing") == false, "no landing invented")
	_check(jg.contains(".ogv") and jg.contains("not 3D"), "footage flat, OGV")
	_check(jg.contains("NOT IN BUILD"), "missing footage reported")
	_check(jg.contains("model, not telemetry"), "panel says scaled model")
	_check(jg.contains("km from Earth (true)") == false, "room distance never called true km")
	_check(jg.contains("1:196") and jg.contains("98 m"), "own model from public size")
	_check(jg.contains("SHIP_SCALE_MIN") and jg.contains("SHIP_SCALE_MAX"), "table-to-park scale clamped")
	_check(jg.contains('return ""'), "sky pinches fall through")
	var mg: String = _read("res://scripts/main.gd")
	_check(mg.contains("func _identify") and mg.contains("func _try_calibrate"), "star chart code intact")
	_check(mg.contains("show_not_sure"), "not-sure path intact")
	_check(mg.contains("press_at(pinch_point)"), "journey hooked additively")
	print("Journey: ", "ALL PASS" if _fail == 0 else "SOME FAILED")
	quit(_fail)
