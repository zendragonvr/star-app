class_name SunNode
extends Node3D
## Builds an animated, realistic Sun: a sphere with sun_surface.gdshader plus a billboard quad
## with sun_corona.gdshader (corona, prominences, flares). Size it with `radius` (meters),
## or place it with your sky layout helper using base_size = 2.0 * radius.
##
## quality: 0 cheap, 1 medium, 2 full. Start at 1 on Quest, raise to 2 only if you hold 72 fps.

@export var radius := 1.0
@export_range(0, 2) var quality := 1
@export var time_scale := 1.0               # >1 makes the plasma churn faster
@export var corona_scale := 4.0             # quad half-size in sun radii

var surface_material: ShaderMaterial
var corona_material: ShaderMaterial


func _ready() -> void:
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	sphere.mesh = sm
	surface_material = ShaderMaterial.new()
	surface_material.shader = load("res://sun_surface.gdshader")
	sphere.material_override = surface_material
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sphere)

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * radius * 2.0 * corona_scale
	quad.mesh = qm
	corona_material = ShaderMaterial.new()
	corona_material.shader = load("res://sun_corona.gdshader")
	corona_material.set_shader_parameter("quad_radius_in_suns", corona_scale)
	quad.material_override = corona_material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)

	apply_settings()


func apply_settings() -> void:
	surface_material.set_shader_parameter("quality", quality)
	surface_material.set_shader_parameter("time_scale", time_scale)
	corona_material.set_shader_parameter("time_scale", time_scale)
