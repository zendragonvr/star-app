# vc110 STEP 1 — PlanetLoader. Takes a PlanetEnv and builds/applies
# a world from the existing modules (sky, terrain, rocks, fog,
# particles, light, audio). For vc110 it wraps the existing MarsWorld:
# it does NOT rewrite MarsWorld, it applies mars.tres to it before
# the first activate(), so Mars looks identical to vc109.
# TODO (later, not faked in vc110): a real fade overlay — there is no
# fade UI in the current main scene, so load/unload is instant for
# now; fade_duration is kept for that overlay. Also TODO: height_fog
# and sky_bodies are stored on the env but not yet rendered by
# MarsWorld (it has no height-fog layer and no sky-body meshes);
# they are documented here, not silently claimed as applied.
class_name PlanetLoader
extends Node

var debug_menu_enabled: bool = false
var fade_duration: float = 0.0
var _current_env: Resource = null
var _current_world: Node = null

# Worlds available in this build. Later worlds are added here as
# their .tres files land, one at a time, tested before the next.
func debug_worlds() -> Array:
	return ["Mars", "Moon", "Mercury", "Venus", "Titan", "Pluto", "Europa", "Triton", "Io", "Jupiter", "Saturn", "Uranus", "Neptune", "Sun", "StarBlueWhite", "StarYellow", "StarOrange", "StarRed", "StarRedGiant", "StarWhiteDwarf"]

func debug_jump_to_world(world_name: String) -> bool:
	# Minimal debug-menu entry point, behind debug_menu_enabled.
	# No visible in-headset menu UI exists yet in vc110; callers
	# (planets_core travel) use set_travel() for the real path.
	if not debug_menu_enabled:
		return false
	return world_name in debug_worlds()

func apply_env_to_mars(env: Resource, world: Node) -> void:
	if env == null or world == null:
		return
	if world.has_method("apply_env"):
		world.call("apply_env", env)
	_current_env = env
	_current_world = world

func load_world(env: Resource, world: Node) -> void:
	# Fade out is a TODO (no fade overlay in main scene yet).
	apply_env_to_mars(env, world)
	if world.has_method("activate"):
		world.call("activate")

func unload_world(world: Node) -> void:
	if world == null:
		return
	if world.has_method("deactivate"):
		world.call("deactivate")
	# Free textures/meshes between worlds so memory does not grow:
	# MarsWorld.free_built() removes all built children and clears
	# its detail texture/noise, so the next load rebuilds from env.
	if world.has_method("free_built"):
		world.call("free_built")
	_current_env = null
	_current_world = null

# place() helper for the AI face, per world. It does NOT move the
# face — AiFace positions itself every frame (400 m, 150 m up) —
# it only applies the per-world tint. Mars tint = default cyan-teal.
func place_face(face: Node, env: Resource) -> void:
	if face == null:
		return
	var tint: Color = Color(0.18, 0.83, 0.91)
	if env != null:
		tint = env.face_tint
	if face.has_method("set_face_tint"):
		face.call("set_face_tint", tint)

# vc111 STEP C: fade overlay. planets_core creates a CanvasLayer ColorRect
# and calls fade_to_black() on travel change; the overlay fades back in
# over 0.6s. This is a black-flash + fade-in covering the swap, not a
# pre-swap fade-out delay (that would need a travel state machine).
func make_fade_overlay() -> CanvasLayer:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(0.0, 0.0, 0.0, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.name = "TravelFadeRect"
	layer.add_child(rect)
	layer.name = "TravelFadeLayer"
	return layer
