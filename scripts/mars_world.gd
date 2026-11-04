# vc104 Mars travel world — procedural, no photo, no panorama.
# Node3D, visible ONLY while planets_core travel_body() == "Mars".
# Follows the camera XZ (set by planets_core every frame), so the
# user never walks out of it. Built lazily on first activation so
# the main app does not pay the terrain cost at startup.
# All tunable values are at the top of this file.
class_name MarsWorld
extends Node3D

# ---- config (one place) ----
const SKY_HORIZON: Color = Color(0.85, 0.70, 0.52)  # vc109 pale tan, Perseverance/Curiosity horizon, not bright orange
const SKY_MID: Color = Color(0.72, 0.52, 0.36)  # #b97d5a retuned tan
# vc109 color grade (Mars travel only, NOT main passthrough sky):
const GRADE_SATURATION: float = 0.85
const GRADE_CONTRAST: float = 1.1
const GRADE_TINT: Color = Color(1.06, 0.99, 0.90)  # warm tan
const ANISO_LEVEL: int = 16
const PEBBLE_COUNT: int = 1500
const COBBLE_COUNT: int = 300
const ROVER_DISTANCE: float = 30.0
const SKY_ZENITH: Color = Color(0.490, 0.310, 0.239)  # #7d4f3d
const SKY_RADIUS: float = 900.0
const SUN_ELEV_DEG: float = 35.0
const SUN_AZIM_DEG: float = -45.0
const FOG_DENSITY: float = 0.0009
const TERRAIN_INNER_SIZE: float = 120.0
const TERRAIN_INNER_STEP: float = 1.0
const OUTER_RADII: Array = [60.0, 90.0, 140.0, 210.0, 320.0, 480.0, 720.0, 1080.0, 1500.0]
const ROCK_COUNT: int = 300
const BOULDER_COUNT: int = 8
const DUST_COUNT: int = 800
const SHADOW_DISTANCE: float = 40.0
# vc115 Moon: outer rings out to 9 km, so the horizon from the 28 m
# hilltop reads sharp and far (geometric Moon horizon from 28 m is
# ~9-10 km), not at the 1500 m Mars edge. Same ring point count
# (256/ring), so no extra triangle cost vs Mars except 1 more ring.
const MOON_OUTER_RADII: Array = [60.0, 120.0, 240.0, 400.0, 700.0, 1200.0, 2000.0, 3500.0, 6000.0, 9000.0]
const MOON_SUN_ELEV_DEG: float = 22.0
const MOON_SUN_AZIM_DEG: float = -20.0
const MOON_EARTH_AZIM_DEG: float = 60.0
const MOON_EARTH_ELEV_DEG: float = 30.0
const MoonHeightScript = preload("res://scripts/moon_height.gd")
# vc181 Mars lookout: you spawn on top of a broad hill (simulated, not a
# named real place) so you can see far across the plain to a mountain
# range 3-9 km out. Terrain rings now reach 10 km, fog thinned to match.
const MARS_HILL_H: float = 70.0
const MARS_HILL_R: float = 180.0
const MARS_OUTER_RADII: Array = [60.0, 90.0, 140.0, 210.0, 320.0, 480.0, 720.0, 1080.0, 1500.0, 2000.0, 2600.0, 3300.0, 4100.0, 5000.0, 6000.0, 7200.0, 8500.0, 10000.0]
const MOUNTAIN_INNER: float = 1800.0
const MOUNTAIN_OUTER: float = 2400.0
# Craters: x, z, radius, depth.
const CRATERS: Array = [
	Vector4(35.0, -45.0, 20.0, 1.4),
	Vector4(-60.0, 25.0, 28.0, 1.8),
	Vector4(70.0, 70.0, 16.0, 1.0),
]

var _built: bool = false
var _noise_fbm: FastNoiseLite = null
var _noise_ridge: FastNoiseLite = null
var _noise_patch: FastNoiseLite = null
var _sun_dir: Vector3 = Vector3.ZERO
var _sky_mat: ShaderMaterial = null
var _detail_tex: ImageTexture = null
# vc110: instance vars, defaults = vc109 consts. planet_loader.apply_env()
# sets these BEFORE the first activate() builds anything, so a .tres
# value changes Mars without rewriting this file. Not yet applied:
# height_fog, sky_bodies (no height-fog layer / sky-body meshes yet).
var _sky_horizon: Color = SKY_HORIZON
var _sky_mid: Color = SKY_MID
var _sky_zenith: Color = SKY_ZENITH
var _grade_sat: float = GRADE_SATURATION
var _grade_contrast: float = GRADE_CONTRAST
var _grade_tint: Color = GRADE_TINT
var _pebble_count: int = PEBBLE_COUNT
var _cobble_count: int = COBBLE_COUNT
var _rover_dist: float = ROVER_DISTANCE
var _sun_elev: float = SUN_ELEV_DEG
var _sun_azim: float = SUN_AZIM_DEG
var _fog_density: float = FOG_DENSITY
var _terrain_inner_size: float = TERRAIN_INNER_SIZE
var _terrain_inner_step: float = TERRAIN_INNER_STEP
var _rock_count: int = ROCK_COUNT
var _boulder_count: int = BOULDER_COUNT
var _dust_count: int = DUST_COUNT
var _shadow_dist: float = SHADOW_DISTANCE
var _mountain_inner: float = MOUNTAIN_INNER
var _mountain_outer: float = MOUNTAIN_OUTER
var _ground_basalt: Color = Color(0.30, 0.19, 0.12)
var _ground_dust: Color = Color(0.60, 0.40, 0.26)
var _sun_color: Color = Color(1.0, 0.92, 0.80)
var _sun_energy: float = 2.2
var _terrain_amp: float = 2.2
var _terrain_freq: float = 0.012
var _terrain_ridge: float = 1.2
# vc111: env-driven extras, defaults = Mars vc109
var _fog_color: Color = Color(0.85, 0.70, 0.52)
var _height_fog: float = 0.0
var _show_stars: bool = false
var _star_brightness: float = 0.0
var _sun_angular_deg: float = 0.35
var _sun_disc: bool = true
var _ambient_fill: float = 0.0
var _particle_type: int = 0
var _rock_color: Color = Color(0.45, 0.28, 0.18)
var _world_kind: String = "surface"
var _face_tint_unused: Color = Color(0.18, 0.83, 0.91)
var _has_lake: bool = false
var _has_lava: bool = false
var _sky_bodies: Array = []
var _craters: Array = []
# vc115 Moon mode: set in apply_env from env.name == "Moon".
var _is_moon: bool = false
var _world_name: String = ""  # vc157: Mars rover/footprints/tracks are Mars only, never on Mercury/Venus
# vc115 fresh-crater ray centres (x, z, radius, age), collected from
# MoonHeight's own hash at build time, so rays match the terrain.
var _moon_rays: Array = []
var _shadow_list: Array = []  # vc181 blob shadows: Vector4(x, z, height, width)

func apply_env(env: Resource) -> void:
	if env == null or _built:
		return
	_is_moon = (env.name == "Moon")
	_world_name = str(env.name)
	_sky_horizon = env.sky_horizon_color
	_sky_mid = env.sky_mid_color
	_sky_zenith = env.sky_zenith_color
	_grade_sat = env.grade_saturation
	_grade_contrast = env.grade_contrast
	_grade_tint = env.grade_tint
	_pebble_count = env.pebble_count
	_cobble_count = env.cobble_count
	_rock_count = env.rock_count
	_boulder_count = env.boulder_count
	_dust_count = env.particle_density
	_shadow_dist = env.shadow_distance
	_sun_color = env.sun_color
	_sun_energy = env.sun_energy
	_sun_elev = env.sun_elevation_deg
	_sun_azim = env.sun_azimuth_deg
	_fog_density = env.fog_density
	_terrain_inner_size = env.terrain_inner_size
	_terrain_inner_step = env.terrain_inner_step
	_terrain_amp = env.terrain_amplitude
	_terrain_freq = env.terrain_frequency
	_terrain_ridge = env.terrain_ridge_amount
	_fog_color = env.fog_color
	_height_fog = env.height_fog
	_show_stars = env.show_stars
	_star_brightness = env.star_brightness
	_sun_angular_deg = env.sun_angular_size_deg
	_sun_disc = env.sun_disc
	_ambient_fill = env.ambient_fill
	_particle_type = env.particle_type
	_rock_color = env.rock_color
	_world_kind = env.world_kind
	_has_lake = env.has_lake
	_has_lava = env.has_lava
	_sky_bodies = env.sky_bodies
	# Craters: deterministic from env count/size (Mars default 3 matches CRATERS).
	_craters = []
	if env.terrain_crater_count == 3:
		_craters = CRATERS.duplicate()
	else:
		var rngc := RandomNumberGenerator.new()
		rngc.seed = 9876
		for ci in range(env.terrain_crater_count):
			var ang := rngc.randf_range(0.0, TAU)
			var dist := rngc.randf_range(15.0, 110.0)
			_craters.append(Vector4(cos(ang) * dist, sin(ang) * dist, env.terrain_crater_size * rngc.randf_range(0.6, 1.4), rngc.randf_range(0.8, 1.8)))
	if env.ground_tint.size() >= 2:
		_ground_basalt = env.ground_tint[0]
		_ground_dust = env.ground_tint[1]

func free_built() -> void:
	# vc110: free textures/meshes between worlds so memory does not grow.
	for c: Node in get_children():
		c.queue_free()
	_built = false
	_detail_tex = null
	_sky_mat = null
	_noise_fbm = null
	_noise_ridge = null
	_noise_patch = null

func _ready() -> void:
	visible = false

func sun_direction() -> Vector3:
	var el: float = deg_to_rad(_sun_elev)
	var az: float = deg_to_rad(_sun_azim)
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()

# ONE height function: terrain vertices, rock Y, and ground height
# all call this, so nothing floats or clips.
# vc115 Moon: MoonHeight.get_height IS the function — rendering,
# footprints/tracks, and any ground query all go through here, so
# craters never pop in as LOD rings move (deterministic function,
# same at every ring). No baking: a baked 400 m texture sampled
# for rendering but not for raycasts would diverge from the
# function; direct per-vertex evaluation is fast enough (see
# headless timing in MERGED_FIXES vc115 entry).
func ground_height(x: float, z: float) -> float:
	if _is_moon:
		return MoonHeightScript.get_height(x, z)
	if _noise_fbm == null:
		return 0.0
	var h: float = _noise_fbm.get_noise_2d(x * _terrain_freq, z * _terrain_freq) * _terrain_amp
	h += _noise_fbm.get_noise_2d(x * 0.05, z * 0.05) * 0.6
	var r: float = _noise_ridge.get_noise_2d(x * 0.02, z * 0.02)
	h += (1.0 - abs(r)) * _terrain_ridge - 0.6
	# vc179 Phase 3 — megaripples, sand only, 7 m spacing, ~0.35 m tall,
	# one wind direction (0.8, 0.6). Sand mask is low-frequency
	# _noise_patch, same check used to keep boulders out of sand.
	# Moon returns earlier in this function, so Moon is unaffected.
	# Far ground calls this same function, so it matches exactly.
	# This is artistic / simulated, not a surveyed Mars feature.
	if _noise_patch != null:
		var sand: float = smoothstep(0.1, 0.4, _noise_patch.get_noise_2d(x * 0.004, z * 0.004))
		var ripple: float = sin((x * 0.8 + z * 0.6) * TAU / 7.0) * 0.35
		h += ripple * sand
	if _world_name == "Mars":
		var r0: float = sqrt(x * x + z * z)
		# Smooth summit: small bumps fade out near you, so nothing pokes
		# above eye level and blocks the view; full roughness from 120 m.
		h *= lerp(0.2, 1.0, smoothstep(15.0, 120.0, r0))
		h += MARS_HILL_H * exp(-pow(r0 / MARS_HILL_R, 2.0))
		var band: float = smoothstep(2500.0, 4500.0, r0) * (1.0 - smoothstep(8200.0, 9800.0, r0))
		if band > 0.0:
			var rid: float = 1.0 - abs(_noise_ridge.get_noise_2d(x * 0.0007, z * 0.0007))
			var big: float = (_noise_fbm.get_noise_2d(x * 0.00035, z * 0.00035) + 1.0) * 0.5
			h += band * (90.0 + 520.0 * rid * rid * big + 60.0 * big)
	var _cr_list: Array = _craters if _craters.size() > 0 else CRATERS
	for c: Vector4 in _cr_list:
		var dx: float = x - c.x
		var dz: float = z - c.z
		var d: float = sqrt(dx * dx + dz * dz)
		var t: float = d / c.z
		if t < 1.0:
			h -= c.w * (1.0 - t * t)
		var rim: float = exp(-pow((t - 1.0) * 4.0, 2.0))
		h += c.w * 0.5 * rim
	return h

