shader_type spatial;

#include "res://assets/troop_dye.gdshaderinc"

uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D dye_texture : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec4 team_color : source_color;
uniform float surface_roughness = .9;
uniform float surface_metallic = .0;
uniform float normal_strength = 1.0;
uniform bool use_roughness_texture = false;
uniform bool use_metallic_texture = false;
uniform bool use_normal_texture = false;
uniform int fabric = 0;

float dye_mask(vec3 base, vec2 uv) {
	float red = max(base.r, .001);
	float green = max(base.g, .001);
	float blue_fabric = smoothstep(.025, .12, (base.b - base.r) / max(base.b, .001));
	switch (fabric) {
		case 0: // Mounted warriors share the infantry shirt atlas.
			return texture(dye_texture, uv).r * (1.0 - smoothstep(.14, .25, (base.g - base.b) / red));
		case 1: // Olive tunics on archers, including their baked distance atlases.
			return smoothstep(.71, .95, base.g / red)
				* smoothstep(.105, .31, (base.g - base.b) / green)
				* smoothstep(.008, .026, green);
		case 2: return blue_fabric;
		case 3: // Ochre cloth on the mounted archer.
			return smoothstep(.34, .56, base.g / red)
				* smoothstep(.35, .57, (base.g - base.b) / green)
				* smoothstep(.045, .15, base.r);
		case 4: return max(warrior_fabric(base), blue_fabric);
		case 5: return texture(dye_texture, uv).r; // Front boards of the standard round shield.
		default: return warm_wood(base); // Painted boards on Varangian shields.
	}
}

void fragment() {
	vec3 base = texture(base_texture, UV).rgb;
	float mask = dye_mask(base, UV);
	ALBEDO = troop_dye(base, team_color.rgb, mask, -VERTEX.z);
	// glTF packs roughness into G and metallic into B.
	ROUGHNESS = use_roughness_texture ? surface_roughness * texture(roughness_texture, UV).g : surface_roughness;
	METALLIC = use_metallic_texture ? surface_metallic * texture(metallic_texture, UV).b : surface_metallic;
	if (fabric == 5) {
		ROUGHNESS = mix(surface_roughness, .88, mask);
		METALLIC = mix(surface_metallic, .02, mask);
	}
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
