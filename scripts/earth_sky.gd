# Earth as a sky model — added 2026-11-02, vc146, user request.
# You stand on Earth, so in the real sky Earth is under you, not above.
# This is a MODEL in the sky (same idea as the Moon's Earth overhead):
# pinch it or say "show me Earth" and it comes to you like a planet.
# From the Moon, Earth really is overhead at about this size (2 deg);
# from other worlds it is the bright blue dot you would look for.
# Shape: code-built sphere, blue oceans + land/cloud noise shader
# (same shader as Moon travel Earth, vc115), no photo texture.
extends Node3D
class_name EarthSky

var brought: bool = false
var brought_position: Vector3 = Vector3.ZERO
var sky_radius: float = 85.0

var _model: Node3D = null
var _label: Label3D = null

func _set_brought_scale(s: float) -> void:
	if _model != null:
		_model.scale = Vector3(s, s, s)

func bring_to_front(cam: Node3D) -> void:
	var cf: Vector3 = -cam.global_transform.basis.z
	cf.y = 0.0
	if cf.length() < 0.01:
		cf = Vector3(0.0, 0.0, -1.0)
	cf = cf.normalized()
	var right114: Vector3 = Basis(Vector3.UP, deg_to_rad(-45.0)) * cf
	right114.y = 0.0
	right114 = right114.normalized()
	brought_position = cam.global_position + right114 * 4.0
	brought = true
	_set_brought_scale(0.5)
	global_position = brought_position

func send_back() -> void:
	brought = false
	_set_brought_scale(1.0)
	# Return to the fixed sky spot (az 60, el 30, 85 m).
	var az: float = deg_to_rad(60.0)
	var el: float = deg_to_rad(30.0)
	global_position = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)) * sky_radius

func _ready() -> void:
	_model = Node3D.new()
	var sm := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 1.5
	ss.height = 3.0
	sm.mesh = ss
	var emat := ShaderMaterial.new()
	emat.shader = Shader.new()
	emat.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 sun_dir;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(h(i), h(i+vec2(1.,0.)), f.x), mix(h(i+vec2(0.,1.)), h(i+vec2(1.,1.)), f.x), f.y); }
varying vec3 v_nrm;
void vertex(){ v_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment(){
	vec3 nn = normalize(v_nrm);
	float lit = smoothstep(-0.05, 0.15, dot(nn, sun_dir));
	float land = n(UV * 6.0);
	vec3 ocean = vec3(0.22, 0.42, 0.85);
	vec3 landc = mix(vec3(0.25, 0.45, 0.20), vec3(0.45, 0.35, 0.20), n(UV * 3.0 + 4.0));
	vec3 col = mix(ocean, landc, step(0.55, land));
	float cloud = step(0.62, n(UV * 9.0 + 11.0));
	col = mix(col, vec3(0.95), cloud * 0.8);
	col *= 0.05 + lit * 0.95;
	ALBEDO = col;
}
"""
	emat.set_shader_parameter("sun_dir", Vector3(0.5, 0.5, 0.5).normalized())
	sm.material_override = emat
	_model.add_child(sm)
	add_child(_model)
	_label = Label3D.new()
	_label.font_size = 32
	_label.text = "Earth"
	_label.position = Vector3(0, 2.2, 0)
	add_child(_label)
	_set_brought_scale(1.0)
	send_back()