func _init_noises() -> void:
	_noise_fbm = FastNoiseLite.new()
	_noise_fbm.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_fbm.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_fbm.fractal_octaves = 5
	_noise_fbm.frequency = 1.0
	_noise_fbm.seed = 1337
	_noise_ridge = FastNoiseLite.new()
	_noise_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_ridge.fractal_octaves = 5
	_noise_ridge.frequency = 1.0
	_noise_ridge.seed = 4242
	_noise_patch = FastNoiseLite.new()
	_noise_patch.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_patch.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_patch.fractal_octaves = 3
	_noise_patch.frequency = 1.0
	_noise_patch.seed = 777

func _collect_moon_rays() -> void:
	# vc115: scan MoonHeight's own hash (layers 0-1 only, the big
	# fresh craters that throw rays), keep the 3 largest fresh
	# (age < 0.35) craters. Centres match the terrain exactly.
	_moon_rays = []
	var layers: Array = MoonHeightScript.LAYERS
	for li in range(2):
		var L = layers[li]
		var cell: float = L[0]
		var span: int = 4 if li == 0 else 7
		for cx in range(-span, span + 1):
			for cz in range(-span, span + 1):
				if MoonHeightScript._h(cx, cz, li * 7 + 1) > L[1]:
					continue
				var age: float = MoonHeightScript._h(cx, cz, li * 7 + 5)
				if age >= 0.35:
					continue
				var px: float = (float(cx) + MoonHeightScript._h(cx, cz, li * 7 + 2)) * cell
				var pz: float = (float(cz) + MoonHeightScript._h(cx, cz, li * 7 + 3)) * cell
				var rad: float = lerpf(L[2], L[3], pow(MoonHeightScript._h(cx, cz, li * 7 + 4), 2.5))
				if rad < 20.0:
					continue
				_moon_rays.append(Vector4(px, pz, rad, age))
	_moon_rays.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.z > b.z)
	if _moon_rays.size() > 3:
		_moon_rays.resize(3)

func _soil_color(x: float, z: float, slope_dark: float) -> Color:
	if _is_moon:
		# vc115 dark gray regolith, albedo ~0.12, slightly warm, NO orange.
		var patch: float = (_noise_patch.get_noise_2d(x * 0.008, z * 0.008) + 1.0) * 0.5
		var c: Color = Color(0.115, 0.108, 0.10).lerp(Color(0.16, 0.15, 0.14), clamp(patch, 0.0, 1.0))
		# Soft ray streaks of lighter ejecta around fresh craters.
		for rc in _moon_rays:
			var vx: float = x - rc.x
			var vz: float = z - rc.y
			var dist: float = sqrt(vx * vx + vz * vz)
			if dist < rc.z * 0.8 or dist > rc.z * 6.0:
				continue
			var ang: float = atan2(vz, vx)
			var ray_pat: float = pow(0.5 + 0.5 * sin(ang * 14.0 + rc.w * 40.0), 6.0)
			var fade: float = clamp(1.0 - (dist - rc.z) / (rc.z * 5.0), 0.0, 1.0)
			c = c.lerp(Color(0.22, 0.21, 0.20), ray_pat * fade * 0.30)
		if slope_dark > 0.0:
			c = c.lerp(Color(0.07, 0.065, 0.06), slope_dark)
		return c
	var patch: float = (_noise_patch.get_noise_2d(x * 0.008, z * 0.008) + 1.0) * 0.5
	var basalt: Color = _ground_basalt  # vc109 darker basalt sand
	var dust: Color = _ground_dust  # vc109 brown-ochre, not bright orange
	var c: Color = basalt.lerp(dust, clamp(patch, 0.0, 1.0))
	if slope_dark > 0.0:
		c = c.lerp(Color(0.23, 0.15, 0.10), slope_dark)
	return c

func _slope_dark(x: float, z: float) -> float:
	var hx: float = ground_height(x + 1.0, z) - ground_height(x - 1.0, z)
	var hz: float = ground_height(x, z + 1.0) - ground_height(x, z - 1.0)
	var ny: float = 2.0 / sqrt(hx * hx + 4.0 + hz * hz)
	# Slope > 30 deg means normal.y < cos(30deg) = 0.866.
	if ny < 0.866:
		return clamp((0.866 - ny) * 3.0, 0.0, 0.7)
	return 0.0

func _build_mesh_from_grid(verts: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, normals: PackedVector3Array = PackedVector3Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if normals.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# vc115 Moon: vertex normal from the SAME height function, via
# central differences. Reused for lambert relief shading and for
# slope darkening, so _slope_dark's extra height calls are skipped.
func _moon_normal(x: float, z: float, step: float) -> Vector3:
	var hx: float = ground_height(x + step, z) - ground_height(x - step, z)
	var hz: float = ground_height(x, z + step) - ground_height(x, z - step)
	return Vector3(-hx, 2.0 * step, -hz).normalized()

func _moon_slope_dark(nrm: Vector3) -> float:
	if nrm.y < 0.866:
		return clamp((0.866 - nrm.y) * 3.0, 0.0, 0.7)
	return 0.0


func _detail_texture() -> ImageTexture:
	# Procedural 512px noise, mipmaps generated, so rock/ground textures
	# get anisotropic filtering + mipmaps without an external download.
	if _detail_tex != null:
		return _detail_tex
	var img: Image = Image.create(512, 512, false, Image.FORMAT_RGB8)
	var n: FastNoiseLite = FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 1.0
	n.seed = 999
	for y: int in range(512):
		for x: int in range(512):
			var v: float = (n.get_noise_2d(float(x) * 0.05, float(y) * 0.05) + 1.0) * 0.5
			var g: float = (n.get_noise_2d(float(x) * 0.4, float(y) * 0.4) + 1.0) * 0.5
			var c: float = clamp(0.75 + v * 0.35 + (g - 0.5) * 0.25, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c))
	img.generate_mipmaps()
	_detail_tex = ImageTexture.create_from_image(img)
	return _detail_tex

func _terrain_material() -> ShaderMaterial:
	# vc109 multi-scale ground: procedural noise at macro/mid/micro
	# scales, faded by distance to camera, so detail is visible up
	# close and never tiles from far away. Unshaded (the vc104
	# ArrayMesh has no normals, so a lit material cannot shade it
	# reliably in GL Compatibility); colour grade is applied here.
	# Triplanar is NOT used: the ground is a flat XZ plane, slope
	# darkening comes from vertex colours (vc104, kept).
	var code: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform float grade_sat = 0.85;
