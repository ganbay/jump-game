shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// A character from the 3D icon, painted like the game's PlasmaBlob: flat bands
// with hard edges -- a saturated rim, a solid body, a lifted middle and a
// blown-out core -- picked by how squarely the surface faces the camera, so an
// inflated mesh still reads as the same flat 2D cell. The churn moves the band
// boundaries, never shades across them.

instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float seed = 0.0;
uniform float wobble = 0.045;
uniform float churn_speed = 2.4;
uniform float rim_cut = 0.32;
uniform float mid_cut = 0.62;
uniform float core_cut = 0.86;
uniform float band_churn = 0.08;
uniform float core_gain = 1.6;

varying vec3 opos;

void vertex() {
	float a = atan(VERTEX.y, VERTEX.x);
	float t = TIME * churn_speed + seed;
	VERTEX.xy *= 1.0 + wobble * (0.6 * sin(3.0 * a + t) + 0.4 * sin(5.0 * a - t * 1.3));
	opos = VERTEX;
}

// A hard step, antialiased over one pixel.
float band(float edge, float x) {
	float w = max(fwidth(x), 0.001);
	return smoothstep(edge - w, edge + w, x);
}

void fragment() {
	// abs(): the mesh is drawn double-sided and its winding is not relied on.
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float t = TIME * churn_speed + seed;
	float n = sin(opos.x * 5.0 + t) * sin(opos.y * 4.3 - t * 0.7)
		+ 0.5 * sin((opos.x + opos.y) * 9.0 + t * 1.4);
	float g = f + n * band_churn;
	vec3 rim = tint.rgb * 1.35 + vec3(0.12);
	vec3 body = tint.rgb;
	vec3 mid = mix(tint.rgb, vec3(1.0), 0.4) * 1.1;
	vec3 core = vec3(core_gain);
	vec3 col = mix(rim, body, band(rim_cut, f));
	col = mix(col, mid, band(mid_cut, g));
	col = mix(col, core, band(core_cut, g));
	ALBEDO = col;
}
