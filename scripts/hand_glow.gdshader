// Trippy hand outline, written from scratch for Star App.
// A fresnel rim that traces the hand silhouette from every angle,
// flowing through rainbow hues over time. Transparent so the real
// hand shows through in passthrough; depth still occludes planets
// correctly behind the hand. Unshaded: pure light, no fake shading.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float rim_power = 2.5;
uniform float flow_speed = 1.5;

void fragment() {
	float fres = pow(1.0 - dot(normalize(NORMAL), normalize(VIEW)), rim_power);
	vec3 rainbow = 0.5 + 0.5 * cos(TIME * flow_speed + vec3(0.0, 2.1, 4.2) + VERTEX.y * 4.0);
	vec3 col = mix(tint.rgb, rainbow, 0.65);
	ALBEDO = col * 0.25;
	EMISSION = col * (0.5 + fres * 2.5);
	ALPHA = 0.30 + fres * 0.60;
}
