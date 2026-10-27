# Fresh planets + Moon + Sun, written 2026-10-26.
# Bodies live on the sky sphere like stars, in passthrough.
# Bring-to-you (user direction): when a body is selected, it moves
# from the sky to a spot in front of the user, in passthrough,
# instead of the user leaving the real room. Focused body returns
# to the sky when deselected. Hand-tracking pinch calls
# select_body() — the pinch detection itself is the next step.
extends Node3D

@export var lat_deg: float = 28.5496
@export var lon_deg: float = -81.7729
@export var yaw_offset_deg: float = 0.0

const AstroMathScript = preload("res://scripts/astro_math.gd")

var _bodies: Dictionary = {}
var _body_radius: Dictionary = {}
var _focused: String = ""
var _telescope: String = ""
var _travel: String = ""
# v22 UI (zero API, local only): highlight + zoom dial state.
# _zoom applies to the SELECTED planet only (room and telescope
# scale); it resets on Back / new selection, never on sky bodies.
var _zoom: float = 1.0
var _glow: MeshInstance3D = null
var _dial: Node3D = null
var _dial_handle: MeshInstance3D = null
var _dial_label: Label3D = null
var _travel_sphere: MeshInstance3D = null
var _sun_light: DirectionalLight3D = null
var _last_update: float = -1.0

func _make_saturn_ring_texture() -> ImageTexture:
	var img: Image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y: int in range(512):
		for x: int in range(512):
			var dx: float = (float(x) - 255.5) / 255.5
			var dy: float = (float(y) - 255.5) / 255.5
			var r: float = sqrt(dx * dx + dy * dy)
			# Normalised: outer edge = 1.0, inner edge = 0.48
			# (1.1 / 2.27 planet radii). Cassini division
			# gap at 0.78-0.84, bands vary by radius.
			var a: float = 0.0
			if r >= 0.48 and r <= 1.0:
				if r >= 0.78 and r <= 0.84:
					a = 0.05
				else:
					a = 0.55 + 0.25 * sin(r * 40.0) + 0.15 * sin(r * 90.0)
					a = clamp(a, 0.25, 0.85)
			img.set_pixel(x, y, Color(0.85, 0.80, 0.68, a))
	return ImageTexture.create_from_image(img)

# v17 Mars rover travel — ONE real panorama only.
# Curiosity, Rocknest, Gale Crater, Oct-Nov 2012, Mastcam,
# ~900 images, white-balanced to Earth lighting.
# Source: NASA/JPL-Caltech/MSSS, via Wikimedia Commons
# (PIA16453, 13726x3008, downscaled to 4096x897 for Quest).
# Cylindrical panorama, not a full sphere — top/bottom
# stretch on a sphere, horizon is the honest part.
# Never presented as live, never as a different rover/place.
const TRAVEL_TEXTURES: Dictionary = {
	"Mars": "res://data/travel/mars_rocknest_360.jpg",
}

# v14 all planets textured — REAL scans only, no invented detail.
# Solar System Scope textures, CC BY 4.0, attribution in repo.
# Venus uses the atmosphere texture (what you actually see),
# not the radar surface map. Saturn sphere only in v14 —
# its ring is a separate mesh, not in this build.
# Simulated bodies are labelled simulated in the panel,
# never presented as real scans.
const TELESCOPE_TEXTURES: Dictionary = {
	"Sun": "res://data/textures/2k_sun.jpg",
	"Moon": "res://data/textures/2k_moon.jpg",
	"Mercury": "res://data/textures/2k_mercury.jpg",
	"Venus": "res://data/textures/2k_venus_atmosphere.jpg",
	"Mars": "res://data/textures/2k_mars.jpg",
	"Jupiter": "res://data/textures/2k_jupiter.jpg",
	"Saturn": "res://data/textures/2k_saturn.jpg",
	"Uranus": "res://data/textures/2k_uranus.jpg",
	"Neptune": "res://data/textures/2k_neptune.jpg",
}

