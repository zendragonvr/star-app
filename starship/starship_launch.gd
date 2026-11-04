# Starship-style launch, Star Bridge feature, phases 1-7.
# Work lives only in starship/ plus minimum hooks in main.gd.
# Solar system, sky, face, ride, pinch system and teacher are NOT changed here.
# Passthrough stays on. No SpaceX logos, lettering or branding anywhere.
# No camera shake, no artificial camera motion, the user stands still.
# No glow/bloom: glow is faked with additive sprites. No recorded audio,
# no TTS, no AI models in this feature. All sounds are synthesized here.
# Unofficial; not affiliated with SpaceX. Starship is a trademark of its owner.
# Phase 1: true-size static stack, hand placement, 150-500 m, default 250 m.
# Phase 2-5: Highlights (150 s total, catch at 150 s) and Real-time (catch at 420 s),
# hand-authored keyframe path, hot staging, boostback, return, tower catch.
# Phase 6: procedural AudioStreamWAV sounds, delayed by distance / 343 m/s.
# Phase 7: minimal TRAVEL-style UI, Reduce effects, Indoor 1:10 demo mode.
# NOT headset-tested: frame rate and test video need a headset run by the user.
extends Node3D

const STACK_H: float = 121.3
const STACK_W: float = 9.0
const BOOSTER_H: float = 70.0
const SHIP_H: float = 51.3
const MIN_DIST: float = 150.0
const MAX_DIST: float = 500.0
const DEFAULT_DIST: float = 200.0  # vc165: default 200 m, stack fills about 34 deg
# vc183 (user 2026-11-04): outdoors the whole launch is shown 10x real size
# (stack 1.2 km tall instead of 121 m), placed ~900 m away so it towers over
# you. NOT real size any more - the info label says so. Indoor stays 1:10.
const SIZE_MULT: float = 10.0
const BIG_DEFAULT_DIST: float = 900.0
const BIG_MIN_DIST: float = 400.0
const BIG_MAX_DIST: float = 3000.0
const INDOOR_DIST: float = 8.0

var _camera: Node3D = null
var mode: String = "off"
var highlights: bool = true
var reduce_effects: bool = false
var muted: bool = false
var indoor: bool = false
var _scale: float = 1.0
var _pad: Vector3 = Vector3.ZERO
var _place_dist: float = 200.0
var _ground_nudge: float = 0.0
var _last_drag: float = 0.0
var _beam: Node3D = null
var _soot: Node3D = null
var _surround: Node3D = null
var _downrange: Vector3 = Vector3(1.0, 0.0, 0.0)
var _tower_pos: Vector3 = Vector3.ZERO
var _catch_pos: Vector3 = Vector3.ZERO
var _sim: float = 0.0
var _count: float = 0.0
var _launching: bool = false
var _caught: bool = false
var _hold_t: float = 0.0
var _pending_sounds: Array = []
var _rumble_player: AudioStreamPlayer = null
var _crackle_player: AudioStreamPlayer = null
var _fade_players: Array = []
var _sounds: Dictionary = {}
var _players: Array = []

var _marker: Node3D = null
var _tower: Node3D = null
var _mount: Node3D = null
var _booster: Node3D = null
var _ship: Node3D = null
var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _flame_b: Node3D = null
var _flame_s: Node3D = null
var _glow_b: Sprite3D = null
var _glow_s: Sprite3D = null
var _steam: GPUParticles3D = null
var _trail: Node3D = null
var _figure: Node3D = null
var _info: Label3D = null
var _info_t: float = 0.0
var _clock: Label3D = null
var _buttons: Dictionary = {}

func set_camera(cam: Node3D) -> void:
	_camera = cam

func is_active() -> bool:
	return mode != "off"

func is_placing() -> bool:
	return mode == "placing"

func start_placing() -> void:
	mode = "placing"
	if _tower != null:
		_tower.visible = true
	if _mount != null:
		_mount.visible = true
	if _booster != null:
		_booster.visible = true
	if _ship != null:
		_ship.visible = true
	if _beam != null:
		_beam.visible = true
	for _c in get_children():
		if _c is DirectionalLight3D:
			_c.visible = true
	if _surround != null:
		_surround.visible = true
	_place_dist = INDOOR_DIST if indoor else BIG_DEFAULT_DIST
	_ground_nudge = 0.0
	_show_info("Look at the real ground where it should stand, then pinch to place it.\nPinch and drag toward or away from you to move it nearer or farther.")
	_scale = 0.1 if indoor else SIZE_MULT
	_set_far(true)
	_build_all()
	_show_buttons(["PLACE", "INDOOR", "UP", "DOWN", "RESET"])
	_update_marker()

# vc181 REAL SUN: main.gd feeds the true Sun direction (with Sky Sync yaw)
# once a second, so the stack is lit from the real Sun and its shadow on the
# real ground points the same way as real shadows. Night: no shadow.
var sun_dir: Vector3 = Vector3(0.4, 0.6, 0.3).normalized()
var _sunlight_node: DirectionalLight3D = null

func set_sun_dir(d: Vector3) -> void:
	sun_dir = d.normalized()
	_apply_sun()

func _apply_sun() -> void:
	if _sunlight_node == null:
		return
	var up_hint: Vector3 = Vector3.UP if abs(sun_dir.y) < 0.98 else Vector3.FORWARD
	# A DirectionalLight shines along its -Z, i.e. FROM the Sun toward the ground.
	_sunlight_node.global_transform = Transform3D(Basis.looking_at(-sun_dir, up_hint), _sunlight_node.global_position)
	var day: bool = sun_dir.y > 0.02
	# vc181: shadow maps OFF. The see-through shadow catcher (shadow_to_opacity)
	# does not draw in GL Compatibility (tested), so the shadow pass only cost
	# frame time. Drawn ground shadows below replace it.
	_sunlight_node.shadow_enabled = false
	_sunlight_node.light_energy = 1.2 if day else 0.25
	_sunlight_node.light_color = Color(1.0, 0.95, 0.85) if sun_dir.y > 0.17 else (Color(1.0, 0.75, 0.5) if day else Color(0.6, 0.7, 0.9))

var _mat_steel: StandardMaterial3D = null
var _mat_dark: StandardMaterial3D = null
var _mat_tiles: StandardMaterial3D = null

func _steel() -> StandardMaterial3D:
	if _mat_steel != null:
		return _mat_steel
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = Color(0.78, 0.80, 0.84)
	m.metallic = 0.7
	m.roughness = 0.35
	_mat_steel = m
	return m

func _dark() -> StandardMaterial3D:
	if _mat_dark != null:
		return _mat_dark
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = Color(0.25, 0.26, 0.28)
	m.metallic = 0.4
	m.roughness = 0.6
	_mat_dark = m
	return m

func _tile_material() -> StandardMaterial3D:
	if _mat_tiles != null:
		return _mat_tiles
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in range(256):
		for x in range(256):
			var v: float = 0.05 + rng.randf() * 0.12
			if rng.randf() < 0.02:
				v = 0.5
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	var tex := ImageTexture.new()
	tex.set_image(img)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = Color(0.12, 0.12, 0.13)
	m.albedo_texture = tex
	m.metallic = 0.3
	m.roughness = 0.8
	_mat_tiles = m
	return m

func _additive(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	return m

func _glow_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var dx: float = (float(x) - 64.0) / 64.0
			var dy: float = (float(y) - 64.0) / 64.0
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 0.85, 0.6, a))
	var tex := ImageTexture.new()
	tex.set_image(img)
	return tex

func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, y: float, mat: Material) -> Node3D:
	var n := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	# vc180: radial 64 -> 32 halves cylinder cost. rings stays 1 (0 is not a valid ring count here).
	mesh.radial_segments = 32
	mesh.rings = 1
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	n.mesh = mesh
	n.material_override = mat
	n.position = Vector3(0.0, y, 0.0)
	parent.add_child(n)
	return n

func _box(parent: Node3D, sx: float, sy: float, sz: float, pos: Vector3, mat: Material) -> Node3D:
	var n := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(sx, sy, sz)
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)
	return n

