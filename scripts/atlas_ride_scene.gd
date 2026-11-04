# 3I/ATLAS ride scene — added 2026-11-01, travel_ride.gd by the user, math unchanged.
# Comfort rule, from the user: you can feel fast without being moved.
# The platform never moves, the camera is never rotated or moved
# artificially, the platform and the horizon stay still, only the
# streaks and chunks stream past. Speed ramps up over 6 s, down over 5 s
# (TravelRide defaults). ride_seconds is 45 for the app; 25 is for the
# demo video only, not this app build.
# FPS guard: if the headset is running below 72 fps when the ride is
# requested, the ride is skipped and a still view is shown instead.
# (Guard is skipped outside XR, so headless tests do not false-trip it.)
extends Node3D
class_name AtlasRideScene

signal ride_started
signal ride_finished

const COMFORT_PATH := "user://ride_comfort.cfg"
const NARRATION_FACTS: Array = [
	"The Sun is now a tiny point, 2,400 times brighter than the full Moon.",
	"Earth is hidden in the Sun's glare.",
	"The tail streams ahead because the comet is leaving the Sun.",
	"At this speed, Alpha Centauri is 22,000 years away.",
]

var ride: TravelRide = null
var streak_instance: MeshInstance3D = null
var vignette_instance: MeshInstance3D = null
var sun_marker: MeshInstance3D = null
var platform: Node3D = null
var info_panel: Label3D = null
var prompt_active: bool = false
var ride_active: bool = false
var still_view_only: bool = false

var _camera: Node3D = null
var _prompt_nodes: Array = []
var _narration_idx: int = 0
var _narration_acc: float = 0.0
var _instant_stop: bool = false
var _stop_t: float = 0.0
var _fps_low: bool = false

func setup(camera: Node3D) -> void:
	_camera = camera
	_build_platform()
	_build_streak_and_vignette()
	_build_lights_and_tail()
	_build_chunks()
	_build_info_panel()
	ride = TravelRide.new()
	ride.camera = _camera
	ride.streak_instance = streak_instance
	ride.vignette_instance = vignette_instance
	ride.sun_marker = sun_marker
	ride.comfort = load_comfort()
	ride.ride_seconds = 45.0
	ride.ride_started.connect(func(): ride_active = true; ride_started.emit())
	ride.ride_finished.connect(_on_ride_finished)
	add_child(ride)
	# _ready() on the ride runs when the tree processes, which is after
	# setup() in the app flow, but do not rely on that timing for the mesh:
	# build it now if it is not built yet, so start_ride() can never run on a null mesh.
	if streak_instance.mesh == null:
		streak_instance.mesh = TravelRide.build_streak_mesh(ride.streak_count)
	visible = false

static func load_comfort() -> int:
	var f := FileAccess.open(COMFORT_PATH, FileAccess.READ)
	if f == null:
		return TravelRide.Comfort.NORMAL
	var v := int(f.get_as_text().strip_edges())
	f.close()
	return clampi(v, 0, 2)

static func save_comfort(v: int) -> void:
	var f := FileAccess.open(COMFORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(v))
	f.close()

static func has_saved_comfort() -> bool:
	return FileAccess.file_exists(COMFORT_PATH)

func _build_platform() -> void:
	platform = Node3D.new()
	platform.name = "AtlasPlatform"
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.2
	cm.height = 0.4
	base.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.13, 0.11)  # dark charcoal-brown rock
	base.material_override = mat
	platform.add_child(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 8:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.25, 0.6)
		sm.height = sm.radius * 1.2
		rock.mesh = sm
		rock.material_override = mat
		rock.position = Vector3(rng.randf_range(-2.5, 2.5), 0.2, rng.randf_range(-2.5, 2.5))
		platform.add_child(rock)
	for i in 5:
		var ice := MeshInstance3D.new()
		var im := CylinderMesh.new()
		im.top_radius = rng.randf_range(0.4, 0.8)
		im.bottom_radius = im.top_radius
		im.height = 0.03
		ice.mesh = im
		var imat := StandardMaterial3D.new()
		imat.albedo_color = Color(0.85, 0.92, 0.95)  # pale ice
		ice.material_override = imat
		ice.position = Vector3(rng.randf_range(-2.5, 2.5), 0.21, rng.randf_range(-2.5, 2.5))
		platform.add_child(ice)
	add_child(platform)

