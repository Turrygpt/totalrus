shader_type spatial;
uniform float snow : hint_range(0.,1.) = 0.;
render_mode cull_back;
#include "res://campaign_map/territory_overlay.gdshaderinc"

uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_paint : filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 ground;
varying float steepness;

void vertex() {
	ground = VERTEX;
	steepness = 1.0 - NORMAL.y;
	TANGENT = normalize(vec3(1.,0.,0.) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

void fragment() {
	vec2 uv = ground.xz * .23;
	vec3 grass_detail = texture(grass, uv).rgb;
	vec3 mottling = texture(grass, ground.xz * .009 + vec2(.31,.67)).rgb;
	vec3 stone = texture(rock, ground.xz * .16).rgb;
	float slope = smoothstep(.08,.36,steepness);
	float bank = 1.0-smoothstep(2.8,5.7,ground.y);
	float grain = dot(grass_detail,vec3(.25,.58,.17));
	float patches = dot(mottling,vec3(.25,.58,.17));
	vec3 pasture = pow(COLOR.rgb,vec3(2.2)) * (.45+grain*1.35) * (.65+patches*.85);
	pasture = mix(pasture,vec3(.36,.30,.19)*(.7+grain*.8),bank*.6);
	ALBEDO = mix(pasture,stone*vec3(.77,.76,.65),slope*.85);
	ALBEDO = mix(ALBEDO,vec3(.25,.19,.12)*(.65+grain*.65),COLOR.a*.8);
	NORMAL_MAP = mix(texture(grass_normal,uv).rgb,texture(rock_normal,ground.xz*.16).rgb,slope);
	NORMAL_MAP_DEPTH = .55;
	ROUGHNESS = clamp(mix(texture(grass_roughness,uv).r,texture(rock_roughness,ground.xz*.16).r,slope),.65,1.);
	float road = texture(road_paint,ground.xz/(map_half*2.)+.5).r;
	float grit = dot(stone,vec3(.28,.56,.16));
	vec3 dirt = vec3(.28,.197,.105)*(.70+grit*1.15);
	ALBEDO = mix(ALBEDO,dirt,road);
	NORMAL_MAP_DEPTH *= 1.-road*.65;
	ROUGHNESS = mix(ROUGHNESS,.96,road);
	float cover = snow * (.78+.22*smoothstep(.04,.16,patches)) * (1.-slope*.5);
	cover *= 1.-road*.42;
	ALBEDO = mix(ALBEDO,vec3(.62,.70,.76)*(.85+grain*.3),cover);
	vec4 ink = territory_ink(ground.xz,0.);
	ALBEDO = mix(ALBEDO,ink.rgb,ink.a);
	NORMAL_MAP_DEPTH *= 1.-cover*.65;
	SPECULAR = .18;
}
