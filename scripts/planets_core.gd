# Fresh planets + Moon + Sun, written 2026-10-26.
# Bodies live on the sky sphere like stars, in passthrough.
# Bring-to-you (user direction): when a body is selected, it moves
# from the sky to a spot in front of the user, in passthrough,
# instead of the user leaving the real room. Focused body returns
# to the sky when deselected. Hand-tracking pinch calls
# select_body() — the pinch detection itself is the next step.
extends Node3D

@export var lat_deg: float = 28.4152
@export var lon_deg: float = -81.7879
@export var yaw_offset_deg: float = 0.0
@export var alt_offset_deg: float = 0.0  # vc78 PRECISE: height correction from Moon lock pinch
# TEMPORARY vc34 TEST MODE ONLY — remove for the final build.
# When true, planets sit in the room in a circle (see _update_bodies)
# so pinch/highlight/hologram/travel can be tested indoors without a Moon lock.
# This is NOT real sky alignment. Real sky lock mode is test_mode = false.
var test_mode: bool = false

const AstroMathScript = preload("res://scripts/astro_math.gd")
const SkyLayoutScript = preload("res://scripts/sky_layout.gd")
var face_node: Node3D = null  # vc114: set by main to _ai_face, for keep_clear guard
var _sky_layout: Node = null  # vc114

var _bodies: Dictionary = {}
var _body_radius: Dictionary = {}
var _focused: String = ""
# Hand-hold: while a pinched hand stays near the room planet, the
# planet rides the hand instead of its anchor. Released on pinch
# release, Back, travel, or new selection. Room mode only.
var _holding: bool = false
var _hold_pos: Vector3 = Vector3(0, 0, -3.0)
var _telescope: String = ""
var _telescope_8k_body: String = ""
var _travel: String = ""
# v22 UI (zero API, local only): highlight + zoom dial state.
# _zoom applies to the SELECTED planet only (room and telescope
# scale); it resets on Back / new selection, never on sky bodies.
var _zoom: float = 1.0
var _glow: MeshInstance3D = null
var _sun_glow: MeshInstance3D = null  # vc156 old-Sun motion: soft glow shell, pulses
var _sun_glow_mat: StandardMaterial3D = null
var _sun_flare: MeshInstance3D = null  # vc156 old-Sun solar flare: bright spot on the limb, bursts every ~26 s
var _sun_flare_mat: StandardMaterial3D = null
var _sun_flare_t: float = 0.0
var _dial: Node3D = null
var _brought: String = ""
# vc70 SMOOTH TRANSITION: pinch does not jump planets. Old glides back to sky, new zooms in from sky, 0.9s smoothstep, no overlap of huge planets.
var _trans_old: String = ""
var _trans_new: String = ""
var _trans_t: float = 1.0
var _trans_dur: float = 0.9
var _trans_old_from: Vector3 = Vector3.ZERO
var _trans_old_to: Vector3 = Vector3.ZERO
var _trans_new_from: Vector3 = Vector3.ZERO
var _trans_new_to: Vector3 = Vector3.ZERO
var _trans_old_scale: float = 1.5
var _trans_new_scale_from: float = 3.5
var _trans_back: bool = false  # vc83: true when the transition is a reverse back to the sky, not a bring-to-front
var _dial_handle: MeshInstance3D = null
var _dial_label: Label3D = null
var _travel_sphere: MeshInstance3D = null
var _mars_world: Node3D = null  # vc104: procedural Mars world, Mars travel only
var _planet_loader: Node = null  # vc110: PlanetLoader, Mars via mars.tres only
var _mars_env: Resource = null  # vc110: data/worlds/mars.tres, loaded once
var _mars_env_applied: bool = false
var _loader_envs: Dictionary = {}
var _loader_world_name: String = ""
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _fade_timer: float = 0.0
var _prev_travel: String = ""  # vc110: track Mars travel transitions for loader unload
var _travel_cyl: MeshInstance3D = null  # vc98 Mars template: horizon cylinder, undistorted, not a full sphere
var _travel_cyl_mat: StandardMaterial3D = null
var _travel_ground: MeshInstance3D = null
var _travel_sky: MeshInstance3D = null
var _travel_ring: MeshInstance3D = null
var _travel_deck: MeshInstance3D = null
var _travel_aurora_a: MeshInstance3D = null
var _travel_aurora_b: MeshInstance3D = null
var _travel_sun: MeshInstance3D = null
var _travel_deck_tex: Dictionary = {}
var _sun_light: DirectionalLight3D = null
var _last_update: float = -1.0
# Awe-teacher hologram: one small light-figure + "AI" tag, reused
# for the focused planet only. Built from primitives here (our own
# meshes, no copied art). Follows room-mode focus in _process.
var _holo: Node3D = null
var _holo_blend: float = 0.0
var _holo_mat: StandardMaterial3D = null

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