uniform float grade_contrast = 1.1;
uniform vec3 grade_tint = vec3(1.06, 0.99, 0.90);
uniform vec3 fog_color = vec3(0.85, 0.70, 0.52);
uniform float fog_density = 0.0009;
uniform float height_fog = 0.0;
uniform float moon_mode = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float ambient_fill = 0.05;
uniform float opposition_strength = 0.0;
uniform float moon_exposure = 4.0;
uniform float relief_ambient = 0.45;
varying vec3 v_col;
varying vec3 v_wp;
varying vec3 v_nrm;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	v_col = COLOR.rgb;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	float dist = distance(CAMERA_POSITION_WORLD, v_wp);
	float macro = vnoise(v_wp.xz * 0.05);
	float mid = vnoise(v_wp.xz * 0.30);
	float micro = vnoise(v_wp.xz * 2.0);
	float micro_w = clamp(1.0 - dist / 120.0, 0.0, 1.0);
	float mid_w = clamp(1.0 - dist / 300.0, 0.0, 1.0);
	vec3 col = v_col * (0.82 + macro * 0.36 + mid * 0.14 * mid_w + micro * 0.12 * micro_w);
	if (moon_mode > 0.5) {
		// vc115 Moon relief: lambert from the vertex normal (same
		// height function), perturbed by 3-scale procedural grain
		// (macro/mid/micro noise gradients). This is the long-shadow
		// relief: crater walls away from the sun go very dark, lit
		// walls stay gray. No cast shadows on an unshaded material;
		// ambient_fill keeps shadows very dark, not pure black.
		vec3 n = normalize(v_nrm);
		float gx = vnoise(v_wp.xz * 0.5) - 0.5 + (vnoise(v_wp.xz * 3.0) - 0.5) * 0.6 + (vnoise(v_wp.xz * 12.0) - 0.5) * 0.3;
		float gz = vnoise(v_wp.xz * 0.5 + 7.0) - 0.5 + (vnoise(v_wp.xz * 3.0 + 7.0) - 0.5) * 0.6 + (vnoise(v_wp.xz * 12.0 + 7.0) - 0.5) * 0.3;
		n.xz += vec2(gx, gz) * 0.35;
		n = normalize(n);
		float diff = clamp(dot(n, sun_dir), 0.0, 1.0);
		// vc179 FIX: exposure. Real regolith albedo (~0.12) x a 12 deg
		// sun gave ~3% brightness, a near-black floor once the shader
		// compiles. x4 lifts flat ground to mid-grey and sun-facing
		// slopes bright. Tune this one number in-headset.
		col = v_col * (ambient_fill + diff) * moon_exposure;
		// vc179 Phase 6 — opposition glow, Moon only. Prompt asked
		// for a per-frame sun_dir_view uniform + a new _process, but
		// MarsWorld has no _process and adding one needs asking
		// first, so this uses the mathematically identical world-
		// space form instead: dot(surface-to-camera, sun_dir) is
		// the same dot product as in view space, rotation preserves
		// it, and CAMERA_POSITION_WORLD updates every fragment, so
		// the glow follows the head with no per-frame code.
		// Glow peaks when the sun is directly behind the camera,
		// i.e. around the viewer's own shadow. Mars: strength 0.
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - v_wp);
		float opp = pow(max(dot(to_cam, sun_dir), 0.0), 200.0);
		col *= 1.0 + opposition_strength * opp;
		ALBEDO = col;
	} else {
	// vc181 sun relief: slopes facing the sun brighter, slopes away darker,
	// normalised so flat ground keeps its old colour. Ambient is high on
	// Mars (dusty sky light fills shadows), so shading stays soft.
	vec3 rn = normalize(v_nrm);
	float rd = clamp(dot(rn, sun_dir), 0.0, 1.0);
	col *= (relief_ambient + rd) / (relief_ambient + max(sun_dir.y, 0.05));
	// vc179 FIX: was "return;" above. Godot 4.3 rejects return in
	// fragment(), so the WHOLE ground shader failed to compile and the
	// ground was never drawn on any world (see-through floor).
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, grade_sat);
	col = (col - 0.5) * grade_contrast + 0.5;
	col *= grade_tint;
	col *= 0.97;
	float fog_f = 1.0 - exp(-dist * fog_density);
	fog_f = clamp(fog_f * (1.0 + height_fog * clamp(1.0 - v_wp.y / 50.0, 0.0, 1.0)), 0.0, 1.0);
	col = mix(col, fog_color, fog_f);
	ALBEDO = col;
	}
}
"""
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	m.set_shader_parameter("grade_sat", _grade_sat)
	m.set_shader_parameter("grade_contrast", _grade_contrast)
	m.set_shader_parameter("grade_tint", Vector3(_grade_tint.r, _grade_tint.g, _grade_tint.b))
	m.set_shader_parameter("fog_color", Vector3(_fog_color.r, _fog_color.g, _fog_color.b))
	m.set_shader_parameter("fog_density", _fog_density)
	m.set_shader_parameter("height_fog", _height_fog)
	m.set_shader_parameter("moon_mode", 1.0 if _is_moon else 0.0)
	var sd: Vector3 = sun_direction()
	m.set_shader_parameter("sun_dir", sd)
	m.set_shader_parameter("ambient_fill", _ambient_fill)
	# vc179 Phase 6: Moon 0.6, Mars 0.0 (no change to Mars).
	m.set_shader_parameter("opposition_strength", 0.6 if _is_moon else 0.0)
	return m

func _build_terrain() -> void:
	if _is_moon:
		_collect_moon_rays()
	var h00: float = ground_height(0.0, 0.0)
	# Inner grid: Mars 120 m at 1 m steps; Moon 240 m at 2 m steps
	# (same 121x121 vertex count, so same 72 fps budget, but the
	# 140 m hill is fully inside the detailed grid).
	var n: int = int(_terrain_inner_size / _terrain_inner_step) + 1  # 121
	var verts: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for gz: int in range(n):
		for gx: int in range(n):
			var x: float = (float(gx) - float(n - 1) * 0.5) * _terrain_inner_step
			var z: float = (float(gz) - float(n - 1) * 0.5) * _terrain_inner_step
			verts.append(Vector3(x, ground_height(x, z) - h00, z))
			var nrm: Vector3 = _moon_normal(x, z, _terrain_inner_step)
			normals.append(nrm)  # vc181: every world gets normals -> sun relief shading
			if _is_moon:
				colors.append(_soil_color(x, z, _moon_slope_dark(nrm)))
			else:
				colors.append(_soil_color(x, z, _slope_dark(x, z)))
	for gz: int in range(n - 1):
		for gx: int in range(n - 1):
			var a: int = gz * n + gx
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)
	# Skirt around the inner perimeter, dropping 3 m, to hide the
	# step down to the outer ring (which sits 0.4 m below).
	var perim: PackedInt32Array = PackedInt32Array()
	for gx: int in range(n):
		perim.append(gx)
	for gz: int in range(1, n):
		perim.append(gz * n + (n - 1))
	for gx: int in range(n - 2, -1, -1):
		perim.append((n - 1) * n + gx)
	for gz: int in range(n - 2, 0, -1):
		perim.append(gz * n)
	var skirt_base: int = verts.size()
	for pi: int in range(perim.size()):
		var v: Vector3 = verts[perim[pi]]
		verts.append(Vector3(v.x, v.y - 3.0, v.z))
		colors.append(colors[perim[pi]])
		if normals.size() > 0:
			normals.append(normals[perim[pi]])
	for pi: int in range(perim.size()):
		var p0: int = perim[pi]
		var p1: int = perim[(pi + 1) % perim.size()]
		var s0: int = skirt_base + pi
		var s1: int = skirt_base + ((pi + 1) % perim.size())
		indices.append(p0)
		indices.append(s0)
		indices.append(p1)
		indices.append(p1)
		indices.append(s0)
		indices.append(s1)
	var inner: MeshInstance3D = MeshInstance3D.new()
	inner.mesh = _build_mesh_from_grid(verts, colors, indices, normals)
	var mat: ShaderMaterial = _terrain_material()  # vc109 multi-scale + tan grade
	inner.material_override = mat
	inner.name = "MarsTerrainInner"
	add_child(inner)
	# vc179 Phase 1 B3 — far ground to the real horizon, with planet
	# curvature. Mars/Moon only, so no other world changes by accident.
	# Uses the SAME height function and the SAME material as the inner
	# ground, so heights and fog line up. 129x129 vertices, 8 km x 8 km,
	# 32,768 triangles. Sits 0.15 m below the inner ground (outer rings
	# sit 0.4 m below, so this fills between them without z-fighting).
	# Bumps fade to flat from 60% to 95% of half-size, so nothing pokes
	# above the horizon at the far edge. Curvature drop =
	# distance^2 / (2 * R). No new @export field: radius is chosen
	# from the world already in memory (_is_moon / _world_name).
	# free_built() frees all children, so this is freed with the rest.
	# vc179 FIX: far ground DISABLED. It had no vertex colours, so the
	# terrain shader (which reads COLOR) drew it pure white: the white
	# streaks on Mars and the bright band on the Moon. Its 62.5 m grid
	# also poked up through the real ground. The existing outer rings
	# already reach 1500 m (Mars) and 9000 m (Moon), so nothing is lost.
	if false:
		var R: float = 1737400.0 if _is_moon else 3389500.0
		var fn: int = 128
		var fhalf: float = 4000.0
		var fstep: float = (fhalf * 2.0) / float(fn)
		var fst := SurfaceTool.new()
		fst.begin(Mesh.PRIMITIVE_TRIANGLES)
		for fiz in fn + 1:
			for fix in fn + 1:
				var fx: float = -fhalf + float(fix) * fstep
				var fz: float = -fhalf + float(fiz) * fstep
				var fr: float = sqrt(fx * fx + fz * fz)
				var fflat: float = 1.0 - smoothstep(fhalf * 0.6, fhalf * 0.95, fr)
				# Same height function as inner ground, relative to
				# the same origin height h00, then faded to flat.
				var fy: float = (ground_height(fx, fz) - h00) * fflat
				fy -= (fx * fx + fz * fz) / (2.0 * R)
				fy -= 0.15
				fst.set_uv(Vector2(fx, fz) * 0.02)
				fst.add_vertex(Vector3(fx, fy, fz))
		for fiz in fn:
			for fix in fn:
				var fa: int = fiz * (fn + 1) + fix
				var fb: int = fa + 1
				var fc: int = fa + (fn + 1)
				var fd: int = fc + 1
				# Same winding as the inner ground (a, c, b / b, c, d).
				# Terrain material is cull_disabled, so winding cannot
				# hide this from above in any case.
				fst.add_index(fa); fst.add_index(fc); fst.add_index(fb)
				fst.add_index(fb); fst.add_index(fc); fst.add_index(fd)
		fst.generate_normals()
		var far_mi: MeshInstance3D = MeshInstance3D.new()
		far_mi.mesh = fst.commit()
		far_mi.material_override = mat
		far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far_mi.name = "MarsTerrainFar"
		add_child(far_mi)
	# Outer square rings: Mars 60 m out to 1500 m; Moon 60 m out to
	# 9000 m (vc115 horizon). 256 points per ring, sitting 0.4 m
	# below the inner surface, covered by the skirt.
	var ring_points: int = 256
	var per_side: int = ring_points / 4
	var overts: PackedVector3Array = PackedVector3Array()
	var ocolors: PackedColorArray = PackedColorArray()
	var onormals: PackedVector3Array = PackedVector3Array()
	var oindices: PackedInt32Array = PackedInt32Array()
	var radii: Array = MOON_OUTER_RADII if _is_moon else (MARS_OUTER_RADII if _world_name == "Mars" else OUTER_RADII)
	for ri: int in range(radii.size()):
		var s: float = float(radii[ri])
		for pi: int in range(ring_points):
			var side: int = pi / per_side
			var f: float = float(pi % per_side) / float(per_side)
			var x: float = 0.0
			var z: float = 0.0
			if side == 0:
				x = lerp(-s, s, f)
				z = -s
			elif side == 1:
				x = s
				z = lerp(-s, s, f)
			elif side == 2:
				x = lerp(s, -s, f)
				z = s
			else:
				x = -s
				z = lerp(s, -s, f)
			overts.append(Vector3(x, ground_height(x, z) - h00 - 0.4, z))
			var onrm: Vector3 = _moon_normal(x, z, max(2.0, s * 0.02))
			onormals.append(onrm)
			if _is_moon:
				ocolors.append(_soil_color(x, z, _moon_slope_dark(onrm)))
			else:
				ocolors.append(_soil_color(x, z, _slope_dark(x, z)))
	for ri: int in range(radii.size() - 1):
		for pi: int in range(ring_points):
			var a: int = ri * ring_points + pi
			var b: int = ri * ring_points + ((pi + 1) % ring_points)
			var c: int = (ri + 1) * ring_points + pi
			var d: int = (ri + 1) * ring_points + ((pi + 1) % ring_points)
			oindices.append(a)
			oindices.append(c)
			oindices.append(b)
			oindices.append(b)
			oindices.append(c)
			oindices.append(d)
	var outer: MeshInstance3D = MeshInstance3D.new()
	outer.mesh = _build_mesh_from_grid(overts, ocolors, oindices, onormals)
	outer.material_override = mat
	outer.name = "MarsTerrainOuter"
	add_child(outer)

func _make_rock_base(seed: int) -> ArrayMesh:
	# Displaced sphere, flattened bottom. Normals are the radial
	# direction (exact for a sphere, close enough after the
	# small radial displacement), so no SurfaceTool is needed.
	var src: SphereMesh = SphereMesh.new()
	src.radius = 1.0
	src.height = 2.0
	src.radial_segments = 10
	src.rings = 6
	var arrs: Array = src.get_mesh_arrays()
	var sverts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var sidx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
	var rng_noise: FastNoiseLite = FastNoiseLite.new()
	rng_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rng_noise.frequency = 1.0
	rng_noise.seed = seed
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for vi: int in range(sverts.size()):
		var v: Vector3 = sverts[vi]
		var d: Vector3 = v.normalized()
		var disp: float = 1.0 + rng_noise.get_noise_3d(d.x * 2.0 + float(seed), d.y * 2.0, d.z * 2.0) * 0.35
		v = d * disp
		if v.y < -0.3:
			v.y = -0.3
			normals.append(Vector3(0.0, -1.0, 0.0))
		else:
			normals.append(d)
		verts.append(v)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_INDEX] = sidx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh

func _build_moon_footprints() -> void:
	# REMOVED 2026-11-01, user request: remove the Apollo thing from the Moon.
	# No footprints, no tracks, no traverse in the Moon world anymore.
	# Kept as a no-op so callers do not break; the Moon is now clean
	# regolith, craters, hill, and Earth only.
	return
	# vc115 Moon (old, removed): NO rover, NO rocks — only footprints and tracks
	# near the player, dark gray decals on the regolith, using the
	# SAME MoonHeight function for their height, so they sit on the
	# ground instead of floating or clipping.
	var h00: float = ground_height(0.0, 0.0)
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.06, 0.055, 0.05, 0.5)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC  # vc115 aniso 16x
	for fi: int in range(24):
		var fx: float = -0.4 + float(fi % 2) * 0.8
		var fz: float = 2.0 + float(fi) * 0.35
		var fp: MeshInstance3D = MeshInstance3D.new()
		var fpm: PlaneMesh = PlaneMesh.new()
		fpm.size = Vector2(0.35, 0.25)
		fp.mesh = fpm
		fp.rotation.x = -PI / 2.0
		fp.position = Vector3(fx, ground_height(fx, fz) - h00 + 0.03, fz)
		fp.material_override = fmat
		fp.name = "MoonFootprint"
		add_child(fp)
	# Two track strips leading away from the player, like a walking
	# traverse, dark gray, no rover model in vc115. Built as 2 m
	# segments, each at its own ground height, so the tracks follow
	# the hill instead of floating over it as one flat plane would.
	for side: float in [-0.9, 0.9]:
		for si: int in range(10):
			var d0: float = 2.0 + float(si) * 2.0
			var cx: float = d0 * 0.7071 - side * 0.64
			var cz: float = d0 * 0.7071 + side * 0.64
			var track: MeshInstance3D = MeshInstance3D.new()
			var pm: PlaneMesh = PlaneMesh.new()
			pm.size = Vector2(2.1, 0.8)
			track.mesh = pm
			track.rotation.x = -PI / 2.0
			track.rotation.z = -PI / 4.0
			track.position = Vector3(cx, ground_height(cx, cz) - h00 + 0.04, cz)
			track.material_override = fmat
			track.name = "MoonTrack"
			add_child(track)

func _build_rocks() -> void:
	# vc115 Moon was: no rocks at all. vc179 Phase 5 REVERSES that
	# deliberately, per the phased plan: grey, angular, half-buried
	# cobbles/boulders near fresh-crater rims (_moon_rays, collected
	# in _build_terrain) and dense pebbles at the feet, for scale.
	# Mountain ring is still NOT built for Moon (see guard before it).
	# If the headset test hates rocks on the Moon, revert this by
	# setting moon.tres pebble/cobble/boulder counts back to 0.
	_shadow_list = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1337
	# Cluster centres, so rock fields are clumpy, not uniform.
	var clusters: Array = []
	for ci: int in range(30):
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(5.0, 120.0)
		clusters.append(Vector2(cos(ang) * dist, sin(ang) * dist))
	var h00: float = ground_height(0.0, 0.0)
	var bases: Array = []
	for bi: int in range(5):
		bases.append(_make_rock_base(100 + bi * 17))
	var per_base: int = _rock_count / 5
	for bi: int in range(5):
		var mm: MultiMesh = MultiMesh.new()
		mm.mesh = bases[bi]
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = per_base
		for ii: int in range(per_base):
			var cl: Vector2 = clusters[rng.randi_range(0, clusters.size() - 1)]
			var x: float = cl.x + rng.randf_range(-8.0, 8.0)
			var z: float = cl.y + rng.randf_range(-8.0, 8.0)
			# Density falls off with distance: skip most far rocks.
			var dist: float = sqrt(x * x + z * z)
			if dist > 60.0 and rng.randf() < 0.6:
				x *= 0.5
				z *= 0.5
				dist = sqrt(x * x + z * z)
			var scale: float = 0.1 + pow(rng.randf(), 2.0) * 1.4
			# vc179 Phase 3 — half-buried, angular, two tones. Sink
			# 30-50% of height, non-uniform scale 0.6-1.4 per axis,
			# rotation already all 3 axes. Two tones from _rock_color
			# (tres) or _rock_color * 0.6, brightness +/-10%.
			# Instance colour only: 0 new materials, 0 new draw calls.
			var y: float = ground_height(x, z) - h00 - scale * rng.randf_range(0.3, 0.5)
			var t: Transform3D = Transform3D(
				Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))).scaled(Vector3(scale * rng.randf_range(0.6, 1.4), scale * rng.randf_range(0.6, 1.4), scale * rng.randf_range(0.6, 1.4))),
				Vector3(x, y, z)
			)
			mm.set_instance_transform(ii, t)
			if scale > 0.35 and dist < 90.0:
				_shadow_list.append(Vector4(x, z, scale * 0.6, scale * 1.1))
			var col: Color = _rock_color if rng.randf() < 0.5 else _rock_color * 0.6
			col *= rng.randf_range(0.9, 1.1)
			mm.set_instance_color(ii, col)
		var inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
		inst.multimesh = mm
		var rmat: StandardMaterial3D = StandardMaterial3D.new()
		rmat.vertex_color_use_as_albedo = true
		rmat.roughness = 0.95
		rmat.metallic = 0.0
		rmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC  # vc109 aniso 16x equivalent in GL Compatibility
		rmat.albedo_texture = _detail_texture()
		inst.material_override = rmat
		inst.visibility_range_end = 150.0
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		inst.name = "MarsRocks%d" % bi
		add_child(inst)
	# Large boulders, 2-5 m, 20-120 m, as landmarks.
	var bmm: MultiMesh = MultiMesh.new()
	bmm.mesh = bases[0]
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.instance_count = _boulder_count
	for ii: int in range(_boulder_count):
		# vc179 Phase 3 — no boulders in sand areas. Sand is the same
		# low-frequency _noise_patch check used for megaripples in
		# ground_height(): retry up to 5 times for a non-sand spot.
		# vc179 Phase 5 — Moon boulders go near fresh-crater rims
		# instead: a random _moon_ray centre, at 1.0-1.5x its radius.
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(20.0, 120.0)
		var x: float = cos(ang) * dist
		var z: float = sin(ang) * dist
		if _is_moon and _moon_rays.size() > 0:
			var rc: Vector4 = _moon_rays[rng.randi_range(0, _moon_rays.size() - 1)]
			var rang: float = rng.randf_range(0.0, TAU)
			var rdist: float = rc.z * rng.randf_range(1.0, 1.5)
			x = rc.x + cos(rang) * rdist
			z = rc.y + sin(rang) * rdist
			# Skip the sand retry for Moon (no sand, no megaripples).
			ang = 0.0
			dist = 0.0
		if not _is_moon:
			for _try in range(5):
				var _sand_check: float = smoothstep(0.1, 0.4, _noise_patch.get_noise_2d(x * 0.004, z * 0.004))
				if _sand_check < 0.5:
					break
				ang = rng.randf_range(0.0, TAU)
				dist = rng.randf_range(20.0, 120.0)
				x = cos(ang) * dist
				z = sin(ang) * dist
		var scale: float = rng.randf_range(2.0, 5.0)
		var y: float = ground_height(x, z) - h00 - scale * rng.randf_range(0.3, 0.5)
		var t: Transform3D = Transform3D(
			Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))).scaled(Vector3(scale * rng.randf_range(0.6, 1.4), scale * rng.randf_range(0.6, 1.4), scale * rng.randf_range(0.6, 1.4))),
			Vector3(x, y, z)
		)
		bmm.set_instance_transform(ii, t)
		_shadow_list.append(Vector4(x, z, scale * 0.6, scale * 1.1))
		var bcol: Color = _rock_color if rng.randf() < 0.5 else _rock_color * 0.6
		bcol *= rng.randf_range(0.9, 1.1)
		bmm.set_instance_color(ii, bcol)
	var binst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	binst.multimesh = bmm
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.95
	bmat.metallic = 0.0
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	bmat.albedo_texture = _detail_texture()
	binst.material_override = bmat
	binst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	binst.name = "MarsBoulders"
	add_child(binst)

	# vc109 pebbles + cobbles (biggest-return item 4). Simple meshes,
	# sunk 10-30% into terrain, culled by visibility_range, shadows OFF.
	var peb: MultiMesh = MultiMesh.new()
	peb.mesh = bases[1]
	peb.transform_format = MultiMesh.TRANSFORM_3D
	peb.use_colors = true
	peb.instance_count = _pebble_count
	for ii: int in range(_pebble_count):
		var ang: float = rng.randf_range(0.0, TAU)
		# vc179 Phase 3 — more pebbles within 10 m of the player:
		# 70% within 10 m, 30% within 15 m as before.
		# vc179 Phase 5 — Moon: 70% within 8 m, so the ground at
		# the feet reads as powdery grey, and grey colour, not brown.
		var dist: float = sqrt(rng.randf()) * 10.0 if rng.randf() < 0.7 else sqrt(rng.randf()) * 15.0
		if _is_moon:
			dist = sqrt(rng.randf()) * 8.0 if rng.randf() < 0.7 else sqrt(rng.randf()) * 15.0
		var x: float = cos(ang) * dist
		var z: float = sin(ang) * dist
		var scale: float = rng.randf_range(0.02, 0.10)
		var y: float = ground_height(x, z) - h00 - scale * rng.randf_range(0.3, 0.5)
		peb.set_instance_transform(ii, Transform3D(Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))).scaled(Vector3(scale * rng.randf_range(0.6, 1.4), scale * rng.randf_range(0.6, 1.4), scale * rng.randf_range(0.6, 1.4))), Vector3(x, y, z)))
		peb.set_instance_color(ii, (_rock_color if _world_name != "Mars" else Color(0.35, 0.23, 0.15)) * rng.randf_range(0.9, 1.1))
	var pinst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	pinst.multimesh = peb
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.vertex_color_use_as_albedo = true
	pmat.roughness = 0.95
	pmat.metallic = 0.0
	pmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	pmat.albedo_texture = _detail_texture()
	pinst.material_override = pmat
	pinst.visibility_range_end = 15.0
	pinst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pinst.name = "MarsPebbles"
	add_child(pinst)
	var cob: MultiMesh = MultiMesh.new()
	cob.mesh = bases[2]
	cob.transform_format = MultiMesh.TRANSFORM_3D
	cob.use_colors = true
	cob.instance_count = _cobble_count
	for ii: int in range(_cobble_count):
		var cl2: Vector2 = clusters[rng.randi_range(0, clusters.size() - 1)]
		var x2: float = cl2.x + rng.randf_range(-15.0, 15.0)
		var z2: float = cl2.y + rng.randf_range(-15.0, 15.0)
		if sqrt(x2 * x2 + z2 * z2) > 60.0:
			x2 *= 0.5
			z2 *= 0.5
		# vc179 Phase 5 — Moon cobbles: 70% near fresh-crater rims,
		# 30% on open plains (the cluster spot above).
		if _is_moon and _moon_rays.size() > 0 and rng.randf() < 0.7:
			var rc2: Vector4 = _moon_rays[rng.randi_range(0, _moon_rays.size() - 1)]
			var rang2: float = rng.randf_range(0.0, TAU)
			var rdist2: float = rc2.z * rng.randf_range(1.0, 1.5)
			x2 = rc2.x + cos(rang2) * rdist2
			z2 = rc2.y + sin(rang2) * rdist2
		var scale2: float = rng.randf_range(0.10, 0.40)
		var y2: float = ground_height(x2, z2) - h00 - scale2 * rng.randf_range(0.3, 0.5)
		cob.set_instance_transform(ii, Transform3D(Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))).scaled(Vector3(scale2 * rng.randf_range(0.6, 1.4), scale2 * rng.randf_range(0.6, 1.4), scale2 * rng.randf_range(0.6, 1.4))), Vector3(x2, y2, z2)))
		cob.set_instance_color(ii, (_rock_color if _world_name != "Mars" else Color(0.40, 0.26, 0.17)) * rng.randf_range(0.9, 1.1))
	var cinst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	cinst.multimesh = cob
	cinst.material_override = pmat
	cinst.visibility_range_end = 60.0
	cinst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cinst.name = "MarsCobbles"
	add_child(cinst)
	# vc179 Phase 5 — Moon still gets NO mountain ring, even though
	# Moon now gets rocks/pebbles/cobbles/boulders above.
	if _is_moon or _world_name == "Mars":
		return  # vc181 Mars: real 3D mountains in ground_height, no flat curtain
	# Mountain ring: low-poly curtain, 1800-2400 m, tinted 70%
	# toward the horizon sky colour so it reads far away.
	var mverts: PackedVector3Array = PackedVector3Array()
	var mindices: PackedInt32Array = PackedInt32Array()
	var segs: int = 128
	for si: int in range(segs + 1):
		var ang: float = float(si % segs) / float(segs) * TAU
		var peak: float = 60.0 + (_noise_patch.get_noise_2d(cos(ang) * 3.0, sin(ang) * 3.0) + 1.0) * 0.5 * 160.0
		var cx: float = cos(ang) * _mountain_inner
		var cz: float = sin(ang) * _mountain_inner
		mverts.append(Vector3(cx, -10.0, cz))
		mverts.append(Vector3(cx, peak, cz))
	for si: int in range(segs):
		var a: int = si * 2
		var b: int = a + 1
		var c: int = ((si + 1) % segs) * 2
		var d: int = c + 1
		mindices.append(a)
		mindices.append(c)
		mindices.append(b)
		mindices.append(b)
		mindices.append(c)
		mindices.append(d)
	var marr: Array = []
	marr.resize(Mesh.ARRAY_MAX)
	marr[Mesh.ARRAY_VERTEX] = mverts
	marr[Mesh.ARRAY_INDEX] = mindices
	var mmesh: ArrayMesh = ArrayMesh.new()
	mmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, marr)
	var minst: MeshInstance3D = MeshInstance3D.new()
	minst.mesh = mmesh
	var mmat: StandardMaterial3D = StandardMaterial3D.new()
	mmat.albedo_color = _sky_horizon.lerp(Color(0.45, 0.28, 0.18), 0.3)
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	minst.material_override = mmat
	minst.name = "MarsMountains"
	add_child(minst)


func _build_rover() -> void:
	# vc181 PERSEVERANCE-STYLE rover, procedural (not a NASA model, no logos).
	# Real proportions: ~3 m long, 2.7 m wide, 2.2 m to the mast head;
	# six 52.5 cm wheels on a rocker-bogie; mast with camera head front-right;
	# MMRTG power unit angled off the back; 2.1 m arm folded at the front;
	# high-gain antenna on the deck. Light grey body, dust-tinted.
	# Parked 14 m below you on the hill, side-on so its profile reads.
	var h00: float = ground_height(0.0, 0.0)
	var rx: float = 17.0
	var rz: float = -13.0
	var ry: float = ground_height(rx, rz) - h00
	var up: Vector3 = _moon_normal(rx, rz, 1.5)
	var fwd: Vector3 = Vector3(rz, 0.0, -rx).normalized()  # side-on to you
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right: Vector3 = up.cross(fwd).normalized() * -1.0
	var root: Node3D = Node3D.new()
	root.transform = Transform3D(Basis(fwd, up, right), Vector3(rx, ry, rz))
	root.name = "MarsRoverPerseveranceStyle"
	var dust := Color(0.80, 0.72, 0.62)
	var mats: Dictionary = {}
	for k in [["body", Color(0.82, 0.80, 0.76), 0.2], ["dark", Color(0.16, 0.15, 0.15), 0.4], ["wheel", Color(0.56, 0.55, 0.53), 0.6], ["gold", Color(0.78, 0.62, 0.30), 0.7], ["glass", Color(0.05, 0.05, 0.07), 0.9]]:
		var m := StandardMaterial3D.new()
		m.albedo_color = (k[1] as Color).lerp(dust, 0.18)
		m.metallic = k[2]
		m.roughness = 0.55
		mats[k[0]] = m
	var add_box := func(size: Vector3, pos: Vector3, mat: String, rot: Vector3 = Vector3.ZERO) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = pos
		mi.rotation = rot
		mi.material_override = mats[mat]
		root.add_child(mi)
	var add_cyl := func(r: float, hgt: float, pos: Vector3, mat: String, rot: Vector3) -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = hgt
		cm.radial_segments = 16
		mi.mesh = cm
		mi.position = pos
		mi.rotation = rot
		mi.material_override = mats[mat]
		root.add_child(mi)
	# Body (warm electronics box) and deck
	add_box.call(Vector3(2.1, 0.55, 1.65), Vector3(0.0, 1.05, 0.0), "body")
	add_box.call(Vector3(2.2, 0.06, 1.75), Vector3(0.0, 1.35, 0.0), "body")
	# Wheels: 6 x 52.5 cm, rocker-bogie arms
	for wz in [-1.22, 1.22]:
		for wx in [1.15, 0.1, -1.05]:
			add_cyl.call(0.2625, 0.40, Vector3(wx, 0.2625, wz), "wheel", Vector3(PI / 2.0, 0.0, 0.0))
			add_cyl.call(0.12, 0.42, Vector3(wx, 0.2625, wz), "dark", Vector3(PI / 2.0, 0.0, 0.0))
		add_box.call(Vector3(1.4, 0.08, 0.08), Vector3(0.6, 0.62, wz * 0.95), "dark", Vector3(0.0, 0.0, -0.35))   # rocker
		add_box.call(Vector3(1.2, 0.08, 0.08), Vector3(-0.45, 0.5, wz * 0.95), "dark", Vector3(0.0, 0.0, 0.25))  # bogie
		add_box.call(Vector3(0.08, 0.45, 0.08), Vector3(1.15, 0.55, wz), "dark")
		add_box.call(Vector3(0.08, 0.35, 0.08), Vector3(-1.05, 0.48, wz), "dark")
	# Mast (Remote Sensing Mast), front-right, head at ~2.2 m
	add_cyl.call(0.06, 0.85, Vector3(0.85, 1.78, 0.55), "body", Vector3.ZERO)
	add_box.call(Vector3(0.28, 0.24, 0.55), Vector3(0.88, 2.25, 0.55), "body")
	for ez in [0.40, 0.70]:
		add_cyl.call(0.045, 0.06, Vector3(1.03, 2.25, ez), "glass", Vector3(0.0, 0.0, PI / 2.0))  # paired cameras
	add_cyl.call(0.07, 0.06, Vector3(1.03, 2.32, 0.55), "glass", Vector3(0.0, 0.0, PI / 2.0))     # laser/telescope eye
	# MMRTG power unit, angled up off the back, dark finned cylinder
	add_cyl.call(0.32, 0.66, Vector3(-1.35, 1.35, 0.0), "dark", Vector3(0.0, 0.0, deg_to_rad(-55.0)))
	for f in range(4):
		add_box.call(Vector3(0.03, 0.62, 0.78), Vector3(-1.35, 1.35, 0.0), "dark", Vector3(deg_to_rad(45.0 * f), 0.0, deg_to_rad(-55.0)))
	# High-gain antenna (hex dish) and UHF mast on the deck
	add_cyl.call(0.3, 0.05, Vector3(-0.55, 1.55, -0.5), "gold", Vector3(deg_to_rad(20.0), 0.0, 0.0))
	add_cyl.call(0.03, 0.35, Vector3(-0.2, 1.55, 0.6), "body", Vector3.ZERO)
	# Robotic arm, 2.1 m, folded across the front, turret with tools
	add_box.call(Vector3(0.09, 0.09, 1.1), Vector3(1.22, 0.95, 0.0), "body")
	add_box.call(Vector3(0.09, 0.09, 0.9), Vector3(1.32, 0.80, -0.1), "body")
	add_box.call(Vector3(0.3, 0.3, 0.35), Vector3(1.38, 0.78, -0.55), "dark")
	# Sample tubes / bit carousel at the front of the body
	add_cyl.call(0.22, 0.12, Vector3(1.08, 1.05, -0.45), "body", Vector3(0.0, 0.0, PI / 2.0))
	add_child(root)
	_shadow_list.append(Vector4(rx, rz, 1.6, 2.7))
	# Tracks: two ground-hugging strips from the rover back up the hill
	# toward you (it drove past you), sampled on the real ground.
	var tmat: StandardMaterial3D = StandardMaterial3D.new()
	tmat.albedo_color = Color(0.20, 0.13, 0.08, 0.5)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var back: Vector3 = -fwd
	back.y = 0.0
	back = back.normalized()
	var side_v: Vector3 = Vector3(-back.z, 0.0, back.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sd in [-1.22, 1.22]:
		var prev_a := Vector3.ZERO
		var prev_b := Vector3.ZERO
		for k in range(41):
			var c: Vector3 = Vector3(rx, 0.0, rz) + back * (1.2 + float(k) * 0.6) + side_v * sd
			var a: Vector3 = c - side_v * 0.2
			var b: Vector3 = c + side_v * 0.2
			a.y = ground_height(a.x, a.z) - h00 + 0.03
			b.y = ground_height(b.x, b.z) - h00 + 0.03
			if k > 0:
				for v in [prev_a, a, b, prev_a, b, prev_b]:
					st.add_vertex(v)
			prev_a = a
			prev_b = b
	var track := MeshInstance3D.new()
	track.mesh = st.commit()
	track.material_override = tmat
	track.name = "MarsTrack"
	add_child(track)
	# Footprints near you (yours), lying FLAT on the ground (vc181 fix:
	# they used to stand upright because of a 90 deg rotation).
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.20, 0.13, 0.08, 0.5)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for fi: int in range(16):
		var fx: float = -0.4 + float(fi % 2) * 0.8
		var fz: float = 2.0 + float(fi) * 0.35
		var fp: MeshInstance3D = MeshInstance3D.new()
		var fpm: PlaneMesh = PlaneMesh.new()
		fpm.size = Vector2(0.14, 0.30)
		fp.mesh = fpm
		fp.position = Vector3(fx, ground_height(fx, fz) - h00 + 0.03, fz)
		fp.material_override = fmat
		fp.name = "MarsFootprint"
		add_child(fp)

func _build_shadows() -> void:
	# vc181 cast shadows for rocks, boulders and the rover. The ground is
	# unshaded (for speed on Quest), so real shadow maps cannot land on it.
	# Instead each object gets a soft dark shape stretched AWAY from the
	# sun, length = height / tan(sun elevation), draped on the real ground
	# (5x5 grid sampled from ground_height). One mesh, one draw call.
	if _shadow_list.is_empty():
		return
	var sd: Vector3 = sun_direction()
	var el: float = max(asin(clamp(sd.y, -1.0, 1.0)), deg_to_rad(5.0))
	var away: Vector3 = Vector3(-sd.x, 0.0, -sd.z)
	if away.length() < 0.01:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	var perp: Vector3 = Vector3(-away.z, 0.0, away.x)
	var h00: float = ground_height(0.0, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s4: Vector4 in _shadow_list:
		var base := Vector3(s4.x, 0.0, s4.y)
		var length: float = min(s4.z / tan(el), 40.0)
		var width: float = s4.w
		var grid: Array = []
		for j in range(5):
			for i in range(5):
				var u: float = float(i) / 4.0
				var v: float = float(j) / 4.0
				var p: Vector3 = base + perp * (u - 0.5) * width + away * (v * length - width * 0.25)
				p.y = ground_height(p.x, p.z) - h00 + 0.04
				grid.append([p, Vector2(u, v)])
		for j in range(4):
			for i in range(4):
				var idx: Array = [j * 5 + i, j * 5 + i + 1, (j + 1) * 5 + i + 1, j * 5 + i, (j + 1) * 5 + i + 1, (j + 1) * 5 + i]
				for q in idx:
					st.set_uv(grid[q][1])
					st.add_vertex(grid[q][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled; uniform vec3 col; uniform float a; void fragment(){ vec2 p = vec2(UV.x * 2.0 - 1.0, UV.y * 1.6 - 0.3); float d = length(p * vec2(1.0, 0.85)); float tail = 1.0 - smoothstep(0.5, 1.0, UV.y); ALBEDO = col; ALPHA = a * (1.0 - smoothstep(0.45, 1.0, d)) * (0.55 + 0.45 * tail); }"
	mat.set_shader_parameter("col", Vector3(0.10, 0.06, 0.04) if _world_name == "Mars" else Vector3(0.02, 0.02, 0.02))
	mat.set_shader_parameter("a", 0.55 if _world_name == "Mars" else 0.8)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "RockShadows"
	add_child(mi)

func _build_sky() -> void:
	_sun_dir = sun_direction()
	var shader_code: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 horizon_color;
uniform vec3 mid_color;
uniform vec3 zenith_color;
uniform vec3 sun_dir;
uniform float sun_visible = 1.0;
uniform float sun_angular_rad = 0.0061;
uniform vec3 below_color = vec3(0.25, 0.15, 0.10);
varying vec3 v_world;
void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 dir = normalize(v_world - CAMERA_POSITION_WORLD);
	float elev = dir.y;
	vec3 col;
	if (elev >= 0.0) {
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.35, elev));
		col = mix(col, zenith_color, smoothstep(0.35, 1.0, elev));
	} else {
		col = mix(horizon_color, below_color, clamp(-elev * 3.0, 0.0, 1.0));
	}
	float sun_dot = max(dot(dir, sun_dir), 0.0);
	float halo = (pow(sun_dot, 600.0) * 0.9 + pow(sun_dot, 60.0) * 0.25) * sun_visible;
	vec3 sun_col = vec3(0.85, 0.92, 1.0);
	col = mix(col, sun_col, clamp(halo, 0.0, 1.0));
	// vc179 Phase 2 — pale bluish glow around the Sun, real Mars dust
	// scattering. Adapted to THIS sky shader: it has no LIGHT0/EYEDIR,
	// it has dir + sun_dir + sun_visible, so the glow uses sun_dot.
	// Sun disc itself stays small and pale (sun_angular_deg from env).
	col += vec3(0.78, 0.85, 0.95) * pow(sun_dot, 48.0) * 0.5 * sun_visible;
	float disc = smoothstep(cos(sun_angular_rad * 0.5 + 0.0002), cos(sun_angular_rad * 0.5 - 0.0002), sun_dot) * sun_visible;
	col = mix(col, vec3(0.95, 0.97, 1.0), disc);
	float haze = exp(-abs(elev) * 12.0);
	col = mix(col, horizon_color * 1.08, haze * 0.35);
	float d = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	col += (d - 0.5) / 255.0;
	ALBEDO = col;
}
"""
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = Shader.new()
	_sky_mat.shader.code = shader_code
	_sky_mat.set_shader_parameter("horizon_color", _sky_horizon)
	_sky_mat.set_shader_parameter("mid_color", _sky_mid)
	_sky_mat.set_shader_parameter("zenith_color", _sky_zenith)
	_sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	_sky_mat.set_shader_parameter("sun_visible", 1.0 if _sun_disc else 0.0)
	_sky_mat.set_shader_parameter("sun_angular_rad", deg_to_rad(_sun_angular_deg))
	# vc115 Moon: black below the horizon too, no brown band.
	_sky_mat.set_shader_parameter("below_color", Vector3(0.0, 0.0, 0.0) if (_is_moon or _world_kind == "ring_platform") else (Vector3(_sky_horizon.r, _sky_horizon.g, _sky_horizon.b) if _world_kind == "cloud_deck" else Vector3(0.25, 0.15, 0.10)))
	var sky: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	# vc181 FIX: the sky dome was 900 m away and is drawn without writing
	# depth, so it painted OVER every bit of ground farther than 900 m:
	# Mars' 1.5 km rings and mountain ring, the Moon's 9 km terrain, all
	# hidden. Dome now sits just inside the camera far plane.
	var _sky_r: float = 11400.0 if (_is_moon or _world_name == "Mars") else (24500.0 if _world_kind == "ring_platform" else 3800.0)
	sphere.radius = _sky_r
	sphere.height = _sky_r * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	sky.mesh = sphere
	sky.material_override = _sky_mat
	sky.position = Vector3(0.0, 1.7, 0.0)
	sky.name = "MarsSky"
	add_child(sky)
	# vc111: sky bodies (simple unshaded spheres at angular size) + star points.
	for sb in _sky_bodies:
		var sbd: Dictionary = sb
		var az: float = deg_to_rad(float(sbd.get("azimuth", 0.0)))
		var el: float = deg_to_rad(float(sbd.get("elevation", 20.0)))
		var dir: Vector3 = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
		var rad: float = 850.0 * tan(deg_to_rad(float(sbd.get("angular_size_deg", 2.0))) * 0.5)
		var sm: MeshInstance3D = MeshInstance3D.new()
		var ss: SphereMesh = SphereMesh.new()
		ss.radius = max(rad, 1.0)
		ss.height = max(rad, 1.0) * 2.0
		sm.mesh = ss
		if str(sbd.get("name", "")) == "Earth":  # vc158: Earth overhead on ANY travel world, photorealistic, not just Moon
			# vc115 Earth, lit from the sun side with a partial
			# phase: shader lambert against the Moon sun direction,
			# blue oceans + land/cloud noise on the lit side, very
			# dark (not pure black) on the night side. Fixed in the
			# sky: MarsWorld never rotates, so Earth does not move.
			var emat: ShaderMaterial = ShaderMaterial.new()
			emat.shader = Shader.new()
			emat.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 sun_dir;
