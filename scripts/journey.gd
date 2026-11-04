# Launch Watch: real-trip replays. First trip: Artemis II.
# ADDITIVE ONLY — this file never edits star chart, sky lock,
# pinch, teacher, or passthrough behavior. Main calls press_at()
# first and acts only on non-""; everything else falls through
# byte-identical. Lock + Moon direction are READ here, never set.
# Truth rules, locked: direction true (sky lock), room distance
# shrunk to fit, panel shows real-trip km/days with simplified leg
# fractions and says plainly it is a scaled model, NOT live
# telemetry. No per-second speeds or distances are quoted (missing
# data is omitted, never invented). No lines anywhere. No landing
# ever claimed: Artemis II flew around the Moon and came home.
extends Node3D

const TRIP: Dictionary = {
	"name": "Artemis II",
	"kind": "REPLAY",
	"launch": "Apr 1, 2026",
	"splash": "Apr 10, 2026",
	"days": 9.0,
	"mission_minutes": 3.0,
	"time_scale": 4320.0,
	"one_way_km": 384400.0,
	"avg_kmh": 3600.0,
	"crew": ["Reid Wiseman", "Victor Glover", "Christina Koch", "Jeremy Hansen"],
	"note": "Lunar flyby — no landing. First crewed lunar flyby since Apollo 17 (1972).",
	"model": "SLS + Orion model 1:196 (98 m stack), primitives, own build",
	"footage": "res://data/video/artemis2_launch.ogv",
}
const SHIP_BASE_M: float = 0.5
const SHIP_SCALE_MIN: float = 0.5
const SHIP_SCALE_MAX: float = 16.0
const MOON_MARK_M: float = 9.0
const FLYBY_R_M: float = 1.4

var _main: Node = null
var _camera: XRCamera3D = null
var _phase: String = "off"
var _t: float = 0.0
var _playing: bool = false
var _pad_pos: Vector3 = Vector3.ZERO
var _scale: float = 1.0
var _held: Dictionary = {}
var _scale_anchor_d: float = -1.0
var _scale_anchor_s: float = 1.0
var _panel_tick: float = 0.0

var _ship: Node3D = null
var _moonmark: MeshInstance3D = null
var _moonlabel: Label3D = null
var _panel: Label3D = null
var _patch: MeshInstance3D = null
var _patchlabel: Label3D = null
var _site: MeshInstance3D = null
var _screen: MeshInstance3D = null
var _screenlabel: Label3D = null
var _viewport: SubViewport = null
var _player: VideoStreamPlayer = null
var _has_footage: bool = false

func setup(main_ref: Node, camera: XRCamera3D) -> void:
	_main = main_ref
	_camera = camera
	var hands: Node = _main.get_node_or_null("HandTracking")
	if hands != null:
		hands.pinch_drag_detected.connect(_on_hand_drag)
		hands.pinch_released.connect(_on_hand_release)