func _ready() -> void:
	# v3 overlay sizes: real angular sizes at 85 m, not virtual
	# world sizes. Sun/Moon ~0.5 degrees = ~0.4 m at 85 m.
	# Planets are points over the real sky, not orbs to walk to.
	var defs: Array = [
		["Sun", Color(1.0, 0.85, 0.3), 0.4],
		["Moon", Color(0.9, 0.9, 0.95), 0.4],
		["Mercury", Color(0.7, 0.65, 0.6), 0.25],
		["Venus", Color(1.0, 0.85, 0.6), 0.35],
		["Mars", Color(1.0, 0.5, 0.3), 0.35],
		["Jupiter", Color(0.95, 0.75, 0.5), 0.5],
		["Saturn", Color(0.95, 0.85, 0.6), 0.45],
		["Uranus", Color(0.6, 0.85, 0.9), 0.35],
		["Neptune", Color(0.4, 0.5, 1.0), 0.35],
	]
	for d: Array in defs:
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = d[2]
		sphere.height = d[2] * 2.0
		mesh_inst.mesh = sphere
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = d[1]
		if TELESCOPE_TEXTURES.has(d[0]):
			var tex: Texture2D = load(TELESCOPE_TEXTURES[d[0]])
			if tex != null:
				mat.albedo_texture = tex
				mat.albedo_color = Color(1.0, 1.0, 1.0)
				# Real scan: show the texture itself, not a tint.
				mat.emission_enabled = false
			else:
				mat.emission_enabled = true
				mat.emission = d[1]
				mat.emission_energy_multiplier = 1.0
		else:
			mat.emission_enabled = true
			mat.emission = d[1]
			mat.emission_energy_multiplier = 1.0
		if d[0] == "Moon":
			# v21 phase: Moon is the ONLY shaded body, so the
			# Sun light above gives it a real terminator.
			# Full disc was wrong — tonight is waning gibbous,
			# so part of the Moon must be dark, in sky, room,
			# and telescope alike. No emission, or the dark
			# side would glow and the phase would vanish.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mat.roughness = 1.0
			mat.metallic = 0.0
		else:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_inst.material_override = mat
		# v18 tilt: set once, rotation in _process spins
		# around this tilted local Y axis.
		if AXIAL_TILT_DEG.has(d[0]):
			mesh_inst.rotation.x = deg_to_rad(float(AXIAL_TILT_DEG[d[0]]))
		if d[0] == "Saturn":
			# v21 ring: real Saturn rings, flat annulus, child
			# of the sphere so it scales with sky / room /
			# telescope and tilts with the planet (26.73°).
			# Inner 1.1× planet radius, outer 2.27×, Cassini
			# division gap, pale beige-grey, transparent.
			# No ring in v14-v20 was the biggest "not Saturn"
			# tell in telescope and in the room.
			var ring_inst: MeshInstance3D = MeshInstance3D.new()
			var plane: PlaneMesh = PlaneMesh.new()
			plane.size = Vector2(2.04, 2.04)
			ring_inst.mesh = plane
			ring_inst.rotation.x = -PI / 2.0
			var rmat: StandardMaterial3D = StandardMaterial3D.new()
			rmat.albedo_texture = _make_saturn_ring_texture()
			rmat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			ring_inst.material_override = rmat
			ring_inst.name = "SaturnRing"
			mesh_inst.add_child(ring_inst)
		mesh_inst.name = d[0]
		add_child(mesh_inst)
		_bodies[d[0]] = mesh_inst
		_body_radius[d[0]] = d[2]
	# v21 Moon phase light: a single DirectionalLight that
	# points from the Sun's real direction. Only the Moon
	# uses shaded material (below), so only the Moon gets
	# a terminator — planets stay unshaded, stars stay
	# unshaded, passthrough is untouched. The light is
	# updated every second in _update_bodies, so the phase
	# is always tonight's real phase, never a full disc.
	_sun_light = DirectionalLight3D.new()
	_sun_light.light_energy = 1.2
	_sun_light.shadow_enabled = false
	_sun_light.name = "SunLight"
	add_child(_sun_light)
	# v17 travel sphere: opaque, 20 m radius, centred on the
	# origin. It blocks passthrough + sky on purpose — travel
	# is full VR, not AR. scale.x = -1 so the panorama reads
	# the right way round from inside the sphere.
	_travel_sphere = MeshInstance3D.new()
	var tsphere: SphereMesh = SphereMesh.new()
	tsphere.radius = 20.0
	tsphere.height = 40.0
	_travel_sphere.mesh = tsphere
	var tmat: StandardMaterial3D = StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if TRAVEL_TEXTURES.has("Mars"):
		var ttex: Texture2D = load(TRAVEL_TEXTURES["Mars"])
		if ttex != null:
			tmat.albedo_texture = ttex
			tmat.albedo_color = Color(1.0, 1.0, 1.0)
	_travel_sphere.material_override = tmat
	_travel_sphere.scale = Vector3(-1.0, 1.0, 1.0)
	_travel_sphere.visible = false
	_travel_sphere.name = "TravelSphere"
	add_child(_travel_sphere)
	# v22 highlight glow: one transparent shell, reused for the
	# focused planet only. Non-focused bodies never get it, and
	# it follows the focused body in _process (room/telescope),
	# hidden on Back, on travel, and when nothing is focused.
	_glow = MeshInstance3D.new()
	var gsphere: SphereMesh = SphereMesh.new()
	gsphere.radius = 1.0
	gsphere.height = 2.0
	gsphere.radial_segments = 16
	gsphere.rings = 8
	_glow.mesh = gsphere
	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.9, 0.6, 0.22)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow.material_override = gmat
	_glow.visible = false
	_glow.name = "HighlightGlow"
	add_child(_glow)
	# v22 zoom dial: room-mode only, at a fixed spot right of
	# the focused planet (world origin space, same space the
	# focused planet sits in). Ring + handle + small value
	# label. No menu, no scrolling. Hidden unless a planet
	# is focused and not in telescope/travel.
	_dial = Node3D.new()
	_dial.position = Vector3(0.7, -0.3, -2.2)
	_dial.name = "ZoomDial"
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.13
	torus.outer_radius = 0.16
	ring.mesh = torus
	var rmat: StandardMaterial3D = StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 1.0, 1.0)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat
	_dial.add_child(ring)
	_dial_handle = MeshInstance3D.new()
	var hsphere: SphereMesh = SphereMesh.new()
	hsphere.radius = 0.035
	hsphere.height = 0.07
	_dial_handle.mesh = hsphere
	var hmat: StandardMaterial3D = StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.85, 0.3)
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dial_handle.material_override = hmat
	_dial.add_child(_dial_handle)
	_dial_label = Label3D.new()
	_dial_label.font_size = 24
	_dial_label.pixel_size = 0.002
	_dial_label.width = 120
	_dial_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_dial_label.position = Vector3(0.0, 0.24, 0.0)
	_dial.add_child(_dial_label)
	_dial.visible = false
	add_child(_dial)
	_update_dial()
	_update_bodies(true)

