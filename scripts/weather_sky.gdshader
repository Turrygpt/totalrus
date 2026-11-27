shader_type sky;
render_mode disable_fog;

uniform vec4 zenith : source_color;
uniform vec4 horizon : source_color;
uniform sampler2D cloud_map : filter_linear_mipmap, repeat_enable;
uniform float cloudiness = 0.3;
uniform float sunlight = 1.0;

void sky() {
	float height = EYEDIR.y;
	vec3 air = mix(horizon.rgb, zenith.rgb, smoothstep(0.0, 0.38, height));
	air = mix(air, horizon.rgb * 0.43, smoothstep(0.0, 0.65, -height));
	float sun_angle = -1.0;
	if (LIGHT0_ENABLED) {
		sun_angle = dot(EYEDIR, normalize(LIGHT0_DIRECTION));
	}
	float glow = pow(max(sun_angle, 0.0), 70.0);
	air += vec3(0.22, 0.13, 0.065) * glow * sunlight;
	float cloud_alpha = 0.0;
	if (!AT_CUBEMAP_PASS && height > -0.025) {
		vec2 plane = EYEDIR.xz / (max(height, 0.0) + 0.21);
		vec2 uv = plane * 0.16 + vec2(0.17, 0.38);
		float distance_fade = smoothstep(-0.025, 0.12, height);
		float threshold = mix(0.62, 0.28, cloudiness);
		float shape = texture(cloud_map, uv).r;
		float coverage = smoothstep(threshold, threshold + 0.13, shape);
		float shade = smoothstep(threshold - 0.04, threshold + 0.22, texture(cloud_map, uv + vec2(0.014, -0.009)).r);
		vec3 bright = mix(vec3(0.51, 0.58, 0.67), vec3(1.04, 0.99, 0.91), sunlight);
		vec3 dark = mix(vec3(0.23, 0.29, 0.36), vec3(0.48, 0.57, 0.68), sunlight);
		vec3 cloud = mix(bright, dark, shade * 0.78);
		cloud += vec3(0.21, 0.12, 0.035) * glow * sunlight * (1.0 - shade);
		cloud_alpha = coverage * distance_fade;
		air = mix(air, cloud, cloud_alpha);
	}
	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(0.99986, 0.99993, sun_angle) * sunlight;
		air += vec3(3.0, 2.15, 1.2) * disk * (1.0 - cloud_alpha * 0.85);
	}
	COLOR = air;
}
