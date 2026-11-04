# vc180 SKY SYNC MENU (user 2026-11-04).
# Left-hand MENU button (palm up, pinch) opens two buttons in front of you:
# SYNC MOON and SYNC SUN. Pinch one, a ring cursor appears in the centre of
# your view. Turn your head so the ring sits on the REAL Moon or Sun, pinch
# anywhere, and the whole sky turns so the virtual Moon/Sun lands exactly
# under the ring. Every planet and star is placed from that one reference.
# Voice backup: say "sync moon" or "sync sun" (no menu needed).
#
# Why a head-centred ring and not the fingertips: with two eyes open, a
# fingertip in front of the Moon is 2-3 degrees off from where each eye
# sees it. The centre of the headset view has no such error.
#
# What sync corrects: only the compass direction (yaw). A Quest has no
# compass, but its tilt sensor knows up/down exactly, and the Moon/Sun
# height comes from time + location, so height is not touched (alt offset
# stays 0). If the ring is far higher/lower than the Moon should be, the
# sync is refused: you are aiming at the wrong thing, or location is off.
extends Node3D

signal synced(yaw_deg: float, body: String, alt_error_deg: float)
signal message(text: String)
signal teacher_requested  # vc181: AI TEACHER button (Talk to Teacher moved into this menu)

const AstroMathScript = preload("res://scripts/astro_math.gd")
const MENU_DIST: float = 0.9
const CURSOR_DIST: float = 20.0
const MAX_ALT_ERROR_DEG: float = 8.0

var camera: Node3D = null
var lat_deg: float = 28.4152
var lon_deg: float = -81.7879
var blocked: bool = false  # main sets true while travelling / splash

var mode: String = "off"  # off | menu | aim
var target: String = ""   # "Moon" | "Sun"
var _menu_was_down: bool = false
var _menu_root: Node3D = null
var _buttons: Array = []  # [{name, node, mat, label}]
var _title: Label3D = null
var _cursor: Node3D = null
var _cursor_label: Label3D = null

func _ready() -> void:
	_build()
	_set_mode("off")

func is_active() -> bool:
	return mode != "off"