# Imagined cloud deck: soft horizontal bands blending top color
# through band color to bottom color. Abstract on purpose — real
# palette, no fake storms, no fake continents. 256 px is plenty
# for a glowing floor seen through haze.
func _make_cloud_deck(top: Color, band: Color, bottom: Color) -> ImageTexture:
	var img: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y: int in range(256):
		var t: float = float(y) / 255.0
		var w: float = 0.5 + 0.5 * sin(t * 18.0 + sin(t * 5.0) * 1.5)
		var c: Color = top.lerp(band, smoothstep(0.15, 0.55, t + (w - 0.5) * 0.12))
		c = c.lerp(bottom, smoothstep(0.55, 0.95, t))
		for x: int in range(256):
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# Aurora curtain: bright lower edge fading upward, shared by all
# four gas giants (oxygen-green hush). Tint comes from each
# curtain's material color, not the texture.
func _make_aurora_tex() -> ImageTexture:
	var img: Image = Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y: int in range(128):
		var t: float = float(y) / 127.0
		var a: float = pow(1.0 - t, 1.8) * (0.75 + 0.25 * sin(t * 40.0))
		for x: int in range(64):
			var edge: float = sin(float(x) / 63.0 * PI)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clamp(a * edge, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

# vc91 Mars travel — ONE real panorama only.
# Perseverance, Neretva Vallis Delta, Jezero Crater, Sol 1155,
# May 20, 2024, Mastcam-Z, 217 images (NASA PIA26816),
# ASU full mosaic 22560 wide, downscaled to 4096x1870 for Quest.
# Cylindrical panorama, not a full sphere — top/bottom
# stretch on a sphere, horizon is the honest part.
# Never presented as live, never as a different rover/place.
# Old Curiosity Rocknest file kept on disk, not used.
const TRAVEL_TEXTURES: Dictionary = {
	"Mars": "res://data/travel/mars_sol1155_4k.jpg",  # vc91 TRAVEL: Perseverance Sol 1155 4K, old Rocknest file kept on disk, not used
}

# "You are there" worlds: the 7 planets. Mars alone has a real
# panorama (above). The other six are SIMULATED backdrops built
# only from each globe's own real texture (same scan the globe
# shows — bands, clouds, colours, nothing invented), wrapped on
# a see-through shell so passthrough and the real room stay on.
# Venus shows its real cloud deck only, never a fake ground.
# Gas giants read as floating among clouds: no floor anywhere.
const TRAVEL_WORLDS: Array = ["Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune", "Sun"]  # vc182: Sun added (artistic photosphere world)
const LOADER_WORLDS: Dictionary = {"Mars": "mars.tres", "Moon": "moon.tres", "Mercury": "mercury.tres", "Venus": "venus.tres", "Titan": "titan.tres", "Pluto": "pluto.tres", "Europa": "europa.tres", "Triton": "triton.tres", "Io": "io.tres", "Jupiter": "jupiter.tres", "Saturn": "saturn.tres", "Uranus": "uranus.tres", "Neptune": "neptune.tres", "Sun": "sun.tres", "StarBlueWhite": "starbluewhite.tres", "StarYellow": "staryellow.tres", "StarOrange": "starorange.tres", "StarRed": "starred.tres", "StarRedGiant": "starredgiant.tres", "StarWhiteDwarf": "starwhitedwarf.tres"}
const TRAVEL_SHELL_ALPHA_REAL: float = 0.90
const TRAVEL_SHELL_ALPHA_SIM: float = 0.85
# Imagined grounds: only the four gas giants get one (no solid
# surface exists there). Mercury keeps its orbiting view, Venus
# keeps clouds only, Mars keeps the real panorama. Each deck is
# procedural cloud bands in that planet's real palette — an
# artist's impression from real scans, always labelled imagined.
const TRAVEL_DECK_PLANETS: Array = []  # vc157: was Jupiter/Uranus/Neptune, Saturn removed in vc154 — the see-through deck (alpha 0.92) is gone for every planet now. Gas giants have their own solid cloud deck in MarsWorld, rocky planets have terrain, no deck anywhere.

# v14 all planets textured — REAL scans only, no invented detail.
# Solar System Scope textures, CC BY 4.0, attribution in repo.
# Venus uses the atmosphere texture (what you actually see),
# not the radar surface map. Saturn sphere only in v14 —
# its ring is a separate mesh, not in this build.
# Simulated bodies are labelled simulated in the panel,
# never presented as real scans.
# v23 ULTRA REALISM: 4k files (real spacecraft mosaics, see
# docs/texture_upgrade_4k.md) are preferred for Moon, Mars,
# Jupiter, Saturn when present; otherwise the 2k file below is
# used, so the app works before AND after the files are added.
# Venus stays the 2k atmosphere texture — never a radar surface.
# Sun/Mercury/Uranus/Neptune stay 2k until the 4k headset verdict.
# Surreal pass: Moon prefers a real 8k file when present
# (8k_moon.jpg, real NASA/Celestia data only, never invented),
# then 4k, then 2k. Mars/Jupiter/Saturn stay 4k-first. Nothing
# new is shipped here — absent files simply fall back.
const TELESCOPE_TEXTURES_8K: Dictionary = {
	"Moon": "res://data/textures/8k_moon.jpg",
}
const TELESCOPE_TEXTURES_4K: Dictionary = {
	"Moon": "res://data/textures/4k_moon.jpg",
	"Mars": "res://data/textures/4k_mars.jpg",
	"Jupiter": "res://data/textures/4k_jupiter.jpg",
	"Saturn": "res://data/textures/4k_saturn.jpg",
}
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
		["Sun", Color(1.0, 0.85, 0.3), 0.4],  # vc177 REVERT to real size: was 4.0 in vc159 (10x bigger), which made the sky Sun look huge/close (8 m wide at 85 m = ~5.4 deg, real Sun is ~0.5 deg). 0.4 m radius at 85 m = ~0.5 deg, same as the Moon, accurate. User 2026-11-03: sky Sun looked too close.
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
		# vc156 OLD SUN BACK, user 2026-11-02: "I like our old sun much
		# better, I just wanted to add motion to it and solar flares".
		# The vc149 animated shader Sun is out. Old Sun is back: a
		# plain textured sphere, radius 0.4, 2k_sun.jpg, tilt 7.25 deg,
		# same as before vc149. Motion + flare glow are added below
		# in _process (vc156 Sun motion), not a new shader Sun.
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = d[2]
		sphere.height = d[2] * 2.0
		mesh_inst.mesh = sphere
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = d[1]
		if TELESCOPE_TEXTURES_4K.has(d[0]) or TELESCOPE_TEXTURES.has(d[0]):
			# v23: 4k first when the file is in the project,
			# else the 2k fallback. Surreal pass: Moon tries a
			# real 8k file first, then 4k, then 2k. Literal
			# load() paths so the exporter includes whichever
			# files are present.
			var tex: Texture2D = null
			if TELESCOPE_TEXTURES_4K.has(d[0]) and ResourceLoader.exists(TELESCOPE_TEXTURES_4K[d[0]]):
				tex = load(TELESCOPE_TEXTURES_4K[d[0]])
			if tex == null and TELESCOPE_TEXTURES.has(d[0]):
				tex = load(TELESCOPE_TEXTURES[d[0]])
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
	# vc159: SunGlow orb and SunFlare explosions REMOVED at user word 2026-11-02 — they looked like an orb around the Sun and explosions. Old textured Sun only, no glow shell, no flare burst, just the Sun, 10x bigger in the sky.
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
	# Travel shell: 20 m sphere around the origin, see-through
	# so passthrough and the real room stay on — never an opaque
	# dome. scale.x = -1 so textures read the right way round
	# from inside. The per-planet texture is set in
	# _update_bodies (Mars: real rover panorama; others: each
	# globe's own real texture). No floor anywhere — gas giants
	# read as floating, never standing. The shell never spins,
	# so there is nothing to cause dizziness.
	_travel_sphere = MeshInstance3D.new()
	var tsphere: SphereMesh = SphereMesh.new()
	tsphere.radius = 20.0
	tsphere.height = 40.0
	_travel_sphere.mesh = tsphere
	var tmat: StandardMaterial3D = StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED  # vc92: travel sphere must be OPAQUE, a see-through sphere blended away in-headset
	tmat.albedo_color = Color(1.0, 1.0, 1.0, TRAVEL_SHELL_ALPHA_SIM)
	_travel_sphere.material_override = tmat
	_travel_sphere.scale = Vector3(1.0, 1.0, 1.0)  # vc92: no negative scale, cull front does the inside view
	_travel_sphere.visible = false
	_travel_sphere.name = "TravelSphere"
	add_child(_travel_sphere)
	# vc104: procedural Mars world, built lazily on first Mars
	# travel activation (see mars_world.gd activate()). Hidden
	# for every other planet and outside travel.
	_mars_world = load("res://scripts/mars_world.gd").new()
	_mars_world.visible = false
	_mars_world.name = "MarsWorld"
	add_child(_mars_world)
	# vc110 STEP 1: Mars via PlanetLoader + mars.tres. Loader applies
	# the env BEFORE the first activate() builds anything, so Mars
	# looks identical to vc109. Other planets keep old travel for now.
	_planet_loader = load("res://scripts/planet_loader.gd").new()
	_planet_loader.name = "PlanetLoader"
	add_child(_planet_loader)
	_sky_layout = SkyLayoutScript.new()
	_sky_layout.name = "SkyLayout"
	add_child(_sky_layout)
	_mars_env = load("res://data/worlds/mars.tres")
	if _mars_env != null and _planet_loader.has_method("apply_env_to_mars"):
		_planet_loader.call("apply_env_to_mars", _mars_env, _mars_world)
	if _planet_loader != null and _planet_loader.has_method("make_fade_overlay"):
		_fade_layer = _planet_loader.call("make_fade_overlay")
		add_child(_fade_layer)
		_fade_rect = _fade_layer.get_node_or_null("TravelFadeRect")
		_mars_env_applied = true
	# vc98 MARS TEMPLATE: horizon cylinder (4096x1400 cropped band, aspect 2.93, circumference/height = 2.93 at R=20, H=42.9, so pixels are square, no pole stretch), ground disc at feet, sky dome above. Same template will copy to every world.
	_travel_cyl_mat = StandardMaterial3D.new()
	_travel_cyl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_travel_cyl_mat.cull_mode = BaseMaterial3D.CULL_FRONT  # inside faces only
	_travel_cyl_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	var _cylmesh: CylinderMesh = CylinderMesh.new()
	_cylmesh.top_radius = 20.0
	_cylmesh.bottom_radius = 20.0
	_cylmesh.height = 42.9
	_cylmesh.radial_segments = 64
	_cylmesh.cap_top = false
	_cylmesh.cap_bottom = false
	_travel_cyl = MeshInstance3D.new()
	_travel_cyl.mesh = _cylmesh
	_travel_cyl.material_override = _travel_cyl_mat
	_travel_cyl.visible = false
	_travel_cyl.name = "TravelCyl"
	add_child(_travel_cyl)
	var _gmat: StandardMaterial3D = StandardMaterial3D.new()
	_gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gmat.albedo_color = Color(0.45, 0.28, 0.16)  # Mars ground, sampled from Sol 1155 ground band
	var _gmesh: CylinderMesh = CylinderMesh.new()
	_gmesh.top_radius = 20.0
	_gmesh.bottom_radius = 20.0
	_gmesh.height = 0.1
	_gmesh.cap_top = true
	_gmesh.cap_bottom = false
	_travel_ground = MeshInstance3D.new()
	_travel_ground.mesh = _gmesh
	_travel_ground.material_override = _gmat
	_travel_ground.visible = false
	_travel_ground.name = "TravelGround"
	add_child(_travel_ground)
	var _smat: StandardMaterial3D = StandardMaterial3D.new()
	_smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smat.cull_mode = BaseMaterial3D.CULL_FRONT
	_smat.albedo_color = Color(0.75, 0.55, 0.35)  # Mars butterscotch sky
	var _smesh: SphereMesh = SphereMesh.new()
	_smesh.radius = 40.0
	_smesh.height = 80.0
	_travel_sky = MeshInstance3D.new()
	_travel_sky.mesh = _smesh
	_travel_sky.material_override = _smat
	_travel_sky.visible = false
	_travel_sky.name = "TravelSky"
	add_child(_travel_sky)
	# Saturn travel ring: the real ring structure overhead, same
	# procedural texture as the globe's rings (Cassini division
	# included), tilted like the planet. Static — no spinning.
	# Visible only while travelling Saturn.
	_travel_ring = MeshInstance3D.new()
	var tring: PlaneMesh = PlaneMesh.new()
	tring.size = Vector2(36.0, 36.0)
	_travel_ring.mesh = tring
	_travel_ring.rotation.x = -PI / 2.0 + deg_to_rad(26.73)
	var trmat: StandardMaterial3D = StandardMaterial3D.new()
	trmat.albedo_texture = _make_saturn_ring_texture()
	trmat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	trmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_travel_ring.material_override = trmat
	_travel_ring.position = Vector3(0.0, 9.0, 0.0)
	_travel_ring.visible = false
	_travel_ring.name = "TravelRingSaturn"
	add_child(_travel_ring)
	# Imagined cloud deck: a glowing floor of cloud bands at the
	# feet, gas giants only. See-through enough that the real
	# room breathes through (alpha 0.92). Static — no motion, no
	# dizziness. Texture per planet is set in _apply_travel_look.
	_travel_deck = MeshInstance3D.new()
	var deckplane: PlaneMesh = PlaneMesh.new()
	deckplane.size = Vector2(44.0, 44.0)
	_travel_deck.mesh = deckplane
	var deckmat: StandardMaterial3D = StandardMaterial3D.new()
	deckmat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
	deckmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	deckmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	deckmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_travel_deck.material_override = deckmat
	_travel_deck.position = Vector3(0.0, -1.8, 0.0)
	_travel_deck.visible = false
	_travel_deck.name = "TravelDeck"
	add_child(_travel_deck)
	# Aurora curtains: real phenomenon on all four gas giants,
	# two quiet veils fore and aft. Shared texture, pale tint.
	var aurtex: ImageTexture = _make_aurora_tex()
	for ai: int in range(2):
		var aur: MeshInstance3D = MeshInstance3D.new()
		var aurplane: PlaneMesh = PlaneMesh.new()
		aurplane.size = Vector2(26.0, 9.0)
		aur.mesh = aurplane
		var aurmat: StandardMaterial3D = StandardMaterial3D.new()
		aurmat.albedo_texture = aurtex
		aurmat.albedo_color = Color(0.45, 1.0, 0.70, 0.30)
		aurmat.emission_enabled = true
		aurmat.emission = Color(0.40, 0.95, 0.65)
		aurmat.emission_energy_multiplier = 0.8
		aurmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		aurmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		aurmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		aur.material_override = aurmat
		if ai == 0:
			aur.position = Vector3(0.0, 6.0, -14.0)
			_travel_aurora_a = aur
			aur.name = "TravelAuroraA"
		else:
			aur.position = Vector3(0.0, 7.0, 14.0)
			aur.rotation.y = PI
			_travel_aurora_b = aur
			aur.name = "TravelAuroraB"
		aur.visible = false
		add_child(aur)
	# Travel sun: the REAL sun direction, placed live every second
	# in _apply_travel_look. Same small disc from every world
	# (physics is fair that way) — only its pallor changes with
	# distance, cold and dim out by Neptune. Hidden at night.
	_travel_sun = MeshInstance3D.new()
	var sunball: SphereMesh = SphereMesh.new()
	sunball.radius = 0.35
	sunball.height = 0.70
	_travel_sun.mesh = sunball
	var sunmat: StandardMaterial3D = StandardMaterial3D.new()
	sunmat.albedo_color = Color(1.0, 0.98, 0.92)
	sunmat.emission_enabled = true
	sunmat.emission = Color(1.0, 0.96, 0.88)
	sunmat.emission_energy_multiplier = 3.0
	sunmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_travel_sun.material_override = sunmat
	_travel_sun.visible = false
	_travel_sun.name = "TravelSun"
	add_child(_travel_sun)
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
	# v23 highlight fix (headset report 2026-10-28): the old pale-gold
	# shell (alpha 0.22) washed out against bright planet textures
	# and real passthrough. Deep orange at alpha 0.60 with emission,
	# so it reads on bright and dark backgrounds alike. Shell shape,
	# follow logic, and pinch behaviour are unchanged.
	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.45, 0.08, 0.60)
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.40, 0.05)
	gmat.emission_energy_multiplier = 1.6
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow.material_override = gmat
	_glow.visible = false
	_glow.name = "HighlightGlow"
	add_child(_glow)
	# Awe-teacher hologram: a small abstract light-figure, clearly
	# not human — a glowing capsule wisp + round head, see-through
	# pale cyan, with a floating "AI" tag so nobody mistakes it
	# for a person. ~0.5 m tall beside the planet, never over it.
	_holo = Node3D.new()
	_holo.name = "TeacherHolo"
	var homat: StandardMaterial3D = StandardMaterial3D.new()
	homat.albedo_color = Color(0.55, 0.90, 1.00, 0.35)
	homat.emission_enabled = true
	homat.emission = Color(0.50, 0.85, 1.00)
	homat.emission_energy_multiplier = 1.6
	_holo_mat = homat
	homat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	homat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	homat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hobody: MeshInstance3D = MeshInstance3D.new()
	var hocapsule: CapsuleMesh = CapsuleMesh.new()
	hocapsule.radius = 0.14
	hocapsule.height = 0.50
	hobody.mesh = hocapsule
	hobody.material_override = homat
	_holo.add_child(hobody)
	var hohead: MeshInstance3D = MeshInstance3D.new()
	var hosphere: SphereMesh = SphereMesh.new()
	hosphere.radius = 0.11
	hosphere.height = 0.22
	hohead.mesh = hosphere
	hohead.position = Vector3(0.0, 0.38, 0.0)
	hohead.material_override = homat
	_holo.add_child(hohead)
	var holabel: Label3D = Label3D.new()
	holabel.text = "AI"
	holabel.font_size = 24
	holabel.pixel_size = 0.003
	holabel.width = 120
	holabel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	holabel.modulate = Color(0.75, 0.97, 1.00)
	holabel.outline_size = 2
	holabel.outline_modulate = Color(0.0, 0.05, 0.10)
	holabel.position = Vector3(0.0, 0.62, 0.0)
	_holo.add_child(holabel)
	# vc40 hologram upgrade (user: old figure was too simple, not
	# a hologram): bigger figure (~0.75 m), brighter emission,
	# plus a glowing base ring so it reads as a projected hologram.
	var horing: MeshInstance3D = MeshInstance3D.new()
	var hotorus: TorusMesh = TorusMesh.new()
	hotorus.inner_radius = 0.18
	hotorus.outer_radius = 0.22
	horing.mesh = hotorus
	horing.material_override = homat
	horing.rotation.x = -PI / 2.0
	horing.position = Vector3(0.0, -0.28, 0.0)
	_holo.add_child(horing)
	_holo.visible = false
	add_child(_holo)
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
	_dial_label.font_size = 32
	_dial_label.pixel_size = 0.003
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
	# vc156 old-Sun motion: when the Sun is brought in or in telescope,
	# spin it visibly (3 deg/s, sped up for look, not real Sun speed),
	# and always pulse the glow + fire a flare burst every ~26 s.
	if _bodies.has("Sun"):
		var _sun: Node3D = _bodies["Sun"]
		if _focused == "Sun" or _telescope == "Sun":
			_sun.rotate_y(deg_to_rad(3.0) * delta)
		# vc159: no glow, no flare — Sun just spins slowly when brought/telescope, like before.
	# v22 highlight + smooth zoom, every frame (not 1/sec):
	# focused/telescope scale lerps toward base * zoom * pulse,
	# so dial changes zoom smoothly instead of jumping.
	# Glow follows only the focused body; dial shows in room
	# mode only (in telescope the planet fills the view).
	# vc70 TRANSITION: ease both bodies along their paths, smoothstep so it starts/ends soft, not a jump.
	if _trans_t < 1.0 and _trans_new != "" and _bodies.has(_trans_new):
		_trans_t = min(1.0, _trans_t + delta / _trans_dur)
		var _e: float = _trans_t * _trans_t * (3.0 - 2.0 * _trans_t)
		var _nb: Node3D = _bodies[_trans_new]
		_nb.global_position = _trans_new_from.lerp(_trans_new_to, _e)
		var _ns: float = lerp(_trans_new_scale_from, (3.5 if _trans_new not in ["Sun", "Moon"] else 1.0) if _trans_back else (1.5 if _trans_new == "Sun" else 3.0), _e)  # vc159 brought bigger
		_nb.scale = Vector3(_ns, _ns, _ns)
		_nb.visible = true
		if _trans_old != "" and _bodies.has(_trans_old):
			var _ob: Node3D = _bodies[_trans_old]
			_ob.global_position = _trans_old_from.lerp(_trans_old_to, _e)
			var _os: float = lerp(_trans_old_scale, 3.5 if _trans_old not in ["Sun", "Moon"] else 1.0, _e)
			_ob.scale = Vector3(_os, _os, _os)
			_ob.visible = true
		if _trans_t >= 1.0:
			_trans_old = ""
			_trans_new = ""
			_trans_back = false
	if _focused != "" and _travel == "" and _bodies.has(_focused):
		var fbody: Node3D = _bodies[_focused]
		# vc68 GRAB: held planet follows the hand every frame, not once a second in _update_bodies.
		if _holding:
			fbody.global_position = fbody.global_position.lerp(_hold_pos, 0.5)
		# vc62: brought body STAYS IN THE WORLD where it was brought, it does
		# NOT follow the head every frame. Glued-to-face was why vc61 got
		# stuck on Neptune: turn to Saturn and Neptune followed you, always
		# dead ahead, so no other planet could ever win a pinch. Position
		# is set once in bring_to_front, below. Here we only keep it visible.
		if _brought != "" and _bodies.has(_brought):
			var _bb: Node3D = _bodies[_brought]
			_bb.visible = true
			# vc123 REVERT: vc114 keep-clear guard OFF for the brought body.
			# It pushed a front-centre planet to 40deg from the face every frame,
			# undoing the front position. Sky bodies are not guarded (see report).
		# Surreal pass, visuals only: telescope base 5.0 at -1.8 m
		# feels huge and close; room stays 1.5 at -3.0 m. Pulse is
		# slower and softer (was 10%/5% at 4.0 rad/s) so the glow
		# breathes instead of throbbing. Step 1 glow colour, 1.9x
		# shell, and emission are unchanged. Scale lerp 0.12 (was
		# 0.25) glides instead of snapping. Same targets/logic.
		# vc46 USER CORRECTION 2026-10-28: planet is NEVER brought to
		# the user — user never said that. Planet STAYS in the sky
		# at dir*85. Telescope magnifies it IN PLACE (bigger scale
		# at the same sky direction), it does not fly to the room.
		# Dial + hologram are CAMERA-relative, in front of the user
		# where a hand can actually reach them, not planet-relative
		# at 85 m where no hand can ever touch them.
		var _cam: Node = get_node_or_null("../XROrigin/XRCamera")
		# vc55: NO auto telescope scale. Base = normal scale only, manual zoom via _zoom (dial) only.
		var base: float = 1.5 if test_mode else (1.0 if _focused in ["Sun", "Moon"] else 3.5)
		var pulse: float = 1.0 + (0.03 if _telescope != "" else 0.06) * sin(Time.get_unix_time_from_system() * 2.2)
		# vc59: brought planet must fit in view, not fill it / flash. Brought scale = 1.5, always.
		var target: float = 1.5 if _brought == _focused and _brought != "" else base * _zoom * pulse  # vc177: Sun brought scale now 1.5 too (0.6 m / 0.4 m sky radius), no special case
		if not (_trans_t < 1.0 and _focused == _trans_new):
			fbody.scale = fbody.scale.lerp(Vector3(target, target, target), 0.12)
		# vc55 USER SPEC: highlighted OUTLINED on pinch. Glow shell follows focused body, body scale itself does NOT auto-zoom.
		if _glow != null:
			# vc60: glow HIDDEN for playtest — orange shell was filling the whole view, no matter what planet.
			_glow.visible = false
		if _dial != null:
			# vc56 PLAYTEST: dial HIDDEN — zoom is for finished product, not playtest.
			_dial.visible = false
			# vc46 dial: CAMERA-relative, 0.9 m in front, right/down,
			# so a hand can actually reach and pinch it. Old code
			# put it at planet position + world offset — at 85 m
			# out, or at the origin, no hand could ever touch it.
			if _cam != null:
				var _cb2: Basis = (_cam as Node3D).global_transform.basis
				_dial.global_position = (_cam as Node3D).global_position + _cb2 * Vector3(0.55, -0.35, -0.75)
				_dial.scale = Vector3(1.5, 1.5, 1.5)
			else:
				_dial.global_position = fbody.global_position + Vector3(0.7, -0.3, 0.8)
		# Awe-teacher: show beside the planet in room mode only.
		# Hidden in telescope (the planet fills the view — the
		# figure must never cover it), in travel, and with no
		# focus. A new pinch moves _focused, so the figure glides
		# to the new planet; a failed pinch clears focus, so it
		# vanishes instead of haunting the wrong object.
		if _holo != null:
			# vc57 CLEAN: hologram figure + AI tag hidden — no words/figures in the way.
			if _telescope == "":
				_holo.visible = false
				_holo_blend = lerp(_holo_blend, 1.0, 0.15)
				# vc46 hologram: camera-relative, left of the dial,
				# in view while looking at the planet, not at 85 m.
				var htarget: Vector3
				if _cam != null:
					var _cb3: Basis = (_cam as Node3D).global_transform.basis
					htarget = (_cam as Node3D).global_position + _cb3 * Vector3(-0.65, -0.35, -1.1)
				else:
					htarget = fbody.global_position + Vector3(1.0, -0.55, 0.35)
				htarget.y += sin(Time.get_unix_time_from_system() * 2.0) * 0.04
				_holo.global_position = _holo.global_position.lerp(htarget, 0.18)
				var hs: float = max(_holo_blend, 0.01)
				_holo.scale = Vector3(hs, hs, hs)
				# Projected-hologram shimmer: slow breathing of the
				# emission only. Size, spot, and tag never move for it.
				if _holo_mat != null:
					_holo_mat.emission_energy_multiplier = 1.6 + 0.35 * sin(Time.get_unix_time_from_system() * 3.1)
			else:
				_holo.visible = false
				_holo_blend = 0.0
	else:
		if _glow != null:
			_glow.visible = false
		if _dial != null:
			_dial.visible = false
		if _holo != null:
			_holo.visible = false
			_holo_blend = 0.0
	# vc95 SMOOTH TRAVEL: sphere follows the camera EVERY FRAME, not once a second in _update_bodies. The 1-second jumps were the choppy slices in the vc94 video - head moves, sphere stays, then jumps.
	if _travel != "" and _travel_sphere != null:
		var _tcam2: Node = get_node_or_null("../XROrigin/XRCamera")
		if _tcam2 != null:
			_travel_sphere.global_position = (_tcam2 as Node3D).global_position
			if _travel_cyl != null:
				_travel_cyl.global_position = (_tcam2 as Node3D).global_position
			if _travel_ground != null:
				_travel_ground.global_position = (_tcam2 as Node3D).global_position + Vector3(0.0, -1.6, 0.0)
			if _travel_sky != null:
				_travel_sky.global_position = (_tcam2 as Node3D).global_position
	# vc104 Mars world: visible only for Mars travel, follows the
	# camera XZ at feet level (camera Y - 1.7), hidden otherwise.
	# vc110: Mars goes through PlanetLoader. On leaving Mars, the
	# loader frees the built world (textures/meshes) so memory does
	# not grow between worlds; the next Mars entry rebuilds from
	# mars.tres. Fade is a TODO (no fade overlay in main scene yet).
	if _fade_rect != null:
		if _travel != _prev_travel and LOADER_WORLDS.has(_travel):
			_fade_timer = 0.6
			_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
		if _fade_timer > 0.0:
			_fade_timer -= delta
			if _fade_timer <= 0.0:
				_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
			else:
				_fade_rect.color = Color(0.0, 0.0, 0.0, clamp(_fade_timer / 0.6, 0.0, 1.0))
	if _mars_world != null:
		if LOADER_WORLDS.has(_travel):
			var _mcam: Node = get_node_or_null("../XROrigin/XRCamera")
			if _mcam != null:
				var _mpos: Vector3 = (_mcam as Node3D).global_position
				# vc179 FIX: home sky (8,920 stars at 90 m + sky planets at
				# 85 m) was never hidden in travel, so it drew in front of
				# any ground farther than ~90 m: stars and planets "under
				# the floor". Hidden during travel, restored on exit below.
				var _skyn: Node3D = get_node_or_null("../SkyCore") as Node3D
				if _skyn != null:
					_skyn.visible = false
				for _bn: String in _bodies.keys():
					(_bodies[_bn] as Node3D).visible = false
				if _loader_world_name != _travel:
					# vc179 FIX: place the world ONCE on entry. Before, it
					# was moved to the camera every frame, so the ground and
					# rocks moved with your head: no parallax, no walking,
					# it read as a flat picture glued to your face.
					_mars_world.global_position = Vector3(_mpos.x, _mpos.y - 1.6, _mpos.z)
					if _loader_world_name != "" and _planet_loader != null:
						_planet_loader.call("unload_world", _mars_world)
					var _env: Resource = _loader_env_for(_travel)
					if _env != null and _planet_loader != null:
						_planet_loader.call("apply_env_to_mars", _env, _mars_world)
						var _face: Node = get_node_or_null("../AiFace")
						if _face != null:
							_planet_loader.call("place_face", _face, _env)
					_loader_world_name = _travel
			_mars_world.call("activate")
			# vc115 Moon: keep-clear guard also applies to Earth —
			# Earth at +60deg/30deg is 58deg from the face (0/12deg),
			# so the guard returns early; it only moves Earth if a
			# future change ever puts it within 40deg of the face.
			if _travel == "Moon" and _sky_layout != null and face_node != null:
				var _earth: Node = _mars_world.get_node_or_null("SkyBody_Earth")
				if _earth != null:
					_sky_layout.keep_clear_of_face(_earth as Node3D, face_node, 40.0)
		else:
			if _loader_world_name != "":
				# vc179 FIX: leaving travel: bring the home sky back once.
				# Bodies are re-shown by _update_bodies (it sets visible).
				var _skyr: Node3D = get_node_or_null("../SkyCore") as Node3D
				if _skyr != null:
					_skyr.visible = true
				_update_bodies(false)
			if _loader_world_name != "" and _planet_loader != null:
				_planet_loader.call("unload_world", _mars_world)
				_loader_world_name = ""
			if _prev_travel == "Mars" and _planet_loader != null:
				_mars_env_applied = false
			else:
				_mars_world.call("deactivate")
	_prev_travel = _travel
	var now: float = Time.get_unix_time_from_system()
	if abs(now - _last_update) >= 1.0:
		_update_bodies(false)

