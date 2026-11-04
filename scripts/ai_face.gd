# vc114: face place(face, 0, 12, 400, 30, 1.0) — 30deg tall, elevation 12deg, azimuth 0, 400 m; passthrough back ON in main (vc114, permanent); motion breathe/drift/hair_drift/dissolve 0 KEPT from vc113, not reverted.
# vc113 FACE TEST ONLY: v3 face.png (1024x1024 grayscale, outlined eyelids/irises/brows/lip edges/nostrils/dark mouth gap), glow 0.6, point_size 1.8, star_chance 0.01, sampling brightness^1.8, point_count 60000, breathe/drift/hair_drift/dissolve 0, face 34deg tall (176x245 at 400m), passthrough OFF in main.gd (test only).
# vc108: FACING FIX ONLY (scope change: asset swap + mouth glow are NEXT builds, not this one).
# Bug: face appeared facing away when it first showed. Root cause found in code review:
# _process returned early while hidden, so placement AND _update_turn only ran while
# visible. Rotation went stale while hidden, then turned at only 2 deg/sec once shown
# (up to 90 s for a 180 deg error). Fix: placement + yaw turn now run EVERY frame,
# even while hidden, still capped at 2 deg/sec, so the face is already facing the
# camera when it appears. No look_at() exists on the face node anywhere (grep-verified);
# _update_turn already aims local +Z at the camera. Fallbacks NOT applied here:
# no scale.x = -1 mirror flip, no negative depth_strength — those are for AFTER the
# headset test, only if the face still looks mirrored / hollow. Test print added:
# global_position + rotation.y once per second (remove for release).
# vc107: Claude's supplied ai_face.gd, integrated with the SMALLEST possible change.
# Original logic preserved exactly except for the patches marked [vc107 PATCH] below:
#  (1) Texture fallback: if face_tex/mouth_tex are null (no face.png/depth.png/mouth.png
#      supplied yet), a procedural placeholder map is generated in code (same blobs as
#      vc105, adapted to Claude's UV orientation) so _build_mesh() never crashes on a
#      null texture. Replace with real art later: res://data/ai_face/face.png +
#      depth.png + mouth.png, 1024x1024, VRAM compression OFF, lossless, no mipmaps,
#      filter linear. Do NOT copy reference images.
#  (2) Placement/scale: Claude's mesh is 1x1 unit and expects an external place() call
#      that does not exist in this project, so _process places it 400 m in front of the
#      camera, 150 m above the horizon, scale (180, 250, 180) — vc105 placement, kept.
#  (3) Voice trigger: hidden by default (vc79 lesson). While the existing VoiceUI
#      plays for >=0.5 s the face shows and set_voice() is fed from the existing
#      AIVoice spectrum bus (jaw 150-900, wide 900-2500, hiss 3000-8000 Hz); after
#      2 s silence it hides and state returns to idle. No new LLM/STT/TTS, no API key.
#  (4) point_count: code default is 30000 (Claude); main.gd sets 20000 before add_child
#      (profiling rule: start 20k, raise only if 72 fps holds).
#  (5) Debug: no debug prints, no debug state shortcut in this build (later phase).
#  Shader path unchanged: res://ai_face.gdshader (file at single-source root).
#  NOT built in vc107: ai_state.gd, ai_voice.gd, ai_brain.gd, proxy server (later phases).
class_name AIFace
extends MeshInstance3D
## Particle face. Mesh is a 1 x 1 unit plane of points, so use base_size = 1.0
## with sky_layout.place(). Keep this node top_level and out of the camera tree.

@export var face_tex: Texture2D        # lossless import, no mipmaps
@export var depth_tex: Texture2D       # optional
@export var mouth_tex: Texture2D       # lossless import, no mipmaps
@export var point_count := 60000  # vc113 TEST: 60000, back to 40000 if fps < 72
@export var seed_value := 1234
@export var turn_speed_deg := 2.0      # yaw only, never changes position
@export var dissolve_min_s := 20.0
@export var dissolve_max_s := 40.0
@export var debug_face := false  # [vc107 PATCH] debug flag, default off; no prints/shortcut in this build

var _mat: ShaderMaterial
var _listen := 0.0
var _think := 0.0
var _speak := 0.0
var _listen_t := 0.0
var _think_t := 0.0
var _speak_t := 0.0

