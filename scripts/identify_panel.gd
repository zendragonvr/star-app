# Fresh identify panel, written 2026-10-26.
# Small, upper-right, readable in 2 seconds, no scrolling, no menus.
# The panel follows the camera: it sits in front of the user in
# passthrough, never as a world menu the user has to walk to.
# It shows the object name plus the scientific numbers an
# astronomer can check (RA, Dec, alt, az, magnitude when known).
# If the pinch was not sure, it says so plainly instead of
# guessing a wrong name — a wrong name is worse than no name.
extends Node3D

signal typing_finished

var _label: Label3D
var _name_label: Label3D
var _desc_label: Label3D
var _type_text: String = ""
var _type_chars: int = 0
var _type_acc: float = 0.0
var _typing: bool = false
var _tick_player: AudioStreamPlayer = null
var _tick_half_done: bool = false
var _camera: XRCamera3D = null
var _hide_after_unix: float = -1.0
# vc81 PANEL LOCKED ABOVE PLANET: when anchored, panel follows the planet/orb node, not the camera.
# Position = anchor world pos + WORLD UP * offset. Billboard labels still face camera so they stay readable, but their POSITION never moves with your head.
# When anchor is null, falls back to old camera-relative position. User 2026-10-30: words locked to view mess with the visual.
var _anchor: Node3D = null
var _face_panel_mode: bool = false  # vc114: panel opposite face from planet, -45 deg, below eye level
func set_face_panel_mode(v: bool) -> void:
	_face_panel_mode = v
var _anchor_offset_x: float = 1.0  # vc78: this is now UP offset above the planet, not right offset
var _panel_scale: float = 1.0  # vc161: panel text scale, 1.0 = old size. Brought planets are 2x bigger, so their words must be 2x bigger to match, Sun 3.33x (see main).
var _fade_start_unix: float = -1.0
var _fading: bool = false
var _fade_t: float = 0.0
func fade_out_after_voice() -> void:
	# vc78 FADE: 2 sec to finish reading after voice ends, then fade 1 sec, then clear. Next pinch cancels fade (see show_name_desc).
	_fade_start_unix = Time.get_unix_time_from_system() + 2.0

func fade_out_now() -> void:
	# vc87 FADE ON REVERSE (user 2026-10-30 05:18 EDT): when a planet goes back to the sky, its words must fade away with it, in the same 1 sec fade, not stay stuck in front of you. _process starts fading when now >= _fade_start_unix, so now = immediate.
	_fade_start_unix = Time.get_unix_time_from_system()
func stop_typing() -> void:
	# vc94: reverse stops typing too, so typing_finished never fires a desc voice after the planet went back.
	_typing = false
	_type_text = ""
	if _tick_player != null:
		_tick_player.stop()

func set_anchor(node: Node3D, offset_x: float) -> void:
	_anchor = node
	_anchor_offset_x = offset_x

# vc118 SIDEWAYS panel: widen the description label so a short panel wraps
# into a few wide lines instead of a tall narrow column. Call with 300 to
# restore the normal planet width.
func set_panel_scale(s: float) -> void:
	_panel_scale = s
	if _label != null:
		_label.pixel_size = 0.0012 * s
	if _name_label != null:
		_name_label.pixel_size = 0.0020 * s
	if _desc_label != null:
		_desc_label.pixel_size = 0.0022 * s

func set_desc_width(px: float) -> void:
	if _desc_label != null:
		_desc_label.width = px
func clear_anchor() -> void:
	_anchor = null