uniform sampler2D earth_tex;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(h(i), h(i+vec2(1.,0.)), f.x), mix(h(i+vec2(0.,1.)), h(i+vec2(1.,1.)), f.x), f.y); }
varying vec3 v_nrm;
void vertex(){ v_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment(){
	vec3 nn = normalize(v_nrm);
	float lit = smoothstep(-0.05, 0.15, dot(nn, sun_dir));
	vec3 col = texture(earth_tex, UV).rgb;
	col *= 0.05 + lit * 0.95;
	ALBEDO = col;
}
"""
			emat.set_shader_parameter("sun_dir", sun_direction())
			# vc158: photo-real Earth — NASA Blue Marble Next Generation, public domain, credit NASA. Same 2k style as the other planets' photo textures, not a code-drawn shader Earth.
			var _earth_tex: Texture2D = load("res://data/textures/2k_earth.jpg")
			if _earth_tex != null:
				emat.set_shader_parameter("earth_tex", _earth_tex)
			sm.material_override = emat
		else:
			var smat: StandardMaterial3D = StandardMaterial3D.new()
			var scol: Color = sbd.get("color", Color(0.7, 0.8, 1.0))
			smat.albedo_color = scol
			smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			smat.emission_enabled = true
			smat.emission = scol
			smat.emission_energy_multiplier = 0.6
			sm.material_override = smat
		sm.position = dir * 850.0 + Vector3(0.0, 1.7, 0.0)
		sm.name = "SkyBody_" + str(sbd.get("name", "body"))
		add_child(sm)
	if _show_stars:
		var sverts: PackedVector3Array = PackedVector3Array()
		var rngs := RandomNumberGenerator.new()
		rngs.seed = 555
		var star_r: float = 11000.0 if (_is_moon or _world_name == "Mars") else (24000.0 if _world_kind == "ring_platform" else 3600.0)  # vc181: beyond the farthest terrain, inside camera far
		for si in range(1200):
			var th: float = rngs.randf_range(0.0, TAU)
			var ph: float = acos(rngs.randf_range(0.0, 1.0))
			sverts.append(Vector3(sin(ph) * cos(th), cos(ph), sin(ph) * sin(th)) * star_r + Vector3(0.0, 1.7, 0.0))
		var sarr: Array = []
		sarr.resize(Mesh.ARRAY_MAX)
		sarr[Mesh.ARRAY_VERTEX] = sverts
		var smesh: ArrayMesh = ArrayMesh.new()
		smesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, sarr)
		var stars: MeshInstance3D = MeshInstance3D.new()
		stars.mesh = smesh
		var stmat: ShaderMaterial = ShaderMaterial.new()
		stmat.shader = Shader.new()
		# vc179 Phase 4 — star_brightness from the .tres actually
		# drives the stars now (before, _star_brightness was stored
		# and never used). Moon 0.3, labelled simulated. Other
		# worlds have show_stars off, so this changes nothing for them.
		stmat.shader.code = "shader_type spatial; render_mode unshaded, depth_draw_never, fog_disabled; uniform float star_brightness = 1.0; void vertex() { POINT_SIZE = 2.5; } void fragment() { vec2 c = POINT_COORD - vec2(0.5); float a = smoothstep(0.5, 0.0, length(c)); ALBEDO = vec3(1.0) * star_brightness; ALPHA = a * star_brightness; }"
		stmat.set_shader_parameter("star_brightness", _star_brightness)
		stars.material_override = stmat
		stars.name = "WorldStars"
		add_child(stars)

func _build_light_and_dust() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.light_color = _sun_color
	light.light_energy = _sun_energy
	light.shadow_enabled = true
	light.directional_shadow_max_distance = _shadow_dist
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.look_at_from_position(_sun_dir * 100.0, Vector3.ZERO, Vector3.UP)
	light.name = "MarsSunLight"
	add_child(light)
	if _ambient_fill > 0.0:
		var fill: DirectionalLight3D = DirectionalLight3D.new()
		# vc179 Phase 2 — shadows tinted by the sky, not black, on Mars
		# only. There is no Environment node in this file to set
		# ambient_light_color on, so this uses the existing ambient
		# fill light instead, coloured by the Mars sky mid colour.
		# Moon keeps the neutral fill: its sky_mid is black, so the
		# Mars branch must not run for Moon.
		fill.light_color = _sky_mid if _world_name == "Mars" else (Color(0.7, 0.7, 0.7) if _is_moon else Color(0.7, 0.75, 0.85))
		fill.light_energy = _ambient_fill
		fill.shadow_enabled = false
		fill.rotation_degrees = Vector3(180.0, 0.0, 0.0)
		fill.name = "WorldFillLight"
		add_child(fill)
	# Dust: GPUParticles3D, slow particles in a 30 m box,
	# following the camera because MarsWorld follows the camera.
	# vc115: skipped when count is 0 (Moon is airless, no dust).
	# vc179 Phase 3 — Mars dust only, subtle: smaller, lower alpha,
	# slower, drifting in the same (0.8, 0.6) direction as the
	# megaripples. Other worlds keep the old dust settings, so
	# this change does not alter them. Dust is simulated.
	if _dust_count <= 0:
		return
	var dust: GPUParticles3D = GPUParticles3D.new()
	dust.amount = _dust_count
	dust.lifetime = 8.0
	dust.one_shot = false
	dust.explosiveness = 0.0
	var pp: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pp.emission_box_extents = Vector3(15.0, 5.0, 15.0)
	pp.direction = Vector3(0.8, 0.0, 0.6) if _world_name == "Mars" else Vector3(1.0, 0.0, 0.2)
	pp.spread = 20.0
	pp.initial_velocity_min = 0.1 if _world_name == "Mars" else 0.2
	pp.initial_velocity_max = 0.4 if _world_name == "Mars" else 0.8
	pp.gravity = Vector3.ZERO
	dust.process_material = pp
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.10, 0.10) if _world_name == "Mars" else Vector2(0.15, 0.15)
	dust.draw_pass_1 = quad
	var dmat: StandardMaterial3D = StandardMaterial3D.new()
	dmat.albedo_color = Color(0.85, 0.65, 0.45, 0.07) if _world_name == "Mars" else Color(0.85, 0.65, 0.45, 0.10)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dust.material_override = dmat
	dust.position = Vector3(0.0, 1.7, 0.0)
	dust.emitting = true
	dust.name = "MarsDust"
	add_child(dust)

func _build_ring_platform() -> void:
	# vc182 SATURN, user 2026-11-04: "you should be floating on its rings".
	# You float INSIDE the A ring, just outside the Cassini Division
	# (~125,000 km from Saturn's centre). Real facts used:
	#  - ring particles are water ice, from dust to house-sized chunks,
	#    many small and few big, all orbiting together (so they barely move
	#    relative to you);
	#  - the main rings are only ~10-100 m thick, so the ring is a thin,
	#    glittering sheet at eye level all the way round;
	#  - from here Saturn's globe is ~55 deg wide, its equator in the ring
	#    plane; ring structure (B ring, Cassini Division, A ring, Encke
	#    gap) uses real radii.
	# Chunk layout, chunk shapes and the ringlet pattern are simulated.
	# Scale for the far scene: 1 km real = 0.0859 m (Saturn radius 5,000 m).
	var eye: float = 1.6
	var sk: float = 5000.0 / 58232.0
	var my_r_km: float = 125000.0
	# Saturn: away from the Sun-ish so it is mostly lit, in the ring plane.
	var sflat := Vector3(_sun_dir.x, 0.0, _sun_dir.z)
	if sflat.length() < 0.01:
		sflat = Vector3(0, 0, 1)
	sflat = sflat.normalized()
	var sat_dir: Vector3 = sflat.rotated(Vector3.UP, deg_to_rad(110.0))
	var sat_c: Vector3 = sat_dir * (my_r_km * sk) + Vector3(0.0, eye, 0.0)
	# --- Saturn globe, lit by the Sun (banded texture, NASA/JPL-based map) ---
	var globe := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 5000.0
	gs.height = 10000.0 * 0.902  # real oblateness: polar radius 90% of equatorial
	gs.radial_segments = 96
	gs.rings = 48
	globe.mesh = gs
	var gmat := StandardMaterial3D.new()
	var tpath: String = "res://data/textures/4k_saturn.jpg" if ResourceLoader.exists("res://data/textures/4k_saturn.jpg") else "res://data/textures/2k_saturn.jpg"
	if ResourceLoader.exists(tpath):
		gmat.albedo_texture = load(tpath)
	else:
		gmat.albedo_color = Color(0.92, 0.84, 0.64)
	gmat.roughness = 1.0
	gmat.disable_fog = true
	globe.material_override = gmat
	globe.position = sat_c
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	globe.name = "SaturnGlobe"
	add_child(globe)
	# --- The ring sheet: annulus centred on Saturn, real radii, in the ring plane ---
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_in: float = 74500.0 * sk   # C ring inner edge
	var r_out: float = 136775.0 * sk # A ring outer edge
	var segs: int = 256
	for i in range(segs):
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var p := [Vector3(cos(a0) * r_in, 0, sin(a0) * r_in), Vector3(cos(a0) * r_out, 0, sin(a0) * r_out), Vector3(cos(a1) * r_out, 0, sin(a1) * r_out), Vector3(cos(a1) * r_in, 0, sin(a1) * r_in)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(p[k])
	var sheet := MeshInstance3D.new()
	sheet.mesh = st.commit()
	var smat := ShaderMaterial.new()
	smat.shader = Shader.new()
	smat.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform float km_per_m = 11.646;
uniform vec3 cam_pos_world;
varying vec3 v_local;
varying vec3 v_world;
float h(float x){ return fract(sin(x * 127.1) * 43758.5453); }
float vn(float x){ float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h(i), h(i + 1.0), f); }
void vertex(){ v_local = VERTEX; v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	float r = length(v_local.xz) * km_per_m;   // km from Saturn's centre
	float a = 0.0;
	vec3 c = vec3(0.86, 0.80, 0.70);
	if (r < 92000.0) { a = 0.18; c = vec3(0.62, 0.58, 0.54); }            // C ring, dim
	else if (r < 117580.0) { a = 0.85; c = vec3(0.93, 0.87, 0.76); }      // B ring, brightest
	else if (r < 122170.0) { a = 0.06; }                                   // Cassini Division
	else if (r < 133400.0 || r > 133740.0) { a = 0.6; c = vec3(0.88, 0.84, 0.78); } // A ring
	else { a = 0.0; }                                                      // Encke gap
	a *= 0.75 + 0.5 * (vn(r * 0.02) - 0.5) + 0.2 * (vn(r * 0.31) - 0.5);  // fine ringlets (simulated)
	// Near you the sheet fades out: up close the ring is the chunks themselves.
	float d = distance(CAMERA_POSITION_WORLD, v_world);
	a *= smoothstep(600.0, 2500.0, d) * 0.8;
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	smat.set_shader_parameter("km_per_m", 1.0 / sk)
	sheet.material_override = smat
	# Real ring is ~10-100 m thick and you are inside it: 4 thin layers a
	# few metres above/below you, so it reads as a glittering band at eye
	# level stretching round to Saturn, not a single invisible edge-on plane.
	sheet.position = Vector3(sat_c.x, eye - 18.0, sat_c.z)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.name = "SaturnRingSheet"
	add_child(sheet)
	for off in [-6.0, 6.0, 18.0]:
		var sh2 := MeshInstance3D.new()
		sh2.mesh = sheet.mesh
		sh2.material_override = smat
		sh2.position = Vector3(sat_c.x, eye + off, sat_c.z)
		sh2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sh2)
	# --- Ice chunks around you: lumpy, lit, many small, few big ---
	var bases: Array = []
	for bi in range(3):
		bases.append(_make_rock_base(700 + bi * 31))
	var rng := RandomNumberGenerator.new()
	rng.seed = 125000
	var ice_mat := StandardMaterial3D.new()
	ice_mat.vertex_color_use_as_albedo = true
	ice_mat.roughness = 0.55
	ice_mat.metallic = 0.0
	ice_mat.albedo_texture = _detail_texture()
	for bi in range(3):
		var mm := MultiMesh.new()
		mm.mesh = bases[bi]
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var n: int = 600
		mm.instance_count = n
		for ii in range(n):
			var dist: float = 4.0 + pow(rng.randf(), 1.3) * 420.0
			var ang: float = rng.randf_range(0.0, TAU)
			var size: float = 0.03 + pow(rng.randf(), 9.0) * 7.0       # power law: mostly pebbles, a few houses
			size = min(size, dist * 0.08)                              # nothing huge right in your face
			var y: float = eye + rng.randf_range(-14.0, 14.0) * clamp(dist / 90.0, 0.12, 1.0)
			var pos := Vector3(cos(ang) * dist, y, sin(ang) * dist)
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(size * rng.randf_range(0.7, 1.3), size * rng.randf_range(0.6, 1.1), size * rng.randf_range(0.7, 1.3)))
			mm.set_instance_transform(ii, Transform3D(b, pos))
			var w: float = rng.randf_range(0.82, 1.0)
			mm.set_instance_color(ii, Color(w, w * 0.97, w * 0.92))  # clean water ice, faint tan dust
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = ice_mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.name = "SaturnIce%d" % bi
		add_child(inst)
	# Far glitter: tiny bright points out to 2.5 km, thinning the ring into
	# the bright line at eye level. One draw call.
	var pv := PackedVector3Array()
	for k in range(4000):
		var d2: float = 300.0 + pow(rng.randf(), 0.6) * 2400.0
		var a2: float = rng.randf_range(0.0, TAU)
		pv.append(Vector3(cos(a2) * d2, eye + rng.randf_range(-4.0, 4.0), sin(a2) * d2))
	var parr: Array = []
	parr.resize(Mesh.ARRAY_MAX)
	parr[Mesh.ARRAY_VERTEX] = pv
	var pm := ArrayMesh.new()
	pm.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, parr)
	var pts := MeshInstance3D.new()
	pts.mesh = pm
	var ptm := ShaderMaterial.new()
	ptm.shader = Shader.new()
	ptm.shader.code = "shader_type spatial; render_mode unshaded, depth_draw_never, fog_disabled; void vertex(){ POINT_SIZE = 2.0; } void fragment(){ ALBEDO = vec3(0.95, 0.93, 0.88); ALPHA = 0.8; }"
	pts.material_override = ptm
	pts.name = "SaturnRingGlitter"
	add_child(pts)

func _build_sun_surface() -> void:
	# vc182 SUN "land of lava and fire", user 2026-11-04.
	# HONEST NOTE: the Sun has NO solid surface. This is an artistic
	# visualization of standing on the photosphere: real features are
	# granulation (boiling convection cells), sunspots' dark umbra, spicules
	# (jets of plasma), prominences (huge glowing arches of plasma) and a
	# dark-red chromosphere/corona glow above. Sizes are shrunk a lot so
	# they fit around you (real granules are ~1,000 km across).
	var eye: float = 0.0
	# --- Ground: the boiling photosphere, gentle swells, 6 km across ---
	var n: int = 121
	var half: float = 3000.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for j in range(n):
		for i in range(n):
			var u: float = float(i) / float(n - 1) * 2.0 - 1.0
			var v: float = float(j) / float(n - 1) * 2.0 - 1.0
			# denser near the centre: square the radius
			var x: float = sign(u) * u * u * half
			var z: float = sign(v) * v * v * half
			var y: float = 1.2 * sin(x * 0.02) * cos(z * 0.017) + 4.0 * sin(x * 0.003 + 1.0) * cos(z * 0.0025) - 4.0 * sin(1.0)  # feet on the surface at the spawn
			pts.append(Vector3(x, y, z))
	for j in range(n - 1):
		for i in range(n - 1):
			var a: int = j * n + i
			for k in [a, a + n, a + 1, a + 1, a + n, a + n + 1]:
				st.add_vertex(pts[k])
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	var gm := ShaderMaterial.new()
	gm.shader = Shader.new()
	gm.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
varying vec3 v_wp;
vec2 hash2(vec2 p){ p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))); return fract(sin(p) * 43758.5453); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x; float b = hash2(i + vec2(1, 0)).x; float c = hash2(i + vec2(0, 1)).x; float d = hash2(i + vec2(1, 1)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); }
// Voronoi: distance to nearest cell centre and to the border (lanes)
vec2 cells(vec2 p, float t){
	vec2 i = floor(p); vec2 f = fract(p); float d1 = 8.0; float d2 = 8.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = hash2(i + g); o = 0.5 + 0.4 * sin(t * 0.35 + 6.2831 * o);
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; } }
	return vec2(d1, d2 - d1); }
void vertex(){ v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	float t = TIME;
	vec2 p = v_wp.xz;
	float dist = length(p - CAMERA_POSITION_WORLD.xz);
	// granules ~6 m near you, plus big supergranule brightness swells
	vec2 g = cells(p / 3.0 + vec2(vn(p * 0.05 + t * 0.02), vn(p * 0.05 - t * 0.02)) * 0.6, t);
	vec2 g2 = cells(p / 0.9 + 17.0, t * 1.6);
	float lane = smoothstep(0.02, 0.22, g.y);               // 0 in dark lanes, 1 in hot cell centres
	float centre = 1.0 - smoothstep(0.0, 0.6, g.x);
	float big = vn(p * 0.004 + t * 0.003);
	float heat = clamp(lane * (0.55 + 0.45 * centre) * (0.75 + 0.5 * big), 0.0, 1.2);
	heat *= mix(0.8, 1.1, smoothstep(0.0, 0.15, g2.y)) * mix(1.0, 0.9, smoothstep(40.0, 0.0, dist) * 0.0) ;  // fine boiling texture inside each cell
	// far away the cells blur into a bright glowing plain
	heat = mix(heat, 0.8, smoothstep(150.0, 900.0, dist));
	vec3 deep = vec3(0.35, 0.04, 0.0);
	vec3 mid = vec3(1.0, 0.33, 0.02);
	vec3 hot = vec3(1.0, 0.78, 0.30);
	vec3 white = vec3(1.0, 0.95, 0.80);
	vec3 col = mix(deep, mid, smoothstep(0.0, 0.5, heat));
	col = mix(col, hot, smoothstep(0.5, 0.9, heat));
	col = mix(col, white, smoothstep(0.95, 1.2, heat));
	// sunspot: one dark umbra/penumbra region out on the plain
	float sd = length(p - vec2(420.0, -650.0));
	float umbra = 1.0 - smoothstep(60.0, 90.0, sd);
	float pen = 1.0 - smoothstep(90.0, 170.0, sd);
	col = mix(col, col * 0.45, pen * 0.8);
	col = mix(col, vec3(0.12, 0.02, 0.0), umbra);
	// glowing haze toward the horizon
	col = mix(col, vec3(1.0, 0.55, 0.2), smoothstep(800.0, 3000.0, dist) * 0.6);
	ALBEDO = col;
}
"""
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.name = "SunPhotosphere"
	add_child(ground)
	# --- Spicules: thin jets of glowing plasma, like flames, all around ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 1919
	var flame := ShaderMaterial.new()
	flame.shader = Shader.new()
	flame.shader.code = "shader_type spatial; render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled; varying float vy; varying float ph; void vertex(){ vy = UV.y; ph = INSTANCE_CUSTOM.x; VERTEX.x += sin(TIME * 1.7 + ph * 6.28 + VERTEX.y * 0.25) * 0.25 * (1.0 - UV.y); } void fragment(){ float tip = smoothstep(0.0, 0.9, 1.0 - vy); float edge = 1.0 - abs(UV.x * 2.0 - 1.0); float flick = 0.7 + 0.3 * sin(TIME * 9.0 + ph * 40.0); ALBEDO = mix(vec3(1.0, 0.25, 0.02), vec3(1.0, 0.85, 0.45), tip * edge) * flick; ALPHA = 1.0; }"
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	qm.center_offset = Vector3(0.0, 0.5, 0.0)
	var mm := MultiMesh.new()
	mm.mesh = qm
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = 900
	for ii in range(900):
		var d: float = 4.0 + pow(rng.randf(), 1.5) * 600.0
		var a: float = rng.randf_range(0.0, TAU)
		var hgt: float = rng.randf_range(1.5, 6.0) * (1.0 + d / 80.0)
		var wid: float = hgt * rng.randf_range(0.06, 0.15)
		var pos := Vector3(cos(a) * d, -0.4, sin(a) * d)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wid, hgt, 1.0))
		b = Basis(Vector3(1, 0, 0), rng.randf_range(-0.25, 0.25)) * b
		mm.set_instance_transform(ii, Transform3D(b, pos))
		mm.set_instance_custom_data(ii, Color(rng.randf(), 0, 0, 0))
	var sp := MultiMeshInstance3D.new()
	sp.multimesh = mm
	sp.material_override = flame
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.name = "SunSpicules"
	add_child(sp)
	# --- Prominences: giant arches of glowing plasma rising off the surface ---
	var pmat := ShaderMaterial.new()
	pmat.shader = Shader.new()
	pmat.shader.code = "shader_type spatial; render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled; varying vec3 v_l; void vertex(){ v_l = VERTEX; } void fragment(){ float f = 0.6 + 0.4 * sin(TIME * 0.8 + v_l.x * 0.02 + v_l.y * 0.03); float fil = 0.5 + 0.5 * sin(v_l.x * 0.09 + v_l.z * 0.11 + TIME * 1.3); ALBEDO = mix(vec3(1.0, 0.18, 0.05), vec3(1.0, 0.55, 0.25), fil) * f * 0.8; ALPHA = 1.0; }"
	for k in range(7):
		var d: float = rng.randf_range(350.0, 2400.0)
		var a: float = rng.randf_range(0.0, TAU)
		var radius: float = rng.randf_range(60.0, 260.0) * (d / 900.0 + 0.4)
		var tor := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = radius
		tm.outer_radius = radius + radius * rng.randf_range(0.07, 0.16)
		tm.rings = 48
		tm.ring_segments = 8
		tor.mesh = tm
		tor.material_override = pmat
		tor.position = Vector3(cos(a) * d, -radius * 0.25, sin(a) * d)
		tor.rotation = Vector3(PI / 2.0, a + rng.randf_range(-0.6, 0.6), 0.0)  # stand the ring up: an arch
		tor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tor.name = "SunProminence"
		add_child(tor)
	# --- Glow overhead: bright haze near the "horizon", dark red higher up ---
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 3500.0  # inside the world sky sphere (3800), else it hides this glow
	dm.height = 7000.0
	dome.mesh = dm
	var dmat := ShaderMaterial.new()
	dmat.shader = Shader.new()
	dmat.shader.code = "shader_type spatial; render_mode unshaded, cull_front, depth_draw_never, fog_disabled; varying vec3 v_d; void vertex(){ v_d = normalize(VERTEX); } void fragment(){ float e = v_d.y; vec3 c = mix(vec3(1.0, 0.55, 0.18), vec3(0.45, 0.06, 0.02), smoothstep(0.0, 0.35, e)); c = mix(c, vec3(0.08, 0.01, 0.0), smoothstep(0.35, 0.9, e)); float streak = pow(0.5 + 0.5 * sin(atan(v_d.z, v_d.x) * 23.0 + TIME * 0.05), 8.0) * smoothstep(0.1, 0.6, e) * 0.08; ALBEDO = c + vec3(1.0, 0.6, 0.3) * streak; }"
	dome.material_override = dmat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.name = "SunChromosphere"
	add_child(dome)
	var _wsky: Node = get_node_or_null("MarsSky")
	if _wsky != null:
		(_wsky as Node3D).visible = false  # the glow dome IS the sky here

