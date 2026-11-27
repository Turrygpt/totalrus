shader_type spatial;

#include "res://assets/crowd_lod_mask.gdshaderinc"

instance uniform float lod_detail : instance_index(15) = 1.0;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float normal_scale = 1.0;
uniform bool has_normal = false;
uniform bool cutout = false;
uniform float cutout_threshold = 0.5;

void fragment() {
	if (lod_threshold(FRAGCOORD.xy) >= lod_detail) { discard; }
	vec4 base = texture(base_texture, UV) * base_tint;
	if (cutout && base.a < cutout_threshold) { discard; }
	ALBEDO = base.rgb;
	ROUGHNESS = roughness * dot(texture(roughness_texture, UV), roughness_channel);
	METALLIC = metallic * dot(texture(metallic_texture, UV), metallic_channel);
	SPECULAR = specular;
	if (has_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
