shader_type spatial;
render_mode unshaded;

// The star the cast erupts from, drawn the way the game draws a star: a solid
// body with a lighter band churning over it, a bright limb line, flat hot rings
// round the vent and a hard shock ring. Noise only decides where the band
// boundaries fall -- every band itself is one flat colour.

uniform vec3 base_color : source_color = vec3(0.26, 0.14, 0.7);
uniform vec3 band_color : source_color = vec3(0.4, 0.26, 0.92);
uniform vec3 limb_color : source_color = vec3(0.75, 0.65, 1.0);
uniform vec3 hot_color : source_color = vec3(1.0, 0.85, 1.0);
uniform vec3 erupt_point = vec3(0.0, 100.0, 0.0);
uniform float noise_scale = 0.07;
uniform float flow = 0.12;
uniform float band_cut = 0.52;
uniform float limb_cut = 0.16;
uniform float heat_outer = 9.0;
uniform float heat_inner = 4.0;
uniform float heat_gain = 1.5;
uniform float shock_radius = 10.0;
uniform float shock_width = 0.9;
uniform float shock_gain = 0.0;

varying vec3 wp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 3; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s / 0.875;
}

float band(float edge, float x) {
	float w = max(fwidth(x), 0.0005);
	return smoothstep(edge - w, edge + w, x);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm(wp * noise_scale + vec3(0.0, TIME * flow, 0.0));
	vec3 col = mix(base_color, band_color, band(band_cut, n));
	float d = distance(wp, erupt_point);
	// Wobble the hot rings by the same noise, so they churn like the bands.
	float dn = d * (1.0 + (n - 0.5) * 0.35);
	col = mix(col, mix(band_color, hot_color, 0.5), 1.0 - band(heat_outer, dn));
	col = mix(col, hot_color * heat_gain, 1.0 - band(heat_inner, dn));
	float ring = band(shock_radius - shock_width, dn) * (1.0 - band(shock_radius + shock_width, dn));
	col = mix(col, hot_color * 1.2, ring * shock_gain);
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, limb_color * 1.3, 1.0 - band(limb_cut, f));
	ALBEDO = col;
}