func _build_cloud_deck() -> void:
	# vc157 gas giants (Jupiter, Uranus, Neptune), user 2026-11-02:
	# floors still see-through, planets still Mars copycats.
	# Old path was a tiny 4 m cloud disc + a see-through travel
	# deck (alpha 0.92) + a "visualization, no solid surface" label
	# floating in view — that is why the floor looked see-through
	# and fake. New path: a solid, opaque cloud deck at foot level,
	# 150 m across, banded in the planet's own colours (Jupiter tan/
	# brown, Uranus pale cyan, Neptune deep blue), no rocks, no
	# label, no see-through deck. The deck is an imagined standing
	# place — gas giants have no solid surface in reality — and the
	# travel panel must say that honestly, not pretend it is ground.
	var bands: Array = [
		[150.0, -0.5, _sky_zenith],
		[110.0, -0.4, _sky_mid],
		[75.0, -0.3, _ground_dust],
		[45.0, -0.2, _sky_horizon],
		[18.0, 0.0, _ground_basalt],
	]
	for b in bands:
		var disc: MeshInstance3D = MeshInstance3D.new()
		var cm: CylinderMesh = CylinderMesh.new()
		cm.top_radius = float(b[0])
		cm.bottom_radius = float(b[0])
		cm.height = 0.4
		disc.mesh = cm
		disc.position = Vector3(0.0, float(b[1]) - 0.2, 0.0)
		var dmat: StandardMaterial3D = StandardMaterial3D.new()
		dmat.albedo_color = b[2]
		dmat.roughness = 0.9
		dmat.metallic = 0.0
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc.material_override = dmat
		disc.name = "CloudDeckBand"
		add_child(disc)

