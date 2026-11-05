shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Corona, coronal streamers, prominences (looping arches of plasma) and flares.
// Put it on a QuadMesh centred on the Sun, sized (2 * quad_radius_in_suns * sun_radius).
// It always faces the viewer. The sun sphere hides the middle of it, so the glow starts at the limb.

uniform float quad_radius_in_suns = 4.0;
uniform float time_scale = 1.0;
uniform vec3 halo_color : source_color = vec3(1.0, 0.50, 0.12);
uniform vec3 streamer_color : source_color = vec3(1.0, 0.78, 0.50);
uniform vec3 prom_color : source_color = vec3(1.0, 0.30, 0.16);
uniform float corona_strength = 1.0;
uniform float prominence_strength = 1.0;
uniform float flare_strength = 1.0;
uniform float flare_period = 26.0;      // seconds between flares

varying vec2 v_uv;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	v_uv = UV;
}

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

// One looping arch of plasma standing on the limb at angle th.
float arch(float r, float ang, float th, float w, float h, float thick, float t, float seed) {
	float d = atan(sin(ang - th), cos(ang - th));
	float u = d / w;
	if (abs(u) > 1.0) {
		return 0.0;
	}
	float ra = 1.0 + h * pow(1.0 - u * u, 0.75);
	float x = (r - ra) / thick;
	float strand = 0.65 + 0.35 * vnoise(vec3(u * 9.0, seed, t * 0.35));
	float feet = 1.0 + 0.8 * pow(abs(u), 4.0);
	return exp(-x * x) * strand * feet;
}

void fragment() {
	float t = TIME * time_scale;
	vec2 c = (v_uv - 0.5) * 2.0 * quad_radius_in_suns;
	float r = length(c);
	float ang = atan(c.y, c.x);
	vec2 dir = vec2(cos(ang), sin(ang));

	float out_r = max(r - 1.0, 0.0);

	// Soft halo that hugs the limb
	float halo = exp(-out_r * 5.0) * 0.8 + exp(-out_r * 1.6) * 0.14;

	// Coronal streamers: long rays that drift slowly
	float n = 0.5 + 0.5 * sin(ang * 3.0 + 1.3 + t * 0.03 + sin(ang * 2.0 + t * 0.02) * 1.5);
	n *= 0.6 + 0.4 * (0.5 + 0.5 * sin(ang * 7.0 - t * 0.04 + r * 0.8));
	n = mix(n, 0.5 + 0.5 * sin(ang * 5.0 + 4.0 + t * 0.025), 0.35);
	float ray = pow(clamp(n, 0.0, 1.0), 2.2) * exp(-out_r * 0.95) * smoothstep(1.0, 1.12, r) * 0.55;

	// Prominences: several arches that grow and fade at different times
	float prom = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float period = 24.0 + fi * 7.0;
		float cycle = floor(t / period + fi * 0.37);
		float life = sin(3.14159 * fract(t / period + fi * 0.37));
		float th = 6.2831 * hash11(fi * 13.7 + cycle * 3.1);
		float w = 0.07 + 0.13 * hash11(fi * 5.3 + cycle * 1.7);
		float h = (0.16 + 0.34 * hash11(fi * 9.1 + cycle * 2.3)) * (0.35 + 0.65 * life);
		float thick = 0.010 + 0.014 * h;
		prom += arch(r, ang, th, w, h, thick, t, fi * 3.0 + cycle) * life;
		prom += arch(r, ang, th + 0.01, w * 0.85, h * 0.72, thick * 0.8, t, fi * 3.0 + cycle + 9.0) * life * 0.7;
	}

	// Flares: a fast bright burst at the limb, then a long fade
	float cyc = floor(t / flare_period);
	float ft = fract(t / flare_period);
	float fth = 6.2831 * hash11(cyc * 17.3 + 3.0);
	float fd = atan(sin(ang - fth), cos(ang - fth));
	float flare = exp(-ft * 8.0) * smoothstep(0.0, 0.015, ft);
	flare *= exp(-pow(fd / 0.10, 2.0)) * exp(-out_r * 3.2) * smoothstep(1.0, 1.03, r);
	flare += exp(-ft * 8.0) * exp(-pow(fd / 0.35, 2.0)) * exp(-out_r * 2.0) * 0.25 * smoothstep(1.0, 1.03, r);

	vec3 col = halo_color * halo * corona_strength
			+ streamer_color * ray * 0.9 * corona_strength
			+ prom_color * prom * 1.6 * prominence_strength
			+ vec3(1.0, 0.82, 0.55) * flare * 2.2 * flare_strength;

	col *= smoothstep(quad_radius_in_suns, quad_radius_in_suns * 0.75, r);
	ALBEDO = col;
	ALPHA = 1.0;
}
