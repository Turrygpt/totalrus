shader_type spatial;

uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
#include "res://assets/troop_dye.gdshaderinc"

uniform vec4 team_color : source_color;

void fragment() {
	vec3 base = texture(base_texture, UV).rgb;
	// The shared backs and edges show more grain than the painted faces.
	ivec2 tile = ivec2(floor(UV * vec2(4.0, 3.0)));
	float coverage = tile.y < 2 || tile.x == 0 ? 1.0 : .72;
	float paint = warm_wood(base) * coverage;
	ALBEDO = troop_dye(base, team_color.rgb, paint, -VERTEX.z);
	METALLIC = 0.05;
	ROUGHNESS = 0.83;
}
