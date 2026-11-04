class_name TravelRide
extends Node3D
## Ride on 3I/ATLAS. Needs ephemeris.gd in the project.
##
## Scene setup (see the prompts):
##   - A static "surface" platform under the player (does NOT move: it is the comfort anchor).
##   - streak_instance: a MeshInstance3D with material_override = ShaderMaterial(ride_streaks.gdshader)
##     (this script builds its mesh). Keep it at the origin, unrotated.
##   - vignette_instance: a small sphere MeshInstance3D, child of the XRCamera3D, with
##     material_override = ShaderMaterial(ride_comfort_vignette.gdshader), render_priority 100.
##   - sun_marker: any small bright node. It is placed where the Sun really is, behind you.
## Call start_ride() from the TRAVEL flow.

signal ride_started
signal ride_finished

enum Comfort { SENSITIVE, NORMAL, THRILL }

@export var comfort: Comfort = Comfort.NORMAL
@export var ride_seconds := 45.0
@export var ramp_up_seconds := 6.0
@export var ramp_down_seconds := 5.0
@export var fade_seconds := 1.5
@export var camera: Node3D
@export var streak_instance: MeshInstance3D
@export var vignette_instance: MeshInstance3D
@export var sun_marker: Node3D
@export var sun_marker_distance := 800.0
@export var streak_count := 1500

const VISUAL_SPEED := [8.0, 16.0, 28.0]      # apparent flow speed in m/s (exaggerated, on purpose)
const VIGNETTE_MAX := [0.75, 0.50, 0.22]
const BOX_Z := 160.0

var running := false
var elapsed := 0.0
var speed_norm := 0.0                         # 0..1 ramp
var _travel := 0.0
var _streak_mat: ShaderMaterial
var _vig_mat: ShaderMaterial
var _geo: Dictionary = {}


func _ready() -> void:
	if streak_instance:
		streak_instance.mesh = build_streak_mesh(streak_count)
		streak_instance.top_level = true
		streak_instance.global_transform = Transform3D.IDENTITY
		streak_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_streak_mat = streak_instance.material_override as ShaderMaterial
	if vignette_instance:
		_vig_mat = vignette_instance.material_override as ShaderMaterial
	_apply()


func start_ride(jd: float = -1.0) -> void:
	if running:
		return
	if jd < 0.0:
		jd = Ephemeris.now_jd()
	_geo = ride_geometry(jd)
	if sun_marker:
		sun_marker.position = _geo.sun_dir * sun_marker_distance
	elapsed = 0.0
	running = true
	ride_started.emit()


func stop_ride() -> void:
	if not running:
		return
	running = false
	speed_norm = 0.0
	_apply()
	ride_finished.emit()


## Real numbers for the HUD or the AI guide.
func get_readout() -> Dictionary:
	return _geo


func _process(delta: float) -> void:
	if running:
		elapsed += delta
		speed_norm = _ramp(elapsed)
		_travel = fmod(_travel + speed_norm * VISUAL_SPEED[comfort] * delta, BOX_Z)
		if elapsed >= ride_seconds:
			stop_ride()
			return
	_apply()


func _ramp(t: float) -> float:
	if t < ramp_up_seconds:
		return smootherstep01(t / ramp_up_seconds)
	if t < ride_seconds - ramp_down_seconds:
		return 1.0
	return 1.0 - smootherstep01((t - (ride_seconds - ramp_down_seconds)) / ramp_down_seconds)


static func smootherstep01(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * c * (c * (c * 6.0 - 15.0) + 10.0)


func _apply() -> void:
	if _streak_mat:
		var cam_pos := camera.global_position if camera else Vector3.ZERO
		_streak_mat.set_shader_parameter("cam_pos", cam_pos)
		_streak_mat.set_shader_parameter("travel", _travel)
		_streak_mat.set_shader_parameter("speed", speed_norm * VISUAL_SPEED[comfort])
	if _vig_mat:
		var fade := 0.0
		if running:
			fade = maxf(1.0 - smootherstep01(elapsed / fade_seconds),
					1.0 - smootherstep01((ride_seconds - elapsed) / fade_seconds))
		_vig_mat.set_shader_parameter("strength", speed_norm * VIGNETTE_MAX[comfort])
		_vig_mat.set_shader_parameter("fade", fade)


## Where the Sun and Earth are, as seen by someone riding the comet, in ride axes
## (forward = -Z = direction of travel, up = +Y, right = +X). Also real numbers for the HUD.
static func ride_geometry(jd: float) -> Dictionary:
	var p := Ephemeris.atlas_helio(jd)
	var v := Ephemeris.atlas_helio(jd + 0.5) - Ephemeris.atlas_helio(jd - 0.5)
	var f := v.normalized()
	var up_e := Vector3(0.0, 0.0, 1.0)                 # ecliptic north
	var up := (up_e - f * up_e.dot(f)).normalized()
	var right := f.cross(up)
	var earth := Ephemeris.planet_helio("earth", jd)
	var to_sun := (-p).normalized()
	var to_earth := (earth - p).normalized()
	var sun_dist := p.length()
	return {
		"sun_dir": Vector3(to_sun.dot(right), to_sun.dot(up), -to_sun.dot(f)),
		"earth_dir": Vector3(to_earth.dot(right), to_earth.dot(up), -to_earth.dot(f)),
		"speed_kms": Ephemeris.atlas_speed_kms(jd),
		"sun_dist_au": sun_dist,
		"earth_dist_au": (earth - p).length(),
		"sun_angular_diameter_arcmin": 0.5334 * 60.0 / sun_dist,
		"sun_magnitude": -26.74 + 5.0 * log(sun_dist) / log(10.0),
	}


static func build_streak_mesh(count: int, seed_value: int = 7) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in count:
		var r := Vector2(rng.randf(), rng.randf())
		for c in 4:
			verts.append(Vector3.ZERO)          # real positions are computed in the shader
			uvs.append(corners[c])
			uv2s.append(r)
		var b := i * 4
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	return m
