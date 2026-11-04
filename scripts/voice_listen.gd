# Voice listen, Grok rewrite 2026-11-02, vc135. Explicit failure states, nothing silent.
# - Mic bus: created here at startup if it does not exist (same state as
#   Project Settings bus, without a fragile .tres format guess): bus "Mic",
#   AudioEffectCapture buffer_length 1.0, bus MUTED so you hear nothing,
#   send defaults to Master. Capture effect is NOT on Master anymore.
# - Player: AudioStreamMicrophone on bus "Mic", played only while listening.
# - _process drains EVERY frame, status 4x/sec with level + frame count,
#   auto-stop at 6s. stop() emits audio_ready(wav), never returns a wav
#   for main to double-send.
# - Old main interface kept as aliases: set_camera, listen_position,
#   is_listening, start_listen, stop_listen, start_wake, drain_clip.
extends Node3D

signal status(text)
signal audio_ready(wav: PackedByteArray)
signal listen_started()
signal listen_stopped()

const TARGET_RATE := 16000
const MAX_SEC := 6.0

var _label: Label3D = null
var _camera: XRCamera3D = null
var _player: AudioStreamPlayer = null
var _cap: AudioEffectCapture = null
var _frames := PackedVector2Array()
var _listening := false
var _t := 0.0
var _tick := 0.0
var _peak := 0.0
var _bus_error: String = ""
var _wake_active := false
var _wake_frames := PackedVector2Array()
var _heard_speech := false
var _quiet_sec := 0.0

func _ready() -> void:
	_label = Label3D.new()
	_label.text = ""
	_label.visible = false
	add_child(_label)
	# Mic bus setup. If a Mic bus already exists (editor layout), use it.
	var bus: int = AudioServer.get_bus_index("Mic")
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus, "Mic")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, true)
		# Remove any capture on Master, per Grok fix, then ensure Mic has one.
		var master: int = AudioServer.get_bus_index("Master")
		if master >= 0:
			for i in range(AudioServer.get_bus_effect_count(master) - 1, -1, -1):
				if AudioServer.get_bus_effect(master, i) is AudioEffectCapture:
					AudioServer.remove_bus_effect(master, i)
		_cap = null
		for i in range(AudioServer.get_bus_effect_count(bus)):
			var eff = AudioServer.get_bus_effect(bus, i)
			if eff is AudioEffectCapture:
				_cap = eff
				break
		if _cap == null:
			_cap = AudioEffectCapture.new()
			_cap.buffer_length = 1.0
			AudioServer.add_bus_effect(bus, _cap)
		else:
			_cap.buffer_length = 1.0
	else:
		_bus_error = "Mic bus: NO BUS"
	if _cap == null and _bus_error == "":
		_bus_error = "Mic bus: NO CAPTURE"
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = "Mic"
	add_child(_player)

func set_camera(camera: XRCamera3D) -> void:
	_camera = camera

func _process(delta: float) -> void:
	if _camera != null:
		var cam_basis: Basis = _camera.global_transform.basis
		global_position = _camera.global_position + cam_basis * Vector3(0.0, -0.32, -0.75)
	if not _listening:
		# vc145 WAKE: rolling capture while not push-listening, so main
		# can drain a 3s clip every 3s and check for "Star Bridge".
		# vc172: after headset sleep/pause the mic player can stop while
		# _wake_active stays true, so capture goes silent and wake looks
		# dead even though the flag is on. Re-play the player here without
		# clearing frames, so the rolling 3 s buffer keeps working.
		if _wake_active and _player != null and not _player.playing:
			_player.play()
		if _wake_active and _cap != null:
			var wn: int = _cap.get_frames_available()
			if wn > 0:
				_wake_frames.append_array(_cap.get_buffer(wn))
				var maxf: int = int(AudioServer.get_mix_rate() * 6.0)  # vc183: 6 s window, covers the wait while the last clip is being transcribed
				if _wake_frames.size() > maxf:
					_wake_frames = _wake_frames.slice(_wake_frames.size() - maxf)
		return
	if _cap == null:
		status.emit("Mic bus: NO CAPTURE")
		_listening = false
		return
	var n: int = _cap.get_frames_available()
	if n > 0:
		var chunk: PackedVector2Array = _cap.get_buffer(n)
		_frames.append_array(chunk)
		for f in chunk:
			_peak = max(_peak, abs(f.x))
	_t += delta
	_tick += delta
	if _tick >= 0.25:
		_tick = 0.0
		var bars: String = "▮".repeat(clampi(int(_peak * 10), 0, 5))
		status.emit("Listening… %ds · lvl %s · %dk frames" % [int(_t), bars, _frames.size() / 1000])
		_peak = 0.0
	if _t >= MAX_SEC:
		stop()

