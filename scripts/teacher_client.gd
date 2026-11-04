# Fresh teacher client, written 2026-10-26.
# The app never calls the Meta API directly and never sends the
# user's location. It talks only to the Cloudflare Worker relay,
# which holds the API key as a secret. The Worker URL is set in
# the scene / config when the relay is deployed — until then it
# is empty, and the teacher honestly says it is not set up yet.
# Cache first, always: a cached answer costs zero credits, and
# the panel says "saved". A fresh API call costs a fraction of
# a cent, and the panel says "live". That is how the user knows
# credits are being used.
# No invented answers: if there is no cache and no live answer,
# the panel says the teacher is offline / not set up, never a
# made-up explanation.
extends Node

signal answer_ready(object_name: String, answer: String, source_label: String)
# v23: emitted when a network ask starts (cache miss), so the panel
# can show "Asking teacher..." instead of answering instantly.
signal ask_started(object_name: String)

@export var worker_url: String = ""
@export var cache_path: String = "user://teacher_cache.json"

# v23 reliability (headset report 2026-10-28: a pinch sometimes said
# "offline" while the relay was live, a later pinch worked). Policy:
# 3 attempts ~1 s apart, 25 s request timeout so a slow answer does
# not count as a failure, "Asking teacher..." from the first attempt,
# per-object saved-answer fallback before ever saying offline.
# Worker URL, question format, and POST body are UNCHANGED, and a
# failed call still says offline after all retries — never invented.
const MAX_ATTEMPTS: int = 5
const RETRY_DELAYS: Array = [1.0, 2.0, 3.0, 4.0]
const RETRY_DELAY_S: float = 1.0 # kept for tests/teacher_test.gd, runtime uses RETRY_DELAYS
const REQUEST_TIMEOUT_S: float = 25.0
const OFFLINE_TEXT: String = "Offline right now — try again later."
const DEFAULT_QUESTION: String = "What is this, in plain words?"
# vc182 (user 2026-11-04): the teacher must ALWAYS answer. Muse sometimes
# replied "I'm not confident..." and stopped. The app now adds this style
# note to every question it sends (the relay passes the question through),
# and if a reply still opens with a hedge, it asks once more, more firmly.
# Honest, not invented: for things science doesn't know yet, it says what
# scientists currently think instead of refusing.
const ANSWER_STYLE: String = "\n\n(Answer as a friendly, expert space teacher speaking out loud in a VR headset. Always give a direct, helpful answer in 2-4 short sentences, using your best knowledge. Never say you are not confident, not sure, or unable to answer, and never refuse. If something is truly unknown to science, say what scientists currently think.)"
const ANSWER_STYLE_FIRM: String = "\n\n(Important: answer the question directly now, in 2-4 short spoken sentences, with your best knowledge. Do not mention confidence, uncertainty or being an AI. Do not refuse.)"
# vc185: daily horoscope requests get their own style (for fun, tradition).
const HOROSCOPE_STYLE: String = "\n\n(This is for fun, in Western astrology tradition. Write it like a warm, upbeat daily horoscope column read out loud: one line on love, one on work or school, one on health or energy, and one lucky tip, 4-5 short spoken sentences. No disclaimers, no mention of being an AI.)"
var _hedge_retry: bool = false
var _hedge_re: RegEx = null

func _is_hedge(answer: String) -> bool:
	if _hedge_re == null:
		_hedge_re = RegEx.new()
		_hedge_re.compile("(?i)^\\W*(i'?m|i am|i'?m not|sorry|unfortunately|as an ai|i (do not|don'?t|cannot|can'?t))[^.]{0,60}(not (confident|sure|certain)|unsure|cannot|can'?t|unable|don'?t (know|have)|do not (know|have)|not able)")
	return _hedge_re.search(answer.strip_edges()) != null

var _http: HTTPRequest = null
var _cache: Dictionary = {}
var _pending_object: String = ""
var _pending_question: String = ""
var _attempt: int = 0
var _request_id: int = 0
var _active_object: String = ""
var _active_question: String = ""

func _ready() -> void:
	_load_cache()
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func _load_cache() -> void:
	var f: FileAccess = FileAccess.open(cache_path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_cache = data
	f.close()

func _save_cache() -> void:
	var f: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cache))
	f.close()

static func cache_key(object_name: String, question: String) -> String:
	return object_name.to_lower().strip_edges() + "|" + question.to_lower().strip_edges()

func cached_answer(object_name: String, question: String) -> String:
	return _cache.get(cache_key(object_name, question), "")

func ask(object_name: String, question: String) -> void:
	# Cache first, always: a repeat pinch shows the saved answer
	# right away, even if the network hiccups — no call needed.
	var key: String = cache_key(object_name, question)
	var hit: String = _cache.get(key, "")
	if hit != "" and _is_hedge(hit):
		_cache.erase(key)  # vc182: an old saved "I'm not confident" is thrown away and asked fresh
		hit = ""
	if hit != "":
		answer_ready.emit(object_name, hit, "saved")
		return
	if worker_url.strip_edges() == "":
		answer_ready.emit(object_name, "Relay not set up yet — needs to be deployed first.", "local")
		return
	# vc40: same object + same question already in flight: DO NOT
	# cancel/restart it. Rapid pinches (room -> telescope -> travel)
	# used to restart Teacher every time, so it never answered.
	# Only a DIFFERENT object/question cancels the old call.
	if _pending_object == object_name and _pending_question == question:
		return
	_request_id += 1
	# A newer pinch wins: cancel any in-flight older call (its
	# cancelled finish is ignored) so its answer can never land
	# on this object, and its retry chain dies via _request_id.
	if _pending_object != "" and _http != null:
		_http.cancel_request()
	_pending_object = object_name
	_pending_question = question
	_attempt = 1
	_hedge_retry = false
	ask_started.emit(object_name)
	_send_request()

