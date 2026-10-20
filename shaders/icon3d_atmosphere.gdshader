shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front, shadows_disabled;

// A shell a little larger than the planet, drawn from its inside face: only the
// band outside the planet's silhouette survives the depth test. Two flat steps
// rather than a falloff, the way the 2D icon stacks its halo.

uniform vec3 glow_color : source_color = vec3(0.55, 0.42, 1.0);
uniform float inner_cut = 0.55;
uniform float outer_cut = 0.25;
uniform float gain = 0.45;

float band(float edge, float x) {
	float w = max(fwidth(x), 0.0005);
	return smoothstep(edge - w, edge + w, x);
}

void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = glow_color * gain;
	ALPHA = 0.35 * band(outer_cut, f) + 0.45 * band(inner_cut, f);
}