func _ready() -> void:
	_main = get_parent()
	_ship = _build_ship()
	_ship.visible = false
	add_child(_ship)
	_moonmark = MeshInstance3D.new()
	var msphere: SphereMesh = SphereMesh.new()
	msphere.radius = 0.5
	msphere.height = 1.0
	_moonmark.mesh = msphere
	var mmat: StandardMaterial3D = StandardMaterial3D.new()
	if ResourceLoader.exists("res://data/textures/2k_moon.jpg"):
		mmat.albedo_texture = load("res://data/textures/2k_moon.jpg")
		mmat.albedo_color = Color(1.0, 1.0, 1.0)
	else:
		mmat.albedo_color = Color(0.9, 0.9, 0.95)
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_moonmark.material_override = mmat
	_moonmark.visible = false
	_moonmark.name = "JourneyMoon"
	add_child(_moonmark)
	_moonlabel = _label("Moon — true direction", Color(0.9, 0.9, 0.95))
	_moonlabel.visible = false
	add_child(_moonlabel)
	_panel = _label("", Color(1.0, 1.0, 1.0))
	_panel.width = 300
	_panel.visible = false
	add_child(_panel)
	_patch = MeshInstance3D.new()
	var psphere: SphereMesh = SphereMesh.new()
	psphere.radius = 0.12
	psphere.height = 0.24
	_patch.mesh = psphere
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = Color(1.0, 0.80, 0.30, 0.90)
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.72, 0.20)
	pmat.emission_energy_multiplier = 1.4
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patch.material_override = pmat
	_patch.visible = false
	_patch.name = "JourneyPatch"
	add_child(_patch)
	_patchlabel = _label("ARTEMIS II REPLAY", Color(1.0, 0.88, 0.55))
	_patchlabel.visible = false
	add_child(_patchlabel)
	_site = MeshInstance3D.new()
	var sring: TorusMesh = TorusMesh.new()
	sring.inner_radius = 0.13
	sring.outer_radius = 0.16
	_site.mesh = sring
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.85, 0.35)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_site.material_override = smat
	_site.visible = false
	_site.name = "JourneySite"
	add_child(_site)
	_build_screen()

func _label(text: String, col: Color) -> Label3D:
	var lab: Label3D = Label3D.new()
	lab.text = text
	lab.font_size = 24
	lab.pixel_size = 0.002
	lab.width = 260
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = col
	lab.outline_size = 2
	lab.outline_modulate = Color(0.0, 0.0, 0.0)
	return lab

func _build_ship() -> Node3D:
	# SLS + Orion from public proportions (98 m stack -> 0.5 m
	# model, 1:196): orange core, twin white boosters, white
	# capsule cone, escape tower. Primitives, own build, labeled
	# model on the panel — never presented as real footage.
	var ship: Node3D = Node3D.new()
	ship.name = "JourneyShip"
	var core: MeshInstance3D = MeshInstance3D.new()
	var corecyl: CylinderMesh = CylinderMesh.new()
	corecyl.top_radius = 0.021
	corecyl.bottom_radius = 0.021
	corecyl.height = 0.30
	core.mesh = corecyl
	var coremat: StandardMaterial3D = StandardMaterial3D.new()
	coremat.albedo_color = Color(0.85, 0.45, 0.15)
	core.material_override = coremat
	core.position = Vector3(0.0, 0.05, 0.0)
	ship.add_child(core)
	for side: float in [-0.035, 0.035]:
		var srb: MeshInstance3D = MeshInstance3D.new()
		var srbcyl: CylinderMesh = CylinderMesh.new()
		srbcyl.top_radius = 0.012
		srbcyl.bottom_radius = 0.012
		srbcyl.height = 0.32
		srb.mesh = srbcyl
		var srbmat: StandardMaterial3D = StandardMaterial3D.new()
		srbmat.albedo_color = Color(0.92, 0.92, 0.94)
		srb.material_override = srbmat
		srb.position = Vector3(side, 0.04, 0.0)
		ship.add_child(srb)
	var cap: MeshInstance3D = MeshInstance3D.new()
	var capcone: CylinderMesh = CylinderMesh.new()
	capcone.top_radius = 0.004
	capcone.bottom_radius = 0.020
	capcone.height = 0.06
	cap.mesh = capcone
	var capmat: StandardMaterial3D = StandardMaterial3D.new()
	capmat.albedo_color = Color(0.90, 0.90, 0.92)
	cap.material_override = capmat
	cap.position = Vector3(0.0, 0.23, 0.0)
	ship.add_child(cap)
	var tower: MeshInstance3D = MeshInstance3D.new()
	var towercyl: CylinderMesh = CylinderMesh.new()
	towercyl.top_radius = 0.003
	towercyl.bottom_radius = 0.003
	towercyl.height = 0.08
	tower.mesh = towercyl
	var towmat: StandardMaterial3D = StandardMaterial3D.new()
	towmat.albedo_color = Color(0.75, 0.75, 0.78)
	tower.material_override = towmat
	tower.position = Vector3(0.0, 0.30, 0.0)
	ship.add_child(tower)
	return ship