var _dissolving := false
# [vc107 PATCH] voice-trigger / placement state (vc105 behaviour, kept)
var _voice_player: AudioStreamPlayer = null
var _analyzer: AudioEffectSpectrumAnalyzerInstance = null
var _play_timer := 0.0
var _silence_timer := 0.0
var _manual_show := false
var _jaw_s := 0.0
var _wide_s := 0.0
var _hiss_s := 0.0
var _dissolve_clock := 0.0
var _next_dissolve := 25.0
var _since_dissolve := 0.0
var _print_timer := 0.0  # [vc108] test-build print, once per second; remove for release


func _ready() -> void:
	top_level = true
	visible = false  # [vc107 PATCH] hidden by default
	_setup_voice_bus()  # [vc107 PATCH]
	_ensure_face_textures()  # [vc107 PATCH] Phase 0 fallback, never crash on null
	_build_mesh()
	_setup_material()
	_next_dissolve = randf_range(dissolve_min_s, dissolve_max_s)



# [vc107 PATCH] Procedural placeholder maps, vc105 blobs adapted to Claude UV.
# Claude samples img.get_pixel(int(u*w), int(v*h)) and verts y = 0.5 - p.y,
# so vc105 v (0=chin, 1=top) equals 1 - p.y here.
func _gauss107(dx: float, dy: float, sx: float, sy: float) -> float:
	return exp(-(dx * dx / (2.0 * sx * sx) + dy * dy / (2.0 * sy * sy)))

func _face_brightness107(u: float, v105: float) -> float:
	var dx: float = u - 0.5
	var dy: float = v105 - 0.45
	var oval: float = (dx / 0.34) * (dx / 0.34) + (dy / 0.40) * (dy / 0.40)
	if oval > 1.0:
		return 0.03
	var b: float = 0.35
	b += 0.55 * _gauss107(u - 0.5, v105 - 0.72, 0.16, 0.12)
	b += 0.65 * _gauss107(u - 0.38, v105 - 0.58, 0.06, 0.05)
	b += 0.65 * _gauss107(u - 0.62, v105 - 0.58, 0.06, 0.05)
	b += 0.35 * _gauss107(u - 0.36, v105 - 0.42, 0.10, 0.08)
	b += 0.35 * _gauss107(u - 0.64, v105 - 0.42, 0.10, 0.08)
	b += 0.45 * _gauss107(u - 0.5, v105 - 0.48, 0.05, 0.12)
	b += 0.25 * _gauss107(u - 0.5, v105 - 0.32, 0.12, 0.06)
	return clamp(b, 0.0, 1.0)

func _mouth_mask107(u: float, v105: float) -> float:
	var dx: float = (u - 0.5) / 0.14
	var dy: float = (v105 - 0.32) / 0.06
	var d: float = dx * dx + dy * dy
	if d >= 1.0:
		return 0.0
	return clamp(1.0 - d, 0.0, 1.0)

func _ensure_face_textures() -> void:
	# vc111 STEP A: try real art files first (Lossless, no mipmaps, no VRAM
	# compression is an import setting on the .import files, not code).
	# Files were NOT present in this build, so this falls through to the
	# procedural placeholder below. Do not invent/download a face photo.
	if face_tex == null and ResourceLoader.exists("res://data/ai_face/face.png"):
		face_tex = load("res://data/ai_face/face.png")
	if mouth_tex == null and ResourceLoader.exists("res://data/ai_face/mouth.png"):
		mouth_tex = load("res://data/ai_face/mouth.png")
	if depth_tex == null and ResourceLoader.exists("res://data/ai_face/depth.png"):
		depth_tex = load("res://data/ai_face/depth.png")
	if face_tex != null and mouth_tex != null:
		return
	var face_img: Image = Image.create(512, 512, false, Image.FORMAT_L8)
	var mouth_img: Image = Image.create(512, 512, false, Image.FORMAT_L8)
	for y: int in range(512):
		for x: int in range(512):
			var u: float = float(x) / 511.0
			var v105: float = 1.0 - float(y) / 511.0
			face_img.set_pixel(x, y, Color(_face_brightness107(u, v105), 0.0, 0.0, 1.0))
			mouth_img.set_pixel(x, y, Color(_mouth_mask107(u, v105), 0.0, 0.0, 1.0))
	if face_tex == null:
		face_tex = ImageTexture.create_from_image(face_img)
	if mouth_tex == null:
		mouth_tex = ImageTexture.create_from_image(mouth_img)

