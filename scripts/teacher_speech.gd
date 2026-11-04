# Teacher speech via relay audio, NOT DisplayServer TTS (vc139 crashed Quest).
# Splits the answer into <=180-char sentence chunks, GETs /speak per chunk
# (worker proxies Google Translate TTS, MP3), plays each via AudioStreamMP3
# in order, exactly like planet voice files play through the app audio.
extends Node

var worker_url: String = ""
var _http: HTTPRequest = null
var _http2: HTTPRequest = null
var _player: AudioStreamPlayer = null
var _queue: Array = []
var _busy: bool = false
var _next_body: PackedByteArray = PackedByteArray()
var _next_ready: bool = false
var _prefetch_text: String = ""

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_chunk_done)
	_http2 = HTTPRequest.new()
	_http2.timeout = 15.0
	add_child(_http2)
	_http2.request_completed.connect(_on_prefetch_done)
	DirAccess.make_dir_recursive_absolute("user://tts_cache")
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_play_finished)

func stop() -> void:
	_queue.clear()
	_busy = false
	_next_body = PackedByteArray()
	_next_ready = false
	if _http != null:
		_http.cancel_request()
	if _http2 != null:
		_http2.cancel_request()
	if _player != null and _player.playing:
		_player.stop()

func speak(text: String) -> void:
	stop()
	if text.strip_edges() == "" or worker_url.strip_edges() == "":
		return
	_queue = _split_chunks(text)
	_next_chunk()

# vc185: add more speech AFTER what is already playing (used to follow a
# zodiac reading with today's horoscope, without cutting the reading off).
func enqueue(text: String) -> void:
	if text.strip_edges() == "" or worker_url.strip_edges() == "":
		return
	if not _busy and not (_player != null and _player.playing):
		speak(text)
		return
	var was_empty: bool = _queue.is_empty()
	_queue.append_array(_split_chunks(text))
	if was_empty and not _next_ready and _prefetch_text == "":
		_start_prefetch()

func _split_chunks(text: String) -> Array:
	# Split on sentence ends, accumulate to <=180 chars per chunk.
	var out: Array = []
	var cur := ""
	var i := 0
	while i < text.length():
		var c: String = text[i]
		cur += c
		var is_end := (c == "." or c == "!" or c == "?") and (i + 1 >= text.length() or text[i + 1] == " ")
		if is_end or cur.length() >= 180:
			if cur.strip_edges() != "":
				out.append(cur.strip_edges())
			cur = ""
		i += 1
	if cur.strip_edges() != "":
		out.append(cur.strip_edges())
	return out

func _cache_path(chunk: String) -> String:
	return "user://tts_cache/" + str(chunk.hash()) + ".mp3"

func _play_body(body: PackedByteArray) -> void:
	var stream := AudioStreamMP3.new()
	stream.data = body
	stream.loop = false
	_player.stream = stream
	_player.play()

func _start_prefetch() -> void:
	# vc143 PREFETCH: while the current chunk plays, download the next
	# one on a second request, so there is no download gap between chunks.
	_next_ready = false
	_next_body = PackedByteArray()
	_prefetch_text = ""
	if _queue.is_empty():
		return
	var chunk: String = String(_queue[0])
	_prefetch_text = chunk
	var cached := FileAccess.open(_cache_path(chunk), FileAccess.READ)
	if cached != null:
		_next_body = cached.get_buffer(cached.get_length())
		cached.close()
		_next_ready = true
		return
	var url: String = worker_url.strip_edges().trim_suffix("/") + "/speak?text=" + chunk.uri_encode()
	_http2.request(url)

func _next_chunk() -> void:
	# If a prefetched chunk is ready, play it at once and prefetch the next.
	if _next_ready:
		_next_ready = false
		_queue.pop_front()
		_busy = true
		_play_body(_next_body)
		_start_prefetch()
		return
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var chunk: String = String(_queue.pop_front())
	# vc143 RACE FIX: if a prefetch for this chunk is still in flight,
	# cancel it, or its late arrival would replay this chunk as the next one.
	if _http2 != null:
		_http2.cancel_request()
	_next_ready = false
	_prefetch_text = ""
	var cached := FileAccess.open(_cache_path(chunk), FileAccess.READ)
	if cached != null:
		_play_body(cached.get_buffer(cached.get_length()))
		_start_prefetch()
		return
	var url: String = worker_url.strip_edges().trim_suffix("/") + "/speak?text=" + chunk.uri_encode()
	var err: int = _http.request(url)
	if err != OK:
		_next_chunk()

func _on_chunk_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200 or body.is_empty():
		_next_chunk()
		return
	# Save for repeat questions (same chunk text = instant speech next time).
	# The chunk text itself is not stored with the audio; the filename is
	# only its hash, so this cache is keyed by exact chunk text.
	_play_body(body)
	_start_prefetch()

func _on_prefetch_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# Only accept the prefetch if its chunk is still the next one in line.
	if code == 200 and not body.is_empty() and not _queue.is_empty() and String(_queue[0]) == _prefetch_text:
		_next_body = body
		_next_ready = true

func _on_play_finished() -> void:
	_next_chunk()
