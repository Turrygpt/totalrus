shader_type spatial;
uniform float snow : hint_range(0.,1.) = 0.;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D branches : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = smoothstep(0.7, 5.5, VERTEX.y);
	VERTEX.x += sin(TIME * 1.15 + world.x * .24 + world.z * .17) * .065 * bend;
	VERTEX.z += sin(TIME * .83 + world.z * .29) * .038 * bend;
}
void fragment() {
	vec4 leaf = texture(branches, UV);
	ALBEDO = leaf.rgb * COLOR.rgb * vec3(.71,.76,.69);
	ALBEDO = mix(ALBEDO,vec3(.53,.62,.66),snow*.84*smoothstep(.02,.24,leaf.g));
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = .38+snow*.18*step(UV.y,.5);
	ROUGHNESS = .92;
	SPECULAR = .12;
	BACKLIGHT = ALBEDO * .20;
}