func _body_dir(name: String, jds: Dictionary) -> Vector3:
	if name == "Moon":
		return AstroMathScript.moon_world_dir(jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg, alt_offset_deg)
	return AstroMathScript.planet_world_dir(name, jds["tt"], jds["ut1"], lat_deg, lon_deg, yaw_offset_deg, alt_offset_deg)

func _update_bodies(_force: bool) -> void:
	var now: float = Time.get_unix_time_from_system()
	_last_update = now
	if _travel_sphere != null:
		_travel_sphere.visible = _travel != "" and not LOADER_WORLDS.has(_travel)  # vc104: Mars uses the procedural world, not the skybox sphere
	if _travel_cyl != null:
		_travel_cyl.visible = false  # vc100: skybox sphere, not cylinder
	if _travel_ground != null:
		_travel_ground.visible = false  # vc100: skybox ground is in the image
	if _travel_sky != null:
		_travel_sky.visible = false  # vc100: skybox sky is in the image
		# vc92 FIX: sphere follows the CAMERA, not world origin. Origin-centred sphere could leave the user outside it after a recenter / room move, so the panorama never appeared.
		var _tcam: Node = get_node_or_null("../XROrigin/XRCamera")
		if _tcam != null:
			_travel_sphere.global_position = (_tcam as Node3D).global_position
		else:
			_travel_sphere.global_position = Vector3(0, 0, 0)
	if _travel_ring != null:
		_travel_ring.visible = _travel == "Saturn"
		_travel_ring.global_position = Vector3(0, 9.0, 0)
	var on_deck_world: bool = TRAVEL_DECK_PLANETS.has(_travel)
	if _travel_deck != null:
		_travel_deck.visible = on_deck_world
		_travel_deck.global_position = Vector3(0, -1.8, 0)
	if _travel_aurora_a != null:
		_travel_aurora_a.visible = on_deck_world
		_travel_aurora_a.global_position = Vector3(0, 6.0, -14.0)
	if _travel_aurora_b != null:
		_travel_aurora_b.visible = on_deck_world
		_travel_aurora_b.global_position = Vector3(0, 7.0, 14.0)
	if _travel_sun != null and _travel == "":
		_travel_sun.visible = false
	var jds: Dictionary = AstroMathScript.jds_from_unix(now)
	if _travel != "":
		_apply_travel_look(_body_dir("Sun", jds))
	# v21 Moon phase light: point the light from the Sun's
	# real direction toward the origin. DirectionalLight
	# shines along -Z of its transform, so look_at origin.
	if _sun_light != null:
		var sdir: Vector3 = _body_dir("Sun", jds)
		_sun_light.global_position = sdir * 100.0
		var upv: Vector3 = Vector3.UP if abs(sdir.y) < 0.95 else Vector3.RIGHT
		_sun_light.look_at(Vector3.ZERO, upv)
	for name: String in _bodies.keys():
		var mesh_inst: Node3D = _bodies[name]
		if name == _travel or LOADER_WORLDS.has(_travel):
			# vc179 FIX: in a travel world hide ALL home-sky bodies, not
			# only the one you travelled to (else they blink back each second).
			# Travel: hide the room Mars orb, the panorama
			# sphere IS Mars around you. Restored on exit.
			mesh_inst.visible = false
			continue
		mesh_inst.visible = true
		if _trans_t < 1.0 and (name == _trans_old or name == _trans_new):
			mesh_inst.visible = true
			continue
		if name == _brought and _brought != "":
			# vc66 STAY IN ONE SPOT: brought position is set ONCE in
			# bring_to_front, never again here. The old every-second
			# camera+forward reset was why vc65 Mars moved wherever
			# you looked — up, over here, everywhere. Now it stays,
			# so you can walk up to it, walk around it, and grab it.
			# Grab only: if you are holding it, it rides your hand.
			if _holding and name == _focused:
				mesh_inst.global_position = mesh_inst.global_position.lerp(_hold_pos, 0.5)
			# vc177: brought scale = target_brought_radius / body_radius: Sun 1.5 (0.6 m / 0.4 m), planets 1.5.
			var _bs: float = target_brought_radius(name) / float(_body_radius.get(name, 0.35))
			mesh_inst.scale = Vector3(_bs, _bs, _bs)
			mesh_inst.visible = true
			continue
		if name == _focused and _holding:
			# Hand-grab only: planet rides the holding hand.
			mesh_inst.global_position = mesh_inst.global_position.lerp(_hold_pos, 0.5)
		elif name == _telescope or name == _focused:
			# vc46: STAYS IN THE SKY. No bring-to-you, no -1.8 m,
			# no -3.0 m. Position = real sky direction * 85 m,
			# scale = _process (telescope 30x zoom in place).
			var dir2: Vector3 = _body_dir(name, jds)
			mesh_inst.visible = true  # vc75 FULL SKY: focused/telescope bodies show even below horizon
			mesh_inst.global_position = dir2 * 85.0
		elif test_mode:
			# TEST MODE: planets in a circle around the room, 4 m out,
			# big enough to see and pinch indoors. Saturn is straight
			# ahead at start (0, 1.0, -4.0), the rest around the circle.
			# Order is fixed so Saturn is always the first test target.
			var order: Array = ["Saturn", "Jupiter", "Mars", "Moon", "Venus", "Mercury", "Neptune", "Uranus", "Sun"]
			var idx: int = order.find(name)
			if idx < 0:
				idx = 0
			var ang: float = deg_to_rad(float(idx) * 40.0)
			mesh_inst.visible = true
			mesh_inst.global_position = Vector3(sin(ang) * 4.0, 1.0, -cos(ang) * 4.0)
			mesh_inst.scale = Vector3(1.5, 1.5, 1.5)
		else:
			var dir: Vector3 = _body_dir(name, jds)
			# v21 horizon hide, sky mode only: below-horizon
			# bodies are hidden, not shown over the room.
			# Focused / telescope / travel bodies above stay
			# visible — they are in the room, not in the sky.
			mesh_inst.visible = true  # vc75 FULL SKY: sky bodies show even below horizon, look down to see Sun etc.
			mesh_inst.global_position = dir * 85.0
			# vc39 user verdict 2026-10-28: real-sky planets were 0.5 deg
			# dots, impossible to aim at, while test-mode planets were
			# big and clicked fine. Position stays TRUE, only the
			# marker is drawn bigger so it can be seen/aimed at:
			# planets 3.5x (about 1.7 deg wide), Sun/Moon unchanged
			# (they already click fine). Focused/telescope scale
			# is overwritten by the focus lerp, so room/telescope
			# size is unchanged.
			var _sky_scale: float = 3.5 if name not in ["Sun", "Moon"] else 1.0
			mesh_inst.scale = Vector3(_sky_scale, _sky_scale, _sky_scale)

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
			_holding = false
			_update_dial()
		_focused = name
		print("Star App: focused ", name, " (bring-to-you, passthrough)")

