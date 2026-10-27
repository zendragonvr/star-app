# Fresh sky core, written 2026-10-26. Stars as one MultiMesh,
# NO constellation lines — user 2026-10-26: "I do not want
# those lines. Like how you have the lines all over the stars
# and everything. I do not want that." Stars only, as points,
# over the real sky. Passthrough stays on: this is a
# passthrough app, not a full-VR world.
# Observer defaults to Clermont, FL. Calibration yaw is a single
# offset added to azimuth before placement (face north, recenter).
extends Node3D

const AstroMathScript = preload("res://scripts/astro_math.gd")

@export var lat_deg: float = 28.5496
@export var lon_deg: float = -81.7729
@export var yaw_offset_deg: float = 0.0
@export var sky_radius: float = 90.0

var _stars: Array = []
var _star_id_to_index: Dictionary = {}
var _multimesh_instance: MultiMeshInstance3D
var _halo_instance: MultiMeshInstance3D
var _halo_star_indices: Array = []
var _last_update_unix: float = -1.0
var _boot_unix: float = 0.0

func _ready() -> void:
	_boot_unix = Time.get_unix_time_from_system()
	_load_stars()
	_build_meshes()
	_update_sky(true)

func _process(_delta: float) -> void:
	var now: float = Time.get_unix_time_from_system()
	if abs(now - _last_update_unix) >= 1.0:
		_update_sky(false)

const GREEK: Dictionary = {
	"Alp": "Alpha", "Bet": "Beta", "Gam": "Gamma", "Del": "Delta",
	"Eps": "Epsilon", "Zet": "Zeta", "Eta": "Eta", "The": "Theta",
	"Iot": "Iota", "Kap": "Kappa", "Lam": "Lambda", "Mu": "Mu",
	"Nu": "Nu", "Xi": "Xi", "Omi": "Omicron", "Pi": "Pi",
	"Rho": "Rho", "Sig": "Sigma", "Tau": "Tau", "Ups": "Upsilon",
	"Phi": "Phi", "Chi": "Chi", "Psi": "Psi", "Ome": "Omega",
}

static func display_name_for(proper: String, bayer: String, flam: String, con: String) -> String:
	if proper != "":
		return proper
	if bayer != "" and con != "":
		var g: String = GREEK.get(bayer, bayer)
		# Bayer codes can carry a suffix like "Alp-1" (double star).
		if "-" in bayer:
			var base: String = bayer.split("-")[0]
			g = GREEK.get(base, base)
		return g + " " + con
	if flam != "" and con != "":
		return flam + " " + con
	return ""

static func star_color(spect: String, ci: float) -> Color:
	# Real star colours, by spectral class first, colour index
	# as fallback. O/B blue, A white-blue, F yellow-white,
	# G yellow, K orange, M red. Stars are NOT textured surfaces
	# — their look IS their colour and light, which is what this
	# colour is. HYG v41, CC BY-SA 4.0, spect + ci columns.
	if spect != "":
		match spect[0]:
			"O": return Color(0.61, 0.69, 1.0)
			"B": return Color(0.67, 0.75, 1.0)
			"A": return Color(0.79, 0.84, 1.0)
			"F": return Color(0.97, 0.97, 1.0)
			"G": return Color(1.0, 0.96, 0.92)
			"K": return Color(1.0, 0.82, 0.63)
			"M": return Color(1.0, 0.71, 0.42)
	if ci < 0.0:
		return Color(0.67, 0.75, 1.0)
	if ci < 0.5:
		return Color(0.85, 0.88, 1.0)
	if ci < 1.0:
		return Color(1.0, 0.96, 0.92)
	if ci < 1.5:
		return Color(1.0, 0.82, 0.63)
	return Color(1.0, 0.71, 0.42)