func _unlit(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 10
	return m

func _label(text: String, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0005
	l.width = 700
	l.modulate = Color(1, 1, 1)
	l.outline_size = 4
	l.outline_modulate = Color(0, 0, 0)
	l.no_depth_test = true
	l.render_priority = 11
	l.outline_render_priority = 10
	return l

const ACCENT := Color(0.18, 0.83, 0.91)   # Star Bridge teal (same as the AI face)

var _card_mats: Array = []
var _open_t: float = 1.0
var _panel: MeshInstance3D = null

static func _ui_shader() -> Shader:
	# One shader draws every piece of the menu: rounded glass panels with a
	# soft glowing edge, and the three icons, as signed-distance shapes, so
	# everything is crisp at any distance and costs 1 quad each.
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
uniform vec2 size = vec2(0.3, 0.2);       // metres, for rounded corners in real units
uniform float radius = 0.03;
uniform vec3 accent : source_color = vec3(0.18, 0.83, 0.91);
uniform float hover = 0.0;                // 0..1
uniform float fade = 1.0;
uniform int icon = -1;                    // -1 panel, 0 moon, 1 sun, 2 teacher
uniform float base_alpha = 0.72;
float rbox(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
void fragment(){
	vec2 p = (UV - 0.5) * size;
	float d = rbox(p, size * 0.5, radius);
	float inside = 1.0 - smoothstep(-0.001, 0.001, d);
	float edge = 1.0 - smoothstep(0.0, 0.004 + 0.004 * hover, abs(d + 0.002));
	float glow = exp(-abs(d) * 160.0) * (0.25 + 0.75 * hover);
	vec3 top = vec3(0.07, 0.10, 0.16);
	vec3 bot = vec3(0.02, 0.03, 0.06);
	vec3 col = mix(bot, top, UV.y < 0.0 ? 0.0 : 1.0 - UV.y);
	col += accent * 0.10 * hover;
	float sheen = smoothstep(0.0, 0.5, 1.0 - UV.y) * 0.05;   // glassy highlight on top
	col += vec3(sheen);
	float a = inside * base_alpha;
	vec3 outc = col;
	if (icon >= 0) {
		vec2 q = (UV - vec2(0.5, 0.40)) * size / (size.x * 0.5);   // icon space, ~-1..1
		float ic = 0.0;
		if (icon == 0) {        // crescent Moon
			float c1 = length(q) - 0.42;
			float c2 = length(q - vec2(0.2, 0.12)) - 0.36;
			ic = 1.0 - smoothstep(0.0, 0.02, max(c1, -c2));
		} else if (icon == 1) { // Sun: disc + rays
			float disc = length(q) - 0.24;
			float ang = atan(q.y, q.x);
			float rays = (length(q) - 0.42 - 0.05 * cos(ang * 12.0)) ;
			float ray_mask = step(0.5, 0.5 + 0.5 * cos(ang * 12.0));
			ic = max(1.0 - smoothstep(0.0, 0.02, disc), (1.0 - smoothstep(0.0, 0.02, rays)) * ray_mask * step(0.30, length(q)));
		} else {                // AI teacher: four-point spark + small spark
			vec2 a2 = abs(q);
			float star = a2.x * a2.y * 18.0 + (a2.x + a2.y) - 0.48;
			vec2 q2 = abs(q - vec2(0.36, 0.34));
			float star2 = q2.x * q2.y * 40.0 + (q2.x + q2.y) - 0.16;
			ic = max(1.0 - smoothstep(0.0, 0.03, star), 1.0 - smoothstep(0.0, 0.03, star2));
		}
		vec3 icol = mix(vec3(0.85, 0.92, 0.95), accent, 0.35 + 0.65 * hover);
		outc = mix(outc, icol, ic);
		a = max(a, ic);
	}
	outc = mix(outc, accent * (1.2 + hover), edge);
	a = max(a, edge);
	outc += accent * glow;
	a = max(a, glow * 0.8);
	ALBEDO = outc;
	ALPHA = clamp(a, 0.0, 1.0) * fade;
}
"""
	return sh

func _ui_quad(w: float, h: float, r: float, icon: int, alpha: float, prio: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _ui_shader()
	m.set_shader_parameter("size", Vector2(w, h))
	m.set_shader_parameter("radius", r)
	m.set_shader_parameter("icon", icon)
	m.set_shader_parameter("base_alpha", alpha)
	m.set_shader_parameter("accent", Vector3(ACCENT.r, ACCENT.g, ACCENT.b))
	m.render_priority = prio
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _build() -> void:
	_menu_root = Node3D.new()
	add_child(_menu_root)
	# Backplate: dark glass with a teal glowing rim.
	_panel = _ui_quad(0.92, 0.42, 0.045, -1, 0.78, 8)
	_panel.position = Vector3(0.0, 0.01, -0.01)
	_menu_root.add_child(_panel)
	_title = _label("STAR BRIDGE", 40)
	_title.modulate = Color(0.92, 0.97, 1.0)
	_title.position = Vector3(-0.40, 0.165, 0.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_menu_root.add_child(_title)
	var sub := _label("LOOK  •  PINCH", 26)
	sub.modulate = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9)
	sub.position = Vector3(0.40, 0.165, 0.0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_menu_root.add_child(sub)
	var names: Array = [["SYNC MOON", "Moon", -0.29, 0], ["SYNC SUN", "Sun", 0.0, 1], ["AI TEACHER", "Teacher", 0.29, 2]]
	for n in names:
		var b := Node3D.new()
		b.position = Vector3(n[2], -0.025, 0.0)
		var card := _ui_quad(0.25, 0.27, 0.03, n[3], 0.85, 9)
		b.add_child(card)
		var lab := _label(n[0], 32)
		lab.position = Vector3(0.0, -0.095, 0.002)
		lab.modulate = Color(0.92, 0.97, 1.0)
		b.add_child(lab)
		_menu_root.add_child(b)
		var mat: ShaderMaterial = card.material_override
		_buttons.append({"name": n[1], "node": b, "mat": mat, "label": lab, "text": n[0], "hover": 0.0})
	# Cursor: thin teal ring with four ticks and a centre dot, always in the
	# middle of the view. The hole (~1.4 deg) fits the real Moon/Sun (0.5 deg).
	_cursor = Node3D.new()
	add_child(_cursor)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = CURSOR_DIST * tan(deg_to_rad(0.7))
	tm.outer_radius = tm.inner_radius + 0.035
	tm.rings = 64
	tm.ring_segments = 48  # vc195 fix: ring_segments is the main circle - zip had 6, hexagonal ring again
	ring.mesh = tm
	ring.rotation.x = PI / 2.0
	ring.material_override = _unlit(ACCENT)
	_cursor.add_child(ring)
	for k in range(4):
		var tick := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.16, 0.01)
		tick.mesh = bm
		var ang: float = float(k) * PI * 0.5
		var rr: float = tm.outer_radius + 0.14
		tick.position = Vector3(cos(ang) * rr, sin(ang) * rr, 0.0)
		tick.rotation.z = ang + PI * 0.5
		tick.material_override = _unlit(ACCENT)
		_cursor.add_child(tick)
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.025
	dm.height = 0.05
	dm.radial_segments = 8
	dm.rings = 4
	dot.mesh = dm
	dot.material_override = _unlit(Color(1, 1, 1))
	_cursor.add_child(dot)
	_cursor_label = _label("", 30)
	_cursor_label.modulate = Color(0.92, 0.97, 1.0)
	add_child(_cursor_label)

func _set_mode(m: String) -> void:
	mode = m
	_menu_root.visible = m == "menu"
	_cursor.visible = m == "aim"
	_cursor_label.visible = m == "aim"

func _true_dir(body: String) -> Vector3:
	var j: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	if body == "Moon":
		return AstroMathScript.moon_world_dir(j["tt"], j["ut1"], lat_deg, lon_deg, 0.0, 0.0)
	return AstroMathScript.planet_world_dir("Sun", j["tt"], j["ut1"], lat_deg, lon_deg, 0.0, 0.0)

static func _alt(d: Vector3) -> float:
	return rad_to_deg(asin(clamp(d.y, -1.0, 1.0)))

static func _az(d: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)

func open_menu() -> void:
	if camera == null or blocked:
		return
	# Menu sits in front of you at eye level, fixed in the room (easy to aim).
	var fwd: Vector3 = -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	_menu_root.global_position = camera.global_position + fwd * MENU_DIST
	_menu_root.look_at(camera.global_position, Vector3.UP)
	_menu_root.rotate_object_local(Vector3.UP, PI)  # face the user, not away
	_open_t = 0.0
	for b in _buttons:
		if b["name"] == "Teacher":
			continue
		var up: bool = _alt(_true_dir(b["name"])) > -1.0
		(b["label"] as Label3D).text = b["text"] if up else b["text"] + "\nbelow horizon"
		(b["label"] as Label3D).modulate = Color(0.92, 0.97, 1.0) if up else Color(0.55, 0.6, 0.65)
	_set_mode("menu")

func close() -> void:
	_set_mode("off")

func start_aim(body: String) -> void:
	if blocked:
		return
	if _alt(_true_dir(body)) < -1.0:
		message.emit("The %s is below the horizon right now, so it can't be used. Try SYNC %s." % [body, "SUN" if body == "Moon" else "MOON"])
		_set_mode("off")
		return
	target = body
	_cursor_label.text = "Put the ring on the REAL %s, then pinch" % body
	_set_mode("aim")

func _aim_on_button(pinch_point: Vector3) -> Dictionary:
	var aim: Vector3 = (pinch_point - camera.global_position).normalized()
	var gaze: Vector3 = -camera.global_transform.basis.z
	for b in _buttons:
		var bdir: Vector3 = ((b["node"] as Node3D).global_position - camera.global_position).normalized()
		# Hand OR head on the button (within 8 deg) picks it.
		if bdir.dot(aim) > 0.990 or bdir.dot(gaze) > 0.990:
			return b
	return {}

# Called first thing in main._on_pinch. Returns true if the pinch was used.
func handle_pinch(pinch_point: Vector3) -> bool:
	if mode == "off" or camera == null:
		return false
	if mode == "menu":
		var b: Dictionary = _aim_on_button(pinch_point)
		if b.is_empty():
			close()  # pinch away from the buttons closes the menu
		elif b["name"] == "Teacher":
			close()
			teacher_requested.emit()
		else:
			start_aim(b["name"])
		return true
	# mode == "aim": confirm with the head ring.
	var aim: Vector3 = -camera.global_transform.basis.z
	var truth: Vector3 = _true_dir(target)
	var alt_err: float = _alt(aim) - _alt(truth)
	# vc182 (user 2026-11-04): NO refusal. Wherever the ring is when you
	# pinch, that compass direction becomes the Moon's/Sun's direction.
	# Works indoors with a phone Star Chart held at eye level too.
	var yaw: float = fposmod(_az(aim) - _az(truth) + 540.0, 360.0) - 180.0
	synced.emit(yaw, target, alt_err)
	_set_mode("off")
	return true

func _process(_delta: float) -> void:
	if camera == null:
		return
	# Left MENU button (hand tracking: left palm up + pinch). Edge-triggered.
	var down: bool = false
	var t: XRPositionalTracker = XRServer.get_tracker(&"left_hand") as XRPositionalTracker
	if t != null:
		down = bool(t.get_input(&"menu_button"))
	if down and not _menu_was_down and not blocked:
		if mode == "off":
			open_menu()
		else:
			close()
	_menu_was_down = down
	if blocked and mode != "off":
		close()
	if mode == "menu":
		# Open animation: ease out, scale up from 85% and fade in over 0.25 s.
		_open_t = min(_open_t + _delta / 0.25, 1.0)
		var e: float = 1.0 - pow(1.0 - _open_t, 3.0)
		_menu_root.scale = Vector3.ONE * lerp(0.85, 1.0, e)
		(_panel.material_override as ShaderMaterial).set_shader_parameter("fade", e)
		var gaze: Vector3 = -camera.global_transform.basis.z
		for b in _buttons:
			var bdir: Vector3 = ((b["node"] as Node3D).global_position - camera.global_position).normalized()
			var target: float = 1.0 if bdir.dot(gaze) > 0.990 else 0.0
			b["hover"] = lerp(float(b["hover"]), target, min(_delta * 12.0, 1.0))
			var m: ShaderMaterial = b["mat"]
			m.set_shader_parameter("hover", b["hover"])
			m.set_shader_parameter("fade", e)
			(b["node"] as Node3D).scale = Vector3.ONE * (1.0 + 0.07 * float(b["hover"]))
			(b["label"] as Label3D).modulate.a = e
	elif mode == "aim":
		var fwd: Vector3 = -camera.global_transform.basis.z
		_cursor.global_position = camera.global_position + fwd * CURSOR_DIST
		_cursor.look_at(camera.global_position, Vector3.UP if abs(fwd.y) < 0.98 else Vector3.FORWARD)
		var up: Vector3 = camera.global_transform.basis.y
		_cursor_label.global_position = camera.global_position + fwd * 1.2 - up * 0.22
		_cursor_label.look_at(camera.global_position, up)
		_cursor_label.rotate_object_local(Vector3.UP, PI)
