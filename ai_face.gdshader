shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;  // vc114 SAFETY NET

// ---- textures ----
uniform sampler2D face_tex : filter_linear, repeat_disable;
uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform sampler2D mouth_mask : filter_linear, repeat_disable;
uniform bool use_depth_tex = false;

// ---- look ----
uniform vec3 color : source_color = vec3(0.18, 0.83, 0.91);
uniform float glow = 0.6;  // vc113 TEST: was 1.0; try 0.4 if still flat (not set yet)
uniform float point_size = 1.8;  // vc113 TEST: was 2.0, inside user 1.6-2.0 range
uniform float star_chance = 0.01;  // vc113 TEST: was 0.015
uniform float depth_strength = 0.35;   // in face-widths (mesh is 1 unit wide)

// ---- layout of the portrait (UV space). Adjust if you swap the portrait ----
uniform float mouth_line = 0.685;      // y of the mouth slit
uniform vec4 eye_uv = vec4(0.385, 0.447, 0.615, 0.447);

// ---- life ----
uniform float breathe = 0.0;  // vc113 TEST ONLY: was 0.01, restore after verdict
uniform float drift = 0.0;  // vc113 TEST ONLY: was 0.002, restore after verdict
uniform float hair_drift = 0.0;  // vc113 TEST ONLY: was 0.05, restore after verdict
uniform float dissolve = 0.0;          // 0..1
uniform float listening = 0.0;         // 0..1
uniform float thinking = 0.0;          // 0..1
uniform float speak_boost = 0.0;       // 0..1

// ---- voice ----
uniform float jaw = 0.0;               // 0..1
uniform float wide = 0.0;              // 0..1
uniform float round_amt = 0.0;         // 0..1
uniform float hiss = 0.0;              // 0..1

varying float v_bright;
varying float v_star;
varying float v_eye;
varying float v_lip;
varying float v_gap;
varying float v_chin;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	vec2 uv = UV;
	float r1 = UV2.x;
	float r2 = UV2.y;

	float b = textureLod(face_tex, uv, 0.0).r;
	float d = use_depth_tex ? textureLod(depth_tex, uv, 0.0).r : b;
	float m = textureLod(mouth_mask, uv, 0.0).r;

	vec3 p = VERTEX;
	p.z = (d - 0.5) * depth_strength;

	// idle motion
	p += vec3(sin(TIME * 0.6 + r1 * 40.0), cos(TIME * 0.5 + r2 * 40.0), sin(TIME * 0.4 + r1 * r2 * 60.0)) * drift;

	// hair / beard: slow downward drift on the lower face
	float hair = smoothstep(0.62, 0.9, uv.y);
	p.y -= hair * (0.5 + 0.5 * sin(TIME * 0.4 + r2 * 6.2831)) * hair_drift * r1;

	// listening: pulled slightly inward
	p.xy *= 1.0 - listening * 0.03;

	// thinking: slow swirl, stronger toward the center
	float swirl = thinking * 0.25 * sin(TIME * 0.8) * (1.0 - clamp(length(p.xy) * 1.4, 0.0, 1.0));
	float cs = cos(swirl);
	float sn = sin(swirl);
	p.xy = vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
	p += (vec3(hash(r1 * 91.0 + floor(TIME * 3.0)), hash(r2 * 53.0 + floor(TIME * 3.0)), 0.5) - 0.5) * thinking * 0.01;

	// speaking: jaw drops as one piece, lips part around the mouth line
	float jaw_w = smoothstep(mouth_line + 0.01, mouth_line + 0.06, uv.y);
	p.y -= jaw * jaw_w * 0.08;
	float side = clamp((uv.y - mouth_line) / 0.03, -1.0, 1.0);
	p.y -= side * m * jaw * 0.03;
	p.x *= 1.0 + wide * 0.15 * m - round_amt * 0.2 * m;
	p += (vec3(hash(r1 * 31.0 + TIME), hash(r2 * 17.0 + TIME), hash(r1 + r2 + TIME)) - 0.5) * hiss * m * 0.02;

	// breathing
	p *= 1.0 + breathe * sin(TIME * 0.9);

	// dissolve and reform
	vec3 dir = normalize(vec3(p.xy, 0.0) + (vec3(r1, r2, r1 * r2) - 0.5) * 0.6 + vec3(0.0, 0.0, 0.0001));
	p += dir * dissolve * 0.08 * (0.5 + r2);

	// vc111 STEP B: lip edge / dark gap / chin-cheek glow factors.
	float lip_dist = abs(uv.y - mouth_line);
	v_lip = (lip_dist < 0.012) ? 1.0 : 0.0;
	float gap_w = 0.02 * jaw;
	v_gap = (gap_w > 0.0 && lip_dist < gap_w && m > 0.5) ? (1.0 - lip_dist / gap_w) : 0.0;
	float chin_f = smoothstep(mouth_line, 1.0, uv.y);
	float cheek_f = max(exp(-(pow((uv.x - eye_uv.x) / 0.12, 2.0) + pow((uv.y - eye_uv.y) / 0.08, 2.0))), exp(-(pow((uv.x - eye_uv.z) / 0.12, 2.0) + pow((uv.y - eye_uv.w) / 0.08, 2.0))));
	v_chin = max(chin_f, cheek_f);
	VERTEX = p;

	// per-point appearance
	float twinkle = 0.8 + 0.2 * sin(TIME * (1.0 + r1 * 3.0) + r2 * 20.0);
	v_bright = mix(0.45, 1.0, b) * (0.7 + 0.3 * r2) * twinkle;
	v_star = step(1.0 - star_chance, fract(r1 * 91.7 + r2 * 13.3));

	float e1 = exp(-(pow((uv.x - eye_uv.x) / 0.07, 2.0) + pow((uv.y - eye_uv.y) / 0.03, 2.0)));
	float e2 = exp(-(pow((uv.x - eye_uv.z) / 0.07, 2.0) + pow((uv.y - eye_uv.w) / 0.03, 2.0)));
	v_eye = max(e1, e2);

	POINT_SIZE = point_size * (1.0 + v_star * 1.8);
}

void fragment() {
	vec2 c = POINT_COORD - vec2(0.5);
	float a = smoothstep(0.5, 0.0, length(c));
	float boost = 1.0 + v_star * 1.5 + speak_boost * 0.25 + v_eye * listening * 1.2;
	boost *= 1.0 + v_lip * 0.6 * jaw;
	boost += smoothstep(0.3, 0.6, jaw) * v_chin * 0.6;
	ALBEDO = color * v_bright * glow * boost;
	ALPHA = a * (1.0 - v_gap * 0.9);
}