func hold_focused(pos: Vector3) -> void:
	# Called every pinch-drag frame while the holding hand moves.
	if _focused != "" and _telescope == "" and _travel == "":
		_holding = true
		_hold_pos = pos

func release_hold() -> void:
	_holding = false

func is_holding() -> bool:
	return _holding

func target_brought_radius(name: String) -> float:
	# vc97: brought scale is always 1.5, regardless of the scale at pinch time. The old brought_radius() used the CURRENT scale, which was still the sky scale (3.5 for planets, 1.0 for Sun) at set_anchor time - so Sun got offset 0.75 (words through the planet), Venus got 1.575 (words far away), Jupiter got 2.1 (looked good by luck). Target scale gives the SAME spacing rule for every body.
	if not _bodies.has(name):
		return 0.5
	if name == "Sun":
		return 0.6  # Brought Sun radius, unchanged. Sky Sun is now 0.4 m again (vc177), so brought scale is 0.6/0.4 = 1.5, same as planets.
	return float(_body_radius.get(name, 0.35)) * 1.5  # vc167 REVERT: brought planets back to 1.5 scale, pre-vc159. Mars 0.525 m, Jupiter 0.75 m, not 1.05 m / 1.5 m.

func brought_radius() -> float:
	# vc84: actual visible radius of the brought planet (sphere radius * scale), NOT grab catch range.
	if _brought == "" or not _bodies.has(_brought):
		return 0.5
	var _b: Node3D = _bodies[_brought]
	return float(_body_radius.get(_brought, 0.35)) * _b.scale.x

