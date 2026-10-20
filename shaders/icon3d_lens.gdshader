shader_type canvas_item;

// Fisheye pass over the 3D render. Barrel distortion: each output pixel at
// radius r samples the render at r * (1 + k r^2), which swells the middle and
// crushes the edges -- normalised so the corners still land on the corners.
// Radius is measured with x scaled by `aspect`, so on a wide frame the bend is
// round rather than stretched; at 1.0 (the square icon) it changes nothing.

uniform float strength = 0.45;
uniform float zoom = 1.0;
uniform float vignette = 0.5;
uniform float aspect = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 q = p * vec2(aspect, 1.0);
	float r2 = dot(q, q);
	float corner = aspect * aspect + 1.0;
	// Radius taken as a fraction of the corner's, so the bend is spread over
	// the whole frame and swells the middle by the same 1 + 2k on any aspect.
	// On a square frame this is exactly r2 / 2, i.e. the plain formula.
	float k = 2.0 * strength;
	vec2 s = p * (1.0 + k * r2 / corner) / ((1.0 + k) * zoom);
	vec3 c = texture(TEXTURE, s * 0.5 + 0.5).rgb;
	c *= 1.0 - vignette * smoothstep(0.4 * corner, corner, r2);
	COLOR = vec4(c, 1.0);
}
