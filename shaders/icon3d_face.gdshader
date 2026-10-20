shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// A face for the 3D icon's cast: two eyes and an optional mouth on a quad laid
// on the front of a body. One face design, many expressions -- what changes
// between characters is the lids, the eye shape and the mouth, set per
// material by icon_3d.gd's FACES table. Flat colour with hard, antialiased
// edges, like the bands it sits on; everything outside the features is
// discarded.
//
// Quad units, origin at the centre, y down. Eyes are mirrored across x; the
// per-eye vec2s are (viewer's left, viewer's right).

uniform vec3 ink_color : source_color = vec3(0.08, 0.03, 0.22);
uniform vec3 shine_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 blush_color : source_color = vec3(1.0, 0.35, 0.55);

// 0: filled eye cut by a lid. 1: closed happy arc, ^ ^.
uniform int eye_mode = 0;
uniform vec2 eye_center = vec2(0.2, 0.04);
uniform vec2 eye_size = vec2(0.1, 0.16);
// The lid: a line cutting the top of each eye, `lid_slope` dropping it towards
// the middle of the face. Positive slope reads determined, negative worried,
// a height of -1 takes the lid off entirely.
uniform vec2 lid_height = vec2(-0.04, -0.04);
uniform vec2 lid_slope = vec2(0.55, 0.55);
uniform vec2 shine_offset = vec2(0.03, -0.03);
uniform float shine_radius = 0.035;
uniform float stroke = 0.035;

// 0: none. 1: "o". 2: smile. 3: open grin. 4: smirk.
uniform int mouth_mode = 0;
uniform vec2 mouth_center = vec2(0.0, 0.22);
uniform vec2 mouth_size = vec2(0.11, 0.08);

// The face styles' extras, matching BlobFace's in the game. All off by
// default, so a face that does not ask for them is unchanged.
// Glasses: a ring of `lens_radius` round each eye, joined by a bridge, with a
// glare streak faded in by `glint`.
uniform float lens_radius = 0.0;
uniform float lens_width = 0.03;
uniform float glint = 0.0;
// Three lashes flicking outward off each eye's outer half, sitting on the lid.
uniform float lash = 0.0;
// Pink cheeks under each eye, 0..1 opacity.
uniform float blush = 0.0;
// A bar over each eye; `brow_tilt` drops the inner ends (angry) or lifts them.
uniform float brow = 0.0;
uniform float brow_tilt = 0.0;

float fill(float d) {
	float w = max(fwidth(d), 0.0005);
	return 1.0 - smoothstep(-w, w, d);
}

// Signed distance-ish to an axis-aligned ellipse, good enough near its edge.
float ellipse(vec2 p, vec2 c, vec2 r) {
	return (length((p - c) / r) - 1.0) * min(r.x, r.y);
}

// Half of an elliptical ring: the upper half if `up` > 0, else the lower.
float arc(vec2 p, vec2 c, vec2 r, float up) {
	float ring = abs(ellipse(p, c, r)) - stroke * 0.5;
	return max(ring, up * (p.y - c.y));
}

// Distance to the segment a-b.
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

void fragment() {
	vec2 p = UV - 0.5;
	int side = p.x < 0.0 ? 0 : 1;
	vec2 m = vec2(abs(p.x), p.y);

	float eye;
	float shine = 0.0;
	if (eye_mode == 1) {
		eye = fill(arc(m, eye_center + vec2(0.0, eye_size.y * 0.35), eye_size * vec2(1.0, 0.7), 1.0));
	} else {
		float lid = lid_height[side] - lid_slope[side] * (m.x - eye_center.x);
		eye = fill(max(ellipse(m, eye_center, eye_size), lid - m.y));
		shine = fill(length(m - eye_center - shine_offset) - shine_radius) * eye;
	}

	float mouth = 0.0;
	if (mouth_mode == 1) {
		mouth = fill(ellipse(p, mouth_center, mouth_size));
	} else if (mouth_mode == 2) {
		mouth = fill(arc(p, mouth_center, mouth_size, -1.0));
	} else if (mouth_mode == 3) {
		mouth = fill(max(ellipse(p, mouth_center, mouth_size), mouth_center.y - p.y));
	} else if (mouth_mode == 4) {
		// A smile tipped up at one corner and pushed off-centre.
		vec2 q = p - mouth_center;
		float a = -0.45;
		q = vec2(cos(a) * q.x - sin(a) * q.y, sin(a) * q.x + cos(a) * q.y);
		mouth = fill(arc(q, vec2(0.0), mouth_size * vec2(0.8, 0.7), -1.0));
	}

	float extras = 0.0;
	float glare = 0.0;
	if (lens_radius > 0.0) {
		float ring = abs(length(m - eye_center) - lens_radius) - lens_width * 0.5;
		float bridge = max(abs(m.y - eye_center.y + 0.02) - lens_width * 0.5,
			m.x - (eye_center.x - lens_radius) - 0.01);
		extras = max(extras, fill(min(ring, bridge)));
		vec2 c = eye_center;
		glare = fill(segment(m, c + vec2(-0.6, 0.35) * lens_radius,
			c + vec2(0.25, -0.6) * lens_radius) - lens_width * 0.6) * glint;
	}
	if (lash > 0.0) {
		for (int k = 0; k < 3; k++) {
			float u = 0.35 + 0.28 * float(k);
			float x = eye_center.x + u * eye_size.x;
			float top = max(eye_center.y - sqrt(1.0 - u * u) * eye_size.y,
				lid_height[side] - lid_slope[side] * u * eye_size.x);
			vec2 dir = normalize(vec2(0.4 + 0.6 * u, -1.0));
			vec2 a = vec2(x, top);
			extras = max(extras, fill(segment(m, a, a + dir * 0.06 * lash) - stroke * 0.4));
		}
	}
	if (brow > 0.0) {
		float y = eye_center.y - eye_size.y - 0.06;
		vec2 inner = vec2(eye_center.x - eye_size.x, y + brow_tilt * 0.06);
		vec2 outer = vec2(eye_center.x + eye_size.x * 1.2, y - brow_tilt * 0.03);
		extras = max(extras, fill(segment(m, inner, outer) - stroke * 0.7 * brow));
	}
	float cheek = 0.0;
	if (blush > 0.0) {
		vec2 at = vec2(eye_center.x + 0.06, eye_center.y + eye_size.y + 0.07);
		cheek = fill(length(m - at) - 0.07) * blush * 0.6;
	}

	float ink = max(max(eye, mouth), extras);
	float cover = max(max(ink, cheek), glare);
	if (cover < 0.01) {
		discard;
	}
	vec3 col = blush_color;
	col = mix(col, ink_color, ink);
	col = mix(col, shine_color * 1.4, max(shine, glare));
	ALBEDO = col;
	ALPHA = cover;
}
