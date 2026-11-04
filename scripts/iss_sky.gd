# ISS in the real sky. vc131 first version, vc180 rework (user 2026-11-04:
# "way too close, gets in the way, doesn't look like the real ISS").
#
# vc180 SKY: the real ISS is ~109 m wide and 420-2000 km away, so to the eye
# it is a bright moving POINT of light (about 1 arcminute), never a visible
# shape. It is now drawn as a small bright point at its true direction, and
# only when it is really above the horizon (the old version parked it at
# 15 deg altitude when it was below the horizon, which was invented).
# Pinch the point (or ask the teacher) to bring a model to you.
#
# vc180 POSITION FIXES (were large errors):
#  1. Topocentric: the old code used the direction from EARTH'S CENTRE. For
#     something 420 km up that is tens of degrees wrong; now it is the
#     direction from YOU (observer position on the rotating Earth).
#  2. J2 drift: the orbit plane turns ~5 deg/day (Earth's bulge). The old
#     Kepler orbit ignored it, so a 2-day-old TLE was ~10 deg off in plane.
#  3. Earth's shadow: when the ISS is in Earth's shadow it cannot be seen;
#     the point is then drawn very faint and the label says so.
# Still approximate (not full SGP4, TLE from 2026-11-02): pass times can be
# off by a minute or so. Never presented as live tracking.
#
# vc180 MODEL: built at REAL size in metres (truss 109 m, 8 solar wings
# 35 x 12 m, modules at real lengths/diameters, US segment + Russian segment
# + Kibo/Columbus/Tranquility/Cupola), then scaled down when brought.
# Procedural shapes and colours only, no photo, no logos. Simplified:
# arrays shown flat, radiators simplified, visiting spacecraft left out.
extends Node3D
class_name IssSky

const AstroMathScript = preload("res://scripts/astro_math.gd")

@export var lat_deg: float = 28.4152
@export var lon_deg_east: float = -81.7879
@export var sky_radius: float = 85.0

var brought: bool = false
var brought_position: Vector3 = Vector3.ZERO
var altitude_deg: float = 0.0
var azimuth_deg: float = 0.0
var range_km: float = 0.0
var sunlit: bool = true
var tle_date: String = "2026-11-02"

const EPOCH_JD: float = 2461346.93427755
const INC_DEG: float = 51.6332
const RAAN_DEG: float = 335.9757
const ECC: float = 0.0007139
const ARGP_DEG: float = 339.3739
const M0_DEG: float = 20.6961
const MEAN_MOTION_REV_DAY: float = 15.49150046
const RE_KM: float = 6378.137
const J2: float = 0.00108263
const BROUGHT_SCALE: float = 0.032  # 109 m real -> 3.5 m model, same footprint as vc159

var _model: Node3D = null
var _point: MeshInstance3D = null
var _point_mat: StandardMaterial3D = null
var _label: Label3D = null

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
	global_position = brought_position
	_apply_look()

func send_back() -> void:
	brought = false
	_apply_look()

func _apply_look() -> void:
	visible = brought or altitude_deg > 0.0
	if _model != null:
		_model.visible = brought
	if _point != null:
		_point.visible = not brought
	if _label != null:
		_label.visible = brought

# ---------- merged-mesh builders (one draw call per material) ----------
func _box(st: SurfaceTool, size: Vector3, xf: Transform3D, col: Color, uv_cells: Vector2 = Vector2.ONE) -> void:
	var h: Vector3 = size * 0.5
	var faces: Array = [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c: Vector3 = n * h
		var hu: Vector3 = u * h
		var hv: Vector3 = v * h
		var p := [c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv]
		var uvs := [Vector2(0, 0), Vector2(uv_cells.x, 0), Vector2(uv_cells.x, uv_cells.y), Vector2(0, uv_cells.y)]
		var wn: Vector3 = (xf.basis * n).normalized()
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(wn)
			st.set_uv(uvs[i])
			st.add_vertex(xf * p[i])

func _cyl(st: SurfaceTool, r: float, length: float, xf: Transform3D, col: Color, segs: int = 20) -> void:
	# Axis along local Y.
	var hl: float = length * 0.5
	for i in range(segs):
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var quad := [d0 * r + Vector3(0, -hl, 0), d1 * r + Vector3(0, -hl, 0), d1 * r + Vector3(0, hl, 0), d0 * r + Vector3(0, hl, 0)]
		var ns := [d0, d1, d1, d0]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal((xf.basis * ns[k]).normalized())
			st.set_uv(Vector2.ZERO)
			st.add_vertex(xf * quad[k])
		for cap in [-1.0, 1.0]:
			var cn := Vector3(0, cap, 0)
			var tri := [Vector3(0, hl * cap, 0), d0 * r + Vector3(0, hl * cap, 0), d1 * r + Vector3(0, hl * cap, 0)]
			var order: Array = [0, 1, 2] if cap < 0.0 else [0, 2, 1]
			for k in order:
				st.set_color(col)
				st.set_normal((xf.basis * cn).normalized())
				st.set_uv(Vector2.ZERO)
				st.add_vertex(xf * tri[k])

static func _along_x(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), pos)

