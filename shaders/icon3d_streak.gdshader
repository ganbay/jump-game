shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Trails and eruption tongues: flat wedges like the 2D icon's tail, one colour
// and one opacity each, taper doing all the shaping. Colour comes in as vertex
// colour, which a mesh stores as 8-bit -- `gain` takes it into the glow.

uniform float gain = 1.3;

void fragment() {
	ALBEDO = COLOR.rgb * gain;
	ALPHA = COLOR.a;
}