func _build_platform() -> void:
	# vc111: cloud-top platform, no solid surface. Label is honest.
	var plat: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 4.0
	cm.bottom_radius = 4.0
	cm.height = 0.4
	plat.mesh = cm
	plat.position = Vector3(0.0, -1.6, 0.0)
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.7, 0.7, 0.75)
	pmat.roughness = 0.8
	plat.material_override = pmat
	plat.name = "CloudPlatform"
	add_child(plat)
	for li in range(3):
		var cloud: MeshInstance3D = MeshInstance3D.new()
		var pm: PlaneMesh = PlaneMesh.new()
		pm.size = Vector2(600.0, 600.0)
		cloud.mesh = pm
		cloud.rotation.x = -PI / 2.0
		cloud.position = Vector3(0.0, -4.0 - float(li) * 12.0, 0.0)
		var cmat: ShaderMaterial = ShaderMaterial.new()
		cmat.shader = Shader.new()
		cmat.shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, fog_disabled; uniform vec3 c1; uniform vec3 c2; uniform float off; float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); } float n(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(h(i), h(i+vec2(1.,0.)), f.x), mix(h(i+vec2(0.,1.)), h(i+vec2(1.,1.)), f.x), f.y); } void fragment(){ float band = sin(UV.y * 24.0 + n(UV * 6.0 + off) * 4.0) * 0.5 + 0.5; vec3 col = mix(c1, c2, band); ALBEDO = col; ALPHA = 0.95; }"
		cmat.set_shader_parameter("c1", _sky_horizon)
		cmat.set_shader_parameter("c2", _sky_zenith)
		cmat.set_shader_parameter("off", float(li) * 3.7)
		cloud.material_override = cmat
		cloud.name = "CloudLayer%d" % li
		add_child(cloud)
	var lbl: Label3D = Label3D.new()
	lbl.text = "visualization, no solid surface"
	lbl.font_size = 48
	lbl.pixel_size = 0.005
	lbl.position = Vector3(0.0, 1.0, -6.0)
	lbl.name = "PlatformLabel"
	lbl.visible = false  # vc182: no words in travel worlds
	add_child(lbl)

