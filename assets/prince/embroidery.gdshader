shader_type spatial;
uniform sampler2D crest_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool has_crest = false;
uniform vec4 cloth_color : source_color = vec4(.24, .29, .35, 1.0);
void fragment() {
    vec2 crest_uv = (UV - .5) / .88 + .5;
    vec4 crest = texture(crest_texture, clamp(crest_uv, vec2(0.0), vec2(1.0)));
    float inside = step(0.0, crest_uv.x) * step(0.0, crest_uv.y) * step(crest_uv.x, 1.0) * step(crest_uv.y, 1.0);
    float coverage = has_crest ? crest.a * inside : 0.0;
    float filter_width = max(fwidth(UV.x), fwidth(UV.y));
    float thread = sin((UV.x + UV.y * .25) * 1050.0) * clamp(.003 / max(filter_width, .0001), 0.0, 1.0);
    float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
    float seam = (1.0 - smoothstep(.007, .014, abs(edge - .035))) * step(.35, fract((UV.x + UV.y) * 44.0));
    vec3 fabric = mix(cloth_color.rgb, crest.rgb, coverage) * (1.0 + thread * .085);
    ALBEDO = mix(fabric, vec3(.58, .42, .21), seam * .85);
    ROUGHNESS = .91 - coverage * .08;
    SPECULAR = .23;
}