func grab_radius() -> float:
	# Generous catch range around the room planet's visible disc.
	if _focused == "" or not _bodies.has(_focused):
		return 0.0
	var fbody: Node3D = _bodies[_focused]
	return max(0.6, float(_body_radius.get(_focused, 0.35)) * fbody.scale.x + 0.3)

func focused_position() -> Vector3:
	if _focused != "" and _bodies.has(_focused):
		return (_bodies[_focused] as Node3D).global_position
	return Vector3.ZERO

func clear_focus() -> void:
	if _telescope_8k_body != "":
		_swap_telescope_texture(_telescope_8k_body, false)
	_focused = ""
	_telescope = ""
	_travel = ""
	_holding = false
	_brought = ""
	# Back resets zoom + highlight (glow hidden in _process).
	_zoom = 1.0
	_update_dial()

func is_brought(name: String) -> bool:
	return _brought == name and _trans_t >= 1.0

func send_back(name: String) -> void:
	# vc83 REVERSE (user 2026-10-30 04:50 EDT): clicking a brought planet again must NOT switch to another planet, it must reverse back to where it was, in the sky, with the same smooth transition.
	if not _bodies.has(name) or _brought != name:
		return
	var _jds83: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	var _bb83: Node3D = _bodies[name]
	_trans_old = ""
	_trans_new = name
	_trans_t = 0.0
	_trans_back = true
	_trans_new_from = _bb83.global_position
	_trans_new_to = _body_dir(name, _jds83) * 85.0
	_trans_new_scale_from = _bb83.scale.x
	_brought = ""