func _setup_voice_bus() -> void:
	var bus_idx: int = AudioServer.get_bus_index("AIVoice")
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_idx, "AIVoice")
	var fx_idx: int = -1
	for i: int in range(AudioServer.get_bus_effect_count(bus_idx)):
		if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectSpectrumAnalyzer:
			fx_idx = i
			break
	if fx_idx < 0:
		var fx: AudioEffectSpectrumAnalyzer = AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(bus_idx, fx)
		fx_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
	_analyzer = AudioServer.get_bus_effect_instance(bus_idx, fx_idx) as AudioEffectSpectrumAnalyzerInstance
	if get_parent() != null:
		_voice_player = get_parent().get_node_or_null("VoiceUI") as AudioStreamPlayer
	if _voice_player != null:
		_voice_player.bus = "AIVoice"

func set_face_tint(tint: Color) -> void:
	# vc110 place() helper: per-world tint only, no logic change.
	# _mat is ShaderMaterial with a "color" uniform in ai_face.gdshader.
	if _mat != null:
		_mat.set_shader_parameter("color", Vector3(tint.r, tint.g, tint.b))

func show_face() -> void:
	_manual_show = true
	visible = true

func hide_face() -> void:
	_manual_show = false
	visible = false

func _band107(lo: float, hi: float) -> float:
	if _analyzer == null:
		return 0.0
	var mag: Vector2 = _analyzer.get_magnitude_for_frequency_range(lo, hi, 0)
	var m: float = (mag.x + mag.y) * 0.5
	var db: float = linear_to_db(m) if m > 0.0 else -60.0
	return clamp((db + 60.0) / 60.0, 0.0, 1.0)

func _build_mesh() -> void:
	if face_tex == null:
		return
	var img := face_tex.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# vc113 TEST: jittered-grid (stratified) sampling + rejection by brightness^1.8
	var pts: Array[Vector2] = []
	var g := 220
	var passes := 0
	while pts.size() < point_count and passes < 60:
		passes += 1
		for cy in g:
			for cx in g:
				var u := (cx + rng.randf()) / g
				var v := (cy + rng.randf()) / g
				var b := img.get_pixel(mini(int(u * w), w - 1), mini(int(v * h), h - 1)).r
				if rng.randf() < pow(b, 1.8):
					pts.append(Vector2(u, v))

	# shuffle then truncate so there is no top-of-image bias
	var idx := range(pts.size())
	idx.shuffle()
	var n := mini(point_count, pts.size())

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	verts.resize(n)
	uvs.resize(n)
	uv2s.resize(n)
	for i in n:
		var p: Vector2 = pts[idx[i]]
		verts[i] = Vector3(p.x - 0.5, 0.5 - p.y, 0.0)
		uvs[i] = p
		uv2s[i] = Vector2(rng.randf(), rng.randf())

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	m.custom_aabb = AABB(Vector3(-0.9, -0.9, -0.6), Vector3(1.8, 1.8, 1.2))
	mesh = m


func _setup_material() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ai_face.gdshader")
	_mat.set_shader_parameter("face_tex", face_tex)
	_mat.set_shader_parameter("mouth_mask", mouth_tex)
	if depth_tex:
		_mat.set_shader_parameter("depth_tex", depth_tex)
		_mat.set_shader_parameter("use_depth_tex", true)
	material_override = _mat
	_mat.render_priority = 10  # vc114 SAFETY NET: face draws on top if anything overlaps
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Call every frame while the AI speaks (values 0..1).
func set_voice(jaw: float, wide: float, hiss: float, round_amt: float = 0.0) -> void:
	_mat.set_shader_parameter("jaw", jaw)
	_mat.set_shader_parameter("wide", wide)
	_mat.set_shader_parameter("hiss", hiss)
	_mat.set_shader_parameter("round_amt", round_amt)


## "idle", "listening", "thinking" or "speaking"
func set_ai_state(s: String) -> void:
	_listen_t = 1.0 if s == "listening" else 0.0
	_think_t = 1.0 if s == "thinking" else 0.0
	_speak_t = 1.0 if s == "speaking" else 0.0
	if s == "speaking":
		_dissolving = false