func _ready() -> void:
	_label = Label3D.new()
	# v4 panel size fix — v3 verdict, 2026-10-26 video: the panel
	# filled the whole view and text was cut off. Root cause:
	# Label3D default font_size is 64, times pixel_size 0.012
	# = 0.77 m tall PER LINE at 1.2 m distance. That is a
	# billboard, not a panel. v4: 32 * 0.0025 = 0.08 m per line,
	# readable in 2 seconds, upper-right, fits in view.
	# Width + word wrap so long teacher answers wrap instead
	# of running off the right edge.
	# v19 panel size fix — v18 video: text ran off the right
	# edge, and lines looked 2-3× too large in recording.
	# Smaller + more centred: font 24 × 0.002 = 0.048 m/line,
	# width 260 px × 0.002 = 0.52 m wide, centred at x=0.15
	# instead of 0.45, so the right edge stays in view.
	_label.font_size = 16
	# vc58: panel was filling the view in video — shrink to ~1/3 size.
	_label.pixel_size = 0.0012
	_label.width = 200
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 1.0, 1.0)
	_label.outline_size = 2
	_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_label.text = ""
	add_child(_label)
	# vc61 METROID CAPTIONS: name in a cool computer font, description
	# types out like a computer, character by character, with a cursor.
	# Monospace bold for the name, monospace for the description.
	var _mono_bold: Font = load("res://data/fonts/DejaVuSansMono-Bold.ttf")
	var _mono: Font = load("res://data/fonts/DejaVuSansMono.ttf")
	_name_label = Label3D.new()
	_name_label.font_size = 32
	_name_label.pixel_size = 0.0020  # vc84: slightly bigger name
	_name_label.width = 400
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.modulate = Color(0.6, 1.0, 1.0)
	_name_label.outline_size = 2
	_name_label.outline_modulate = Color(0.0, 0.0, 0.0)
	if _mono_bold != null:
		_name_label.font = _mono_bold
	_name_label.text = ""
	add_child(_name_label)
	_desc_label = Label3D.new()
	_desc_label.font_size = 16
	_desc_label.pixel_size = 0.0022  # vc84: was 0.0012, text was too small/far to read at 1.8m
	_desc_label.width = 300
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_desc_label.modulate = Color(1.0, 1.0, 1.0)
	_desc_label.outline_size = 2
	_desc_label.outline_modulate = Color(0.0, 0.0, 0.0)
	if _mono != null:
		_desc_label.font = _mono
	_desc_label.text = ""
	add_child(_desc_label)
	# vc132 TYPING SOUNDS REMOVED (user 2026-11-02): captions still type
	# visually, but no tick sound. _tick_player stays null, playback below is gone.

func set_camera(camera: XRCamera3D) -> void:
	_camera = camera

func _process(_delta: float) -> void:
	if _camera != null:
		var cam_basis: Basis = _camera.global_transform.basis
		if _face_panel_mode and _anchor != null and is_instance_valid(_anchor):
			# vc114: panel on the OPPOSITE side of the face from the planet:
			# face at azimuth 0, planet at +45 right, panel at -45 left,
			# 2.5 m out, 0.35 m BELOW eye level, so it cannot cover the face.
			var _flat114: Vector3 = Vector3(cam_basis.z.x, 0.0, cam_basis.z.z)
			if _flat114.length() < 0.1:
				_flat114 = Vector3(0.0, 0.0, 1.0)
			_flat114 = _flat114.normalized()
			var _left114: Vector3 = Basis(Vector3.UP, deg_to_rad(45.0)) * -_flat114
			_left114.y = 0.0
			_left114 = _left114.normalized()
			var _ap: Vector3 = _camera.global_position + _left114 * 2.5 + Vector3(0.0, -0.35, 0.0)
			global_position = _ap
			if _name_label != null:
				_name_label.global_position = _ap + Vector3.UP * 0.15 * _panel_scale
			if _desc_label != null:
				_desc_label.global_position = _ap - Vector3.UP * 0.15 * _panel_scale
		elif _anchor != null and is_instance_valid(_anchor):
			# vc85 LEFT OF PLANET (user 2026-10-30 05:13 EDT: "just put to the left of the planet"): words sit to the LEFT of the planet in your view, at planet centre height, not above it. Left = camera left, so they stay left in view wherever you stand. Vertical offsets use world up only, so they do not swing when you tilt your head.
			var _ap: Vector3 = _anchor.global_position + cam_basis.x * -_anchor_offset_x  # vc85 LEFT IN VIEW, vc97: offset itself is now consistent, see main set_anchor
			global_position = _ap
			if _name_label != null:
				_name_label.global_position = _ap + Vector3.UP * 0.15 * _panel_scale
			if _desc_label != null:
				_desc_label.global_position = _ap - Vector3.UP * 0.15 * _panel_scale
		else:
			global_position = _camera.global_position + cam_basis * Vector3(0.15, 0.28, -1.2)
			if _name_label != null:
				_name_label.global_position = _camera.global_position + cam_basis * Vector3(0.15, 0.38, -1.2)
			if _desc_label != null:
				_desc_label.global_position = _camera.global_position + cam_basis * Vector3(0.15, 0.12, -1.2)
	if _fade_start_unix > 0.0 and Time.get_unix_time_from_system() >= _fade_start_unix and not _fading:
		_fading = true
		_fade_t = 0.0
	if _fading:
		_fade_t += _delta
		var _a: float = clamp(1.0 - _fade_t / 1.0, 0.0, 1.0)
		_label.modulate.a = _a
		if _name_label != null:
			_name_label.modulate.a = _a
		if _desc_label != null:
			_desc_label.modulate.a = _a
		if _a <= 0.0:
			_label.text = ""
			if _name_label != null:
				_name_label.text = ""
			if _desc_label != null:
				_desc_label.text = ""
			clear_anchor()
			_label.modulate.a = 1.0
			if _name_label != null:
				_name_label.modulate.a = 1.0
			if _desc_label != null:
				_desc_label.modulate.a = 1.0
			_fading = false
			_fade_start_unix = -1.0
	if _typing:
		_type_acc += _delta
		while _type_acc >= 0.0167 and _type_chars < _type_text.length():
			_type_acc -= 0.0167
			_type_chars += 1
		# vc132: no typing sound at all, captions only.
		if _desc_label != null:
			if _type_chars < _type_text.length():
				_desc_label.text = _type_text.substr(0, _type_chars) + "▮"
			else:
				_desc_label.text = _type_text
				_typing = false
				# vc67: typing finishes FIRST, then AI reads. Emit so main can start desc voice after typing, not during it.
				typing_finished.emit()
	if _hide_after_unix > 0.0 and Time.get_unix_time_from_system() > _hide_after_unix:
		_label.text = ""
		_hide_after_unix = -1.0