# v18 rotation: correct tilt + direction, time-lapse ONLY.
# Real rotation is invisible in real time (Mars day 24.6 h,
# Jupiter 9.9 h, Venus 243 days). Factor 600x = 1 sec in app
# is 10 min real. Speed = 60 / period_hours degrees/sec.
# Tilt > 90 (Venus 177, Uranus 98) makes the spin look
# retrograde/sideways, which is the real geometry, not a
# fake reverse. Rotation applies to focused/telescope
# bodies only — sky dots are too small to read spin, and
# rotation never changes sky position or calibration.
const ROTATION_PERIOD_H: Dictionary = {
	"Sun": 609.0, "Moon": 655.0, "Mercury": 1407.0,
	"Venus": 5832.0, "Mars": 24.6, "Jupiter": 9.9,
	"Saturn": 10.7, "Uranus": 17.2, "Neptune": 16.1,
}
const AXIAL_TILT_DEG: Dictionary = {
	"Sun": 7.25, "Moon": 1.54, "Mercury": 0.03,
	"Venus": 177.36, "Mars": 25.19, "Jupiter": 3.13,
	"Saturn": 26.73, "Uranus": 97.77, "Neptune": 28.32,
}

func _process(delta: float) -> void:
	# Rotation, focused/telescope only, time-lapse 600x.
	var rotating: Array = []
	if _focused != "" and not rotating.has(_focused):
		rotating.append(_focused)
	if _telescope != "" and not rotating.has(_telescope):
		rotating.append(_telescope)
	for name: String in rotating:
		if _bodies.has(name) and ROTATION_PERIOD_H.has(name):
			var speed_deg: float = 60.0 / float(ROTATION_PERIOD_H[name])
			_bodies[name].rotate_y(deg_to_rad(speed_deg) * delta)
	# v22 highlight + smooth zoom, every frame (not 1/sec):
	# focused/telescope scale lerps toward base * zoom * pulse,
	# so dial changes zoom smoothly instead of jumping.
	# Glow follows only the focused body; dial shows in room
	# mode only (in telescope the planet fills the view).
	if _focused != "" and _travel == "" and _bodies.has(_focused):
		var fbody: MeshInstance3D = _bodies[_focused]
		var base: float = 4.0 if _telescope != "" else 1.5
		var pulse: float = 1.0 + (0.05 if _telescope != "" else 0.10) * sin(Time.get_unix_time_from_system() * 4.0)
		var target: float = base * _zoom * pulse
		fbody.scale = fbody.scale.lerp(Vector3(target, target, target), 0.25)
		if _glow != null:
			_glow.visible = true
			_glow.global_position = fbody.global_position
			var gw: float = float(_body_radius.get(_focused, 0.35)) * fbody.scale.x * 1.7
			_glow.scale = Vector3(gw, gw, gw)
		if _dial != null:
			_dial.visible = _telescope == ""
	else:
		if _glow != null:
			_glow.visible = false
		if _dial != null:
			_dial.visible = false
	var now: float = Time.get_unix_time_from_system()
	if abs(now - _last_update) >= 1.0:
		_update_bodies(false)