func _build_all() -> void:
	if _tower != null:
		return
	var s: float = _scale
	# Marker: ring on the floor plane, follows aim during placement.
	_marker = Node3D.new()
	var ring := MeshInstance3D.new()
	var tmesh := TorusMesh.new()
	tmesh.inner_radius = 9.0 * s
	tmesh.outer_radius = 11.0 * s
	ring.mesh = tmesh
	ring.material_override = _additive(Color(0.2, 1.0, 0.4), 0.8)
	ring.rotation.x = deg_to_rad(90.0)
	_marker.add_child(ring)
	add_child(_marker)
	# vc165 tower: 145 m square steel lattice, 4 corner columns + platforms, not a solid box. Beam at 3/4 height (109 m) is separate, below.
	_tower = Node3D.new()
	for _cx in [-4.0, 4.0]:
		for _cz in [-4.0, 4.0]:
			_box(_tower, 1.0 * s, 145.0 * s, 1.0 * s, Vector3(_cx * s, 72.5 * s, _cz * s), _dark())
	for _py in [20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 140.0]:
		_box(_tower, 10.0 * s, 1.0 * s, 10.0 * s, Vector3(0.0, _py * s, 0.0), _dark())
	add_child(_tower)
	# vc180 catch: TWO parallel beams, not one centred beam. The old single beam ran straight
	# through the booster centre at the catch (a skewer, not a catch). Two beams at local
	# z = +/-5.5 m straddle the 9 m body, so the grid fins rest on them. No pincer swing:
	# the beams are fixed, level, and do not close. +2 draw calls.
	_beam = Node3D.new()
	for _bz in [-5.5, 5.5]:
		_box(_beam, 20.0 * s, 2.0 * s, 2.0 * s, Vector3(10.0 * s, 0.0, _bz * s), _dark())
		_box(_beam, 20.0 * s, 0.5 * s, 0.5 * s, Vector3(10.0 * s, 1.5 * s, _bz * s), _dark())
	add_child(_beam)
	# vc165 lighting: warm directional sun by default (no SkyAlign node in main, so no calibrated sun direction to read). Floodlight glow sprites on tower.
	var _sunlight := DirectionalLight3D.new()
	_sunlight.light_energy = 1.2
	_sunlight.light_color = Color(1.0, 0.9, 0.7)
	_sunlight.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(45.0), 0.0)
	# vc180 Scale: real ground shadow is the strongest anchor in passthrough.
	# UNPROVEN on Quest GL Compatibility: shadow_to_opacity must be headset-tested.
	# Fixed sun angle (-35, 45) is NOT the real Sun, so on a sunny day this shadow
	# will point a different way than real shadows. If it looks wrong, turn shadows off.
	_sunlight.shadow_enabled = true
	_sunlight.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sunlight.directional_shadow_max_distance = 1400.0 * s  # vc181: low Sun = shadows up to ~700 m long
	add_child(_sunlight)
	_sunlight_node = _sunlight
	_apply_sun()
	# vc165: old two-arm pivots removed, replaced by single beam above.
	# vc165 launch mount: about 20 m tall, ring deck on about six thick cylindrical legs that touch the ground. Booster base is about 20 m above ground.
	_mount = Node3D.new()
	for _li in range(6):
		var _la: float = float(_li) * 60.0 * PI / 180.0
		_cyl(_mount, 1.8 * s, 1.8 * s, 20.0 * s, 10.0 * s, _dark()).position = Vector3(cos(_la) * 9.0 * s, 10.0 * s, sin(_la) * 9.0 * s)
	_cyl(_mount, 12.0 * s, 12.0 * s, 2.0 * s, 19.0 * s, _dark())
	add_child(_mount)
	# vc164 ground anchor: opaque concrete pad disc, so the stack visibly sits on the ground, not floating. Tower base is on the same disc in _set_rest_positions via _pad.
	var _pad_disc := MeshInstance3D.new()
	var _dmesh := CylinderMesh.new()
	_dmesh.top_radius = 30.0 * s
	_dmesh.bottom_radius = 30.0 * s
	_dmesh.height = 1.0 * s
	_pad_disc.mesh = _dmesh
	_pad_disc.material_override = _dark()
	_pad_disc.position = Vector3(0.0, 0.5 * s, 0.0)
	_mount.add_child(_pad_disc)
	# vc180: shadow catcher plane, invisible except where shadow falls, so the shadow
	# lands on the real ground. 1 draw call + a shadow pass (roughly doubles stack draws).
	var _shadow_catch := MeshInstance3D.new()
	var _scm := PlaneMesh.new()
	_scm.size = Vector2(1600.0 * s, 1600.0 * s)  # vc181: room for a long low-Sun shadow
	_shadow_catch.mesh = _scm
	var _scmat := StandardMaterial3D.new()
	_scmat.shadow_to_opacity = true
	_scmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scmat.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	_scmat.roughness = 1.0
	_shadow_catch.material_override = _scmat
	_shadow_catch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_catch.position = Vector3(0.0, 0.02 * s, 0.0)
	_shadow_catch.visible = false  # vc181: does not render in GL Compatibility, replaced by _shadows
	_mount.add_child(_shadow_catch)
	_build_shadows()
	# Booster: 70 m cylinder, 9 m wide, grid fins at top.
	_booster = Node3D.new()
	# vc180: steel tone bands, simulated, 0 tris / 0 extra draws. 4 wide x 64 tall image,
	# each row (height) a random brightness 0.92-1.08, so bands run horizontally around the cylinder.
	# If bands come out vertical, swap image width/height.
	var _band_img := Image.create(4, 64, false, Image.FORMAT_RGBA8)
	var _band_rng := RandomNumberGenerator.new()
	_band_rng.seed = 1234
	for _by in range(64):
		var _bv: float = _band_rng.randf_range(0.92, 1.08)
		for _bx in range(4):
			_band_img.set_pixel(_bx, _by, Color(_bv, _bv, _bv, 1.0))
	var _band_tex := ImageTexture.new()
	_band_tex.set_image(_band_img)
	var _band_mat := StandardMaterial3D.new()
	_band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_band_mat.albedo_color = Color(0.78, 0.80, 0.84)
	_band_mat.albedo_texture = _band_tex
	_band_mat.metallic = 0.7
	_band_mat.roughness = 0.35
	_cyl(_booster, 4.5 * s, 4.5 * s, BOOSTER_H * s, 0.0, _band_mat)
	_box(_booster, 3.0 * s, 4.0 * s, 0.5 * s, Vector3(0.0, 32.0 * s, 4.5 * s), _dark())
	_box(_booster, 3.0 * s, 4.0 * s, 0.5 * s, Vector3(0.0, 32.0 * s, -4.5 * s), _dark())
	_box(_booster, 0.5 * s, 4.0 * s, 3.0 * s, Vector3(4.5 * s, 32.0 * s, 0.0), _dark())
	_box(_booster, 0.5 * s, 4.0 * s, 3.0 * s, Vector3(-4.5 * s, 32.0 * s, 0.0), _dark())
	_cyl(_booster, 4.5 * s, 4.5 * s, 6.0 * s, 32.0 * s, _dark())
	_cyl(_booster, 4.5 * s, 4.5 * s, 4.0 * s, -33.0 * s, _dark())
	# vc165 weld rings every ~2 m, thin vertical lines, light zigzag ring at joint, 33 nozzles (outer 20, inner 10, centre 3).
	for _wy in range(-34, 36, 2):
		var _ring := MeshInstance3D.new()
		var _tmesh := TorusMesh.new()
		# vc180: default torus is 64 main segments x 32 tube segments (~4,000 tris) x 35 rings = ~143k.
		# Corrected from Claude's swapped values: ring_segments is the MAIN circle (24, still round),
		# rings is the tube cross-section (4, square tube, invisible at 0.1 m thick) = ~192 tris each, ~7k total.
		_tmesh.ring_segments = 24
		_tmesh.rings = 4
		_tmesh.inner_radius = 4.45 * s
		_tmesh.outer_radius = 4.55 * s
		_ring.mesh = _tmesh
		_ring.material_override = _steel()
		_ring.rotation.x = deg_to_rad(90.0)
		_ring.position = Vector3(0.0, float(_wy) * s, 0.0)
		_booster.add_child(_ring)
	for _vi in range(8):
		var _va: float = float(_vi) * 45.0 * PI / 180.0
		_box(_booster, 0.15 * s, 70.0 * s, 0.15 * s, Vector3(cos(_va) * 4.55 * s, 0.0, sin(_va) * 4.55 * s), _steel())
	for _zi in range(24):
		var _za: float = float(_zi) * 15.0 * PI / 180.0
		var _zy: float = 35.0 * s + (0.4 * s if _zi % 2 == 0 else -0.4 * s)
		_box(_booster, 0.5 * s, 0.5 * s, 0.5 * s, Vector3(cos(_za) * 4.6 * s, _zy, sin(_za) * 4.6 * s), _steel())
	for _bi in range(20):
		var _bang: float = float(_bi) * 18.0 * PI / 180.0
		_cyl(_booster, 0.3 * s, 0.8 * s, 2.0 * s, -36.0 * s, _dark()).position = Vector3(cos(_bang) * 3.8 * s, -36.0 * s, sin(_bang) * 3.8 * s)
	for _bi2 in range(10):
		var _bang2: float = float(_bi2) * 36.0 * PI / 180.0
		_cyl(_booster, 0.3 * s, 0.8 * s, 2.0 * s, -36.0 * s, _dark()).position = Vector3(cos(_bang2) * 2.0 * s, -36.0 * s, sin(_bang2) * 2.0 * s)
	for _bi3 in range(3):
		var _bang3: float = float(_bi3) * 120.0 * PI / 180.0
		_cyl(_booster, 0.3 * s, 0.8 * s, 2.0 * s, -36.0 * s, _dark()).position = Vector3(cos(_bang3) * 0.8 * s, -36.0 * s, sin(_bang3) * 0.8 * s)
	# vc165 soot overlay, lower 40% (28 m), return only, hidden at liftoff and on pad.
	_soot = _cyl(_booster, 4.6 * s, 4.6 * s, 28.0 * s, -21.0 * s, _dark())
	_soot.visible = false
	add_child(_booster)
	# vc164 real ship look: silver top, black heat-tile belly, pointed nose, 4 flaps, 6 engine bells. No logos.
	_ship = Node3D.new()
	# vc165 ship: black speckled tiles, rounded nose (sphere cap on cone), small forward flaps, larger aft flaps.
	_cyl(_ship, 4.5 * s, 4.5 * s, 18.0 * s, 9.0 * s, _tile_material())
	_cyl(_ship, 4.5 * s, 4.5 * s, 18.0 * s, -9.0 * s, _tile_material())
	_cyl(_ship, 0.5 * s, 4.5 * s, 15.3 * s, 25.65 * s, _tile_material())
	var _nose_cap := MeshInstance3D.new()
	var _nmesh := SphereMesh.new()
	_nmesh.radius = 2.0 * s
	_nmesh.height = 4.0 * s
	_nose_cap.mesh = _nmesh
	_nose_cap.material_override = _tile_material()
	_nose_cap.position = Vector3(0.0, 33.0 * s, 0.0)
	_ship.add_child(_nose_cap)
	_box(_ship, 4.0 * s, 0.5 * s, 2.5 * s, Vector3(5.0 * s, 18.0 * s, 0.0), _tile_material())
	_box(_ship, 4.0 * s, 0.5 * s, 2.5 * s, Vector3(-5.0 * s, 18.0 * s, 0.0), _tile_material())
	_box(_ship, 7.0 * s, 0.5 * s, 3.5 * s, Vector3(5.5 * s, -14.0 * s, 0.0), _tile_material())
	_box(_ship, 7.0 * s, 0.5 * s, 3.5 * s, Vector3(-5.5 * s, -14.0 * s, 0.0), _tile_material())
	for _ei in range(6):
		var _ang: float = float(_ei) * 60.0 * PI / 180.0
		_cyl(_ship, 0.4 * s, 1.0 * s, 3.0 * s, -19.5 * s, _dark()).position = Vector3(cos(_ang) * 2.5 * s, -19.5 * s, sin(_ang) * 2.5 * s)
	add_child(_ship)
	# Flames: stretched additive cones, one per cluster, plus glow sprites.
	_flame_b = _make_flame(_booster, 5.0 * s, 65.0 * s, Vector3(0.0, -35.0 * s - 32.5 * s, 0.0))  # vc182: long bright plume like a real liftoff
	_flame_s = _make_flame(_ship, 3.0 * s, 18.0 * s, Vector3(0.0, -18.0 * s - 9.0 * s, 0.0))
	_glow_b = _make_glow(_booster, Vector3(0.0, -35.0 * s - 16.0 * s, 0.0))
	_glow_s = _make_glow(_ship, Vector3(0.0, -18.0 * s - 10.0 * s, 0.0))
	# Steam cloud at pad, under 400 particles.
	_steam = GPUParticles3D.new()
	_steam.amount = 300
	_steam.lifetime = 5.0
	_steam.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.2, 0.0)
	pm.spread = 80.0
	pm.damping_min = 6.0
	pm.damping_max = 10.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0.0, -2.0, 0.0)
	pm.scale_min = 2.0
	pm.scale_max = 6.0
	_steam.process_material = pm
	# vc182 realistic launch cloud: soft billowing puffs (camera-facing
	# quads with a procedural smoke texture, 2 tris each) that start warm-lit
	# by the engines, then turn white-grey as they roll OUTWARD along the
	# ground and swell up, like the steam/dust cloud at a real launch.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 10.0 * s
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 30.0
	pm.initial_velocity_min = 4.0 * s
	pm.initial_velocity_max = 12.0 * s
	pm.radial_velocity_min = 22.0 * s
	pm.radial_velocity_max = 45.0 * s
	pm.damping_min = 3.0 * s
	pm.damping_max = 7.0 * s
	pm.gravity = Vector3(0.0, 0.8 * s, 0.0)
	pm.scale_min = 28.0 * s
	pm.scale_max = 48.0 * s
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -8.0
	pm.angular_velocity_max = 8.0
	pm.scale_curve = _curve_tex([Vector2(0.0, 0.25), Vector2(0.3, 0.7), Vector2(1.0, 1.0)])
	pm.color_ramp = _ramp_tex([[0.0, Color(1.0, 0.72, 0.45, 0.0)], [0.08, Color(1.0, 0.85, 0.7, 0.8)], [0.3, Color(0.95, 0.94, 0.92, 0.7)], [0.7, Color(0.78, 0.78, 0.78, 0.45)], [1.0, Color(0.65, 0.65, 0.66, 0.0)]])
	_steam.lifetime = 9.0
	_steam.amount = 260
	_steam.explosiveness = 0.15
	_steam.local_coords = false
	_steam.draw_pass_1 = _puff_quad()
	_steam.material_override = _smoke_material()
	_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_steam.visibility_aabb = AABB(Vector3(-800, -50, -800) * s, Vector3(1600, 700, 1600) * s)
	add_child(_steam)
	# Exhaust smoke trail behind the climbing booster (stays in the sky).
	_exhaust = GPUParticles3D.new()
	_exhaust.amount = 500
	_exhaust.lifetime = 20.0
	_exhaust.local_coords = false
	_exhaust.emitting = false
	var ep := ParticleProcessMaterial.new()
	ep.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ep.emission_sphere_radius = 3.0 * s
	ep.direction = Vector3(0.0, -1.0, 0.0)
	ep.spread = 15.0
	ep.initial_velocity_min = 5.0 * s
	ep.initial_velocity_max = 15.0 * s
	ep.damping_min = 2.0 * s
	ep.damping_max = 4.0 * s
	ep.gravity = Vector3.ZERO
	ep.scale_min = 22.0 * s
	ep.scale_max = 36.0 * s
	ep.scale_curve = _curve_tex([Vector2(0.0, 0.4), Vector2(1.0, 1.6)])
	ep.color_ramp = _ramp_tex([[0.0, Color(1.0, 0.8, 0.6, 0.0)], [0.05, Color(0.98, 0.96, 0.94, 0.55)], [0.6, Color(0.88, 0.88, 0.9, 0.3)], [1.0, Color(0.85, 0.85, 0.88, 0.0)]])
	_exhaust.process_material = ep
	_exhaust.draw_pass_1 = _puff_quad()
	_exhaust.material_override = _smoke_material()
	_exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_exhaust.visibility_aabb = AABB(Vector3(-20000, -500, -20000) * s, Vector3(40000, 80000, 40000) * s)
	add_child(_exhaust)
	# Exhaust trail: thin additive cylinder, scaled in _process.
	_trail = Node3D.new()
	var trail_mesh := MeshInstance3D.new()
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 5.0 * s
	cmesh.bottom_radius = 12.0 * s
	cmesh.height = 1.0
	trail_mesh.mesh = cmesh
	trail_mesh.material_override = _additive(Color(0.9, 0.9, 0.95), 0.12)
	trail_mesh.visible = false  # vc182: replaced by the _exhaust smoke trail
	_trail.add_child(trail_mesh)
	_trail.visible = false
	add_child(_trail)
	# 1.8 m reference figure, visible in Indoor mode only, for scale check.
	_figure = Node3D.new()
	var _orange_mat := StandardMaterial3D.new()
	_orange_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_orange_mat.albedo_color = Color(1.0, 0.55, 0.1)
	_orange_mat.metallic = 0.0
	_orange_mat.roughness = 0.8
	_cyl(_figure, 0.25 * s, 0.25 * s, 1.4 * s, 0.7 * s, _orange_mat)
	var head := MeshInstance3D.new()
	var hmesh := SphereMesh.new()
	hmesh.radius = 0.15 * s
	hmesh.height = 0.3 * s
	head.mesh = hmesh
	head.material_override = _dark()
	head.position = Vector3(0.0, 1.6 * s, 0.0)
	_figure.add_child(head)
	_figure.visible = indoor
	add_child(_figure)
	# vc165 surroundings at real size: support building, white tank, crane, fence posts, contact shadows, dust discs, ground haze. Positions set in _set_rest_positions relative to _pad.
	_surround = Node3D.new()
	_box(_surround, 20.0 * s, 12.0 * s, 15.0 * s, Vector3(0.0, 6.0 * s, 0.0), _dark())
	_cyl(_surround, 5.0 * s, 5.0 * s, 15.0 * s, 7.5 * s, _steel())
	_box(_surround, 2.0 * s, 35.0 * s, 2.0 * s, Vector3(0.0, 17.5 * s, 0.0), _dark())
	_box(_surround, 20.0 * s, 2.0 * s, 2.0 * s, Vector3(10.0 * s, 35.0 * s, 0.0), _dark())
	# vc180: a car for scale, 4.5 x 1.5 x 1.8 m. _set_rest_positions only moves the first
	# 4 surround children, so this 5th child keeps its own position relative to the pad.
	_box(_surround, 4.5 * s, 1.5 * s, 1.8 * s, Vector3(40.0 * s, 0.75 * s, 30.0 * s), _steel())
	add_child(_surround)
	_make_sounds()
	_set_rest_positions()