func ask_about_selected(object_name: String) -> void:
	# Default first question, so the teacher works on a pinch
	# alone, before voice input lands. Cached after the first ask.
	ask(object_name, DEFAULT_QUESTION)

func _send_request() -> void:
	# POST body format is UNCHANGED: object + question only.
	# Location is never collected here and never sent.
	_active_object = _pending_object
	_active_question = _pending_question
	var style: String = (ANSWER_STYLE_FIRM if _hedge_retry else ANSWER_STYLE)
	if _pending_question.begins_with("Horoscope:"):
		style = HOROSCOPE_STYLE
	var body: Dictionary = {"object": _pending_object, "question": _pending_question + style}
	# vc41 ROOT CAUSE, proven by vc40 diagnostic "(last: result 0,
	# code 404, 5 tries)": worker_url ends with "/" in main.tscn,
	# so this built "...dev//ask". The worker only matches exactly
	# "/ask", so "//ask" returned 404 every time, 5 tries, offline.
	# Outside-headset curl used a single slash, which is why the
	# relay looked live from here and dead in the headset.
	# Strip trailing slashes here, so any URL form works.
	var _base: String = worker_url.strip_edges()
	while _base.ends_with("/"):
		_base = _base.substr(0, _base.length() - 1)
	var err: int = _http.request(_base + "/ask", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_fail_or_retry()

func _fail_or_retry() -> void:
	# One failed attempt is never the verdict: retry on our own
	# up to MAX_ATTEMPTS before ever saying offline. A newer ask()
	# cancels an older retry chain via _request_id.
	if _attempt < MAX_ATTEMPTS and _pending_object != "":
		var id: int = _request_id
		var _delay: float = RETRY_DELAYS[_attempt - 1] if _attempt - 1 < RETRY_DELAYS.size() else 4.0
		_attempt += 1
		await get_tree().create_timer(_delay).timeout
		if id != _request_id or _pending_object == "":
			return
		_send_request()
		return
	var object_name: String = _pending_object
	var question: String = _pending_question
	_pending_object = ""
	_pending_question = ""
	# All retries failed: if any answer for this object was ever
	# saved, show that instead of offline. Offline is the last
	# resort, and it is never an invented answer.
	var fallback: String = saved_answer_for_object(object_name, question)
	if fallback != "":
		answer_ready.emit(object_name, fallback, "saved")
	else:
		answer_ready.emit(object_name, OFFLINE_TEXT, "local")

func saved_answer_for_object(object_name: String, question: String = "") -> String:
	# Any saved answer for this star/planet: exact question first,
	# then the default first-pinch answer, then anything saved.
	var prefix: String = object_name.to_lower().strip_edges() + "|"
	if question != "":
		var exact: String = str(_cache.get(prefix + question.to_lower().strip_edges(), ""))
		if exact != "":
			return exact
	var def: String = str(_cache.get(prefix + DEFAULT_QUESTION.to_lower(), ""))
	if def != "":
		return def
	for k: Variant in _cache.keys():
		if str(k).begins_with(prefix) and str(_cache[k]) != "":
			return str(_cache[k])
	return ""

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# Stray completion with nothing pending: ignore it, never treat
	# it as a failure. (Godot 4.3 has no RESULT_CANCELED member, so a
	# cancel result cannot be named here — the pending guard covers the
	# cancelled-by-newer-pinch case too, since ask() always sets pending.)
	if _pending_object == "":
		return
	# vc42: completion for an old request (user pinched a new object
	# since) is stale — drop it, do NOT retry it, the new object's
	# own request is already in flight and owns the retries.
	if _active_object != _pending_object or _active_question != _pending_question:
		return
	var object_name: String = _pending_object
	var question: String = _pending_question
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail_or_retry()
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or String(data.get("answer", "")).strip_edges() == "":
		_fail_or_retry()
		return
	var answer: String = String(data["answer"])
	# vc182: a hedge ("I'm not confident...") is not an answer: ask once more.
	if _is_hedge(answer) and not _hedge_retry:
		_hedge_retry = true
		_send_request()
		return
	_pending_object = ""
	_pending_question = ""
	var live: bool = bool(data.get("live", false))
	if live and not _is_hedge(answer):
		_cache[cache_key(object_name, question)] = answer
		_save_cache()
	answer_ready.emit(object_name, answer, "live" if live else "saved")

# Test / cache-seeding hook: put an answer in the cache without
# spending credits. Used in headless tests and for verified
# first-pinch explanations the user has approved.
func seed_cache(object_name: String, question: String, answer: String) -> void:
	_cache[cache_key(object_name, question)] = answer
	_save_cache()
