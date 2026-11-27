shader_type spatial;
render_mode cull_disabled;
#include "res://assets/troop_dye.gdshaderinc"
uniform vec4 wool_color : source_color = vec4(0.25, 0.34, 0.44, 1.0);
void fragment() {
    float filtering = clamp(0.001 / max(fwidth(UV.x), 0.0001), 0.0, 1.0);
    float weave = sin(UV.x * 1800.0) * sin(UV.y * 2200.0) * filtering;
    float edge = min(min(UV.x, 1.0 - UV.x), 1.0 - UV.y);
    float border = 1.0 - smoothstep(0.012, 0.019, edge);
    float stitch = (1.0 - smoothstep(0.003, 0.006, abs(edge - 0.029)))
        * step(0.45, fract((UV.x + UV.y) * 100.0));
    vec3 wool = mix(vec3(.15, .13, .11), wool_color.rgb, troop_dye_strength(-VERTEX.z));
    ALBEDO = mix(wool * (1.0 + weave * 0.055), vec3(.42, .29, .14), border * .75 + stitch * .6);
    ROUGHNESS = .94;
    SPECULAR = .2;
    if (!FRONT_FACING) NORMAL = -NORMAL;
}
