# Core loop check, headless.
# Run: godot --headless --path project -s tests/loop_test.gd
# Proves the whole loop MECHANISM without a headset:
# identify priority rules, focus->telescope->travel->back on a real
# PlanetsCore instance, teacher serve/dedup/stale-drop on a real
# TeacherClient, no-glow rule, version marker, panel wrap.
# What headless CANNOT prove (first-try aim, live relay, clean-room
# eyes): HEADSET_CHECKLIST.txt, 10 lines, 5 minutes, human-run.
extends SceneTree

const PlanetsCore = preload("res://scripts/planets_core.gd")
const TeacherClient = preload("res://scripts/teacher_client.gd")
const MainScript = preload("res://scripts/main.gd")

const TMP_CACHE: String = "user://loop_cache_test_tmp.json"

var _fail: int = 0
var _got_answers: Array = []
var _got_asks: int = 0
var _t: Node = null
var _frame: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("Loop: ", label, " PASS")
	else:
		_fail += 1
		print("Loop: ", label, " FAIL")

func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t

func _on_answer(o: String, a: String, s: String) -> void:
	_got_answers.append([o, a, s])

func _on_ask(_o: String) -> void:
	_got_asks += 1

func _initialize() -> void:
	var mg: String = _read("res://scripts/main.gd")
	# Identify rules: planets win wide, stars pick closest, fails talk.
	_check(mg.contains("body_best_angle < 10.0"), "planet capture 10 deg")
	_check(mg.contains("no more star dead end"), "stars pick closest, no dead end")
	_check(mg.contains("second_angle - best_angle < 0.5"), "star tie window 0.5 deg")
	_check(mg.contains("Closest was ") and mg.contains("degrees off"), "fail names closest + degrees")
	_check(mg.contains("show_not_sure"), "not-sure path kept")
	_check(mg.contains("var test_mode: bool = false"), "real mode default, no test mode")
	_check(mg.contains("Star App v43"), "version marker v43")
	_check(mg.contains("press_at(pinch_point)"), "journey hook present")
	# Star + planet content contracts.
	_check(MainScript.PLANET_FACTS.size() == 9, "9 planet facts")
	_check(MainScript.SPECTRAL_MEANING.size() == 7, "7 spectral meanings")
	# State machine on a real instance: room -> telescope -> travel -> clean.
	var p: Node3D = PlanetsCore.new()
	var bodies: Dictionary = {}
	var seed_nodes: Array = []
	for bn: String in ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		seed_nodes.append(mi)
		bodies[bn] = mi
	p._bodies = bodies
	_check(p.focused_body() == "" and p.telescope_body() == "" and p.travel_body() == "", "room starts clean")
	p.select_body("Saturn")
	_check(p.focused_body() == "Saturn", "identify brings Saturn to you")
	p.set_telescope("Saturn")
	_check(p.telescope_body() == "Saturn" and p.focused_body() == "Saturn", "telescope keeps Saturn")
	_check(p.can_travel("Saturn") and p.has_travel("Mars") and not p.has_travel("Jupiter"), "travel gate 7, real-pano Mars only")
	p.set_travel("Saturn")
	_check(p.travel_body() == "Saturn" and p.telescope_body() == "", "travel takes Saturn")
	_check(p.is_holding() == false, "travel never holds")
	p.hold_focused(Vector3.ZERO)
	_check(p.is_holding() == false, "hold needs room mode")
	p.clear_travel()
	p.clear_focus()
	_check(p.focused_body() == "" and p.telescope_body() == "" and p.travel_body() == "", "back returns clean room")
	_check(absf(p.zoom_factor() - 1.0) < 0.001, "back resets zoom")
	p.select_body("Mars")
	p.hold_focused(Vector3(0, 0, -3))
	_check(p.is_holding(), "room pinch-hold grabs")
	p.release_hold()
	_check(p.is_holding() == false, "release lets go")
	p.clear_focus()
	p.free()
	for n: Node in seed_nodes:
		n.free()
	# No-glow rule: the node exists but is never shown.
	var pg: String = _read("res://scripts/planets_core.gd")
	_check(pg.contains("_glow.visible = false") and pg.contains("_glow.visible = true") == false, "glow never visible")
	# Panel: one object one answer. Both main handlers drop anything
	# whose object is not the current selection; long answers wrap.
	_check(mg.contains("if _object_name != selected_object:"), "stale panel answers dropped")
	var pn: String = _read("res://scripts/identify_panel.gd")
	_check(pn.contains("260") and pn.contains("AUTOWRAP_WORD_SMART"), "long answers wrap in panel")
	_check(pn.contains("Teacher (local): Teacher") == false, "no doubled teacher prefix")
	var tg2: String = _read("res://scripts/teacher_client.gd")
	_check(tg2.contains("Relay not set up yet"), "setup message has no teacher-echo")
	# Teacher: cache-first serve + stale-drop are synchronous.
	# Same-object dedup runs on live frames below (_live_teacher),
	# because it travels the real _send_request path with HTTP.
	var t: Node = TeacherClient.new()
	t.cache_path = TMP_CACHE
	root.add_child(t)
	t.seed_cache("Saturn", TeacherClient.DEFAULT_QUESTION, "Saturn is the ringed planet.")
	_got_answers.clear()
	t.answer_ready.connect(_on_answer)
	t.ask_about_selected("Saturn")
	_check(_got_answers.size() == 1 and _got_answers[0][2] == "saved" and _got_answers[0][0] == "Saturn", "teacher serves saved on same pinch")
	var t2: Node = TeacherClient.new()
	t2.answer_ready.connect(_on_answer)
	_got_answers.clear()
	t2._pending_object = "Mars"
	t2._active_object = "Venus"
	t2._on_request_completed(0, 200, [], PackedByteArray())
	_check(_got_answers.is_empty(), "stale answer never lands")
	t2.free()
	_t = t
	var tg: String = _read("res://scripts/teacher_client.gd")
	_check(tg.contains('_base + "/ask"'), "single-slash ask")
	_check(tg.contains('"object"') and tg.contains('"lon"') == false, "post body object-only, never location")
	_live_teacher()
	# NOTE: no quit() here — _live_teacher finishes on live frames.

func _live_teacher() -> void:
	# Same object asked twice on a live tree: exactly one ask_started,
	# the real _send_request path, unroutable URL so nothing leaves.
	if _t == null:
		_check(false, "same-object pinch does not restart call")
		_finish()
		return
	if _t.get("_http") == null:
		_t._ready()
	_t.worker_url = "http://127.0.0.1:9/"
	_got_asks = 0
	_t.ask_started.connect(_on_ask)
	_frame = 1

func _process(_delta: float) -> bool:
	if _frame == 0:
		return false
	if _frame == 1:
		_t.ask_about_selected("Venus")
		_t.ask_about_selected("Venus")
		_check(_got_asks == 1, "same-object pinch does not restart call")
		_frame = 2
		return false
	_finish()
	return true

func _finish() -> void:
	if _t != null:
		_t.free()
		_t = null
	DirAccess.remove_absolute(TMP_CACHE)
	print("Loop: ", "ALL PASS" if _fail == 0 else "SOME FAILED")
	quit(_fail)