func _build_screen() -> void:
	# Flat screen beside the model for the REAL launch footage.
	# Godot plays OGV: without data/video/artemis2_launch.ogv in
	# the build the screen says so plainly. The video is always
	# labeled flat footage, never 3D.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(512, 288)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.size = Vector2(512, 288)
	_viewport.add_child(_player)
	_has_footage = ResourceLoader.exists(TRIP["footage"])
	if _has_footage:
		_player.stream = load(TRIP["footage"])
	_screen = MeshInstance3D.new()
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(1.3, 0.73)
	_screen.mesh = quad
	var qmat: StandardMaterial3D = StandardMaterial3D.new()
	if _has_footage:
		qmat.albedo_texture = _viewport.get_texture()
		qmat.albedo_color = Color(1.0, 1.0, 1.0)
	else:
		qmat.albedo_color = Color(0.05, 0.05, 0.08)
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen.material_override = qmat
	_screen.visible = false
	_screen.name = "JourneyScreen"
	add_child(_screen)
	_screenlabel = _label("", Color(0.85, 0.90, 1.0))
	_screenlabel.visible = false
	add_child(_screenlabel)

func _locked() -> bool:
	return _main != null and bool(_main.get("calibration_done"))

func _moon_room_pos() -> Dictionary:
	# The Moon the star chart already brought to the room.
	if _main == null:
		return {"ok": false, "pos": Vector3.ZERO}
	var planets: Node = _main.get_node_or_null("PlanetsCore")
	if planets == null or planets.focused_body() != "Moon" or planets.telescope_body() != "":
		return {"ok": false, "pos": Vector3.ZERO}
	var node: Node = planets.get_node_or_null("Moon")
	if node == null:
		return {"ok": false, "pos": Vector3.ZERO}
	return {"ok": true, "pos": (node as Node3D).global_position}

func _moon_sky_dir() -> Vector3:
	# Real Moon direction from the (locked) sky. Never invented.
	if _main == null:
		return Vector3(0, 0, -1)
	var planets: Node = _main.get_node_or_null("PlanetsCore")
	if planets == null or not planets.body_directions().has("Moon"):
		return Vector3(0, 0, -1)
	return (planets.body_directions()["Moon"] as Vector3).normalized()

func press_at(point: Vector3) -> String:
	# Journey's ONLY pinch entry. Strictly gated: "" everywhere
	# except on its own objects, so sky pinches fall through to
	# the star chart untouched.
	if _phase == "off":
		var moon: Dictionary = _moon_room_pos()
		if not moon["ok"] or not _patch.visible:
			return ""
		if point.distance_to(_patch.global_position) < 0.35:
			if not _locked():
				_panel.text = "ARTEMIS II — REPLAY\nNo sky lock — pinch the real Moon first.\nNever faking a lock."
				_panel.visible = true
				return "nolock"
			_phase = "brief"
			_show_brief()
			return "armed"
		return ""
	if _phase == "brief":
		if _patch.visible and point.distance_to(_patch.global_position) < 0.35:
			_phase = "off"
			_panel.visible = false
			return "disarmed"
		_place(point)
		return "placed"
	if _phase == "placed":
		if _ship.visible and point.distance_to(_ship.global_position) < 0.6 * _scale + 0.25:
			if _t >= 1.0:
				_t = 0.0
				_playing = true
			else:
				_playing = not _playing
			_update_panel()
			return "ship"
		if _screen.visible and point.distance_to(_screen.global_position) < 0.8:
			_toggle_video()
			return "screen"
		if _site.visible and point.distance_to(_site.global_position) < 0.3:
			_clear_all()
			return "cleared"
	return ""

