shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled;

varying vec3 sphere_position;
varying flat vec3 camera_position_local;

void vertex() {
	sphere_position = VERTEX;
	camera_position_local = inverse(MODELVIEW_MATRIX)[3].xyz;
}

void fragment() {
	vec3 ray = normalize(sphere_position - camera_position_local);
	vec3 center_sample = sphere_position - ray * dot(sphere_position, ray);
	float density = max(0.0, 1.0 - dot(center_sample, center_sample));
	float height_fade = 1.0 - smoothstep(-0.25, 0.8, center_sample.y);
	float drift = 0.9 + 0.1 * sin(dot(center_sample, vec3(4.0, 3.0, 2.0)) + TIME * 0.65);
	ALBEDO = vec3(0.90, 0.78, 0.53);
	ALPHA = density * density * mix(0.045, 0.10, height_fade) * drift;
}
