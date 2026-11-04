# Voice transcribe client, Grok rewrite 2026-11-02, vc135. Every error shown.
# Same relay endpoint as before. Old signals kept for main/wake compatibility:
# text_ready (main voice handler) and transcribe_failed, plus new
# status (panel) and transcribed (main voice handler, preferred).
extends Node

signal status(text)
signal transcribed(text: String)
signal text_ready(text: String)
signal transcribe_started()
signal transcribe_failed()

const URL := "https://star-app-teacher.zendragonvr.workers.dev/transcribe"

@export var worker_url: String = ""

var _http: HTTPRequest = null

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_done)

func transcribe_wav(wav_bytes: PackedByteArray) -> void:
	send(wav_bytes)

func send(wav: PackedByteArray) -> void:
	var base: String = worker_url.strip_edges()
	if base == "":
		base = URL
	while base.ends_with("/"):
		base = base.substr(0, base.length() - 1)
	transcribe_started.emit()
	var body: String = JSON.stringify({"audio_b64": Marshalls.raw_to_base64(wav), "mime": "audio/wav"})
	var err: int = _http.request(base + "/transcribe", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		status.emit("HTTP err req %d" % err)
		transcribe_failed.emit()
		return
	status.emit("Transcribing…")

func _done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		status.emit("HTTP err %d" % result)
		transcribe_failed.emit()
		return
	if code != 200:
		status.emit("HTTP %d" % code)
		transcribe_failed.emit()
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	var text: String = ""
	var live_str: String = ""
	if j is Dictionary:
		text = String(j.get("text", "")).strip_edges()
		live_str = " live:" + str(j.get("live", ""))
	if text != "":
		status.emit('I heard: "%s"%s' % [text, live_str])
		transcribed.emit(text)
		text_ready.emit(text)
	else:
		status.emit("I heard: (empty)" + live_str)
		text_ready.emit("")
		# vc175: main Talk client listens ONLY to transcribed, NOT text_ready,
		# so an empty result never reached _on_voice_text - wake was never
		# restarted, the mic player stayed stopped, and voice looked dead
		# after one silent Talk, with the panel stuck on "I heard: (empty)".
		# Now empty also emits transcribed(""), so _on_voice_text("") runs,
		# shows "I didn't hear anything" and restarts wake (vc172).
		# Wake client ignores transcribed (it only uses text_ready), so this
		# does not double-fire wake.
		transcribed.emit("")