func _body_dir(name: String, jds: Dictionary) -> Vector3:
	if name == "Moon":
		return AstroMathScript.moon_world_dir(jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg)
	return AstroMathScript.planet_world_dir(name, jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg)

func _update_bodies(_force: bool) -> void:
	var now: float = Time.get_unix_time_from_system()
	_last_update = now
	if _travel_sphere != null:
		_travel_sphere.visible = _travel != ""
		_travel_sphere.global_position = Vector3(0, 0, 0)
	var jds: Dictionary = AstroMathScript.jds_from_unix(now)
	# v21 Moon phase light: point the light from the Sun's
	# real direction toward the origin. DirectionalLight
	# shines along -Z of its transform, so look_at origin.
	if _sun_light != null:
		var sdir: Vector3 = _body_dir("Sun", jds)
		_sun_light.global_position = sdir * 100.0
		var upv: Vector3 = Vector3.UP if abs(sdir.y) < 0.95 else Vector3.RIGHT
		_sun_light.look_at(Vector3.ZERO, upv)
	for name: String in _bodies.keys():
		var mesh_inst: MeshInstance3D = _bodies[name]
		if name == _travel:
			# Travel: hide the room Mars orb, the panorama
			# sphere IS Mars around you. Restored on exit.
			mesh_inst.visible = false
			continue
		mesh_inst.visible = true
		if name == _telescope:
			# Telescope zoom: closer, bigger, locked centre.
			# No drift, no fake detail — the texture is the scan.
			# Scale is set in _process (base * zoom * pulse),
			# not here, so dial zoom stays smooth, not 1/sec.
			var target: Vector3 = Vector3(0, 0, -2.0)
			mesh_inst.global_position = mesh_inst.global_position.lerp(target, 0.35)
		elif name == _focused:
			# Bring-to-you: 3 metres in front of the origin, in
			# passthrough. In-headset the camera is at the origin
			# looking down -Z, so this is in front of the user.
			# Scale is set in _process (base * zoom * pulse).
			var target: Vector3 = Vector3(0, 0, -3.0)
			mesh_inst.global_position = mesh_inst.global_position.lerp(target, 0.25)
		else:
			var dir: Vector3 = _body_dir(name, jds)
			# v21 horizon hide, sky mode only: below-horizon
			# bodies are hidden, not shown over the room.
			# Focused / telescope / travel bodies above stay
			# visible — they are in the room, not in the sky.
			mesh_inst.visible = dir.y >= 0.0
			mesh_inst.global_position = dir * 85.0
			mesh_inst.scale = Vector3(1.0, 1.0, 1.0)