func _load_stars() -> void:
	# v16 CRITICAL FIX: stars.csv was NEVER in any APK.
	# FileAccess.open("res://data/stars.csv") is not seen by
	# Godot's export scanner, so "all_resources" still dropped
	# it — every v1-v15 APK shipped with an empty sky, which
	# is why the user correctly said "all we have is Moon and
	# Mars". Textures worked because they use load(), which
	# the scanner does see. Fix: load() the file as a TextFile
	# resource first (export scanner includes it), parse its
	# text, fall back to FileAccess for editor runs.
	var lines: PackedStringArray = []
	var txt_res = load("res://data/stars.csv")
	# Godot 4.3: "TextFile" is not a global GDScript type name
	# (parse error in v16 second build — again, never deliver
	# a build with a script parse error). Check by property
	# instead: a TextFile resource has a "text" String.
	if txt_res != null and txt_res.get("text") != null:
		lines = str(txt_res.get("text")).split("\n")
	else:
		var f: FileAccess = FileAccess.open("res://data/stars.csv", FileAccess.READ)
		if f == null:
			push_error("Star App: could not open res://data/stars.csv")
			return
		while not f.eof_reached():
			lines.append(f.get_line())
		f.close()
	# Skip header.
	var start: int = 1 if lines.size() > 0 else 0
	for li: int in range(start, lines.size()):
		var line: String = lines[li].strip_edges()
		if line.is_empty():
			continue
		var parts: PackedStringArray = line.split(",")
		if parts.size() < 4:
			continue
		var proper: String = parts[4] if parts.size() > 4 else ""
		var bayer: String = parts[5] if parts.size() > 5 else ""
		var flam: String = parts[6] if parts.size() > 6 else ""
		var con: String = parts[7] if parts.size() > 7 else ""
		var entry: Dictionary = {
			"id": int(parts[0]),
			"ra_h": float(parts[1]),
			"dec_deg": float(parts[2]),
			"mag": float(parts[3]),
			"name": display_name_for(proper, bayer, flam, con),
			"proper": proper,
			"bayer": bayer,
			"flam": flam,
			"con": con,
			"spect": parts[8] if parts.size() > 8 else "",
			"ci": float(parts[9]) if parts.size() > 9 and parts[9] != "" else 0.0,
			"dist_pc": float(parts[10]) if parts.size() > 10 and parts[10] != "" else 0.0,
			"absmag": float(parts[11]) if parts.size() > 11 and parts[11] != "" else 0.0,
			"lum": float(parts[12]) if parts.size() > 12 and parts[12] != "" else 0.0,
		}
		entry["color"] = star_color(entry["spect"], entry["ci"])
		_star_id_to_index[entry["id"]] = _stars.size()
		_stars.append(entry)
	print("Star App: loaded ", _stars.size(), " stars")

func _star_brightness(mag: float) -> float:
	# v19: bright stars brighter, faint stars dimmer, but
	# compressed so mag 6 is still visible in VR. Sirius
	# mag -1.44 -> 1.37, Vega 0 -> 1.20, mag 3 -> 0.84,
	# mag 6 -> 0.48. Colour is multiplied by this, so a
	# bright blue star is bright blue, not washed white.
	return clamp(1.20 - mag * 0.12, 0.30, 1.50)

func _build_meshes() -> void:
	_multimesh_instance = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Godot 4.3: ColorFormat enum is not exposed as
	# MultiMesh.COLOR_8BIT in GDScript (parse error in v16
	# first build, which still exported a broken APK — never
	# deliver a build with a script parse error). Use the
	# integer value: 0 = NONE, 1 = 8BIT, 2 = FLOAT.
	mm.color_format = 1
	# v19: round sphere, not a square box. A box reads as a
	# pixel, a sphere reads as a point of light, especially
	# when the user moves and sees it from the side.
	var core_sphere: SphereMesh = SphereMesh.new()
	core_sphere.radius = 0.5
	core_sphere.height = 1.0
	# v20 CRASH FIX: SphereMesh defaults to 64×32 segments
	# (~4,000 triangles per star × 8,920 stars = 35M triangles
	# per frame — that is why v19 was choppy and crashed the
	# Quest). 8×4 segments is a round point at 90 m, ~64
	# triangles per star, 570k total, which the Quest can do.
	core_sphere.radial_segments = 8
	core_sphere.rings = 4
	mm.mesh = core_sphere
	# A tiny sphere per star, scaled by magnitude in _update_sky.
	mm.instance_count = _stars.size()
	_multimesh_instance.multimesh = mm
	# v19: NO white emission. White emission washed out the
	# v16 spectral colours, so blue/orange/red stars all
	# looked white in v18 video. Unshaded albedo = the
	# star's real colour × brightness, nothing else.
	var star_mat: StandardMaterial3D = StandardMaterial3D.new()
	star_mat.albedo_color = Color(1.0, 1.0, 1.0)
	star_mat.emission_enabled = false
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# v16: per-star colours. MultiMesh instance colours only
	# show if the material reads vertex colour as albedo.
	star_mat.vertex_color_use_as_albedo = true
	_multimesh_instance.material_override = star_mat
	# v19: colour each star once, at build, by spectral class
	# × brightness. _update_sky only moves transforms every
	# second, it does not recolour, so this cost is paid once.
	for i: int in range(_stars.size()):
		var c: Color = _stars[i].get("color", Color(1.0, 1.0, 1.0))
		var b: float = _star_brightness(float(_stars[i].get("mag", 3.0)))
		mm.set_instance_color(i, Color(min(c.r * b, 1.0), min(c.g * b, 1.0), min(c.b * b, 1.0), 1.0))
	add_child(_multimesh_instance)
	# v19 glow halo, bright stars only. v20: mag < 1.0 only
	# (~50 stars, not 200), low-poly 8×4, same crash fix as
	# the core — transparent halos overdraw, so fewer is
	# safer, and only the brightest stars need a halo anyway.
	_halo_instance = MultiMeshInstance3D.new()
	var hm: MultiMesh = MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.color_format = 1
	var halo_sphere: SphereMesh = SphereMesh.new()
	halo_sphere.radius = 0.5
	halo_sphere.height = 1.0
	halo_sphere.radial_segments = 8
	halo_sphere.rings = 4
	hm.mesh = halo_sphere
	for i: int in range(_stars.size()):
		if float(_stars[i].get("mag", 99.0)) < 1.0:
			_halo_star_indices.append(i)
	hm.instance_count = _halo_star_indices.size()
	_halo_instance.multimesh = hm
	var halo_mat: StandardMaterial3D = StandardMaterial3D.new()
	halo_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.18)
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.vertex_color_use_as_albedo = true
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_instance.material_override = halo_mat
	for hi: int in range(_halo_star_indices.size()):
		var si: int = _halo_star_indices[hi]
		var hc: Color = _stars[si].get("color", Color(1.0, 1.0, 1.0))
		hm.set_instance_color(hi, Color(hc.r, hc.g, hc.b, 0.18))
	add_child(_halo_instance)
	# No constellation lines, by user direction 2026-10-26.
	# Nothing is drawn between stars, ever.

