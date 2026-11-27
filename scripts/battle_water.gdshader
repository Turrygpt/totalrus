shader_type spatial;
render_mode cull_disabled;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float fine = 1.0 - smoothstep(40.0, 220.0, distance(CAMERA_POSITION_WORLD, world));
	float current = sin(dot(p, vec2(.10, .17)) - TIME * .55 + sin(dot(p, vec2(.047, -.055))) * 1.8);
	float ripple = sin(dot(p, vec2(.86, 1.31)) - TIME * 1.15 + current * 1.3);
	float cross_ripple = sin(dot(p, vec2(-1.39, .64)) + TIME * .74 + ripple * .43);
	float variation = .52 + current * .16 + (ripple + cross_ripple) * fine * .058;
	ALBEDO = mix(vec3(.058, .123, .135), vec3(.14, .23, .24), variation);
	ROUGHNESS = mix(.41, .26, fine);
	SPECULAR = .46;
	NORMAL_MAP = normalize(vec3(.012 * current + .023 * ripple * fine, .021 * cross_ripple * fine, 1.0)) * .5 + .5;
}
