shader_type spatial;
render_mode cull_disabled;
uniform sampler2D fabric : source_color, filter_linear_mipmap_anisotropic;
void vertex() {
	float loose = 1.-smoothstep(-2.65,2.65,VERTEX.x);
	VERTEX.z += sin(TIME*2.1+VERTEX.x*1.4+VERTEX.y*.35)*.3*loose;
}
void fragment() {
	vec4 cloth = texture(fabric,UV);
	ALBEDO = cloth.rgb;
	ROUGHNESS = .95;
	ALPHA = cloth.a;
	ALPHA_SCISSOR_THRESHOLD = .4;
	BACKLIGHT = ALBEDO*.12;
}
