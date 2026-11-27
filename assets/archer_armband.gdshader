shader_type spatial;

uniform vec4 base_tint : source_color;

void fragment() {
	ALBEDO = mix(base_tint.rgb, vec3(1.0), .16);
	ROUGHNESS = .96;
	EMISSION = base_tint.rgb * .10;
}
