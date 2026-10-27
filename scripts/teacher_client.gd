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

@export var worker_url: String = ""
@export var cache_path: String = "user://teacher_cache.json"

var _http: HTTPRequest = null
var _cache: Dictionary = {}
var _pending_object: String = ""
var _pending_question: String = ""

func _ready() -> void:
	_load_cache()
	_http = HTTPRequest.new()
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
	var key: String = cache_key(object_name, question)
	var hit: String = _cache.get(key, "")
	if hit != "":
		answer_ready.emit(object_name, hit, "saved")
		return
	if worker_url.strip_edges() == "":
		answer_ready.emit(object_name, "Teacher is not set up yet — the relay needs to be deployed first.", "local")
		return
	_pending_object = object_name
	_pending_question = question
	var body: Dictionary = {"object": object_name, "question": question}
	var err: int = _http.request(worker_url + "/ask", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		answer_ready.emit(object_name, "Teacher is offline right now — try again later.", "local")

func ask_about_selected(object_name: String) -> void:
	# Default first question, so the teacher works on a pinch
	# alone, before voice input lands. Cached after the first ask.
	ask(object_name, "What is this, in plain words?")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var object_name: String = _pending_object
	var question: String = _pending_question
	_pending_object = ""
	_pending_question = ""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		answer_ready.emit(object_name, "Teacher is offline right now — try again later.", "local")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or String(data.get("answer", "")).strip_edges() == "":
		answer_ready.emit(object_name, "Teacher is offline right now — try again later.", "local")
		return
	var answer: String = String(data["answer"])
	var live: bool = bool(data.get("live", false))
	if live:
		_cache[cache_key(object_name, question)] = answer
		_save_cache()
	answer_ready.emit(object_name, answer, "live" if live else "saved")

# Test / cache-seeding hook: put an answer in the cache without
# spending credits. Used in headless tests and for verified
# first-pinch explanations the user has approved.
func seed_cache(object_name: String, question: String, answer: String) -> void:
	_cache[cache_key(object_name, question)] = answer
	_save_cache()