func _make_flame(parent: Node3D, r: float, h: float, pos: Vector3) -> Node3D:
	# vc182 realistic plume (procedural, simulated look): a white-hot core
	# at the nozzles fading to yellow-orange then a translucent orange tail,
	# soft see-through edges, flickering turbulence that streams downward,
	# and shock diamonds (Mach diamonds) in the core like real engine
	# exhaust. Additive, so it glows over passthrough. 1 draw call.
	var n := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = 0.55 * r
	mesh.height = h
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.cap_top = false
	mesh.cap_bottom = false
	n.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = _plume_shader()
	n.material_override = m
	n.position = pos
	n.visible = false
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n)
	# A wider, fainter outer glow sleeve so the plume has volume.
	var outer := MeshInstance3D.new()
	var om := CylinderMesh.new()
	om.top_radius = r * 1.35
	om.bottom_radius = r * 1.1
	om.height = h * 1.1
	om.radial_segments = 24
	om.rings = 6
	om.cap_top = false
	om.cap_bottom = false
	outer.mesh = om
	var m2 := ShaderMaterial.new()
	m2.shader = m.shader
	m2.set_shader_parameter("intensity", 0.35)
	m2.set_shader_parameter("core_mix", 0.0)
	outer.material_override = m2
	outer.position = Vector3(0.0, -h * 0.05, 0.0)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(outer)
	return n

