shader_type spatial;
uniform vec4 tint : source_color = vec4(.3,.22,.15,1.);
uniform bool roof = false;
uniform float snow : hint_range(0.,1.) = 0.;
varying vec3 position_world;
varying vec3 normal_world;
void vertex() {
	position_world = (MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
	normal_world = normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	vec3 p = position_world;
	float horizontal = p.x*.73+p.z*.41;
	float grain = sin(horizontal*37.+sin(p.y*18.)*1.7)*.04+sin(horizontal*13.+p.y*7.)*.07;
	float seam = smoothstep(.02,.10,abs(fract(p.y*3.5)-.5));
	float boards = floor(p.y*3.5);
	float weather = .88+.12*sin(boards*43.+floor(horizontal*.6)*17.);
	if (roof) {
		seam = smoothstep(.015,.10,abs(fract((p.x+p.z)*2.8)-.5));
		weather = .88+.12*sin(floor((p.x+p.z)*2.8)*43.);
	}
	ALBEDO = tint.rgb*(.62+.38*seam)*(weather+grain);
	float cover = snow*smoothstep(.3,.88,normal_world.y);
	ALBEDO = mix(ALBEDO,vec3(.64,.72,.77),cover*.9);
	ROUGHNESS = .92;
	SPECULAR = .14;
}