func _build_distant_body(body_color: Color, radius_m: float, granulation: bool) -> void:
	var s: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = radius_m
	sm.height = radius_m * 2.0
	s.mesh = sm
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = Shader.new()
	if granulation:
		mat.shader.code = "shader_type spatial; render_mode unshaded, fog_disabled; uniform vec3 col; float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); } float n(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(h(i), h(i+vec2(1.,0.)), f.x), mix(h(i+vec2(0.,1.)), h(i+vec2(1.,1.)), f.x), f.y); } void fragment(){ float g = n(UV * 40.0 + TIME * 0.05) * 0.5 + n(UV * 8.0) * 0.5; float spot = step(0.92, n(UV * 12.0 + 7.0)) * 0.8; vec3 c = col * (0.7 + g * 0.6); c = mix(c, vec3(0.05), spot); ALBEDO = c; }"
	else:
		mat.shader.code = "shader_type spatial; render_mode unshaded, fog_disabled; uniform vec3 col; void fragment(){ ALBEDO = col; }"
	mat.set_shader_parameter("col", body_color)
	s.material_override = mat
	s.position = Vector3(0.0, 20.0, -400.0)
	s.name = "DistantBody"
	add_child(s)
	var glow: MeshInstance3D = MeshInstance3D.new()
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(radius_m * 4.0, radius_m * 4.0)
	glow.mesh = qm
	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.albedo_color = Color(body_color.r, body_color.g, body_color.b, 0.35)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.material_override = gmat
	glow.position = s.position
	glow.name = "BodyGlow"
	add_child(glow)

