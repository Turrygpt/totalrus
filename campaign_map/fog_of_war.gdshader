shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler2D sight : filter_linear, repeat_disable;
uniform vec2 map_half;
uniform sampler2D depth_map : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
void vertex() { POSITION = vec4(VERTEX.xy, 1., 1.); }
void fragment() {
	float depth = texture(depth_map,SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV*2.-1.,depth,1.);
	vec3 position = (INV_VIEW_MATRIX * vec4(view.xyz/view.w,1.)).xyz;
	vec2 world = position.xz;
	vec2 info = texture(sight,world/(2.*map_half)+.5).rg;
	float clouds = texture(cloud_noise,world*.003+vec2(TIME*.001,TIME*.0004)).r;
	ALBEDO = mix(vec3(.035,.048,.066),vec3(.15,.18,.22),clouds);
	ALPHA = (1.-smoothstep(.16,.92,info.r)) * mix(.86,.44,info.g) * (.84+clouds*.16) * step(.00001,depth);
}