# v22 zoom dial API (Main calls these; no lock/teacher code here).
func zoom_factor() -> float:
	return _zoom

func set_zoom(v: float) -> void:
	_zoom = clamp(v, 1.0, 10.0)
	_update_dial()

func step_zoom() -> void:
	# Quick-pinch dial: 1 -> 2 -> 4 -> 7 -> 10 -> 1.
	# Drag (hand_tracking pinch_drag) adjusts smoothly between.
	if _zoom < 2.0:
		set_zoom(2.0)
	elif _zoom < 4.0:
		set_zoom(4.0)
	elif _zoom < 7.0:
		set_zoom(7.0)
	elif _zoom < 10.0:
		set_zoom(10.0)
	else:
		set_zoom(1.0)

func dial_position() -> Vector3:
	if _dial != null:
		return _dial.global_position
	return Vector3(0.7, -0.3, -2.2)

func _update_dial() -> void:
	if _dial_handle == null or _dial_label == null:
		return
	var t: float = (_zoom - 1.0) / 9.0
	var ang: float = lerp(-2.36, 2.36, t)
	_dial_handle.position = Vector3(cos(ang) * 0.145, sin(ang) * 0.145, 0.0)
	_dial_label.text = "Zoom %.1fx" % _zoom

func select_body(name: String) -> void:
	if _bodies.has(name):
		# New selection starts at 1x; highlight (glow in
		# _process) follows the new focused body automatically.
		if _focused != name:
			_zoom = 1.0
			_update_dial()
		_focused = name
		print("Star App: focused ", name, " (bring-to-you, passthrough)")

func clear_focus() -> void:
	_focused = ""
	_telescope = ""
	_travel = ""
	# Back resets zoom + highlight (glow hidden in _process).
	_zoom = 1.0
	_update_dial()

func set_travel(name: String) -> void:
	if TRAVEL_TEXTURES.has(name) and _bodies.has(name):
		_focused = name
		_telescope = ""
		_travel = name
		print("Star App: rover travel ", name)

func clear_travel() -> void:
	_travel = ""

func travel_body() -> String:
	return _travel

func has_travel(name: String) -> bool:
	return TRAVEL_TEXTURES.has(name)

func focused_body() -> String:
	return _focused

func set_telescope(name: String) -> void:
	if _bodies.has(name):
		_focused = name
		_telescope = name
		print("Star App: telescope zoom ", name)

func clear_telescope() -> void:
	_telescope = ""

func telescope_body() -> String:
	return _telescope

func is_real_scan(name: String) -> bool:
	return TELESCOPE_TEXTURES.has(name)

# Current world directions of all bodies, for tap-to-identify.
# A focused (brought-to-you) body keeps its sky direction here,
# so a second pinch on it still identifies it, not empty sky.
func body_directions() -> Dictionary:
	var jds: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	var out: Dictionary = {}
	for name: String in _bodies.keys():
		out[name] = _body_dir(name, jds).normalized()
	return out