static func _along_z(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), pos)

static func _along_y(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pos)

func _cell_texture(base: Color, line: Color) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(base)
	for i in range(64):
		img.set_pixel(i, 0, line)
		img.set_pixel(0, i, line)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_model() -> void:
	# Axes, real metres: X = along the truss (starboard +X), Z = along the
	# pressurised modules (+Z forward, Harmony end), Y = zenith (away from Earth).
	var white := Color(0.90, 0.90, 0.88)   # beta-cloth / MLI blankets on US modules
	var ru := Color(0.80, 0.82, 0.78)      # Russian segment, slightly green-grey
	var truss_c := Color(0.62, 0.63, 0.66)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# --- Integrated truss, 109 m, sits on top of Destiny (S0) ---
	var tz: float = 10.75
	var ty: float = 4.6
	for side in [-1.0, 1.0]:
		for rail in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(-1.2, 1.2), Vector2(1.2, 1.2)]:
			_box(st, Vector3(54.5, 0.35, 0.35), Transform3D(Basis.IDENTITY, Vector3(side * 27.25, ty + rail.x, tz + rail.y)), truss_c)
		for bx in range(0, 27):
			var x: float = side * (1.0 + float(bx) * 2.0)
			_box(st, Vector3(0.25, 2.6, 0.25), Transform3D(Basis.IDENTITY, Vector3(x, ty, tz - 1.2)), truss_c)
			_box(st, Vector3(0.25, 2.6, 0.25), Transform3D(Basis.IDENTITY, Vector3(x, ty, tz + 1.2)), truss_c)
	# --- Heat rejection radiators (S1/P1): 3 white panels each, 23 m, simplified ---
	for side in [-1.0, 1.0]:
		for k in range(3):
			_box(st, Vector3(3.4, 0.15, 23.0), Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-25.0)), Vector3(side * (10.0 + float(k) * 3.6), ty - 5.0, tz - 13.5)), Color(0.96, 0.96, 0.95))
	# --- US pressurised stack along Z ---
	_cyl(st, 1.0, 2.0, _along_z(Vector3(0, 0, 23.2)), white)            # PMA-2 / docking port
	_cyl(st, 2.2, 7.2, _along_z(Vector3(0, 0, 18.6)), white)            # Harmony (Node 2)
	_cyl(st, 2.15, 8.5, _along_z(Vector3(0, 0, 10.75)), white)          # Destiny lab
	_cyl(st, 2.3, 5.5, _along_z(Vector3(0, 0, 3.75)), white)            # Unity (Node 1)
	_cyl(st, 1.0, 2.0, _along_z(Vector3(0, 0, 0.0)), white)             # PMA-1
	_cyl(st, 2.2, 11.2, _along_x(Vector3(-7.8, 0, 18.6)), white)        # Kibo PM (port of Harmony)
	_box(st, Vector3(5.6, 4.0, 5.0), Transform3D(Basis.IDENTITY, Vector3(-16.2, 0, 18.6)), Color(0.78, 0.78, 0.76))  # Kibo exposed facility
	_cyl(st, 2.2, 4.2, _along_y(Vector3(-7.8, 4.3, 18.6)), white)       # Kibo logistics module
	_cyl(st, 2.25, 6.9, _along_x(Vector3(5.65, 0, 18.6)), white)        # Columbus (starboard of Harmony)
	_cyl(st, 2.25, 6.7, _along_x(Vector3(-5.65, 0, 3.75)), white)       # Tranquility (port of Unity)
	_cyl(st, 2.2, 6.6, _along_z(Vector3(-5.65, 0, 9.3)), white)         # PMM (forward of Tranquility)
	_cyl(st, 2.0, 5.5, _along_x(Vector3(4.6, 0, 3.75)), white)          # Quest airlock
	# --- Russian segment along -Z ---
	_cyl(st, 2.05, 12.6, _along_z(Vector3(0, 0, -7.3)), ru)             # Zarya
	_cyl(st, 2.1, 13.1, _along_z(Vector3(0, 0, -20.15)), ru)            # Zvezda
	_cyl(st, 1.17, 6.0, _along_y(Vector3(0, -4.5, -7.3)), ru)           # Rassvet (nadir of Zarya)
	_cyl(st, 2.1, 13.0, _along_y(Vector3(0, -8.6, -14.5)), ru)          # Nauka (nadir of Zvezda)
	_cyl(st, 1.3, 4.0, _along_y(Vector3(0, 3.5, -14.5)), ru)            # Poisk (zenith of Zvezda)
	# --- Canadarm2, 17.6 m, two booms off the truss ---
	_cyl(st, 0.18, 8.0, Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(60.0)), Vector3(6.0, ty + 3.5, tz + 2.5)), Color(0.93, 0.93, 0.91), 8)
	_cyl(st, 0.18, 8.0, Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(-30.0)), Vector3(11.5, ty + 5.5, tz + 2.5)), Color(0.93, 0.93, 0.91), 8)
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.6
	bmat.metallic = 0.2
	body.material_override = bmat
	_model.add_child(body)
	# --- Cupola: 2.95 m wide, 1.5 m tall, nadir of Tranquility, 7 dark windows ---
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.475
	cm.bottom_radius = 0.9
	cm.height = 1.5
	cm.radial_segments = 6  # six side windows read as six facets
	cup.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.10, 0.13, 0.18)
	cmat.metallic = 0.8
	cmat.roughness = 0.1
	cup.material_override = cmat
	cup.position = Vector3(-5.65, -3.0, 3.75)
	_model.add_child(cup)
	# --- Solar array wings: 8 x (35 m x 12 m, two blankets + mast) ---
	# Original arrays: amber/bronze cells. iROSA roll-out arrays (2021-2023)
	# lie over 6 of the 8 wings: narrower, darker blue-grey.
	var sa := SurfaceTool.new()
	sa.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ro := SurfaceTool.new()
	ro.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mast := SurfaceTool.new()
	mast.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wing_i: int = 0
	for px in [-48.5, -33.0, 33.0, 48.5]:
		for zs in [-1.0, 1.0]:
			var zc: float = tz + zs * (2.5 + 17.5)
			for bl in [-1.0, 1.0]:
				_box(sa, Vector3(4.6, 0.05, 33.0), Transform3D(Basis.IDENTITY, Vector3(px + bl * 2.9, ty, zc)), Color(1, 1, 1), Vector2(6.0, 40.0))
			_box(mast, Vector3(0.5, 0.5, 35.0), Transform3D(Basis.IDENTITY, Vector3(px, ty, zc)), Color(0.85, 0.85, 0.85))
			if wing_i < 6:
				for bl2 in [-1.0, 1.0]:
					_box(ro, Vector3(2.9, 0.05, 19.0), Transform3D(Basis.IDENTITY, Vector3(px + bl2 * 2.9, ty + 0.4, tz + zs * (2.5 + 9.5))), Color(1, 1, 1), Vector2(4.0, 24.0))
			wing_i += 1
	# Zvezda's own two small arrays (29.7 m span), blue-grey
	for zx in [-1.0, 1.0]:
		_box(ro, Vector3(10.7, 0.05, 3.3), Transform3D(Basis.IDENTITY, Vector3(zx * 7.5, 0, -24.0)), Color(1, 1, 1), Vector2(14.0, 4.0))
	var sam := StandardMaterial3D.new()
	sam.albedo_texture = _cell_texture(Color(0.74, 0.54, 0.27), Color(0.38, 0.26, 0.12))
	sam.metallic = 0.5
	sam.roughness = 0.3
	sam.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rom := StandardMaterial3D.new()
	rom.albedo_texture = _cell_texture(Color(0.10, 0.13, 0.22), Color(0.30, 0.32, 0.38))
	rom.metallic = 0.5
	rom.roughness = 0.3
	rom.cull_mode = BaseMaterial3D.CULL_DISABLED
	for pair in [[sa, sam], [ro, rom], [mast, bmat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		_model.add_child(mi)

func _ready() -> void:
	_model = Node3D.new()
	_build_model()
	_model.scale = Vector3(BROUGHT_SCALE, BROUGHT_SCALE, BROUGHT_SCALE)
	add_child(_model)
	# Sky point: ~0.3 deg wide at 85 m, bright like the real ISS (up to mag -5).
	_point = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	_point.mesh = q
	_point_mat = StandardMaterial3D.new()
	_point_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_point_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_point_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_point_mat.albedo_texture = _dot_texture()
	_point.material_override = _point_mat
	add_child(_point)
	_label = Label3D.new()
	_label.font_size = 32
	_label.pixel_size = 0.0015
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 4
	add_child(_label)
	_apply_look()
	update_for_unix(Time.get_unix_time_from_system())

func _dot_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d: float = Vector2(float(x) - 15.5, float(y) - 15.5).length() / 15.5
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(a, 1.5)))
	return ImageTexture.create_from_image(img)

