shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D heraldry : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 cloth_tint : source_color = vec4(.52,.24,.20,1.0);
uniform int experience_rank = 0;
uniform int morale_signal = 0;

void vertex() {
	float loose = smoothstep(0.04, 0.9, UV.y);
	VERTEX.z += loose * (0.07 * sin(TIME * 3.1 + UV.y * 9.0 + MODEL_MATRIX[3].x)
		+ 0.023 * sin(TIME * 5.0 + UV.x * 8.0));
}

void fragment() {
	vec4 cloth = texture(heraldry, UV);
	// Gray folds carry the hero's dye. The colored thread keeps the unit emblem.
	float saturation = max(cloth.r, max(cloth.g, cloth.b)) - min(cloth.r, min(cloth.g, cloth.b));
	float thread = smoothstep(0.025, 0.11, saturation);
	vec3 color = mix(cloth_tint.rgb * (0.84 + 2.3 * cloth.r), cloth.rgb, thread);
	int stripes = experience_rank > 0 ? (experience_rank - 1) % 3 + 1 : 0;
	vec3 metal = experience_rank <= 3 ? vec3(0.72, 0.43, 0.24) : (experience_rank <= 6 ? vec3(0.77, 0.83, 0.85) : vec3(0.94, 0.71, 0.29));
	for (int i = 0; i < stripes; i++) {
		vec2 mark = abs(UV - vec2(0.41 + 0.09 * float(i), 0.107));
		float embroidery = 1.0 - smoothstep(0.019, 0.026, mark.x + mark.y * 1.4);
		color = mix(color, metal, embroidery);
	}
	if (morale_signal > 0) {
		float phase = TIME * (morale_signal == 1 ? 8.8 : 15.0);
		float pulse = 0.5 + 0.5 * sin(phase);
		float white = morale_signal == 1 ? pulse * 0.42 : (0.15 + 0.85 * pulse);
		if (morale_signal == 3) {
			white = 1.0;
		}
		color = mix(color, vec3(0.95, 0.96, 0.94), white);
	}
	ALBEDO = color;
	EMISSION = color * 0.12;
	ROUGHNESS = 0.94;
	ALPHA = cloth.a;
	ALPHA_SCISSOR_THRESHOLD = 0.36;
}
