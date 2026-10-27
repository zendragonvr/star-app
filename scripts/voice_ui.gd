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

func play_voice(key: String) -> void:
	var path: String = VOICE_PATH % key
	var stream: AudioStream = load(path)
	if stream != null:
		self.stream = stream
		play()

func play_sound(key: String) -> void:
	var path: String = SOUND_PATH % key
	var stream: AudioStream = load(path)
	if stream != null:
		self.stream = stream
		play()
