uniform sampler2D territory_distance : filter_linear, repeat_disable;
uniform sampler2D territory_ids : filter_nearest, repeat_disable;
uniform sampler2D territory_palette : source_color, filter_nearest, repeat_disable;
uniform vec2 map_half = vec2(770.,642.);
uniform int selected_territory = -1;
uniform int selected_province = -1;

float bilinear(vec4 values,vec2 weight) {
	return mix(mix(values.x,values.y,weight.x),mix(values.z,values.w,weight.x),weight.y);
}

vec4 territory_ink(vec2 point, float water) {
	if (selected_territory < 0) return vec4(0.);
	vec2 uv = point/(map_half*2.)+.5;
	float distance = texture(territory_distance,uv).r*8.;
	if (distance>7.98) return vec4(0.);
	ivec2 dimensions = textureSize(territory_ids,0);
	vec2 texel = uv*vec2(dimensions)-.5;
	ivec2 base = ivec2(floor(texel));
	vec2 weight = fract(texel);
	vec4 a = texelFetch(territory_ids,clamp(base,ivec2(0),dimensions-1),0);
	vec4 b = texelFetch(territory_ids,clamp(base+ivec2(1,0),ivec2(0),dimensions-1),0);
	vec4 c = texelFetch(territory_ids,clamp(base+ivec2(0,1),ivec2(0),dimensions-1),0);
	vec4 d = texelFetch(territory_ids,clamp(base+ivec2(1,1),ivec2(0),dimensions-1),0);
	ivec4 ids = ivec4(round(vec4(a.g,b.g,c.g,d.g)*255.));
	int id = int(round(texture(territory_ids,uv).g*255.));
	vec4 distances = vec4(a.r,b.r,c.r,d.r)*8.;
	// Reconstruct SIGNED distances before interpolation. Interpolating labels or
	// an unsigned distance field makes diagonal frontiers inherit the texel grid.
	vec4 inside = vec4(equal(ids,ivec4(id)))*2.-1.;
	distance = abs(bilinear(distances*inside,weight));
	float aa = max(length(fwidth(point))*.6,.2);
	vec4 selected_sides = vec4(equal(ids,ivec4(selected_territory)))*2.-1.;
	float selected = smoothstep(-aa,aa,bilinear(distances*selected_sides,weight));
	float related = bilinear(vec4(equal(ivec4(round(vec4(a.b,b.b,c.b,d.b)*255.)),ivec4(selected_province))),weight);
	float edge = 1.-smoothstep(.24-aa,.60+aa,distance);
	float band = 1.-smoothstep(.45,mix(1.3,3.6,selected),distance);
	vec3 pigment = texture(territory_palette,vec2((float(id)+.5)/32.,.5)).rgb;
	pigment = mix(pigment,vec3(.8,.48,.06),selected*.9);
	pigment = mix(pigment,vec3(.9,.79,.47),edge*.9);
	float alpha = edge*(.24+related*.06+selected*.18)+band*(.08+selected*.18);
	alpha *= mix(1.,smoothstep(.25,.45,abs(sin((point.x+point.y)*.22))),water);
	return vec4(pigment,clamp(alpha,0.,.75));
}