static func _kepler_e(m_rad: float, ecc: float) -> float:
	var e: float = m_rad
	for _i in range(5):
		e = e - (e - ecc * sin(e) - m_rad) / (1.0 - ecc * cos(e))
	return e

func update_for_unix(unix_seconds: float) -> void:
	var jds := AstroMathScript.jds_from_unix(unix_seconds)
	var jd_ut1: float = jds["ut1"]
	var dt_days: float = jd_ut1 - EPOCH_JD
	var period_s: float = 86400.0 / MEAN_MOTION_REV_DAY
	var a_km: float = pow(398600.4418 * pow(period_s / (2.0 * PI), 2.0), 1.0 / 3.0)
	# vc180 J2 secular drift of the node and perigee (deg/day).
	var n_deg_day: float = MEAN_MOTION_REV_DAY * 360.0
	var p_km: float = a_km * (1.0 - ECC * ECC)
	var k: float = J2 * pow(RE_KM / p_km, 2.0)
	var ci: float = cos(deg_to_rad(INC_DEG))
	var raan: float = deg_to_rad(RAAN_DEG - 1.5 * n_deg_day * k * ci * dt_days)
	var argp: float = deg_to_rad(ARGP_DEG + 0.75 * n_deg_day * k * (5.0 * ci * ci - 1.0) * dt_days)
	var inc: float = deg_to_rad(INC_DEG)
	var m_rad: float = deg_to_rad(fmod(M0_DEG + n_deg_day * dt_days, 360.0))
	var e_rad: float = _kepler_e(m_rad, ECC)
	var r_km: float = a_km * (1.0 - ECC * cos(e_rad))
	var nu_rad: float = 2.0 * atan2(sqrt(1.0 + ECC) * sin(e_rad / 2.0), sqrt(1.0 - ECC) * cos(e_rad / 2.0))
	var u_rad: float = argp + nu_rad
	var sat := Vector3(
		r_km * (cos(raan) * cos(u_rad) - sin(raan) * sin(u_rad) * cos(inc)),
		r_km * (sin(raan) * cos(u_rad) + cos(raan) * sin(u_rad) * cos(inc)),
		r_km * sin(u_rad) * sin(inc))
	# vc180 TOPOCENTRIC: subtract YOUR position on the rotating Earth.
	var lst: float = deg_to_rad(AstroMathScript.gmst_deg(jd_ut1) + lon_deg_east)
	var la: float = deg_to_rad(lat_deg)
	var obs := Vector3(RE_KM * cos(la) * cos(lst), RE_KM * cos(la) * sin(lst), RE_KM * sin(la))
	var topo: Vector3 = sat - obs
	range_km = topo.length()
	var rd := AstroMathScript.radec_from_vector(topo.normalized())
	var aa := AstroMathScript.alt_az(rd["ra_h"], rd["dec_deg"], jd_ut1, lat_deg, lon_deg_east)
	altitude_deg = aa["alt"]
	azimuth_deg = aa["az"]
	# vc180 Earth's shadow (cylinder model): behind Earth from the Sun and
	# within one Earth radius of the Sun-Earth line = in shadow.
	var srd: Dictionary = AstroMathScript.planet_radec_j2000("Sun", jds["tt"])
	var sun_u: Vector3 = AstroMathScript.unit_from_radec(srd["ra_h"], srd["dec_deg"])
	var along: float = sat.dot(sun_u)
	sunlit = along > 0.0 or (sat - sun_u * along).length() > RE_KM
	var dir := AstroMathScript.world_dir_from_alt_az(altitude_deg, azimuth_deg, get_yaw(), 0.0)
	if brought:
		global_position = brought_position
	else:
		global_position = dir * sky_radius
	# Only really above the horizon is drawn. No fake 15 deg any more.
	visible = brought or altitude_deg > 0.0
	_point_mat.albedo_color = Color(1.0, 1.0, 0.97, 1.0) if sunlit else Color(0.5, 0.5, 0.55, 0.25)
	var state: String = "" if sunlit else "\nIn Earth's shadow now, not visible to the eye"
	_label.text = "ISS, %.0f km away%s\nAlt %.1f° Az %.1f°\nModel shrunk from 109 m. TLE %s, approximate" % [range_km, state, altitude_deg, azimuth_deg, tle_date]
	_label.global_position = global_position + Vector3(0, 2.2, 0)

var yaw_offset_deg: float = 0.0
func get_yaw() -> float:
	return yaw_offset_deg
