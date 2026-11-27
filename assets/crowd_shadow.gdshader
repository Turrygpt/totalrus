shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://assets/crowd_lod_mask.gdshaderinc"
varying flat float lod_detail;
uniform sampler2D pose_bones:filter_nearest,repeat_disable;
#include "res://assets/crowd_foot_placement.gdshaderinc"
uniform mat4 cape_to_bone;
uniform int corpse_hips=-1;
uniform int corpse_neck=-1;
global uniform float crowd_time;
mat4 bone_pose(int bone,int frame){
 return mat4(texelFetch(pose_bones,ivec2(bone*4,frame),0),texelFetch(pose_bones,ivec2(bone*4+1,frame),0),texelFetch(pose_bones,ivec2(bone*4+2,frame),0),texelFetch(pose_bones,ivec2(bone*4+3,frame),0));
}
void vertex(){
 lod_detail=fract(COLOR.r);
 float flags=mod(floor(COLOR.r),1024.0);
 float corpse_pose=floor(COLOR.r/1024.0);
 float duration=max(.001,abs(INSTANCE_CUSTOM.y));
 float t=max(0.0,(crowd_time-INSTANCE_CUSTOM.z)*INSTANCE_CUSTOM.w);
 float phase=INSTANCE_CUSTOM.y>0.0 ? mod(t,duration)/duration*8.0 : min(t/duration,1.0)*7.0;
 int frame=int(floor(phase));
 int next_frame=INSTANCE_CUSTOM.y>0.0 ? (frame+1)%8 : min(frame+1,7);
 int start=int(INSTANCE_CUSTOM.x);
 int bone=int(UV2.x);
 mat4 a=bone_pose(bone,start+frame); mat4 b=bone_pose(bone,start+next_frame);
 mat4 final_bone=mat4(mix(a[0],b[0],fract(phase)),mix(a[1],b[1],fract(phase)),mix(a[2],b[2],fract(phase)),mix(a[3],b[3],fract(phase)));
 vec3 local=VERTEX;
 VERTEX=mix((a*vec4(VERTEX,1.0)).xyz,(b*vec4(VERTEX,1.0)).xyz,fract(phase));
 float blend=COLOR.b<0.0 ? 1.0 : smoothstep(0.0,.18,crowd_time-COLOR.g);
 if(blend<1.0){
  mat4 old_a=bone_pose(bone,int(floor(COLOR.b)));mat4 old_b=bone_pose(bone,int(COLOR.a));
  VERTEX=mix(mix((old_a*vec4(local,1)).xyz,(old_b*vec4(local,1)).xyz,fract(COLOR.b)),VERTEX,blend);
  final_bone=mat4(mix(mix(old_a[0],old_b[0],fract(COLOR.b)),final_bone[0],blend),mix(mix(old_a[1],old_b[1],fract(COLOR.b)),final_bone[1],blend),mix(mix(old_a[2],old_b[2],fract(COLOR.b)),final_bone[2],blend),mix(mix(old_a[3],old_b[3],fract(COLOR.b)),final_bone[3],blend));
 }
 if(UV2.y>4.5){
  vec3 cloth=(inverse(cape_to_bone)*vec4(local,1)).xyz;
  mat4 cape_pose=final_bone*cape_to_bone;
  float bottom=clamp(-cloth.y/1.18,0.0,1.0);
  float fallen=mod(floor(flags/2.0),2.0);
  vec3 rear=normalize(vec3(cape_pose[2].x,0,cape_pose[2].z)+vec3(.00001,0,0));
  vec3 hanging=cape_pose[3].xyz+normalize(cape_pose[0].xyz)*cloth.x+vec3(0,cloth.y,0)+rear*(cloth.z+bottom*bottom*(.06+min(floor(flags/16.0),48.0)/8.0*.065));
  VERTEX=mix(VERTEX,hanging,smoothstep(.04,.55,bottom)*(1.0-fallen));
  if(fallen>.5) VERTEX.y=mix(VERTEX.y,max(.045,min(VERTEX.y,.12)),smoothstep(.1,.65,bottom));
 }
 if(corpse_pose>1.0 && corpse_hips>=0 && corpse_neck>=0){
  vec3 pivot=bone_pose(corpse_hips,start+7)[3].xyz;
  vec3 other=bone_pose(corpse_neck,start+7)[3].xyz;
  vec3 axis=normalize(vec3(other.x-pivot.x,0.0,other.z-pivot.z));
  float weight=smoothstep(.52,1.0,phase/7.0);
  float angle=(corpse_pose<4.0 ? .98 : 2.52)*(mod(corpse_pose,2.0)<.5 ? 1.0 : -1.0)*weight;
  vec3 relative=VERTEX-pivot;
  VERTEX=pivot+relative*cos(angle)+cross(axis,relative)*sin(angle)+axis*dot(axis,relative)*(1.0-cos(angle));
  VERTEX.y+=weight*(corpse_pose<4.0 ? .08 : .14);
 }
 bool fallen=mod(floor(flags/2.0),2.0)>.5;
 if (!fallen && (bone == foot_left.x || bone == foot_left.y || bone == foot_right.x || bone == foot_right.y)) {
  VERTEX.y += foot_placement(VERTEX, MODEL_MATRIX, ivec2(start + frame, start + next_frame),
   fract(phase), ivec2(int(floor(COLOR.b)), int(COLOR.a)), fract(COLOR.b), blend);
 }
 bool disarmed=floor(flags/16.0)>62.5;
 if(disarmed && ((UV2.y>.5 && UV2.y<4.5) || UV2.y<-.5)) VERTEX=vec3(0,-50,0);
 if((UV2.y>.5 && UV2.y<1.5 && (fallen || mod(flags,2.0)<.5))||
    (UV2.y>1.5 && UV2.y<2.5 && (fallen || mod(floor(flags/4.0),2.0)<.5))||
    (UV2.y>2.5 && UV2.y<3.5 && fallen && mod(floor(flags/4.0),2.0)<.5)||
    (UV2.y>3.5 && UV2.y<4.5 && (fallen || mod(floor(flags/8.0),2.0)<.5))) VERTEX=vec3(0,-50,0);
}
void fragment(){
 if (lod_threshold(FRAGCOORD.xy) < lod_detail) { discard; }
 ALBEDO=vec3(0);
}