func _place(point: Vector3) -> void:
	_pad_pos = point
	_t = 0.0
	_playing = true
	_phase = "placed"
	var mdir: Vector3 = _moon_sky_dir()
	_moonmark.global_position = mdir * MOON_MARK_M
	_moonmark.visible = true
	_moonlabel.global_position = mdir * MOON_MARK_M + Vector3(0.0, 0.8, 0.0)
	_moonlabel.visible = true
	_site.global_position = _pad_pos
	_site.visible = true
	_screen.global_position = _pad_pos + Vector3(1.4, 1.0, 0.3)
	_screen.visible = true
	if _has_footage:
		_screenlabel.text = "LAUNCH FOOTAGE — flat screen, not 3D"
	else:
		_screenlabel.text = "FOOTAGE NOT IN BUILD — add data/video/artemis2_launch.ogv"
	_screenlabel.global_position = _pad_pos + Vector3(1.4, 1.55, 0.3)
	_screenlabel.visible = true
	_patch.visible = false
	_patchlabel.visible = false
	_ship.visible = true
	_panel.visible = true
	_update_panel()

func _clear_all() -> void:
	_phase = "off"
	_playing = false
	_t = 0.0
	_stop_video()
	for n: Node in [_ship, _moonmark, _moonlabel, _panel, _site, _screen, _screenlabel]:
		(n as Node3D).visible = false

func _toggle_video() -> void:
	if _player == null or not _has_footage:
		return
	if _player.is_playing():
		_player.stop()
	else:
		_player.play()

func _stop_video() -> void:
	if _player != null and _player.is_playing():
		_player.stop()

func _on_hand_drag(_hand_name: String, _point: Vector3) -> void:
	if _phase != "placed":
		_held.clear()
		_scale_anchor_d = -1.0
		return
	_held[_hand_name] = _point
	if _held.size() >= 2:
		var pts: Array = _held.values()
		var d: float = (pts[0] as Vector3).distance_to(pts[1] as Vector3)
		if _scale_anchor_d <= 0.0:
			_scale_anchor_d = d
			_scale_anchor_s = _scale
		elif _scale_anchor_d > 0.01:
			_scale = clamp(_scale_anchor_s * d / _scale_anchor_d, SHIP_SCALE_MIN, SHIP_SCALE_MAX)
			_ship.scale = Vector3(_scale, _scale, _scale)

func _on_hand_release(hand_name: String) -> void:
	_held.erase(hand_name)
	_scale_anchor_d = -1.0

func _path_pos(t: float) -> Vector3:
	# Scaled room path, TRUE direction. Out along a rising curve to
	# the Moon marker, a half-loop around it (flyby — the marker is
	# never touched, no landing), mirrored curve home, rest at an
	# offset splashdown point. Static shape, steady clock: nothing
	# spins fast, nothing to cause dizziness.
	var mpos: Vector3 = _moonmark.global_position
	var back: Vector3 = (_pad_pos - mpos)
	back.y = 0.0
	if back.length() < 0.01:
		back = Vector3(0, 0, 1)
	back = back.normalized()
	var arc0: Vector3 = mpos + back * FLYBY_R_M
	var arc1: Vector3 = mpos - back * FLYBY_R_M
	if t < 0.42:
		var u: float = t / 0.42
		var mid: Vector3 = (_pad_pos + arc0) * 0.5 + Vector3(0, 2.0, 0)
		return _bez(_pad_pos, mid, arc0, u)
	if t < 0.58:
		var a: float = (t - 0.42) / 0.16 * PI
		return mpos + back * (cos(a) * FLYBY_R_M) + Vector3.UP * (sin(a) * FLYBY_R_M)
	if t < 0.95:
		var v: float = (t - 0.58) / 0.37
		var mid2: Vector3 = (arc1 + _splash_pos()) * 0.5 + Vector3(0, 1.5, 0)
		return _bez(arc1, mid2, _splash_pos(), v)
	return _splash_pos()

func _splash_pos() -> Vector3:
	return _pad_pos + Vector3(0.8, -0.6, 0.4)