func show_object(name: String, detail: String) -> void:
	set_panel_scale(1.0)  # vc161: non-planet panels stay old size
	_label.text = name + "\n" + detail
	# vc57 CLEAN: name shows 5s, then fades — view must stay clear, no persistent words.
	_hide_after_unix = Time.get_unix_time_from_system() + 3.0

func show_persistent(name: String, detail: String) -> void:
	set_panel_scale(1.0)  # vc161: non-planet panels stay old size
	# vc134 LISTENING: show_object hides after 3s, so a Listening panel
	# vanished while the mic was still recording, looking dead.
	# Listening prompts use this instead and stay until stop/send.
	_label.text = name + "\n" + detail
	_hide_after_unix = -1.0

func show_name_desc(name: String, detail: String) -> void:
	_fading = false
	_fade_start_unix = -1.0
	_label.modulate.a = 1.0
	if _name_label != null:
		_name_label.modulate.a = 1.0
	if _desc_label != null:
		_desc_label.modulate.a = 1.0
	# vc61: name in cool font (uppercase, monospace bold, cyan),
	# description types out like a computer, 60 chars/sec in vc67 (was 20), with a cursor.
	# Typing sound now lasts ~7-8s for a full description, not ~22s.
	# Captions stay until the next pinch — never cut off mid-read.
	_label.text = ""
	_hide_after_unix = -1.0
	_typing = true
	_type_text = detail
	_type_chars = 0
	_type_acc = 0.0
	if _name_label != null:
		_name_label.text = name.to_upper()
	if _desc_label != null:
		_desc_label.text = "▮"
	if _tick_player != null:
		_tick_player.stop()
	_tick_half_done = false

func show_not_sure() -> void:
	# vc170: "Not sure - try a brighter object" REMOVED (user + Claude 2026-11-03).
	# This function is kept only so old callers do not break; it now shows
	# nothing at all. No caller in main.gd uses it anymore.
	pass

func show_calibrated() -> void:
	_label.text = "Sky locked — saved, one time only"
	_hide_after_unix = -1.0

func show_calibrated_from(name: String) -> void:
	# v15: persistent lock confirmation. This is the confirmation
	# the user asked for 2026-10-27 — "need a way to confirm
	# moon locked". It stays on screen until the next identify,
	# and the diagnostic never overwrites it (diagnostic only
	# overwrites panels starting with "Star App" or empty).
	_label.text = "Sky locked from " + name + " — saved"
	_hide_after_unix = -1.0

func show_teacher_asking() -> void:
	# v23 interim state: shown when a teacher call starts, so a
	# slow or retried call never looks instant-offline. Replaced
	# by show_teacher when the answer (or final offline) lands.
	var line: String = "Teacher: Asking teacher..."
	if _label.text.contains(line):
		return
	if _label.text != "":
		_label.text += "\n\n" + line
	else:
		_label.text = line
	_hide_after_unix = -1.0

func show_teacher(answer: String, source_label: String) -> void:
	# Panel says "live" (= API call just used a fraction of a
	# cent) or "saved" (= cached answer, no credits). Never hide
	# which one it was.
	var clean: String = answer.strip_edges()
	if clean.length() > 300:
		clean = clean.substr(0, 300) + "…"
	var done: String = "Teacher (" + source_label + "): " + clean
	var asking: String = "Teacher: Asking teacher..."
	if _label.text.contains(asking):
		_label.text = _label.text.replace(asking, done)
	elif _label.text != "":
		_label.text += "\n\n" + done
	else:
		_label.text = done
	_hide_after_unix = -1.0

func hide_panel() -> void:
	# vc87: hide must clear NAME and DESC too, and stop typing, or they stay stuck in front of the camera via the unanchored fallback in _process.
	clear_anchor()
	_label.text = ""
	if _name_label != null:
		_name_label.text = ""
	if _desc_label != null:
		_desc_label.text = ""
	_typing = false
	_type_text = ""
	_type_chars = 0
	if _tick_player != null:
		_tick_player.stop()
	_hide_after_unix = -1.0

func current_text() -> String:
	return _label.text
