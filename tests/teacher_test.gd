# Teacher reliability check, headless (v23).
# Run: godot --headless --path project -s tests/teacher_test.gd
# Covers the v23 pinch->teacher contract WITHOUT network:
# cache-key shape, seed/load roundtrip, cache-first ask (saved answer
# right away, no call), per-object saved fallback for repeat pinches,
# retry/timeout policy constants, empty-relay message, and the exact
# default first-pinch question text (must never change shape).
# Live retry timing (3 attempts ~1 s apart) is exercised in-headset;
# it needs the scene tree clock + relay and cannot run headless.
extends SceneTree

const TeacherClient = preload("res://scripts/teacher_client.gd")

const TMP_CACHE: String = "user://teacher_cache_test_tmp.json"
const DEFAULT_Q: String = "What is this, in plain words?"

var _fail: int = 0
var _got: Array = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("Teacher: ", label, " PASS")
	else:
		_fail += 1
		print("Teacher: ", label, " FAIL")

func _on_answer(o: String, a: String, s: String) -> void:
	_got.append([o, a, s])

func _fresh() -> Node:
	var t: Node = TeacherClient.new()
	t.cache_path = TMP_CACHE
	return t

func _initialize() -> void:
	DirAccess.remove_absolute(TMP_CACHE)
	# Key shape: lowercased object|question.
	_check(TeacherClient.cache_key("Mars", DEFAULT_Q) == "mars|what is this, in plain words?", "cache key shape")
	# Default question text is pinned: the relay contract.
	_check(TeacherClient.DEFAULT_QUESTION == DEFAULT_Q, "default question unchanged")
	# Retry policy: 2-3 attempts, pause between, long timeout.
	_check(TeacherClient.MAX_ATTEMPTS == 5, "five tries, proven live")
	_check(TeacherClient.RETRY_DELAYS == [1.0, 2.0, 3.0, 4.0], "1/2/3/4s backoff")
	_check(TeacherClient.REQUEST_TIMEOUT_S == 25.0, "25s timeout")
	_check(TeacherClient.RETRY_DELAY_S > 0.0, "retry delay set")
	_check(TeacherClient.REQUEST_TIMEOUT_S >= 15.0, "long timeout for slow answers")
	# Seed + load roundtrip through a temp cache file.
	var t: Node = _fresh()
	t.seed_cache("Mars", DEFAULT_Q, "Mars is the red planet.")
	_check(t.cached_answer("Mars", DEFAULT_Q) == "Mars is the red planet.", "seeded answer readable")
	var t2: Node = _fresh()
	t2._load_cache()
	_check(t2.cached_answer("Mars", DEFAULT_Q) == "Mars is the red planet.", "cache survives reload")
	# Per-object fallback: repeat pinch with a different question
	# still finds the saved first-pinch answer for that object.
	_check(t2.saved_answer_for_object("Jupiter", "Anything?") == "", "no fallback without any save")
	t2.seed_cache("Jupiter", DEFAULT_Q, "Jupiter is the giant.")
	_check(t2.saved_answer_for_object("Jupiter", "Something else?") == "Jupiter is the giant.", "fallback finds saved object answer")
	# Cache-first ask: repeat pinch emits saved at once, no network.
	_got.clear()
	t2.answer_ready.connect(_on_answer)
	t2.ask_about_selected("Jupiter")
	_check(_got.size() == 1 and _got[0][0] == "Jupiter" and _got[0][2] == "saved", "repeat pinch shows saved answer")
	# Empty relay: honest not-set-up message, still local.
	var t3: Node = _fresh()
	t3.cache_path = TMP_CACHE + ".empty"
	DirAccess.remove_absolute(TMP_CACHE + ".empty")
	_got.clear()
	t3.answer_ready.connect(_on_answer)
	t3.ask("Pluto", DEFAULT_Q)
	_check(_got.size() == 1 and _got[0][2] == "local" and String(_got[0][1]).contains("not set up"), "empty relay says not set up")
	t.free()
	t2.free()
	t3.free()
	DirAccess.remove_absolute(TMP_CACHE)
	DirAccess.remove_absolute(TMP_CACHE + ".empty")
	print("Teacher: ", "ALL PASS" if _fail == 0 else "SOME FAILED")
	quit(_fail)
