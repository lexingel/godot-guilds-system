shader_type canvas_item;
// Screen transition over the whole window. progress 0 = covered, 1 = clear.
// A plain fade from dark, or (iris) a circle opening from the centre with a
// violet rim, for stepping into a rift.
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform bool iris = false;
uniform float aspect = 1.6;
uniform vec4 base_color : source_color = vec4(0.047, 0.039, 0.078, 1.0);
uniform vec4 rim_color : source_color = vec4(0.62, 0.36, 1.0, 1.0);

void fragment() {
	if (!iris) {
		COLOR = vec4(base_color.rgb, 1.0 - progress);
	} else {
		vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
		float d = length(p);
		float r = progress * (length(vec2(aspect, 1.0)) * 0.5 + 0.1);
		float cover = smoothstep(r - 0.012, r + 0.012, d);
		float rim = exp(-pow((d - r) * 26.0, 2.0)) * (1.0 - progress * progress);
		COLOR = vec4(mix(base_color.rgb, rim_color.rgb, rim), max(cover, rim));
	}
}
