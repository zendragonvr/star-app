# vc110 STEP 1 — reusable world settings. One PlanetEnv per world.
# Mars is mars.tres and must look identical to vc109. Later worlds
# (Moon, Mercury, ...) are only new .tres files, no new systems.
# Texture provenance is recorded in source_note: vc110 textures are
# procedural in code (no external download, no copyrighted image).
# NASA images, when used later, are mostly US-government public
# domain — record the exact source in source_note per world.
class_name PlanetEnv
extends Resource

enum ParticleType { DUST, ASH, SNOW, NONE }

@export var name: String = ""
@export var sky_horizon_color: Color = Color(0.85, 0.70, 0.52)
@export var sky_mid_color: Color = Color(0.72, 0.52, 0.36)
@export var sky_zenith_color: Color = Color(0.49, 0.31, 0.24)
@export var haze_strength: float = 0.35
@export var sun_angular_size_deg: float = 0.35
@export var sun_color: Color = Color(1.0, 0.92, 0.80)
@export var sun_energy: float = 2.2
@export var shadow_hardness: float = 1.0
@export var show_stars: bool = false
@export var star_brightness: float = 0.0
@export var fog_color: Color = Color(0.85, 0.70, 0.52)
@export var fog_density: float = 0.0009
@export var height_fog: float = 0.0
@export var terrain_amplitude: float = 2.2
@export var terrain_frequency: float = 0.012
@export var terrain_ridge_amount: float = 1.2
@export var terrain_crater_count: int = 3
@export var terrain_crater_size: float = 20.0
# Ground texture set, 3 layers (sand / gravel / rock). Null in vc110:
# Mars ground is procedural noise in mars_world.gd, not a texture file.
@export var ground_albedo: Array[Texture2D] = []
@export var ground_normal: Array[Texture2D] = []
@export var ground_roughness: Array[Texture2D] = []
@export var ground_tint: Array[Color] = []
@export var rock_mesh_set: Array[Mesh] = []
@export var rock_density: float = 1.0
@export var rock_color: Color = Color(0.45, 0.28, 0.18)
@export var particle_type: ParticleType = ParticleType.DUST
@export var particle_density: int = 800
@export var particle_drift: float = 0.5
# Sky bodies: Array[Dictionary] with keys name, texture, angular_size_deg, azimuth, elevation.
@export var sky_bodies: Array[Dictionary] = []
@export var wind_audio: AudioStream = null
@export var ambient_audio: AudioStream = null
@export var gravity_scale: float = 1.0
@export var eye_height: float = 1.6
@export var source_note: String = ""
# vc110 colour grade (Mars travel only, not main passthrough sky).
@export var grade_saturation: float = 0.85
@export var grade_contrast: float = 1.1
@export var grade_tint: Color = Color(1.06, 0.99, 0.90)
@export var shadow_distance: float = 40.0
@export var sun_elevation_deg: float = 35.0
@export var sun_azimuth_deg: float = -45.0
@export var rock_count: int = 300
@export var boulder_count: int = 8
@export var pebble_count: int = 1500
@export var cobble_count: int = 300
@export var terrain_inner_size: float = 120.0
@export var terrain_inner_step: float = 1.0
# vc111: world kind + face tint + optional features. Defaults keep Mars identical.
@export var world_kind: String = "surface"  # surface | cloud_platform | distant_sun | star
@export var face_tint: Color = Color(0.18, 0.83, 0.91)
@export var platform_label: String = ""
@export var has_lake: bool = false
@export var has_lava: bool = false
@export var sun_disc: bool = true
@export var ambient_fill: float = 0.0
@export var ice_roughness: float = 0.95
