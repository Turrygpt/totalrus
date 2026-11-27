shader_type spatial;
render_mode cull_disabled;
uniform vec4 wool_color : source_color = vec4(.075,.14,.22,1.0);
uniform float battle_time = 0.0;
instance uniform float travel = 0.0;
instance uniform float sway = 0.0;
instance uniform float phase = 0.0;
instance uniform float fallen = 0.0;
varying vec3 cloth_world;
void vertex() {
 float t=1.0-UV.y;
 vec3 anchor=MODEL_MATRIX[3].xyz;
 vec3 side=normalize(MODEL_MATRIX[0].xyz);
 vec3 rear=MODEL_MATRIX[2].xyz; rear.y=0.0; rear=normalize(rear+vec3(.00001,0.0,0.0));
 float slow=sin(battle_time*2.2+phase-t*3.4);
 float gust=sin(battle_time*1.15+phase*.7)*.5+.5;
 float flex=t*t*(.045*slow+.065*gust+travel*.065);
 float side_flex=sway*t*t*.22+sin(battle_time*1.7+phase-t*2.8)*.025*t;
 vec3 hanging=anchor+side*(VERTEX.x+side_flex)+vec3(0.0,VERTEX.y,0.0)+rear*(VERTEX.z+flex);
 // The collar follows the shoulders; gravity keeps the heavy lower cloth hanging.
 vec3 skinned=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 vec3 world=mix(skinned,hanging,smoothstep(.04,.55,t)*(1.0-fallen));
 if (fallen>.5) world.y=mix(skinned.y,max(.045,min(skinned.y,.12)),smoothstep(.1,.65,t));
 world.y+=travel*.011*sin(battle_time*5.2+phase-t*3.0)*t*t*(1.0-fallen);
 VERTEX=(inverse(MODEL_MATRIX)*vec4(world,1.0)).xyz;
 cloth_world=world;
}
void fragment() {
 float t=1.0-UV.y;
 float weave=sin(UV.x*1250.0)*sin(UV.y*1400.0)*clamp(.001/max(fwidth(UV.x),.0001),0.0,1.0);
 float mottling=sin(UV.x*39.0+sin(UV.y*23.0))*.025;
 float hem=step(.974,t)+step(UV.x,.018)+step(.982,UV.x);
 float embroidery=1.0-step(.29,abs(fract(UV.x*22.0)-.5)+abs((t-.947)*32.0));
 vec3 base=wool_color.rgb*(1.0+weave*.045+mottling);
 ALBEDO=mix(base,vec3(.48,.34,.14),clamp(hem+embroidery*.7,0.0,1.0));
 ROUGHNESS=.94; SPECULAR=.22;
 if (!FRONT_FACING) NORMAL=-NORMAL;
}
