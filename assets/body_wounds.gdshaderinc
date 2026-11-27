uniform sampler2D body_wound_data : filter_nearest, repeat_disable;
uniform int body_wound_surface = 1;

vec4 body_wound_color(int row, vec2 uv) {
	vec4 result = vec4(0.0);
	if (row == 0) {
		return result;
	}
	for (int i = 0; i < 3; i++) {
		vec4 stamp = texelFetch(body_wound_data, ivec2(i * 2, row), 0);
		if (int(stamp.z) != body_wound_surface) {
			continue;
		}
		vec4 axes = texelFetch(body_wound_data, ivec2(i * 2 + 1, row), 0);
		vec2 offset = uv - stamp.xy;
		vec2 p = inverse(mat2(axes.xy, axes.zw)) * offset;
		if (max(abs(p.x), abs(p.y)) > 1.0) {
			continue;
		}
		float angle = atan(p.y, p.x + 0.000001);
		float edge = 0.66 + 0.11 * sin(angle * 5.0) + 0.06 * cos(angle * 13.0);
		float grain = fract(sin(dot(floor(p * 29.0), vec2(12.9898, 78.233))) * 43758.5453);
		float coverage = smoothstep(0.0, 0.29, edge - length(p) + 0.10 * grain);
		float cut = (1.0 - smoothstep(0.025, 0.16, abs(p.y + p.x * 0.45)))
			* (1.0 - smoothstep(0.20, 0.46, abs(p.x)));
		vec3 blood = mix(vec3(0.25 + grain * 0.09, 0.012, 0.008), vec3(0.042, 0.002, 0.001), cut);
		float opacity = max(coverage * (0.76 + 0.22 * grain), cut * 0.96);
		result.rgb = mix(result.rgb * result.a, blood, opacity);
		result.a = opacity + result.a * (1.0 - opacity);
		result.rgb /= max(result.a, 0.001);
	}
	return result;
}