func _bez(a: Vector3, m: Vector3, b: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return a * (u * u) + m * (2.0 * u * t) + b * (t * t)

func _km_string(km: float) -> String:
	var n: int = int(round(max(km, 0.0)))
	var s: String = ""
	while n >= 1000:
		s = ",%03d" % [n % 1000] + s
		n = n / 1000
	return str(n) + s

func _clock_string(t: float) -> String:
	var total_h: float = t * float(TRIP["days"]) * 24.0
	var day: int = mini(1 + int(total_h / 24.0), 10)
	var rem: float = total_h - float((day - 1) * 24)
	var hh: int = int(rem)
	var mm: int = int((rem - float(hh)) * 60.0)
	return "Apr %d · %02d:%02d" % [day, hh, mm]

func _true_km(t: float) -> float:
	var one: float = float(TRIP["one_way_km"])
	if t < 0.42:
		return one * t / 0.42
	if t < 0.58:
		return one
	if t < 0.95:
		return one * (1.0 - (t - 0.58) / 0.37)
	return 0.0

func _leg(t: float) -> String:
	if t < 0.03:
		return "Launch"
	if t < 0.42:
		return "Coast out"
	if t < 0.58:
		return "Lunar flyby"
	if t < 0.95:
		return "Coast home"
	return "Splashdown — Pacific"

func _show_brief() -> void:
	var crew: String = ""
	for c: Variant in TRIP["crew"]:
		crew += ("" if crew == "" else " · ") + str(c)
	_panel.text = "ARTEMIS II — REPLAY\nApr 1 → Apr 10, 2026 · 9 days\n" + crew + "\nFlyby — no landing · 1st crew since Apollo 17\nPinch a table/ground spot to stage"
	_panel.visible = true

func _update_panel() -> void:
	_panel.text = "ARTEMIS II — REPLAY\n" + _leg(_t) + " · " + _clock_string(_t) + "\n≈ " + _km_string(_true_km(_t)) + " km out on the real trip\nDir true · room scaled · time x4320 — model, not telemetry\nShip: pinch pauses · gold ring packs up"

func _process(delta: float) -> void:
	if _phase == "off":
		_update_patch()
	if _panel.visible and _camera != null:
		_panel.global_position = _camera.global_position + _camera.global_transform.basis * Vector3(-0.35, -0.28, -1.2)
	if _phase == "placed":
		if _playing:
			_t = min(_t + delta / (float(TRIP["mission_minutes"]) * 60.0), 1.0)
			if _t >= 1.0:
				_playing = false
		var pos: Vector3 = _path_pos(_t)
		var ahead: Vector3 = _path_pos(min(_t + 0.005, 1.0))
		_ship.global_position = pos
		if (ahead - pos).length() > 0.001:
			_ship.look_at(ahead, Vector3.UP)
		_panel_tick += delta
		if _panel_tick > 0.25:
			_panel_tick = 0.0
			_update_panel()
		if _camera != null:
			var sb: Basis = _camera.global_transform.basis
			_screen.global_position = _pad_pos + sb * Vector3(1.4, 1.0, 0.3)
			_screenlabel.global_position = _pad_pos + sb * Vector3(1.4, 1.55, 0.3)

func _update_patch() -> void:
	# The mission patch rides beside the room Moon (same pattern as
	# the dial): upper-left of the planet, never over it.
	var moon: Dictionary = _moon_room_pos()
	if not moon["ok"]:
		_patch.visible = false
		_patchlabel.visible = false
		return
	_patch.visible = true
	_patch.global_position = (moon["pos"] as Vector3) + Vector3(-0.85, 0.55, 0.2)
	if _locked():
		_patchlabel.text = "ARTEMIS II REPLAY"
	else:
		_patchlabel.text = "NO SKY LOCK — pinch Moon first"
	_patchlabel.global_position = (moon["pos"] as Vector3) + Vector3(-0.85, 0.80, 0.2)
	_patchlabel.visible = true
