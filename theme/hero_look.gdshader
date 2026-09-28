shader_type canvas_item;
// A hero's colour variant (see GameState.refresh_looks): turns the hue of
// their clothing and gear, the saturated colours, while skin, metal, hair
// greys and outlines stay as drawn.
uniform float hue_shift = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 hsv = rgb2hsv(COLOR.rgb);
	bool skin = hsv.x > 0.02 && hsv.x < 0.11 && hsv.y < 0.6 && hsv.z > 0.45;
	if (hsv.y > 0.22 && !skin) {
		hsv.x = fract(hsv.x + hue_shift);
		hsv.y *= 0.9;
		COLOR.rgb = hsv2rgb(hsv);
	}
}
