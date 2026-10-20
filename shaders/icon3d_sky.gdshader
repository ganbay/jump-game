shader_type sky;

uniform vec3 zenith : source_color = vec3(0.01, 0.015, 0.06);
uniform vec3 horizon : source_color = vec3(0.10, 0.04, 0.22);
uniform vec3 star_color : source_color = vec3(0.85, 0.9, 1.0);
// Few and large, same as the 2D icon: small dots turn to dirt at 48px.
uniform float star_scale = 40.0;
uniform float star_density = 0.05;
uniform float star_size = 0.09;
uniform float star_gain = 1.6;

float h1(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = mix(horizon, zenith, smoothstep(-0.1, 0.5, d.y));
	vec3 g = d * star_scale;
	vec3 c = floor(g);
	vec3 f = fract(g);
	if (h1(c) < star_density) {
		vec3 o = vec3(h1(c + 1.3), h1(c + 7.1), h1(c + 3.7)) * 0.6 + 0.2;
		float b = h1(c + 11.0);
		col += star_color * smoothstep(star_size * (0.5 + b), 0.0, length(f - o)) * star_gain * (0.4 + b);
	}
	COLOR = col;
}