func listen_position() -> Vector3:
	return global_position

func is_listening() -> bool:
	return _listening

func start_listen() -> bool:
	return start()

func start() -> bool:
	if _cap == null or _bus_error != "":
		status.emit(_bus_error if _bus_error != "" else "Mic bus: NO CAPTURE")
		return false
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		status.emit("Input: OFF")
		return false
	if OS.get_name() == "Android" and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		status.emit("Mic: asking…")
		OS.request_permissions()
		var tree = get_tree()
		if tree != null and tree.has_signal("on_request_permissions_result"):
			tree.on_request_permissions_result.connect(_on_perm, CONNECT_ONE_SHOT)
			return false
		# No permission signal on this build: proceed, the OS prompt still ran.
		_begin()
		return true
	_begin()
	return true

func _on_perm(perm: String, granted: bool) -> void:
	if perm.ends_with("RECORD_AUDIO"):
		if granted:
			status.emit("Mic: granted")
			_begin()
		else:
			status.emit("Mic: DENIED")

func _begin() -> void:
	_frames.clear()
	if _cap != null:
		_cap.clear_buffer()
	_t = 0.0
	_tick = 0.0
	_peak = 0.0
	_heard_speech = false
	_quiet_sec = 0.0
	_wake_active = false
	_player.play()
	_listening = true
	listen_started.emit()
	status.emit("Listening… 0s")

func stop() -> void:
	if not _listening:
		return
	_listening = false
	_player.stop()
	listen_stopped.emit()
	var rate: float = AudioServer.get_mix_rate()
	var secs: float = _frames.size() / rate
	if secs < 0.3:
		status.emit("Too short: %.1fs" % secs)
		return
	var wav: PackedByteArray = _to_wav16k(_frames, rate)
	status.emit("Sending %.1fs of audio (%d KB)…" % [secs, wav.size() / 1024])
	audio_ready.emit(wav)

func stop_listen() -> PackedByteArray:
	# Old main call sites used the returned wav. New flow is audio_ready,
	# so this only stops; main must not transcribe a second copy.
	stop()
	return PackedByteArray()

func start_wake() -> void:
	# vc145 WAKE RE-ENABLED (user 2026-11-02): rolling 3s capture.
	# Push listening takes the player over; wake resumes after it ends.
	if _cap == null:
		return
	_wake_frames.clear()
	_wake_active = true
	if not _player.playing:
		_player.play()

func stop_wake() -> void:
	_wake_active = false
	_wake_frames.clear()
	if not _listening and _player.playing:
		_player.stop()

func drain_clip() -> PackedByteArray:
	if _wake_frames.is_empty():
		return PackedByteArray()
	var wav: PackedByteArray = _to_wav16k(_wake_frames, AudioServer.get_mix_rate())
	# vc182: keep the last 1.5 s, so the next clip OVERLAPS this one. Before,
	# clips were cut back to back every 3 s, so "Star Bridge" said across a
	# cut was split in two and never heard.
	var keep: int = int(AudioServer.get_mix_rate() * 1.5)
	if _wake_frames.size() > keep:
		_wake_frames = _wake_frames.slice(_wake_frames.size() - keep)
	return wav

func _to_wav16k(src: PackedVector2Array, rate: float) -> PackedByteArray:
	var step: float = rate / TARGET_RATE
	var count: int = int(src.size() / step)
	if count < 1:
		count = 1
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in count:
		var f: Vector2 = src[int(i * step)]
		# vc173 LOUDER CHANNEL (Claude 2026-11-03, user: teacher must always work).
		# Old code averaged stereo: (x+y)*0.5. If the Quest mic is one-sided
		# (one channel near silent), averaging HALVED the level, so quiet
		# speech transcribed sometimes and failed sometimes. Now use the
		# louder channel per sample, at full level, so a mono mic is not halved.
		var _v: float = f.x if abs(f.x) >= abs(f.y) else f.y
		pcm.encode_s16(i * 2, int(clamp(_v, -1.0, 1.0) * 32767))
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)
	h.encode_u32(12, 0x20746d66)
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, TARGET_RATE)
	h.encode_u32(28, TARGET_RATE * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)
	h.encode_u32(40, pcm.size())
	return h + pcm