# vc123 REVERT: apply_face_guard is now a no-op for the brought planet.
# vc114 guard pushed it 40deg from the face; the way we had it, the planet
# stayed in front and the words stayed next to it. Kept as a stub so main.gd calls stay safe.
func apply_face_guard() -> void:
	return

func bring_to_front(name: String) -> void:
	if _bodies.has(name):
		# vc70: do NOT jump. Start a smooth zoom transition: old glides back to sky, new zooms in from sky to front.
		# Re-pinching the same planet: no transition, it stays where it is.
		if _brought == name and _trans_t >= 1.0:
			return
		var _cam: Node = get_node_or_null("../XROrigin/XRCamera")
		if _cam != null:
			var _jds70: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
			_trans_old = _brought if _brought != name else ""
			_trans_new = name
			_trans_t = 0.0
			var _bb: Node3D = _bodies[name]
			_trans_new_from = _bb.global_position
			# vc82 CONSISTENT FRONT (user 2026-10-30 04:42 EDT): brought planet must spawn in the SAME place every time, in front of you at eye level, so you can read the words. vc78 brought it along its sky ray, so a high planet came in 1.5m above your head and its words were out of view. Sky position stays precise (lock), only the brought room copy is eye-level front.
			var _cf: Vector3 = -((_cam as Node3D).global_transform.basis.z)
			_cf.y = 0.0
			if _cf.length() < 0.01:
				_cf = Vector3(0.0, 0.0, -1.0)
			_cf = _cf.normalized()
			# vc114 PLANET-COVERS-FACE FIX ONLY: info planet is NOT in front of gaze.
			# Face is at azimuth 0 (camera flat forward, 400 m). Planet goes to
			# azimuth +45 deg to the RIGHT of the face (left/right equidistant
			# from face direction, so +45 is the default), elevation 0 (eye
			# level, no +0.2 up). Size 18 deg across: distance = brought
			# radius (body_radius * 1.5 brought scale) / tan(9 deg). This
			# REPLACES the vc86 1.8/2.8/3.0 m distances.
			# vc123 REVERT to pre-vc114 (user: fix it to the way we had it, do not reinvent):
			# brought planet straight in front, eye level, azimuth 0, NOT +45deg right.
			# vc114 moved it to +45 to keep clear of the face; that is what put planets out of sight.
			var _face_dir114: Vector3 = _cf
			var _right114: Vector3 = _face_dir114
			_right114.y = 0.0
			_right114 = _right114.normalized()
			# vc124 SOLVED RECIPE (memory, vc86/vc82, NOT vc114 18deg):
			# Jupiter 2.8m, Saturn 3.0m (rings), all others 1.8m, straight in front,
			# eye level. This is the fit Jupiter had when user said "that's how
			# they all should look" (2026-10-30 21:32 EDT, vc97 verdict).
			var _bdist: float = 2.8 if name == "Jupiter" else (3.0 if name == "Saturn" else 1.8)  # vc171 REVERT to vc124 recipe: Sun back to 1.8 m like every other body. vc159 moved Sun to 5 m for its 2.0 m radius, vc167 shrank the radius back to 0.6 m but left the 5 m distance, so the Sun looked tiny and far away (0.6 m at 5 m = ~14 deg, vs 0.6 m at 1.8 m = ~37 deg). Jupiter 2.8, Saturn 3.0, all others 1.8, straight front, eye level.
			_trans_new_to = (_cam as Node3D).global_position + _right114 * _bdist
			_trans_new_scale_from = _bb.scale.x
			if _trans_old != "" and _bodies.has(_trans_old):
				var _ob70: Node3D = _bodies[_trans_old]
				_trans_old_from = _ob70.global_position
				_trans_old_scale = _ob70.scale.x
				_trans_old_to = _body_dir(_trans_old, _jds70) * 85.0
			_brought = name
			_bb.visible = true

