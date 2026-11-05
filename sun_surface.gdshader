shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
// Animated photosphere: boiling granules with dark lanes, drifting sunspots, flowing plasma,
// limb darkening and differential rotation. Everything is procedural (no textures).
// Put it on a sphere mesh (any radius). Works in the GL Compatibility renderer.

uniform float time_scale = 1.0;
uniform float granule_scale = 14.0;     // granule cells across the sphere (higher = finer, more cost on screen)
uniform float granule_boil = 0.45;      // how fast the cells churn
uniform float lane_width = 0.34;        // dark lane width between granules
uniform float flow_warp = 0.05;         // how much the plasma flow bends the pattern
uniform float spot_amount = 1.0;        // 0 = no sunspots
uniform float limb_darkening = 0.62;
uniform float brightness = 1.2;
uniform float whiteness = 0.30;         // 0 = deep orange fire, 1 = white-yellow like a photo
uniform int quality = 2;                // 0 cheap, 1 medium, 2 full
uniform vec3 col_deep : source_color = vec3(0.42, 0.07, 0.01);
uniform vec3 col_mid : source_color = vec3(1.0, 0.36, 0.04);
uniform vec3 col_hot : source_color = vec3(1.0, 0.74, 0.28);
uniform vec3 col_white : source_color = vec3(1.0, 0.95, 0.82);

varying vec3 v_pos;

void vertex() {
	v_pos = normalize(VERTEX);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
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

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 17.1;
		a *= 0.5;
	}
	return s;
}

// Cell noise with feature points that wander over time, so cells breathe and churn.
// Returns (F1, F2, random id of the nearest cell).
vec3 worley(vec3 p, float t) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = hash33(ip + g);
				vec3 o = 0.5 + 0.42 * sin(t * (0.5 + 0.8 * h) + 6.2831 * h);
				vec3 d = g + o - fp;
				float dist = dot(d, d);
				if (dist < f1) {
					f2 = f1;
					f1 = dist;
					id = h.x;
				} else if (dist < f2) {
					f2 = dist;
				}
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

void fragment() {
	float t = TIME * time_scale;
	vec3 p = normalize(v_pos);

	// Differential rotation: the equator turns faster than the poles
	float s_lat = p.y;
	float omega = 1.0 - 0.28 * s_lat * s_lat;
	float a = t * 0.025 * omega;
	float ca = cos(a);
	float sa = sin(a);
	p = vec3(p.x * ca - p.z * sa, p.y, p.x * sa + p.z * ca);

	// Plasma flow bends the whole pattern
	vec3 q = p;
	if (quality >= 1) {
		vec3 w = vec3(fbm(p * 2.5 + vec3(0.0, t * 0.05, 0.0)),
				fbm(p * 2.5 + vec3(7.3, 0.0, -t * 0.04)),
				fbm(p * 2.5 + vec3(2.1, t * 0.03, 5.0)));
		q = normalize(p + (w - 0.5) * flow_warp * 2.0);
	}

	// Granulation: bright cells, dark lanes
	float gran;
	if (quality >= 1) {
		vec3 w1 = worley(q * granule_scale, t * granule_boil);
		float lane = smoothstep(0.0, lane_width, w1.y - w1.x);
		gran = mix(0.55, 1.0, lane) * (0.62 + 0.62 * w1.z);
		if (quality >= 2) {
			vec3 w2 = worley(q * granule_scale * 0.22 + 11.0, t * granule_boil * 0.35);
			float lane2 = smoothstep(0.0, 0.5, w2.y - w2.x);
			gran *= mix(0.55, 1.12, lane2);
		}
	} else {
		gran = 0.45 + 0.9 * vnoise(q * granule_scale * 0.8 + vec3(0.0, t * 0.1, 0.0));
	}

	// Large slow waves of brightness (the "rippling" look)
	float wave = fbm(q * 3.2 + vec3(0.0, t * 0.07, 0.0));
	float I = gran * (0.55 + 0.9 * wave);

	// Sunspots: dark umbra with a softer penumbra, in the active latitude bands
	if (spot_amount > 0.0) {
		float sp = fbm(q * 1.6 + vec3(3.0, 1.0, 5.0) + vec3(0.0, 0.0, t * 0.004));
		float band = smoothstep(0.62, 0.30, abs(p.y));
		float penumbra = smoothstep(0.50, 0.57, sp) * band * spot_amount;
		float umbra = smoothstep(0.57, 0.63, sp) * band * spot_amount;
		I *= 1.0 - 0.45 * penumbra;
		I = mix(I, 0.10, umbra * 0.85);
	}

	// Limb darkening and the redder light at the edge
	float mu = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float limb = 1.0 - limb_darkening * (1.0 - mu);

	// Bright faculae near the edge
	float fac = pow(1.0 - mu, 2.0) * smoothstep(0.55, 0.80, vnoise(q * 15.0 + vec3(t * 0.05)));
	I += fac * 0.5;

	// Colour ramp
	vec3 c = mix(col_deep, col_mid, smoothstep(0.05, 0.50, I));
	c = mix(c, col_hot, smoothstep(0.40, 0.95, I));
	c = mix(c, col_white, smoothstep(0.80, 1.35, I) * whiteness + whiteness * 0.20 * smoothstep(0.3, 1.0, I));
	c *= mix(vec3(1.0, 0.70, 0.45), vec3(1.0), pow(mu, 0.5));

	ALBEDO = c * limb * brightness;
}
