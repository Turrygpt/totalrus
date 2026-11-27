shader_type spatial;
uniform float snow : hint_range(0.,1.) = 0.;
render_mode cull_disabled;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 crop : source_color = vec4(.48,.43,.23,1.);
varying vec3 position;
void vertex() { position = VERTEX; }
void fragment() {
	float furrow = .78+.22*smoothstep(-.7,.6,sin(UV.x*120.));
	vec3 detail = texture(soil,position.xz*.35).rgb;
	ALBEDO = crop.rgb*furrow*(.7+dot(detail,vec3(.3,.5,.2))*1.8);
	ALBEDO = mix(ALBEDO,vec3(.59,.67,.72)*furrow,snow*.95);
	ROUGHNESS = .97;
	float edge = min(min(UV.x,1.-UV.x),min(UV.y,1.-UV.y));
	ALPHA = smoothstep(0.,.07,edge)*.98;
}