func _process(delta: float) -> void:
	# [vc107 PATCH] Voice trigger, spectrum -> set_voice, placement/scale.
	if _voice_player == null and get_parent() != null:
		_voice_player = get_parent().get_node_or_null("VoiceUI") as AudioStreamPlayer
		if _voice_player != null:
			_voice_player.bus = "AIVoice"
	if not _manual_show:
		if _voice_player != null and _voice_player.playing:
			_play_timer += delta
			_silence_timer = 0.0
			if _play_timer >= 0.5:
				visible = true
				set_ai_state("speaking")
		else:
			_play_timer = 0.0
			_silence_timer += delta
			if _silence_timer >= 2.0:
				visible = false
				set_ai_state("idle")
	# [vc108] Placement + yaw turn run EVERY frame, even while hidden, so the
	# face is already facing the camera when it appears. No look_at() anywhere:
	# _update_turn aims local +Z at the camera, capped at turn_speed_deg/sec.
	# Position is set here, never changed by _update_turn (yaw only).
	var cam108: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam108 != null:
		var fwd108: Vector3 = -cam108.global_transform.basis.z
		var flat108: Vector3 = Vector3(fwd108.x, 0.0, fwd108.z)
		if flat108.length() < 0.1:
			flat108 = Vector3(0.0, 0.0, -1.0)
		flat108 = flat108.normalized()
		global_position = cam108.global_position + flat108 * 400.0 + Vector3(0.0, 85.0, 0.0)  # vc114: elevation 12deg, 400*tan(12deg)=85.0 m up, azimuth 0
		scale = Vector3(154.0, 214.3, 154.0)  # vc114: 30deg tall at 400m (2*400*tan(15deg)=214.3, width 214.3*143/199=154.0)
		_update_turn(delta)
		# [vc108] Test print, once per second. At origin, standing still, this
		# should show the face 400 m in front of the camera and rotation.y
		# pointing its +Z back at the camera. Remove for release.
		_print_timer += delta
		if debug_face and _print_timer >= 1.0:
			_print_timer = 0.0
			print("AiFace vc111 pos=", global_position, " rot_y_deg=", rad_to_deg(rotation.y), " cam=", cam108.global_position)
	if not visible:
		return
	if _voice_player != null and _voice_player.playing and _analyzer != null:
		var jt: float = _band107(150.0, 900.0)
		var wt: float = _band107(900.0, 2500.0)
		var ht: float = _band107(3000.0, 8000.0)
		var atk: float = 1.0 - exp(-delta * 40.0)
		var rel: float = 1.0 - exp(-delta * 12.0)
		_jaw_s = lerp(_jaw_s, jt, atk if jt > _jaw_s else rel)
		_wide_s = lerp(_wide_s, wt, atk if wt > _wide_s else rel)
		_hiss_s = lerp(_hiss_s, ht, atk if ht > _hiss_s else rel)
		set_voice(_jaw_s, _wide_s, _hiss_s, 0.0)
	var k := 1.0 - exp(-delta * 4.0)
	_listen = lerpf(_listen, _listen_t, k)
	_think = lerpf(_think, _think_t, k)
	_speak = lerpf(_speak, _speak_t, k)
	_mat.set_shader_parameter("listening", _listen)
	_mat.set_shader_parameter("thinking", _think)
	_mat.set_shader_parameter("speak_boost", _speak)

	_update_dissolve(delta)
	# vc113 TEST ONLY: motion off — dissolve forced to 0 after _update_dissolve,
	# so nothing moves while the user checks features. Restore after verdict.
	if _mat != null:
		_mat.set_shader_parameter("dissolve", 0.0)
	# NOTE vc108: _update_turn is NOT called here anymore — it already ran above
	# (every frame, hidden or not). Calling it twice would double the turn rate.


func _update_dissolve(delta: float) -> void:
	var d := 0.0
	if _dissolving:
		_dissolve_clock += delta
		if _dissolve_clock < 1.5:
			d = smoothstep(0.0, 1.5, _dissolve_clock)
		elif _dissolve_clock < 3.5:
			d = 1.0 - smoothstep(1.5, 3.5, _dissolve_clock)
		else:
			_dissolving = false
			_since_dissolve = 0.0
			_next_dissolve = randf_range(dissolve_min_s, dissolve_max_s)
	else:
		_since_dissolve += delta
		if _since_dissolve >= _next_dissolve and _speak_t < 0.5:
			_dissolving = true
			_dissolve_clock = 0.0
	_mat.set_shader_parameter("dissolve", d)


func _update_turn(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var v := cam.global_position - global_position
	var target := atan2(v.x, v.z)
	var step := deg_to_rad(turn_speed_deg) * delta
	rotation.y += clampf(angle_difference(rotation.y, target), -step, step)