func _set_camera_far(far_m: float) -> void:
	# MarsWorld is PlanetsCore/MarsWorld, so the camera is two
	# levels up: ../../XROrigin/XRCamera. Guarded: no-op headless.
	var cam: Node = get_node_or_null("../../XROrigin/XRCamera")
	if cam != null and cam is Camera3D:
		(cam as Camera3D).far = far_m

func activate() -> void:
	if not _built:
		_init_noises()
		if _is_moon:
			# vc115: 9 km terrain needs a far plane beyond it
			# (default Camera3D far is 4000). Restored on deactivate.
			_set_camera_far(12000.0)
		elif _world_name == "Mars":
			# vc179 Phase 1 B4: far ground corners reach ~5.7 km, so
			# Mars travel needs far >= 6000. Restored on deactivate.
			# Main passthrough sky is untouched — this only runs in
			# activate(), i.e. during travel.
			_set_camera_far(12000.0)  # vc181: terrain to 10 km from the hilltop
		if _world_kind == "ring_platform":
			_set_camera_far(26000.0)  # vc182: Saturn 10.7 km away, ring sheet beyond
		elif _world_kind == "sun_surface":
			_set_camera_far(8000.0)
		_build_sky()
		if _world_kind == "sun_surface":
			_build_sun_surface()
			_build_light_and_dust()
		elif _world_kind == "ring_platform":
			_build_ring_platform()
			_build_light_and_dust()
		elif _world_kind == "cloud_deck":
			_build_cloud_deck()
			_build_light_and_dust()
		elif _world_kind == "cloud_platform":
			_build_platform()
			_build_light_and_dust()
		elif _world_kind == "distant_sun":
			_build_distant_body(_sun_color, 60.0, true)
			_build_light_and_dust()
		elif _world_kind == "star":
			_build_distant_body(_sun_color, max(20.0, _sun_angular_deg * 10.0), false)
			_build_light_and_dust()
		else:
			_build_terrain()
			if _is_moon:
				# vc115 Moon: no rocks, no rover — footprints/tracks only.
				_build_moon_footprints()
			else:
				_build_rocks()
			if _is_moon:
				pass  # vc115 Moon: no rover, footprints/tracks only (above).
			elif _world_name == "Mars" and not _has_lake and not _has_lava:
				_build_rover()
			if not _is_moon:
				_build_shadows()
			elif not _has_lake and not _has_lava:
				pass  # vc157: rover + footprints + tracks are Mars only — Mercury/Venus must not look like Mars copycats
			else:
				# Lake/lava worlds: rover placeholder replaced by a flat shiny/emissive plane in the distance.
				var plane: MeshInstance3D = MeshInstance3D.new()
				var pm2: PlaneMesh = PlaneMesh.new()
				pm2.size = Vector2(120.0, 60.0)
				plane.mesh = pm2
				plane.rotation.x = -PI / 2.0
				plane.position = Vector3(0.0, ground_height(0.0, 120.0) + 0.2, 120.0)
				var lmat: StandardMaterial3D = StandardMaterial3D.new()
				if _has_lava:
					lmat.albedo_color = Color(1.0, 0.4, 0.05)
					lmat.emission_enabled = true
					lmat.emission = Color(1.0, 0.35, 0.05)
					lmat.emission_energy_multiplier = 2.0
				else:
					lmat.albedo_color = Color(0.4, 0.5, 0.6)
					lmat.metallic = 0.8
					lmat.roughness = 0.15
				plane.material_override = lmat
				plane.name = "LakeOrLava"
				add_child(plane)
			_build_light_and_dust()
		_built = true
	visible = true

func deactivate() -> void:
	# vc115: restore the default far plane after a Moon visit.
	_set_camera_far(4000.0)
	visible = false