func _star_scale(mag: float) -> float:
	# Brighter (lower mag) = larger. Clamped so faint stars stay
	# visible. v3: about half the v1/v2 size — these are points
	# overlaid on the real sky, not objects in a virtual world.
	var s: float = 0.30 - mag * 0.04
	return clamp(s, 0.06, 0.45)

func _update_sky(force: bool) -> void:
	var now: float = Time.get_unix_time_from_system()
	if not force and abs(now - _last_update_unix) < 1.0:
		return
	_last_update_unix = now
	var jds: Dictionary = AstroMathScript.jds_from_unix(now)
	var mm: MultiMesh = _multimesh_instance.multimesh
	var hm: MultiMesh = _halo_instance.multimesh if _halo_instance != null else null
	var t: Transform3D = Transform3D()
	for i: int in range(_stars.size()):
		var s: Dictionary = _stars[i]
		var dir: Vector3 = AstroMathScript.star_world_dir(s["ra_h"], s["dec_deg"], jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg)
		# v21 horizon hide: dir.y < 0 means alt < 0°, below the
		# horizon. Scale 0 = hidden, so stars never show over
		# the floor, walls, or ceiling, and a below-horizon
		# star (v20 video: Alt -9.5°) can never be pinched.
		# This does not change layout or yaw — it only hides
		# what the real sky cannot show right now.
		var sc: float = _star_scale(s["mag"]) if dir.y >= 0.0 else 0.0
		# v21 boot fade-in, surreal launch: room first,
		# stars fade in gently, bright first. Bright mag <1
		# delay 0s, mag 3 delay 0.5s, mag 6 delay 1.5s, fade
		# over 1s. No big panel at boot, no fake sky dome.
		var fade_delay: float = clamp((s["mag"] + 1.0) * 0.25, 0.0, 1.5)
		var fade: float = clamp((now - _boot_unix - fade_delay) / 1.0, 0.0, 1.0)
		sc *= fade
		t = Transform3D(Basis().scaled(Vector3(sc, sc, sc)), dir * sky_radius)
		mm.set_instance_transform(i, t)
	if hm != null:
		for hi: int in range(_halo_star_indices.size()):
			var si: int = _halo_star_indices[hi]
			var hs: Dictionary = _stars[si]
			var hdir: Vector3 = AstroMathScript.star_world_dir(hs["ra_h"], hs["dec_deg"], jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg)
			var hsc: float = _star_scale(hs["mag"]) * 3.0 if hdir.y >= 0.0 else 0.0
			hm.set_instance_transform(hi, Transform3D(Basis().scaled(Vector3(hsc, hsc, hsc)), hdir * sky_radius))
	# No lines are built. See header.

# For tap-to-identify (Oct 30 step): world direction of a named star.
func star_world_direction_by_name(star_name: String) -> Vector3:
	var jds: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	for s: Dictionary in _stars:
		if s["name"] == star_name:
			return AstroMathScript.star_world_dir(s["ra_h"], s["dec_deg"], jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg)
	return Vector3.ZERO

func named_star_entry(star_name: String) -> Dictionary:
	for s: Dictionary in _stars:
		if s["name"] == star_name:
			return s
	return {}

# All named stars with their current world directions, for
# tap-to-identify. Only named stars are identifiable by name.
func named_star_directions() -> Array:
	var out: Array = []
	var jds: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	for s: Dictionary in _stars:
		if s["name"] != "":
			out.append({"name": s["name"], "dir": AstroMathScript.star_world_dir(s["ra_h"], s["dec_deg"], jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg), "entry": s})
	return out

func star_alt_az_by_name(star_name: String) -> Dictionary:
	var jds: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	for s: Dictionary in _stars:
		if s["name"] == star_name:
			return AstroMathScript.star_alt_az(s["ra_h"], s["dec_deg"], jds["tt"], jds["ut1"], lat_deg, lon_deg)
	return {}