func _build_streak_and_vignette() -> void:
	streak_instance = MeshInstance3D.new()
	streak_instance.name = "RideStreaks"
	var smat := ShaderMaterial.new()
	smat.shader = load("res://scripts/ride_streaks.gdshader")
	streak_instance.material_override = smat
	add_child(streak_instance)
	# Vignette sphere is a child of the camera, per the prompt, not of this node.
	vignette_instance = MeshInstance3D.new()
	vignette_instance.name = "RideVignette"
	var vm := SphereMesh.new()
	vm.radius = 0.3
	vm.height = 0.6
	vignette_instance.mesh = vm
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://scripts/ride_comfort_vignette.gdshader")
	# Godot 4.3: render_priority lives on the MATERIAL, not on MeshInstance3D.
	vmat.render_priority = 100
	vignette_instance.material_override = vmat
	if _camera != null:
		_camera.add_child(vignette_instance)
	sun_marker = MeshInstance3D.new()
	sun_marker.name = "RideSunMarker"
	var sunm := SphereMesh.new()
	sunm.radius = 1.0
	sunm.height = 2.0
	sun_marker.mesh = sunm
	var sunmat := StandardMaterial3D.new()
	sunmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sunmat.emission_enabled = true
	sunmat.emission = Color(1.0, 0.98, 0.9)
	sunmat.emission_energy_multiplier = 20.0
	sun_marker.material_override = sunmat
	add_child(sun_marker)

func _build_lights_and_tail() -> void:
	# Dim hard light from the Sun's direction — set at ride start, see start_ride.
	var light := DirectionalLight3D.new()
	light.name = "RideSunLight"
	light.light_energy = 0.6
	light.shadow_enabled = true
	add_child(light)
	# Faint soft glow around the platform (the coma).
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 5.0
	gm.height = 10.0
	glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.6, 0.85, 1.0, 0.07)
	glow.material_override = gmat
	glow.position = Vector3(0, 0.5, 0)
	add_child(glow)
	var omni := OmniLight3D.new()
	omni.light_energy = 0.3
	omni.omni_range = 12.0
	omni.position = Vector3(0, 1.0, 0)
	add_child(omni)
	# Thin, faint dust tail stretching ahead in the direction of travel (-Z).
	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.8, 0.8, 30.0)
	tail.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color = Color(0.7, 0.85, 1.0, 0.12)
	tail.material_override = tmat
	tail.position = Vector3(0, 0.5, -16.0)
	add_child(tail)
	# Gentle gas jets on the sunward side: small, subtle, static (no CPU animation).
	# Sunward side is resolved at ride start; these are placed toward +Z (behind,
	# where the Sun sits on this ride) and are kept small on purpose.
	for i in 4:
		var jet := MeshInstance3D.new()
		var jm := CylinderMesh.new()
		jm.top_radius = 0.05
		jm.bottom_radius = 0.25
		jm.height = 1.2
		jet.mesh = jm
		var jmat := StandardMaterial3D.new()
		jmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		jmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		jmat.albedo_color = Color(0.7, 0.9, 1.0, 0.15)
		jet.material_override = jmat
		jet.position = Vector3(-1.5 + float(i) * 1.0, 0.8, 2.2)
		add_child(jet)

