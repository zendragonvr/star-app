shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Speed streaks for the 3I/ATLAS ride. Every streak is a quad whose position is computed here,
// wrapped inside a box around the camera, so nothing is simulated on the CPU.
// The box flows along +Z (you travel toward -Z).

uniform vec3 cam_pos = vec3(0.0);                  // headset position, set every frame by travel_ride.gd
uniform vec3 box_size = vec3(60.0, 36.0, 160.0);   // wrap box, meters
uniform float travel = 0.0;                        // accumulated distance (meters), wrapped by the script
uniform float speed = 0.0;                         // current visual speed, m/s
uniform float base_len = 0.35;                     // streak length at rest, meters
uniform float len_per_speed = 0.10;                // extra length per m/s
uniform float width = 0.022;                       // streak width, meters
uniform float min_px_angle = 0.0024;               // keeps far streaks about 2 px wide (no shimmer)
uniform float clear_radius = 1.0;                  // empty bubble around the head
uniform float intensity = 1.8;
uniform vec3 cool_color : source_color = vec3(0.72, 0.86, 1.0);
uniform vec3 warm_color : source_color = vec3(1.0, 0.70, 0.42);

varying float v_alpha;
varying vec3 v_col;

void vertex() {
	vec3 rnd = vec3(UV2.x, UV2.y, fract(UV2.x * 13.37 + UV2.y * 7.77));
	vec3 flow = vec3(0.0, 0.0, 1.0);
	vec3 p = rnd * box_size + flow * travel;
	vec3 local = mod(p - cam_pos + box_size * 0.5, box_size) - box_size * 0.5;
	vec3 center = cam_pos + local;

	float edge = 1.0 - max(max(abs(local.x) / (box_size.x * 0.5), abs(local.y) / (box_size.y * 0.5)), abs(local.z) / (box_size.z * 0.5));
	float fade_edge = smoothstep(0.0, 0.12, edge);
	float dist = max(length(local), 0.001);
	float near_fade = smoothstep(clear_radius, clear_radius * 2.5, dist);

	vec3 view_dir = local / dist;
	vec3 side = normalize(cross(flow, view_dir) + vec3(0.0001, 0.0, 0.0));
	float len = base_len + speed * len_per_speed;
	float w = max(width, dist * min_px_angle) * (0.6 + 0.8 * rnd.z);

	// UV.y = 0 is the bright head (leading end), UV.y = 1 is the tail
	vec3 world = center + flow * ((0.5 - UV.y) * len) + side * ((UV.x - 0.5) * w);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;

	float gate = smoothstep(0.0, 2.0, speed);
	float bright = 0.35 + 0.65 * fract(rnd.x * 91.7 + rnd.y * 33.1);
	v_alpha = bright * fade_edge * near_fade * mix(0.5, 1.0, gate) * intensity;
	v_col = mix(cool_color, warm_color, step(0.86, rnd.z));
}

void fragment() {
	float along = pow(1.0 - UV.y, 1.6) * smoothstep(0.0, 0.05, UV.y);
	float across = 1.0 - pow(abs(UV.x - 0.5) * 2.0, 2.0);
	ALBEDO = v_col * v_alpha;
	ALPHA = clamp(along * across, 0.0, 1.0);
}
