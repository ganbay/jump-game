shader_type canvas_item;
render_mode unshaded;

// The climb's backdrop: a vertical gradient from near-black at the top of the
// screen down to the zone's colour at the bottom.
//
// The glow sits below because that is where the Sun is. The run is an escape
// upward out of Solar gravity, so the light the player is climbing away from
// belongs under them, and it stays screen-fixed rather than scrolling -- no
// matter how high the climb gets, the thing being escaped is still down there.
//
// A gradient rather than a flat fill because a flat fill has only one lever:
// make the whole screen brighter. This puts real colour on screen while leaving
// most of it dark, which is what the platforms and the character need in order
// to read against it.

// Authored the same way ColorRect.color was, so these carry over unchanged.
uniform vec4 top_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Above 1.0 the colour is pushed down toward the bottom edge: the upper half of
// the screen stays near-black and the glow stays a horizon rather than a wash.
uniform float falloff = 2.4;

void fragment() {
	COLOR = vec4(mix(top_color.rgb, bottom_color.rgb, pow(UV.y, falloff)), 1.0);
}
