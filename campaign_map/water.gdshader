shader_type spatial;
uniform float snow : hint_range(0.,1.) = 0.;
render_mode cull_disabled, depth_draw_never;
#include "res://campaign_map/territory_overlay.gdshaderinc"

uniform vec4 deep : source_color = vec4(0.075, 0.185, 0.235, 1.0);
uniform vec4 shallows : source_color = vec4(0.27, 0.38, 0.34, 1.0);
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float water_noise(vec2 p) {
	vec2 grid = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec4 corners = vec4(
		dot(grid, vec2(127.1, 311.7)),
		dot(grid + vec2(1.0, 0.0), vec2(127.1, 311.7)),
		dot(grid + vec2(0.0, 1.0), vec2(127.1, 311.7)),
		dot(grid + vec2(1.0), vec2(127.1, 311.7))
	);
	vec4 values = fract(sin(corners) * 43758.5453);
	return mix(mix(values.x, values.y, f.x), mix(values.z, values.w, f.x), f.y);
}

void fragment() {
	float z = texture(scene_depth, SCREEN_UV).x;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	float depth = max(VERTEX.z - behind.z / behind.w, 0.0);
	vec2 p = world_pos.xz;
	float wide = water_noise(p * .23 + TIME * vec2(.07, .04)) - .5;
	float fine = water_noise(p * .62 + TIME * vec2(-.11, .06)) - .5;
	float edge = 1.0 - smoothstep(0.0, 4.5, depth);
	ALBEDO = mix(deep.rgb, shallows.rgb, edge * .65) * (1.0 + wide * .045 + fine * .025);
	NORMAL = normalize((VIEW_MATRIX * vec4(wide * .06, 1.0, fine * .05, 0.0)).xyz);
	ROUGHNESS = .48 + .13 * edge;
	SPECULAR = .38;
	ALBEDO = mix(ALBEDO,vec3(.38,.49,.55),snow*edge*.85);
	ROUGHNESS = mix(ROUGHNESS,.55,snow*edge);
	vec4 ink = territory_ink(world_pos.xz,1.);
	ALBEDO = mix(ALBEDO,ink.rgb,ink.a);
	ALPHA = 1.0;
}
