shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled;
// Low-poly rock/ice chunks flying past on the 3I/ATLAS ride.
// Same wrap-around-the-camera approach as ride_streaks: position is
// computed in the vertex shader, no CPU per-frame updates.
// Chunks pass 3 to 15 m away, never within 2 m of the head, fade in
// and out at the box edges, and tumble slowly. TIME is the only driver.
uniform vec3 cam_pos = vec3(0.0);
uniform vec3 box_size = vec3(60.0, 36.0, 160.0);
uniform float travel = 0.0;
uniform float seed = 0.0;
uniform vec3 chunk_color : source_color = vec3(0.16, 0.13, 0.11);
uniform float chunk_scale = 0.35;

varying float v_alpha;

void vertex() {
	vec3 rnd = vec3(fract(seed * 0.37 + 0.13), fract(seed * 0.73 + 0.29), fract(seed * 0.19 + 0.71));
	vec3 flow = vec3(0.0, 0.0, 1.0);
	vec3 p = rnd * box_size + flow * travel;
	vec3 local = mod(p - cam_pos + box_size * 0.5, box_size) - box_size * 0.5;
	vec3 center = cam_pos + local;
	float dist = length(local);
	// Visible only in the 3 to 15 m shell, never within 2 m of the head.
	float shell = smoothstep(2.0, 3.0, dist) * (1.0 - smoothstep(15.0, 18.0, dist));
	float edge = 1.0 - max(max(abs(local.x) / (box_size.x * 0.5), abs(local.y) / (box_size.y * 0.5)), abs(local.z) / (box_size.z * 0.5));
	float fade_edge = smoothstep(0.0, 0.12, edge);
	v_alpha = shell * fade_edge;
	// Slow tumble: one slow turn every ~30 s, different axis per chunk.
	float ang = TIME * 0.2 * (0.5 + rnd.x);
	vec3 axis = normalize(vec3(rnd.x - 0.5, rnd.y - 0.5, rnd.z - 0.5) + vec3(0.001, 0.0, 0.0));
	float c = cos(ang);
	float s = sin(ang);
	vec3 v = VERTEX * chunk_scale;
	vec3 rot = v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
	vec3 world = center + rot;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	ALBEDO = chunk_color;
	ALPHA = v_alpha;
}
