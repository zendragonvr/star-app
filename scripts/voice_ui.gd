# v18 UI voice + sounds. Fixed lines only, robot lady voice.
# Dynamic teacher answers are NOT spoken in v18 — they need
# a runtime TTS engine on Quest, which is a separate plugin
# build, not a pre-recorded file. Fixed lines cover: lock,
# not sure, bring-to-room (9 bodies), telescope, travel,
# back to room. Stars: click sound only in v18, name voice
# for 3,089 stars cannot be pre-recorded.
# Sounds are synthesized WAVs, no external audio.
extends AudioStreamPlayer

const VOICE_PATH: String = "res://data/voice/%s.ogg"
const SOUND_PATH: String = "res://data/sounds/%s.wav"

var _seq: Array = []
var _seq_idx: int = 0
var _pause_timer: Timer = null

func _ready() -> void:
	_pause_timer = Timer.new()
	_pause_timer.one_shot = true
	_pause_timer.wait_time = 3.0
	_pause_timer.timeout.connect(_play_seq_next)
	add_child(_pause_timer)
	finished.connect(_on_voice_finished)

func play_name_desc(body_name: String) -> void:
	# vc61: AI voice says "MARS", 3 second pause, then reads the description.
	if _pause_timer != null:
		_pause_timer.stop()
	_seq = []
	_seq_idx = 0
	var low: String = body_name.to_lower().replace(" ", "_")
	_seq = ["voice_%s_name" % low, "voice_%s_desc" % low]
	_play_seq_next()

func _play_seq_next() -> void:
	if _seq_idx >= _seq.size():
		_seq = []
		return
	play_voice(_seq[_seq_idx])

func _on_voice_finished() -> void:
	if _seq.size() == 0:
		return
	_seq_idx += 1
	if _seq_idx >= _seq.size():
		_seq = []
		return
	# 3 second pause between name and description, exactly as specified.
	_pause_timer.start(3.0)

func stop_all() -> void:
	# vc94: reverse must kill the whole voice chain, not just the current clip - a pending name->desc timer or a typing-finished desc would otherwise start reading after the planet went back.
	_seq = []
	_seq_idx = 0
	if _pause_timer != null:
		_pause_timer.stop()
	stop()

func play_voice(key: String) -> void:
	if key not in _seq:
		_seq = []
	var path: String = VOICE_PATH % key
	var stream: AudioStream = load(path)
	if stream != null:
		stop()
		self.stream = stream
		play()

func play_sound(key: String) -> void:
	var path: String = SOUND_PATH % key
	var stream: AudioStream = load(path)
	if stream != null:
		stop()
		self.stream = stream
		play()
