# 3I/ATLAS in the real sky — added 2026-11-01, ephemeris by the user, math unchanged.
# Placement reuses the app's existing RA/Dec -> alt/az -> world-dir pipeline
# (AstroMathScript, the same one planets use), so the comet sits in the
# same sky as the planets, with the same yaw/alt lock offsets.
# Ephemeris.atlas_sky() already returns RA/Dec for the date, so it is
# NOT precessed again here — precessing it a second time would move it.
# Ephemeris position itself is recomputed only when the UTC date changes
# (RA/Dec move ~0.01 deg/day at 12+ AU); the alt/az direction is recomputed
# with the current time like the planets, otherwise the comet would freeze
# in the sky while the stars move. The node is world-locked, not head-locked.
# Visual: small bright point + soft glow + tiny faint tail away from the Sun.
# NOT an 'Oumuamua-style rock: a small nucleus (likely under 1 km) inside
# a coma, tail pointing away from the Sun. Too faint to see by eye, so the
# marker is enlarged on purpose, and the label says so.
extends Node3D
class_name AtlasSky

const AstroMathScript = preload("res://scripts/astro_math.gd")

@export var lat_deg: float = 28.4152
@export var lon_deg_east: float = -81.7879
@export var yaw_offset_deg: float = 0.0
@export var alt_offset_deg: float = 0.0
@export var sky_radius: float = 85.0

var _cached_day: int = -1
var _cached_sky: Dictionary = {}
var altitude_deg: float = 0.0
var azimuth_deg: float = 0.0

var _point: MeshInstance3D
var _glow: MeshInstance3D
var _tail: MeshInstance3D
var _label: Label3D

# vc119 BRING TO YOU, like a planet: when brought, the node stays at a fixed
# room position (eye level, +45 deg right, 4 m out, same rule as planets)
# instead of at 85 m in the sky, until send_back() restores the sky position.
var brought: bool = false
var brought_position: Vector3 = Vector3.ZERO

func _set_brought_scale(s: float) -> void:
	# vc130 LONG COMET: point is an elongated nucleus, long axis along the tail (Z).
	# vc122 uniform scale made it a round blob with a big round glow. Now point is
	# 0.7 x 0.7 x 2.5 times the brought/sky factor, glow is small, tail is long.
	if _point != null:
		_point.scale = Vector3(s * 0.7, s * 0.7, s * 2.5)
	if _glow != null:
		_glow.scale = Vector3(s * 0.5, s * 0.5, s * 0.5)
	if _tail != null:
		_tail.scale = Vector3(s, s, s)

func bring_to_front(cam: Node3D) -> void:
	var cf: Vector3 = -cam.global_transform.basis.z
	cf.y = 0.0
	if cf.length() < 0.01:
		cf = Vector3(0.0, 0.0, -1.0)
	cf = cf.normalized()
	var right114: Vector3 = Basis(Vector3.UP, deg_to_rad(-45.0)) * cf
	right114.y = 0.0
	right114 = right114.normalized()
	brought_position = cam.global_position + right114 * 4.0
	brought = true
	_set_brought_scale(0.5)  # vc159: Atlas NOT removed, user 2026-11-02 — but it looked like shit, tiny. Brought scale doubled, so the comet reads in the room, not as a speck.
	global_position = brought_position

func send_back() -> void:
	brought = false
	_set_brought_scale(1.0)

func _ready() -> void:
	_point = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	_point.mesh = sm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.9, 0.97, 1.0)
	pm.emission_enabled = true
	pm.emission = Color(0.7, 0.9, 1.0)
	pm.emission_energy_multiplier = 3.0
	_point.material_override = pm
	add_child(_point)
	_glow = MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.6
	gm.height = 1.2
	_glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.6, 0.85, 1.0, 0.15)
	_glow.material_override = gmat
	_glow.visible = false  # vc159: Atlas glow orb out, like Sun/star orbs — comet is nucleus + tail only, no orb around it.
	add_child(_glow)
	_tail = MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.4, 0.4, 6.0)
	_tail.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color = Color(0.7, 0.9, 1.0, 0.35)
	_tail.material_override = tmat
	add_child(_tail)
	_label = Label3D.new()
	_label.font_size = 32
	add_child(_label)

