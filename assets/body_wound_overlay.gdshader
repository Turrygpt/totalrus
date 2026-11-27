shader_type spatial;
render_mode depth_draw_never;

#include "res://assets/body_wounds.gdshaderinc"
#include "res://assets/crowd_lod_mask.gdshaderinc"

instance uniform int body_wound_row = 0;
instance uniform float lod_detail : instance_index(15) = 1.0;

void fragment() {
	vec4 blood = body_wound_color(body_wound_row, UV);
	if (blood.a < 0.015 || lod_threshold(FRAGCOORD.xy) >= lod_detail) {
		discard;
	}
	ALBEDO = blood.rgb;
	ALPHA = blood.a;
	ROUGHNESS = 0.85;
}