func clear_brought() -> void:
	_brought = ""

func can_travel(name: String) -> bool:
	return TRAVEL_WORLDS.has(name) and _bodies.has(name)

func _deck_texture(name: String) -> Texture2D:
	# One imagined deck per gas giant, generated once and kept.
	# Palettes sampled from each planet's real appearance; the
	# bands are soft weather-haze, never fake landmarks.
	if _travel_deck_tex.has(name):
		return _travel_deck_tex[name]
	var tex: Texture2D = null
	if name == "Jupiter":
		tex = _make_cloud_deck(Color(0.93, 0.83, 0.67), Color(0.72, 0.48, 0.32), Color(0.45, 0.30, 0.20))
	elif name == "Saturn":
		tex = _make_cloud_deck(Color(0.94, 0.86, 0.67), Color(0.80, 0.68, 0.48), Color(0.55, 0.45, 0.32))
	elif name == "Uranus":
		tex = _make_cloud_deck(Color(0.70, 0.88, 0.90), Color(0.62, 0.83, 0.86), Color(0.50, 0.72, 0.76))
	elif name == "Neptune":
		tex = _make_cloud_deck(Color(0.35, 0.50, 0.95), Color(0.25, 0.38, 0.85), Color(0.15, 0.22, 0.60))
	if tex != null:
		_travel_deck_tex[name] = tex
	return tex