## World direction for the comet at this unix time, using the planets' pipeline.
static func atlas_world_dir(unix_seconds: float, lat: float, lon_east: float, yaw_deg: float = 0.0, alt_off_deg: float = 0.0) -> Vector3:
	var jd := Ephemeris.jd_from_unix(unix_seconds)
	var sky := Ephemeris.atlas_sky(jd)
	var jds := AstroMathScript.jds_from_unix(unix_seconds)
	var aa := AstroMathScript.alt_az(sky["ra_h"], sky["dec_deg"], jds["ut1"], lat, lon_east)
	return AstroMathScript.world_dir_from_alt_az(aa["alt"], aa["az"], yaw_deg, alt_off_deg)

## Same, but through Ephemeris.alt_az / altaz_to_godot_dir, for cross-checking.
## Yaw is a rotation around Y applied afterwards, as the prompt specified.
static func atlas_world_dir_ephemeris(unix_seconds: float, lat: float, lon_east: float, yaw_deg: float = 0.0) -> Vector3:
	var jd := Ephemeris.jd_from_unix(unix_seconds)
	var sky := Ephemeris.atlas_sky(jd)
	var aa := Ephemeris.alt_az(sky["ra_h"], sky["dec_deg"], jd, lat, lon_east)
	var dir := Ephemeris.altaz_to_godot_dir(aa["alt"], aa["az"])
	if yaw_deg != 0.0:
		dir = dir.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	return dir

func update_for_unix(unix_seconds: float) -> void:
	var jd := Ephemeris.jd_from_unix(unix_seconds)
	var day := int(floor(jd))
	if day != _cached_day:
		_cached_day = day
		_cached_sky = Ephemeris.atlas_sky(jd)
	var sky: Dictionary = _cached_sky
	var jds := AstroMathScript.jds_from_unix(unix_seconds)
	var aa := AstroMathScript.alt_az(sky["ra_h"], sky["dec_deg"], jds["ut1"], lat_deg, lon_deg_east)
	altitude_deg = aa["alt"]
	azimuth_deg = aa["az"]
	var dir := AstroMathScript.world_dir_from_alt_az(aa["alt"], aa["az"], yaw_offset_deg, alt_offset_deg)
	if brought:
		global_position = brought_position
	else:
		global_position = dir * sky_radius
	# Tail away from the Sun, as seen from Earth: anti-solar direction in the sky.
	var sun_dir := AstroMathScript.planet_world_dir("Sun", jds["tt"], jds["ut1"], lat_deg, lon_deg_east, yaw_offset_deg, alt_offset_deg)
	var anti := (dir - sun_dir * dir.dot(sun_dir)).normalized()
	if anti.length_squared() > 0.01:
		# vc122: tail/label offsets scale with brought size, else the tail sits 2m off a 0.1m nucleus.
		var _ts: float = 0.5 if brought else 1.0  # vc159 matches brought scale 0.5
		_tail.global_position = global_position + anti * 3.0 * _ts
		_tail.look_at(global_position + anti * 6.0 * _ts, Vector3.UP)
		# vc130: nucleus long axis points along the tail, anti-solar, not a round ball.
		_point.global_position = global_position
		_point.look_at(global_position + anti * 5.0 * _ts, Vector3.UP)
	# vc75 rule: sky bodies show even below the horizon, look down to see them.
	visible = true
	var below := " — below the horizon" if altitude_deg < 0.0 else ""
	_label.text = "3I/ATLAS, interstellar comet. Too faint to see by eye, shown enlarged.%s\nSun %.2f AU, Earth %.2f AU" % [below, sky["helio_au"], sky["dist_au"]]
	_label.global_position = global_position + Vector3(0, 1.2 * (0.5 if brought else 1.0), 0)
