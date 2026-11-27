shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color;
uniform float opacity;
uniform bool snow;

void fragment() {
	float shape;
	if (snow) {
		shape = 1.0 - smoothstep(0.12, 0.5, length(UV - vec2(0.5)));
	} else {
		float edge = 1.0 - smoothstep(0.18, 0.5, abs(UV.x - 0.5));
		shape = edge * smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.35, 1.0, UV.y));
	}
	ALBEDO = tint.rgb;
	ALPHA = shape * opacity * smoothstep(0.8, 4.0, -VERTEX.z);
}