func _build_chunks() -> void:
	# 50 low-poly chunks, one draw each, positions in the vertex shader only.
	var chunk_shader := load("res://scripts/ride_chunks.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 50:
		var inst := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 6
		sm.rings = 4
		sm.radius = 1.0
		sm.height = 2.0
		inst.mesh = sm
		var mat := ShaderMaterial.new()
		mat.shader = chunk_shader
		mat.set_shader_parameter("seed", float(i) * 1.37 + 0.5)
		mat.set_shader_parameter("chunk_scale", rng.randf_range(0.2, 0.6))
		mat.set_shader_parameter("chunk_color", Color(0.16, 0.13, 0.11) if i % 3 != 0 else Color(0.85, 0.92, 0.95))
		inst.material_override = mat
		inst.top_level = true
		inst.global_transform = Transform3D.IDENTITY
		add_child(inst)
		inst.set_meta("ride_chunk", true)

func _build_info_panel() -> void:
	info_panel = Label3D.new()
	info_panel.font_size = 32
	info_panel.width = 400
	info_panel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	info_panel.outline_size = 2
	info_panel.outline_modulate = Color(0.0, 0.0, 0.0)
	add_child(info_panel)

func show_comfort_prompt() -> void:
	if prompt_active:
		return
	prompt_active = true
	var labels := ["Sensitive", "Normal", "Thrill"]
	for i in 3:
		var l := Label3D.new()
		l.text = labels[i]
		l.font_size = 48
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.outline_size = 4
		l.outline_modulate = Color(0.0, 0.0, 0.0)
		add_child(l)
		_prompt_nodes.append(l)
	_position_prompt()

func _position_prompt() -> void:
	if _camera == null:
		return
	var basis := _camera.global_transform.basis
	var origin := _camera.global_position
	for i in _prompt_nodes.size():
		var node: Node3D = _prompt_nodes[i]
		node.global_position = origin + basis * Vector3(-0.6 + float(i) * 0.6, -0.2, -1.2)

func try_pick_comfort(pinch_point: Vector3) -> bool:
	if not prompt_active:
		return false
	for i in _prompt_nodes.size():
		var node: Node3D = _prompt_nodes[i]
		if pinch_point.distance_to(node.global_position) < 0.35:
			ride.comfort = i
			save_comfort(i)
			hide_comfort_prompt()
			return true
	return false

func hide_comfort_prompt() -> void:
	prompt_active = false
	for n in _prompt_nodes:
		n.queue_free()
	_prompt_nodes.clear()

func start_ride() -> bool:
	# FPS guard, XR only: below 72 fps, skip the ride, show a still view.
	if _camera != null and Engine.get_frames_per_second() > 0.0:
		# In XR, frames_per_second reports the headset rate; in editor/headless it is not 72.
		# Only enforce when an XR interface is actually running.
		var xr := XRServer.primary_interface
		if xr != null and xr.is_initialized():
			if Engine.get_frames_per_second() < 72.0:
				_fps_low = true
				still_view_only = true
				visible = true
				_show_still_view()
				return false
	_fps_low = false
	still_view_only = false
	visible = true
	# Orient the ride node so -Z is the direction of travel (comet velocity, Godot axes).
	var jd := Ephemeris.now_jd()
	var vel := (Ephemeris.atlas_helio(jd + 0.5) - Ephemeris.atlas_helio(jd - 0.5)).normalized()
	var fwd := Ephemeris.ecl_to_godot(vel).normalized()  # travel direction, world
	var up_e := Vector3(0, 1, 0)
	var up := (up_e - fwd * up_e.dot(fwd)).normalized()
	var right := fwd.cross(up)
	# Basis: X = right, Y = up, Z = -fwd (so -Z = fwd).
	global_transform = Transform3D(Basis(right, up, -fwd), global_transform.origin)
	# Platform under the player at ride start, world-locked from then on.
	if _camera != null:
		var cp := _camera.global_position
		platform.global_position = Vector3(cp.x, cp.y - 1.6, cp.z)
		info_panel.global_position = platform.global_position + Vector3(3.5, 1.6, 0.0)
	# Sun light from the Sun's direction (ride axes = this node's local axes).
	var geo := TravelRide.ride_geometry(jd)
	var light := get_node_or_null("RideSunLight") as DirectionalLight3D
	if light != null:
		light.global_position = global_position + (global_transform.basis * geo["sun_dir"]) * 20.0
		light.look_at(global_position, Vector3.UP)
	_update_info_panel()
	ride.start_ride(jd)
	_narration_idx = 0
	_narration_acc = 0.0
	return true

func _show_still_view() -> void:
	_update_info_panel()
	if info_panel != null:
		info_panel.text += "\nStill view — frame rate below 72, ride skipped."

func _update_info_panel() -> void:
	if info_panel == null or ride == null:
		return
	var geo := ride.get_readout()
	if geo.is_empty():
		geo = TravelRide.ride_geometry(Ephemeris.now_jd())
	info_panel.text = "3I/ATLAS ride\nSpeed %.1f km/s (real)\nSun %.2f AU, Earth %.2f AU\nVisual speed exaggerated.\nReal speed 59 km/s. Visual speed exaggerated." % [geo["speed_kms"], geo["sun_dist_au"], geo["earth_dist_au"]]

func instant_stop() -> void:
	if not ride_active:
		return
	_instant_stop = true
	_stop_t = 0.0

func _on_ride_finished() -> void:
	ride_active = false
	visible = false
	ride_finished.emit()

func _process(delta: float) -> void:
	if prompt_active:
		_position_prompt()
	if _instant_stop and ride != null:
		_stop_t += delta
		# Fade out fast (0.5 s) then end at once: vignette to black, speed to 0.
		var t := clampf(_stop_t / 0.5, 0.0, 1.0)
		if ride._vig_mat != null:
			ride._vig_mat.set_shader_parameter("fade", t)
		ride.speed_norm = 1.0 - t
		if t >= 1.0:
			_instant_stop = false
			ride.stop_ride()
			if ride._vig_mat != null:
				ride._vig_mat.set_shader_parameter("fade", 0.0)
		return
	if ride_active and ride != null:
		_narration_acc += delta
		if _narration_acc >= 12.0:
			_narration_acc = 0.0
			# Narration is shown on the world-locked panel, one fact every 12 s.
			# Spoken narration needs recorded lines (like the intro video voices);
			# no TTS is invented here, and the Cloudflare teacher is parked.
			if info_panel != null:
				info_panel.text = "3I/ATLAS ride\n" + NARRATION_FACTS[_narration_idx % NARRATION_FACTS.size()]
				_narration_idx += 1
		# Keep chunk shader uniforms in step with the ride travel, no CPU geometry.
		for child in get_children():
			if child is MeshInstance3D and child.has_meta("ride_chunk"):
				var m := child.material_override as ShaderMaterial
				if m != null and _camera != null:
					m.set_shader_parameter("cam_pos", _camera.global_position)
					m.set_shader_parameter("travel", ride._travel)