var _plume_sh: Shader = null
func _plume_shader() -> Shader:
	if _plume_sh != null:
		return _plume_sh
	_plume_sh = Shader.new()
	_plume_sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform float intensity = 1.0;
uniform float core_mix = 1.0;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment(){
	float v = UV.y;                                   // 0 at the nozzles, 1 at the tail
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(face, 1.6);                       // soft, see-through edges
	float t = TIME;
	float turb = vn(vec2(UV.x * 18.0, v * 9.0 - t * 14.0)) * 0.6 + vn(vec2(UV.x * 40.0, v * 22.0 - t * 30.0)) * 0.4;
	float flick = 0.85 + 0.15 * sin(t * 37.0 + UV.x * 9.0);
	float along = (1.0 - smoothstep(0.15, 1.0, v));    // fades toward the tail
	// shock diamonds: bright bands in the core, strongest near the nozzles
	float diamonds = pow(0.5 + 0.5 * cos(v * 6.2831 * 5.0), 6.0) * (1.0 - smoothstep(0.0, 0.55, v)) * pow(face, 6.0) * core_mix;
	vec3 white = vec3(1.0, 0.97, 0.90);
	vec3 yellow = vec3(1.0, 0.78, 0.38);
	vec3 orange = vec3(1.0, 0.42, 0.10);
	vec3 col = mix(white, yellow, smoothstep(0.0, 0.25, v));
	col = mix(col, orange, smoothstep(0.25, 0.8, v));
	float a = body * along * (0.55 + 0.6 * turb) * flick;
	ALBEDO = (col * a + white * diamonds * 0.9) * intensity;
}
"""
	return _plume_sh

func _make_glow(parent: Node3D, pos: Vector3) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = _glow_texture()
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.material_override = _additive(Color(1.0, 0.85, 0.6), 0.8)
	sp.position = pos
	sp.visible = false
	parent.add_child(sp)
	return sp

func _set_rest_positions() -> void:
	var s: float = _scale
	if _mount != null:
		_mount.global_position = _pad
	if _tower != null:
		_tower.global_position = _tower_pos
	if _beam != null:
		_beam.global_position = _tower_pos + Vector3(0.0, 109.0 * s, 0.0)
		_beam.rotation.y = atan2(-_downrange.z, _downrange.x)
	if _booster != null:
		_booster.global_position = _pad + Vector3(0.0, 20.0 * s + 35.0 * s, 0.0)
		_booster.rotation = Vector3.ZERO
	if _ship != null:
		_ship.global_position = _pad + Vector3(0.0, 20.0 * s + 70.0 * s + 18.0 * s, 0.0)
		_ship.rotation = Vector3.ZERO
	if _surround != null:
		_surround.global_position = _pad
		var _children: Array = _surround.get_children()
		if _children.size() >= 4:
			_children[0].position = Vector3(50.0 * s, 6.0 * s, 20.0 * s)
			_children[1].position = Vector3(-45.0 * s, 7.5 * s, 20.0 * s)
			_children[2].position = Vector3(0.0, 17.5 * s, -55.0 * s)
			_children[3].position = Vector3(10.0 * s, 35.0 * s, -55.0 * s)
	if _steam != null:
		_steam.global_position = _pad + Vector3(0.0, 2.0 * s, 0.0)
	if _figure != null:
		# vc180: figure is a real-size scale cue outdoors too, not indoor-only.
		# Moved 40 m toward the camera so it is not hidden behind the stack.
		# At 200 m a 1.8 m person is ~0.5 deg tall, a speck, but the eye compares it to 121 m.
		var _to_cam: Vector3 = _camera.global_position - _pad if _camera != null else Vector3(1, 0, 0)
		_to_cam.y = 0.0
		_figure.global_position = _pad + _to_cam.normalized() * 40.0 * s
		_figure.visible = true

func _update_marker() -> void:
	if _marker == null or _camera == null or mode != "placing":
		return
	var cam_pos: Vector3 = _camera.global_position
	var gaze: Vector3 = -_camera.global_transform.basis.z
	gaze = gaze.normalized()
	# vc165 placement: horizontal direction + chosen distance, NOT floor-plane intersection. At 250 m the ground is only 0.4 deg below horizon, so a tiny wobble moved placement by hundreds of metres. Distance defaults to 200 m, range 150-500 m, adjusted by pinch-drag, at real floor height (y=0) plus nudge.
	var min_d: float = 5.0 if indoor else BIG_MIN_DIST
	var max_d: float = 20.0 if indoor else BIG_MAX_DIST
	if indoor:
		_place_dist = clamp(_place_dist, min_d, max_d)
	else:
		_place_dist = clamp(_place_dist, min_d, max_d)
	var dist: float = _place_dist
	var flat: Vector3 = Vector3(gaze.x, 0.0, gaze.z)
	if flat.length() < 0.01:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()
	_pad = cam_pos + flat * dist
	# vc180 Floor: height from aim, not flat Y=0. Distance is still chosen (pinch-drag);
	# only height comes from the look-down angle, so the base lands on the real ground
	# spot you are aiming at, even on a slope. ~0.1 deg wobble = ~0.35 m at 200 m.
	# Uses head direction, not eye direction, and fails if the spot is hidden behind a fence/trees.
	var _flat_len: float = Vector2(gaze.x, gaze.z).length()
	if gaze.y < -0.002 and _flat_len > 0.01:
		var _aim_y: float = cam_pos.y + (gaze.y / _flat_len) * dist
		_pad.y = clamp(_aim_y, cam_pos.y - 30.0, cam_pos.y - 0.3) + _ground_nudge
	else:
		_pad.y = _ground_nudge  # looking level or up: old behaviour
	_show_info("Distance %d m. Base %.1f m below your eyes. Nudge %.2f m.\nPut the ring on the real ground, hold still, pinch." % [int(dist), cam_pos.y - _pad.y, _ground_nudge])
	# Downrange is 90 degrees right of the view when placed.
	_downrange = Vector3(-flat.z, 0.0, flat.x).normalized()
	_tower_pos = _pad + Vector3(-flat.x, 0.0, -flat.z) * 0.0
	_tower_pos = _pad + Vector3(flat.z, 0.0, -flat.x) * 15.0 * _scale
	_catch_pos = _tower_pos + (_pad - _tower_pos).normalized() * 8.0 * _scale
	_marker.global_position = _pad
	_marker.visible = true
	_set_rest_positions()

func place() -> void:
	if mode != "placing":
		return
	mode = "placed"
	if _marker != null:
		_marker.visible = false
	_show_buttons(["LAUNCH", "MODE", "REDUCE", "MUTE", "RESET"])
	_show_info(("Shown 10x real size\n" if _scale > 1.5 else "") + "Real stack: 121 m tall, 9 m wide, 33 engines\nSay \"launch starship\" to launch.")

func _show_info(text: String) -> void:
	if _info == null:
		_info = Label3D.new()
		_info.font_size = 32
		_info.pixel_size = 0.002
		_info.width = 500
		_info.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_info.outline_size = 2
		_info.outline_modulate = Color(0.0, 0.0, 0.0)
		add_child(_info)
	_info.text = text
	_info_t = 6.0

func _make_button(text: String) -> void:
	if _buttons.has(text):
		return
	var lab := Label3D.new()
	lab.font_size = 48
	lab.pixel_size = 0.0012
	lab.width = 380
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color(1.0, 1.0, 1.0)
	lab.outline_size = 4
	lab.outline_modulate = Color(0.0, 0.0, 0.0)
	lab.text = text
	add_child(lab)
	var btn := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.46, 0.16, 0.03)
	btn.mesh = bmesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.18, 0.40)
	btn.material_override = mat
	add_child(btn)
	_buttons[text] = {"label": lab, "button": btn, "mat": mat}

func _show_buttons(names: Array) -> void:
	# vc181 NO BUTTONS (user 2026-11-04): Starship is voice + pinch only.
	# "spawn starship" -> look at the ground, pinch to place (pinch-drag for
	# distance) -> "launch starship". "reset starship" removes it.
	# Any old buttons are hidden and no new ones are ever made.
	for k in _buttons.keys():
		var d: Dictionary = _buttons[k]
		(d["label"] as Label3D).visible = false
		(d["button"] as MeshInstance3D).visible = false
	if true:
		return
	for n in names:
		_make_button(n)
		var d2: Dictionary = _buttons[n]
		(d2["label"] as Label3D).visible = true
		(d2["button"] as MeshInstance3D).visible = true
		if n == "MODE":
			(d2["label"] as Label3D).text = "HIGHLIGHTS" if highlights else "REAL TIME"
		if n == "REDUCE":
			(d2["label"] as Label3D).text = "REDUCE: ON" if reduce_effects else "REDUCE: OFF"
		if n == "MUTE":
			(d2["label"] as Label3D).text = "MUTE: ON" if muted else "MUTE: OFF"
		if n == "INDOOR":
			(d2["label"] as Label3D).text = "INDOOR: ON" if indoor else "INDOOR: OFF"

func _button_pos(name: String, idx: int) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var basis: Basis = _camera.global_transform.basis
	var x: float = -1.0 + float(idx) * 0.5  # vc165: 5 buttons fit in view
	return _camera.global_position + basis * Vector3(x, -0.38, -0.85)

func button_at(pinch_point: Vector3) -> String:
	if _camera == null:
		return ""
	var idx: int = 0
	for k in _buttons.keys():
		var d: Dictionary = _buttons[k]
		var lab: Label3D = d["label"]
		if not lab.visible:
			continue
		var pos: Vector3 = _button_pos(k, idx)
		var bdir: Vector3 = (pos - _camera.global_position).normalized()
		var pdir: Vector3 = (pinch_point - _camera.global_position).normalized()
		# vc180 Bug 1: require head looking at the button too, so a low placement pinch cannot hit a button by accident.
		var gdir: Vector3 = (-_camera.global_transform.basis.z).normalized()
		if bdir.dot(pdir) > 0.966 and bdir.dot(gdir) > 0.94:
			return k
		idx += 1
	return ""

func press_button(name: String) -> bool:
	if name == "PLACE":
		place()
		return true
	if name == "LAUNCH":
		start_launch()
		return true
	if name == "MODE":
		highlights = not highlights
		_show_buttons(["LAUNCH", "MODE", "REDUCE", "MUTE", "RESET"])
		return true
	if name == "REDUCE":
		reduce_effects = not reduce_effects
		if _steam != null:
			_steam.amount = 150 if reduce_effects else 300
		_show_buttons(["LAUNCH", "MODE", "REDUCE", "MUTE", "RESET"])
		return true
	if name == "MUTE":
		muted = not muted
		_show_buttons(["LAUNCH", "MODE", "REDUCE", "MUTE", "RESET"])
		return true
	if name == "UP":
		_ground_nudge = clamp(_ground_nudge + 0.25, -15.0, 15.0)
		_update_marker()
		_show_info("Ground nudge %.2f m" % _ground_nudge)
		return true
	if name == "DOWN":
		_ground_nudge = clamp(_ground_nudge - 0.25, -15.0, 15.0)
		_update_marker()
		_show_info("Ground nudge %.2f m" % _ground_nudge)
		return true
	if name == "INDOOR":
		indoor = not indoor
		_scale = 0.1 if indoor else SIZE_MULT
		_place_dist = INDOOR_DIST if indoor else BIG_DEFAULT_DIST
		# vc180 Bug 2: _build_all() returns early if _tower exists, so INDOOR never rebuilt.
		# Free the old stack first (flames/glows/soot are children of booster/ship, freed with them).
		for _n in [_marker, _tower, _beam, _mount, _booster, _ship, _steam, _trail, _figure, _surround]:
			if _n != null:
				_n.queue_free()
		for _c in get_children():
			if _c is DirectionalLight3D:
				_c.queue_free()
		_marker = null; _tower = null; _beam = null; _mount = null; _booster = null
		_ship = null; _steam = null; _trail = null; _figure = null; _surround = null
		_soot = null; _flame_b = null; _flame_s = null; _glow_b = null; _glow_s = null
		_build_all()
		mode = "placing"
		_show_buttons(["PLACE", "INDOOR", "UP", "DOWN", "RESET"])
		return true
	if name == "RESET":
		reset_all()
		return true
	return false

func adjust_distance(pinch_point: Vector3) -> void:
	if _camera == null:
		return
	var gaze: Vector3 = -_camera.global_transform.basis.z
	var flat: Vector3 = Vector3(gaze.x, 0.0, gaze.z).normalized()
	var hand_d: float = (pinch_point - _camera.global_position).dot(flat)
	if _last_drag == 0.0:
		_last_drag = hand_d
		return
	var delta: float = hand_d - _last_drag
	_last_drag = hand_d
	var min_d: float = 5.0 if indoor else BIG_MIN_DIST
	var max_d: float = 20.0 if indoor else BIG_MAX_DIST
	_place_dist = clamp(_place_dist + delta * (200.0 if indoor else 1500.0), min_d, max_d)
	_update_marker()

func reset_all() -> void:
	mode = "off"
	_set_far(false)
	_launching = false
	_caught = false
	_sim = 0.0
	_count = 0.0
	_hold_t = 0.0
	if _marker != null:
		_marker.visible = false
	if _tower != null:
		_tower.visible = false
	if _mount != null:
		_mount.visible = false
	if _booster != null:
		_booster.visible = false
	if _ship != null:
		_ship.visible = false
	if _steam != null:
		_steam.emitting = false
	if _trail != null:
		_trail.visible = false
	if _beam != null:
		_beam.visible = false
	if _soot != null:
		_soot.visible = false
	if _flame_b != null:
		_flame_b.visible = false
	if _flame_s != null:
		_flame_s.visible = false
	if _glow_b != null:
		_glow_b.visible = false
	if _glow_s != null:
		_glow_s.visible = false
	# vc180 Bug 5: sunlight, surroundings and figure were never hidden on RESET,
	# so after the first spawn they lit / stayed in the solar system for the rest of the session.
	for _c in get_children():
		if _c is DirectionalLight3D:
			_c.visible = false
	if _surround != null:
		_surround.visible = false
	if _figure != null:
		_figure.visible = false
	if _rumble_player != null and _rumble_player.playing:
		_rumble_player.stop()
	if _crackle_player != null and _crackle_player.playing:
		_crackle_player.stop()
	_show_buttons([])

func start_launch() -> void:
	if mode != "placed":
		return
	mode = "launching"
	_launching = true
	_sim = 0.0
	_count = 0.0
	_caught = false
	_show_buttons(["RESET"])
	if _info != null:
		_info.visible = false  # vc183: no words during the flight
	_info_t = 0.0

func _time_scale(sim: float) -> float:
	if not highlights:
		return 1.0
	# vc182 (user 2026-11-04): whole flight under 2 minutes. 5 s countdown +
	# 20 s real-time liftoff + 388 s of flight at 5x (78 s) + last 12 s of the
	# catch in real time = ~115 s, then a 5 s hold. Was 150 s + countdown.
	# vc183: ~80 s total: 5 s countdown, 12 s liftoff in real time, climb at
	# 8x, return coast at 10x, then the last 18 s (fall + catch) in real time.
	if sim < 12.0:
		return 1.0
	if sim < 161.0:
		return 8.0
	if sim < T_FINAL:
		return 10.0
	return 1.0

func _interp(keys: Array, t: float) -> float:
	if keys.size() == 0:
		return 0.0
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(keys.size() - 1):
		var t0: float = keys[i][0]
		var t1: float = keys[i + 1][0]
		if t >= t0 and t <= t1:
			var f: float = (t - t0) / (t1 - t0)
			f = f * f * (3.0 - 2.0 * f)
			return lerp(keys[i][1], keys[i + 1][1], f)
	return keys[keys.size() - 1][1]

func _ascent_pos(t: float) -> Vector3:
	var alt_keys: Array = [[0.0, 0.0], [7.0, 0.14], [20.0, 1.1], [60.0, 11.0], [120.0, 45.0], [150.0, 70.0], [161.0, 75.0]]
	var down_keys: Array = [[0.0, 0.0], [7.0, 0.05], [20.0, 0.3], [60.0, 3.0], [120.0, 18.0], [150.0, 35.0], [161.0, 45.0]]
	var alt: float = _interp(alt_keys, t) * 1000.0 * _scale
	var down: float = _interp(down_keys, t) * 1000.0 * _scale
	return _pad + _downrange * down + Vector3(0.0, alt, 0.0)

const T_FINAL: float = 402.0  # vc183: last 18 s (402-420) play in real time: the visible fall + landing burn

func _bez(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float) -> Vector3:
	var v: float = 1.0 - u
	return a * v * v * v + b * 3.0 * v * v * u + c * 3.0 * v * u * u + d * u * u * u

func _final_alt() -> float:
	return min(1800.0 * _scale, 3500.0)  # where the real-time fall begins, above the pad

func _booster_pos(t: float) -> Vector3:
	# vc183 SMOOTH RETURN (user: "it just teleports by the platform"). Before,
	# the booster raced in from ~80 km in sped-up time and switched to real
	# time only 250 m above the tower, and the camera could not draw past
	# 4 km anyway, so it popped into view. Now one continuous path:
	#  161-221  boostback burn, heading back toward the pad
	#  221-402  coast: a curve that ends directly above the tower, falling
	#           STRAIGHT DOWN (sped up while it is far away)
	#  402-420  real time: you watch it fall out of the sky, light its
	#           engines (landing burn from 405), slow down and get caught.
	# Position AND speed match at every hand-over, so nothing jumps.
	var s: float = _scale
	if t < 161.0:
		return _ascent_pos(t) + Vector3(0.0, 55.0 * s, 0.0)
	var p161: Vector3 = _ascent_pos(161.0) + Vector3(0.0, 55.0 * s, 0.0)
	var p221: Vector3 = p161 + _downrange * 10000.0 * s + Vector3(0.0, 5000.0 * s, 0.0)
	if t < 221.0:
		return p161.lerp(p221, (t - 161.0) / 60.0)
	var hover: Vector3 = _catch_pos + Vector3(0.0, 109.0 * s + 6.75 * s - 35.0 * s, 0.0)
	var b3: Vector3 = _catch_pos + _downrange * 60.0 * s + Vector3(0.0, _final_alt(), 0.0)
	var t_coast: float = T_FINAL - 221.0
	var fall_v: float = (b3.y - hover.y) / (420.0 - T_FINAL) * 1.3   # m/s entering the real-time fall
	var b2: Vector3 = b3 + Vector3(0.0, fall_v * t_coast / 3.0, 0.0)    # arrive moving straight down
	var to_pad: Vector3 = (b3 - p221)
	to_pad.y = 0.0
	var b1: Vector3 = p221 + to_pad * 0.35 + Vector3(0.0, 8000.0 * s, 0.0)  # arc up over the top, then down
	if t < T_FINAL:
		return _bez(p221, b1, b2, b3, (t - 221.0) / t_coast)
	# Real-time fall: cubic Hermite from b3 (speed fall_v down) to hover (speed 0).
	var T: float = 420.0 - T_FINAL
	var u: float = clamp((t - T_FINAL) / T, 0.0, 1.0)
	var h00: float = 2.0 * u * u * u - 3.0 * u * u + 1.0
	var h10: float = u * u * u - 2.0 * u * u + u
	var h01: float = -2.0 * u * u * u + 3.0 * u * u
	var m0: Vector3 = Vector3(0.0, -fall_v, 0.0) * T
	return b3 * h00 + m0 * h10 + hover * h01

func _ship_pos(t: float) -> Vector3:
	if t < 161.0:
		return _ascent_pos(t) + Vector3(0.0, 108.0 * _scale, 0.0)  # vc165 centre: mount 20 + booster 70 + half ship body 18
	var a: Vector3 = _ascent_pos(161.0) + Vector3(0.0, 108.0 * _scale, 0.0)
	var f: float = (t - 161.0) / 140.0
	return a + _downrange * (55000.0 * _scale * f) + Vector3(0.0, 75000.0 * _scale * f, 0.0)

func _make_wav(seconds: float, kind: String) -> AudioStreamWAV:
	var rate: int = 44100
	var n: int = int(seconds * float(rate))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var seed: int = 12345
	for i in range(n):
		var tt: float = float(i) / float(rate)
		var v: float = 0.0
		if kind == "rumble":
			v = sin(tt * 2.0 * PI * 45.0) * 0.25 + _noise(seed + i) * 0.15
		elif kind == "crackle":
			v = _noise(seed + i * 7) * 0.2 * (0.5 + 0.5 * sin(tt * 2.0 * PI * 8.0))
		elif kind == "thump":
			v = sin(tt * 2.0 * PI * 30.0) * 0.4 * exp(-tt * 3.0)
		elif kind == "boom":
			var b1: float = exp(-abs(tt - 0.05) * 80.0)
			var b2: float = exp(-abs(tt - 0.18) * 80.0)
			v = (_noise(seed + i) * 0.3) * (b1 + b2)
		elif kind == "arm":
			v = (sin(tt * 2.0 * PI * 200.0) * 0.15 + sin(tt * 2.0 * PI * 350.0) * 0.1) * exp(-tt * 2.0) + _noise(seed + i) * 0.05
		else:
			v = _noise(seed + i) * 0.1
		v = clamp(v, -0.5, 0.5)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _noise(seed: int) -> float:
	var x: int = (seed * 1103515245 + 12345) % 2147483648
	return float(x % 1000) / 500.0 - 1.0

func _make_sounds() -> void:
	if _sounds.size() > 0:
		return
	_sounds["rumble"] = _make_wav(4.0, "rumble")
	_sounds["crackle"] = _make_wav(4.0, "crackle")
	_sounds["thump"] = _make_wav(1.0, "thump")
	_sounds["boom"] = _make_wav(0.5, "boom")
	_sounds["arm"] = _make_wav(1.0, "arm")
	(_sounds["rumble"] as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	(_sounds["crackle"] as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	for i in range(4):
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		_players.append(pl)
	_rumble_player = AudioStreamPlayer.new()
	add_child(_rumble_player)
	_crackle_player = AudioStreamPlayer.new()
	add_child(_crackle_player)

func _play_sound_delayed(kind: String, dist: float) -> void:
	if muted or not _sounds.has(kind):
		return
	var delay: float = dist / 343.0
	_pending_sounds.append({"kind": kind, "at": Time.get_unix_time_from_system() + delay})

func _process(delta: float) -> void:
	if _camera == null:
		return
	_update_shadows()
	# vc182 exhaust trail follows the booster's engines while they burn on the climb.
	if _exhaust != null and _booster != null:
		var _burn: bool = _launching and _flame_b != null and _flame_b.visible and _sim < 150.0 and not reduce_effects
		_exhaust.global_position = _booster.global_position + Vector3(0.0, -38.0 * _scale, 0.0)
		_exhaust.emitting = _burn
	if mode == "placing":
		_update_marker()
	if _info != null and _info_t > 0.0:
		_info_t -= delta
		_info.global_position = _camera.global_position + (-_camera.global_transform.basis.z) * 1.2 + Vector3(0.0, 0.25, 0.0)
		_info.visible = _info_t > 0.0
	# Buttons, camera-relative, TRAVEL style.
	var idx: int = 0
	for k in _buttons.keys():
		var d: Dictionary = _buttons[k]
		var lab: Label3D = d["label"]
		if not lab.visible:
			continue
		var pos: Vector3 = _button_pos(k, idx)
		lab.global_position = pos
		var btn: MeshInstance3D = d["button"]
		btn.global_position = pos + (-_camera.global_transform.basis.z) * 0.03
		btn.look_at(_camera.global_position, Vector3.UP)
		var mat: StandardMaterial3D = d["mat"]
		var bdir: Vector3 = (pos - _camera.global_position).normalized()
		var hovered: bool = false
		if _camera != null:
			var gaze: Vector3 = -_camera.global_transform.basis.z
			if bdir.dot(gaze.normalized()) > 0.966:
				hovered = true
		mat.albedo_color = Color(0.10, 0.90, 0.35) if hovered else Color(0.05, 0.18, 0.40)
		idx += 1
	# Pending sounds, delayed by distance.
	var now: float = Time.get_unix_time_from_system()
	var remaining: Array = []
	for s in _pending_sounds:
		if now >= s["at"]:
			var pl: AudioStreamPlayer = null
			for p in _players:
				if not p.playing:
					pl = p
					break
			if pl != null:
				pl.stream = _sounds[s["kind"]]
				pl.volume_db = -40.0 if not muted else -80.0
				pl.play()
				if not muted:
					_fade_players.append(pl)
		else:
			remaining.append(s)
	_pending_sounds = remaining
	# vc163: 1 s fade-in for event sounds, from -40 dB to -12 dB.
	var _still_fading: Array = []
	for fp in _fade_players:
		var fpl: AudioStreamPlayer = fp
		if fpl.playing and not muted:
			fpl.volume_db = min(-12.0, fpl.volume_db + delta * 28.0)
			if fpl.volume_db < -12.0:
				_still_fading.append(fpl)
	_fade_players = _still_fading
	if not _launching:
		return
	# Countdown: ignition at 3 s, liftoff 2 s later, at 5 s.
	_count += delta
	if _count < 3.0:
		return
	if _count >= 3.0 and _count < 5.0:
		if _flame_b != null:
			_flame_b.visible = true
			# on the pad: plume ends at the ground (mount is 20 m tall)
			_flame_b.scale = Vector3(1.0, 21.0 / 65.0, 1.0)
			_flame_b.position = Vector3(0.0, -35.0 * _scale - 10.5 * _scale, 0.0)
		if _glow_b != null:
			_glow_b.visible = true
		if _steam != null:
			_steam.emitting = true
		if _count >= 3.0 and _count - delta < 3.0:
			_play_sound_delayed("rumble", _pad.distance_to(_camera.global_position))
		return
	if _count >= 5.0:
		_sim += delta * _time_scale(_sim)
		_update_launch(delta)

func _update_launch(delta: float) -> void:
	var s: float = _scale
	var t: float = _sim
	# T+ clock, small, camera-relative, only during launch.
	if _clock == null:
		_clock = Label3D.new()
		_clock.font_size = 32
		_clock.pixel_size = 0.002
		_clock.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_clock)
	var mins: int = int(t) / 60
	var secs: int = int(t) % 60
	_clock.text = "T+ %02d:%02d %s" % [mins, secs, "HIGHLIGHTS" if highlights else "REAL TIME"]
	_clock.global_position = _camera.global_position + (-_camera.global_transform.basis.z) * 1.2 + Vector3(0.0, -0.35, 0.0)
	_clock.visible = false  # vc183: no "T+ ... HIGHLIGHTS" text (user request)
	# Booster and ship positions.
	var bpos: Vector3 = _booster_pos(t)
	var spos: Vector3 = _ship_pos(t)
	if _booster != null:
		_booster.global_position = bpos  # vc163: _booster_pos already returns centre
		if t >= 408.0:
			# vc165 final lean: top away from tower, swinging upright in last ~4 s. Axis is downrange (horizontal, perpendicular to tower-pad direction).
			var _p4: float = clamp((t - 408.0) / 12.0, 0.0, 1.0)
			var _lean: float = 12.0
			if _p4 > 0.66:
				_lean = 12.0 * (1.0 - (_p4 - 0.66) / 0.34)
			_booster.global_transform.basis = Basis(_downrange, deg_to_rad(_lean))
		elif t >= 161.0 and t < 169.0:
			var f: float = (t - 161.0) / 8.0
			_booster.rotation.x = deg_to_rad(180.0 * f)
		elif t >= 169.0 and t < 221.0:
			_booster.rotation.x = deg_to_rad(180.0)
		elif t >= 221.0 and t < 230.0:
			# vc165 flip back to upright for return/landing, so engines point down, not up.
			_booster.rotation.x = deg_to_rad(180.0 * (1.0 - (t - 221.0) / 9.0))
		else:
			_booster.rotation.x = 0.0
	if _ship != null:
		_ship.global_position = spos  # vc163: _ship_pos already returns centre
		_ship.visible = t < 300.0
	# Flames and glow, with gentle 0.3 s ramps (no hard flashes).
	var b_flame: bool = false
	var s_flame: bool = false
	if t < 150.0:
		b_flame = true
	elif t >= 168.0 and t < 221.0:
		b_flame = true
	elif t >= 405.0 and t < 420.0:
		b_flame = true  # vc183 landing burn lights partway down the fall
	if t >= 161.0 and t < 300.0:
		s_flame = true
	if _soot != null:
		_soot.visible = t >= 221.0  # vc165: sooty lower half for return only, bright stainless at liftoff/on pad
	if _flame_b != null:
		_flame_b.visible = b_flame
		if b_flame:
			var fl: float = 65.0 * s
			var _fr: float = 1.0 + t / 200.0
			if t >= 408.0:
				# vc165 final plume: long narrow pink-white, several booster widths at start, shortening as it slows.
				var _fp: float = clamp((t - 408.0) / 12.0, 0.0, 1.0)
				fl = lerp(80.0 * s, 20.0 * s, _fp)
				_fr = 0.8
				var _fmat: StandardMaterial3D = _flame_b.material_override as StandardMaterial3D
				if _fmat != null:
					_fmat.albedo_color = Color(1.0, 0.75, 0.85, 0.7)
			elif t >= 60.0:
				fl = fl * (1.0 + t / 100.0)
			if t >= 417.0 and t < 420.0:
				_fr = 0.4  # vc165: centre 3 engines only in last 3 s
			if reduce_effects:
				fl = fl * 0.6
			# vc182: never push the plume through the ground: on/near the pad it
			# stops at the ground and the smoke cloud takes over there.
			var _clear: float = _booster.global_position.y - 35.0 * s - _pad.y
			fl = clamp(fl, 3.0 * s, max(_clear, 3.0 * s) + 2.0 * s)
			_flame_b.scale = Vector3(_fr, fl / (65.0 * s), _fr)
			_flame_b.position = Vector3(0.0, -35.0 * s - fl * 0.5, 0.0)
	if _flame_s != null:
		_flame_s.visible = s_flame
	if _glow_b != null:
		_glow_b.visible = b_flame
		_set_glow_size(_glow_b, 10.0 * s)
	if _glow_s != null:
		_glow_s.visible = s_flame
		if s_flame and t >= 200.0:
			var mat: StandardMaterial3D = _glow_s.material_override as StandardMaterial3D
			if mat != null:
				var a: float = clamp(1.0 - (t - 200.0) / 100.0, 0.0, 0.8)
				mat.albedo_color = Color(1.0, 0.85, 0.6, a)
		_set_glow_size(_glow_s, 6.0 * s)
	# vc163: continuous engine rumble + crackle while any flame is on, with fade-in, stopped when engines cut. Event sounds alone left silence during ascent.
	if _rumble_player != null and _crackle_player != null:
		var _engines_on: bool = b_flame or s_flame
		if _engines_on and not _rumble_player.playing and not muted:
			_rumble_player.stream = _sounds["rumble"]
			_rumble_player.volume_db = -40.0
			_rumble_player.play()
			_fade_players.append(_rumble_player)
			_crackle_player.stream = _sounds["crackle"]
			_crackle_player.volume_db = -30.0
			_crackle_player.play()
		if not _engines_on:
			if _rumble_player.playing:
				_rumble_player.stop()
			if _crackle_player.playing:
				_crackle_player.stop()
	# Steam at ignition and at catch.
	if _steam != null:
		_steam.emitting = (t < 20.0) or (t >= 417.0 and t < 425.0)
	# Trail during ascent.
	if _trail != null:
		if t > 0.0 and t < 161.0 and _booster != null:
			_trail.visible = not reduce_effects
			var mid: Vector3 = (_pad + _booster.global_position) * 0.5
			_trail.global_position = mid
			var dist: float = _pad.distance_to(_booster.global_position)
			_trail.scale = Vector3(1.0, dist, 1.0)
			# vc163: cylinder axis is Y, look_at orients -Z, which would put the trail sideways. Rotate Y onto the pad-to-booster direction instead.
			var _tdir: Vector3 = (_booster.global_position - _pad).normalized()
			if _tdir.length() > 0.01:
				_trail.quaternion = Quaternion(Vector3.UP, _tdir)
		else:
			_trail.visible = false
	# Staging flash, gentle ramp, venting puff via steam briefly.
	if t >= 161.0 and t < 162.0:
		if _steam != null:
			_steam.emitting = true
		if t - delta < 161.0:
			_play_sound_delayed("thump", _pad.distance_to(_camera.global_position))
	# Sonic boom double-crack when booster goes subsonic, delayed by distance.
	if t >= 300.0 and t - delta < 300.0:
		_play_sound_delayed("boom", _booster.global_position.distance_to(_camera.global_position))
	# vc165 catch beam: single level beam, no pincer swing, holds booster just below grid fins. Sound when booster reaches beam.
	if _beam != null:
		_beam.global_position = _tower_pos + Vector3(0.0, 109.0 * s, 0.0)
		_beam.rotation.y = atan2(-_downrange.z, _downrange.x)
		if t >= 420.0 and t - delta < 420.0:
			_play_sound_delayed("arm", _tower_pos.distance_to(_camera.global_position))
	# Catch at 420 s sim.
	if t >= 420.0 and not _caught:
		_caught = true
		_hold_t = 0.0
		if _glow_b != null:
			_glow_b.visible = false
		pass  # vc183: no words during the flight
	if _caught:
		_hold_t += delta
		if _flame_b != null:
			if _hold_t < 2.0:
				# vc165: three engines cut, flame shortens to nothing over ~2 s.
				_flame_b.visible = true
				_flame_b.scale = Vector3(0.4 * (1.0 - _hold_t / 2.0), 0.3 * (1.0 - _hold_t / 2.0), 0.4 * (1.0 - _hold_t / 2.0))
			else:
				_flame_b.visible = false
		if _steam != null:
			_steam.emitting = true
			_steam.amount = 150 if reduce_effects else 300
		if _booster != null and _hold_t < 3.0:
			_booster.rotation.z = sin(_hold_t * 2.0) * 0.01 * exp(-_hold_t * 0.5)
		if _hold_t > 5.0:
			pass  # vc183: no words during the flight
			reset_all()
			if _clock != null:
				_clock.visible = false

func _set_glow_size(sp: Sprite3D, base: float) -> void:
	if _camera == null:
		return
	var dist: float = sp.global_position.distance_to(_camera.global_position)
	var min_size: float = dist * tan(deg_to_rad(0.3))
	var sz: float = base
	if not reduce_effects and min_size > sz:
		sz = min_size
	sp.scale = Vector3(sz, sz, 1.0)


# ---------------- vc181 real-Sun ground shadows ----------------
# Each tall part (tower, booster, ship, mount, buildings, crane, tank) gets a
# soft dark strip on the ground, stretched AWAY from the real Sun, length =
# height / tan(Sun elevation). It is drawn over passthrough, so it lands on
# the real ground (correct where the ground is flat, like the pad itself).
# Booster/ship shadows follow them in flight and fade out once they are
# high up. Sun below the horizon: no shadows. 1 draw call per strip, ~9.
var _shadows: Node3D = null
var _shadow_mat: ShaderMaterial = null
var _shadow_parts: Array = []  # [MeshInstance3D, kind]

func _build_shadows() -> void:
	_shadows = Node3D.new()
	_shadows.name = "SunShadows"
	add_child(_shadows)
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = Shader.new()
	_shadow_mat.shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled; uniform float a = 0.5; void fragment(){ float across = 1.0 - smoothstep(0.6, 1.0, abs(UV.x * 2.0 - 1.0)); float along = 1.0 - smoothstep(0.75, 1.0, UV.y); ALBEDO = vec3(0.0); ALPHA = a * across * along; }"
	_shadow_parts = []
	for k in ["tower", "booster", "ship", "mount", "bldg", "tank", "crane", "boom", "pad"]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		mi.mesh = pm
		mi.material_override = _shadow_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadows.add_child(mi)
		_shadow_parts.append([mi, k])

func _strip(mi: MeshInstance3D, base: Vector3, y0: float, y1: float, w: float, away: Vector3, perp: Vector3, cot: float) -> void:
	# base: point on the ground under the object; y0..y1: object height span above ground.
	var l0: float = max(y0, 0.0) * cot
	var l1: float = min(max(y1, 0.0) * cot, 1500.0 * _scale)
	var length: float = max(l1 - l0, 0.1) + w * 0.5
	var c: Vector3 = base + away * ((l0 + l1) * 0.5)
	c.y = _pad.y + 0.06 * _scale
	mi.global_transform = Transform3D(Basis(perp * w, Vector3.UP, away * length), c)
	mi.visible = true

func _update_shadows() -> void:
	if _shadows == null:
		return
	var on: bool = mode != "off" and sun_dir.y > 0.035
	_shadows.visible = on
	if not on:
		return
	var s: float = _scale
	var away: Vector3 = Vector3(-sun_dir.x, 0.0, -sun_dir.z)
	if away.length() < 0.001:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	var perp: Vector3 = Vector3(-away.z, 0.0, away.x)
	var cot: float = sqrt(max(1.0 - sun_dir.y * sun_dir.y, 0.0)) / max(sun_dir.y, 0.035)
	# Darker shadow in high Sun, softer near sunset.
	_shadow_mat.set_shader_parameter("a", clamp(0.25 + sun_dir.y * 0.6, 0.25, 0.55))
	var g: float = _pad.y
	for part in _shadow_parts:
		var mi: MeshInstance3D = part[0]
		var k: String = part[1]
		mi.visible = false
		if k == "tower" and _tower != null and _tower.visible:
			_strip(mi, Vector3(_tower_pos.x, g, _tower_pos.z), 0.0, 145.0 * s, 10.0 * s, away, perp, cot)
		elif k == "mount" and _mount != null and _mount.visible:
			_strip(mi, Vector3(_pad.x, g, _pad.z), 0.0, 20.0 * s, 24.0 * s, away, perp, cot)
		elif k == "pad" and _mount != null and _mount.visible:
			_strip(mi, Vector3(_pad.x, g, _pad.z), 0.0, 1.0 * s, 60.0 * s, away, perp, cot)
		elif k == "booster" and _booster != null and _booster.visible:
			var by: float = _booster.global_position.y - g
			if by - 35.0 * s < 400.0 * s:
				_strip(mi, Vector3(_booster.global_position.x, g, _booster.global_position.z), by - 35.0 * s, by + 35.0 * s, 9.0 * s, away, perp, cot)
		elif k == "ship" and _ship != null and _ship.visible:
			var sy: float = _ship.global_position.y - g
			if sy - 18.0 * s < 400.0 * s:
				_strip(mi, Vector3(_ship.global_position.x, g, _ship.global_position.z), sy - 18.0 * s, sy + 33.0 * s, 9.0 * s, away, perp, cot)
		elif _surround != null and _surround.visible and _surround.get_child_count() >= 4:
			var ch: Array = _surround.get_children()
			if k == "bldg":
				var p0: Vector3 = (ch[0] as Node3D).global_position
				_strip(mi, Vector3(p0.x, g, p0.z), 0.0, 12.0 * s, 18.0 * s, away, perp, cot)
			elif k == "tank":
				var p1: Vector3 = (ch[1] as Node3D).global_position
				_strip(mi, Vector3(p1.x, g, p1.z), 0.0, 15.0 * s, 10.0 * s, away, perp, cot)
			elif k == "crane":
				var p2: Vector3 = (ch[2] as Node3D).global_position
				_strip(mi, Vector3(p2.x, g, p2.z), 0.0, 35.0 * s, 2.0 * s, away, perp, cot)


# ---------------- vc182 smoke helpers ----------------
var _exhaust: GPUParticles3D = null
var _smoke_tex: ImageTexture = null

func _puff_quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	return q

func _smoke_material() -> StandardMaterial3D:
	if _smoke_tex == null:
		# Soft lumpy puff: radial falloff broken up by layered noise.
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var nz := FastNoiseLite.new()
		nz.seed = 77
		nz.frequency = 0.035
		nz.fractal_octaves = 4
		for y in range(64):
			for x in range(64):
				var d: float = Vector2(float(x) - 31.5, float(y) - 31.5).length() / 31.5
				var n: float = nz.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var a: float = pow(clamp(1.0 - d, 0.0, 1.0), 1.3) * (0.6 + 0.5 * n)
				var shade: float = 0.82 + 0.18 * n
				img.set_pixel(x, y, Color(shade, shade, shade, clamp(a, 0.0, 1.0)))
		img.generate_mipmaps()
		_smoke_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _smoke_tex
	m.disable_receive_shadows = true
	return m

func _curve_tex(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for p in pts:
		c.add_point(p)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

func _ramp_tex(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for st in stops:
		g.add_point(st[0], st[1])
	# remove the two default points Gradient starts with (0 black, 1 white)
	while g.get_point_count() > stops.size():
		g.remove_point(0)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


# vc183: while Starship is out, let the headset camera draw up to 60 km, so
# the climbing stack and the returning booster never vanish past the old
# 4 km limit and "pop" back in. Restored when Starship is reset.
var _far_saved: float = -1.0
func _set_far(on: bool) -> void:
	if _camera == null or not (_camera is Camera3D):
		return
	var cam: Camera3D = _camera as Camera3D
	if on:
		if _far_saved < 0.0:
			_far_saved = cam.far
		cam.far = 60000.0
	elif _far_saved > 0.0:
		cam.far = _far_saved
		_far_saved = -1.0
