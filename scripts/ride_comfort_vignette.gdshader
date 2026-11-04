shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
// Comfort vignette: put this on an inverted-looking sphere (radius ~0.3 m) that is a child of the
// XRCamera3D, with render_priority 100. It darkens the edges of the view while the ride is fast,
// which is the most effective single thing against motion sickness.

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float inner_deg = 38.0;     // clear in the middle of the view
uniform float outer_deg = 62.0;     // fully dark by here
uniform float fade : hint_range(0.0, 1.0) = 0.0;   // 1 = fully black (for fade in and out)

void fragment() {
	vec3 d = normalize(VERTEX);       // view space: the camera looks down -Z
	float ang = degrees(acos(clamp(dot(d, vec3(0.0, 0.0, -1.0)), -1.0, 1.0)));
	float a = smoothstep(inner_deg, outer_deg, ang) * strength;
	ALBEDO = vec3(0.0);
	ALPHA = max(a, fade);
}