func _apply_travel_look(sun_dir: Vector3) -> void:
	# Dress the world for the current travel body. Mars wears the
	# real rover panorama (labelled real on the panel). Every other
	# world reuses its own globe's real texture — the same scan,
	# so bands, clouds, and colours are real observations, never
	# invented detail — at a softer alpha that keeps passthrough.
	# Gas giants also get their imagined deck; the sun sits at its
	# real direction (hidden at night), paler with distance.
	if _travel == "":
		return
	if LOADER_WORLDS.has(_travel):
		# vc111: loader worlds own their travel — do not load sphere texture.
		return
	if _travel == "Mars" and _travel_cyl_mat != null:
		var _ctex: Texture2D = load("res://data/travel/mars_sol1155_4k_cyl.jpg")
		if _ctex != null:
			_travel_cyl_mat.albedo_texture = _ctex
	if _travel_sphere != null:
		var mat: StandardMaterial3D = _travel_sphere.material_override as StandardMaterial3D
		if mat != null:
			var tex: Texture2D = null
			var alpha: float = 1.0  # vc92 opaque
			if _travel == "Mars":
				tex = load("res://data/travel/mars_skybox_panopulse.jpg")  # vc100: PanoPulse AI skybox, Oct 31, imagined, not NASA photo
				alpha = 1.0
			elif _bodies.has(_travel):
				var gmat: StandardMaterial3D = (_bodies[_travel] as MeshInstance3D).material_override as StandardMaterial3D if _travel != "Sun" else null
				if gmat != null:
					tex = gmat.albedo_texture
			if tex != null:
				mat.albedo_texture = tex
			mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	if _travel_deck != null and TRAVEL_DECK_PLANETS.has(_travel):
		var deckmat: StandardMaterial3D = _travel_deck.material_override as StandardMaterial3D
		if deckmat != null:
			var dtex: Texture2D = _deck_texture(_travel)
			if dtex != null:
				deckmat.albedo_texture = dtex
	if _travel_sun != null:
		var sunmat: StandardMaterial3D = _travel_sun.material_override as StandardMaterial3D
		if sun_dir.y > -0.05:
			_travel_sun.visible = true
			_travel_sun.global_position = sun_dir.normalized() * 19.0
			# Sunlight pales with distance: warm near Jupiter,
			# a cold spark by Neptune. (AU: J 5.2, S 9.6, U 19.2,
			# N 30.1 — dimming is real, values are impression.)
			var pallor: Color = Color(1.0, 0.98, 0.92)
			if _travel == "Saturn":
				pallor = Color(1.0, 0.95, 0.85)
			elif _travel == "Uranus":
				pallor = Color(0.90, 0.93, 0.95)
			elif _travel == "Neptune":
				pallor = Color(0.75, 0.82, 1.0)
			if sunmat != null:
				sunmat.albedo_color = pallor
				sunmat.emission = pallor
		else:
			_travel_sun.visible = false

func _loader_env_for(name: String) -> Resource:
	if _loader_envs.has(name):
		return _loader_envs[name]
	if not LOADER_WORLDS.has(name):
		return null
	var env: Resource = load("res://data/worlds/" + str(LOADER_WORLDS[name]))
	if env != null:
		_loader_envs[name] = env
	return env

func debug_jump_to_world(name: String) -> bool:
	if not LOADER_WORLDS.has(name):
		return false
	_travel = name
	return true

func set_travel(name: String) -> void:
	if can_travel(name):
		if _telescope_8k_body != "":
			_swap_telescope_texture(_telescope_8k_body, false)
		_focused = name
		_telescope = ""
		_travel = name
		_holding = false
		print("Star App: travel ", name)

func clear_travel() -> void:
	_travel = ""

func travel_body() -> String:
	return _travel

func has_travel(name: String) -> bool:
	return TRAVEL_TEXTURES.has(name)

func focused_body() -> String:
	return _focused

func _swap_telescope_texture(name: String, use_8k: bool) -> void:
	if not _bodies.has(name):
		return
	# vc156: Sun is a plain textured mesh again, so telescope swap works for it too.
	var mesh_inst: Node3D = _bodies[name]
	var mat: StandardMaterial3D = (mesh_inst as MeshInstance3D).material_override as StandardMaterial3D
	if mat == null:
		return
	if use_8k and TELESCOPE_TEXTURES_8K.has(name) and ResourceLoader.exists(TELESCOPE_TEXTURES_8K[name]):
		mat.albedo_texture = load(TELESCOPE_TEXTURES_8K[name])
		_telescope_8k_body = name
	elif TELESCOPE_TEXTURES_4K.has(name) and ResourceLoader.exists(TELESCOPE_TEXTURES_4K[name]):
		mat.albedo_texture = load(TELESCOPE_TEXTURES_4K[name])
		_telescope_8k_body = ""
	elif TELESCOPE_TEXTURES.has(name):
		mat.albedo_texture = load(TELESCOPE_TEXTURES[name])
		_telescope_8k_body = ""

func set_telescope(name: String) -> void:
	if _bodies.has(name):
		if _telescope_8k_body != "" and _telescope_8k_body != name:
			_swap_telescope_texture(_telescope_8k_body, false)
		_focused = name
		_telescope = name
		_swap_telescope_texture(name, true)
		_holding = false
		print("Star App: telescope zoom ", name)

func clear_telescope() -> void:
	if _telescope_8k_body != "":
		_swap_telescope_texture(_telescope_8k_body, false)
	_telescope = ""

func telescope_body() -> String:
	return _telescope

func is_real_scan(name: String) -> bool:
	return TELESCOPE_TEXTURES.has(name)

# Current world directions of all bodies, for tap-to-identify.
# A focused (brought-to-you) body keeps its sky direction here,
# so a second pinch on it still identifies it, not empty sky.
func body_global_position(name: String) -> Vector3:
	if _bodies.has(name):
		return (_bodies[name] as Node3D).global_position
	return Vector3.ZERO

func body_directions() -> Dictionary:
	var jds: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	var out: Dictionary = {}
	for name: String in _bodies.keys():
		out[name] = _body_dir(name, jds).normalized()
	return out
