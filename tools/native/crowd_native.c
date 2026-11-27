#include "gdextension_interface.h"
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <stdlib.h>
#define CAP 8192
#define STRIDE 12
typedef struct { float x, z; } FieldLimits;
static const FieldLimits DEFAULT_LIMITS = {59.4f, 44.4f};
static int *heads, grid_width, grid_height;
static size_t grid_capacity;
static int occupied_cells[CAP], next_agent[CAP];
static float substep_state[CAP*STRIDE];
typedef struct { float x, z; } Forward;
static Forward input_forward[CAP], output_forward[CAP];
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceGetProcAddress api;
static GDExtensionInterfaceStringNameNewWithUtf8Chars make_name;
static GDExtensionInterfaceClassdbConstructObject2 construct;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfacePackedFloat32ArrayOperatorIndex index_rw;
static GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst index_ro;
static GDExtensionTypeFromVariantConstructorFunc to_array,to_float,to_int;
static GDExtensionVariantFromTypeConstructorFunc from_array,from_int;
static GDExtensionPtrConstructor copy_array, new_array;
static GDExtensionPtrDestructor destroy_array,destroy_name;
static GDExtensionInterfaceVariantCall variant_call;
static GDExtensionInterfaceVariantDestroy destroy_variant;
static uint64_t class_name[8], parent_name[8], size_name[8], method_name[8], empty_name[8], empty_string[8];
static uint64_t render_name[8], grounded_render_name[8], compact_name[8], visible_count_name[8];
static uint64_t prepare_render_name[8], assemble_render_name[8];
static uint64_t bounded_name[8], terrain_name[8];
static uint64_t assignment_name[8];
static GDExtensionPtrDestructor destroy_string;
static float clampf(float x,float a,float b){return x<a?a:(x>b?b:x);}
static int configure_grid(FieldLimits limits){
 double width=2.0*ceil(limits.x/1.5)+3.0,height=2.0*ceil(limits.z/1.5)+3.0;
 if(width*height>INT_MAX)return 0;
 size_t needed=(size_t)width*(size_t)height;
 if(needed>grid_capacity){
  int *resized=realloc(heads,needed*sizeof(*heads));
  if(!resized)return 0;
  memset(resized+grid_capacity,-1,(needed-grid_capacity)*sizeof(*heads));
  heads=resized;
  grid_capacity=needed;
 }
 grid_width=(int)width;
 grid_height=(int)height;
 return 1;
}
static int cell(float x,float z){
 int a=(int)clampf(floorf(x/1.5f)+grid_width/2,0,grid_width-1);
 int b=(int)clampf(floorf(z/1.5f)+grid_height/2,0,grid_height-1);
 return b*grid_width+a;
}
// Flags: facing, spear, opposing team, mounted, melee order, flank, charge pass, braced.
static float body_support(int flags,Forward heading,float nx,float nz){
 if(!(flags&8))return .27f;
 float forward=nx*heading.x+nz*heading.z;
 return sqrtf(.65f*.65f*(1-forward*forward)+1.2f*1.2f*forward*forward);
}
static float infantry_gap(int a,int b){
 if((a&18)==18&&(b&18)==18)return ((a^b)&4)?1.42f:.95f;
 return .27f+.27f;
}
static float contact_gap(const float *p,const float *o,Forward ph,Forward oh,float nx,float nz){
 int a=(int)p[11],b=(int)o[11];
 if(!((a|b)&8))return infantry_gap(a,b);
 float gap=body_support(a,ph,nx,nz)+body_support(b,oh,nx,nz);
 if(((a^b)&4)&&((a^b)&8)){
  if(((a&64)&&!(b&128))||((b&64)&&!(a&128)))gap=fminf(gap,.83f);
 }
 return gap;
}
static void solve(const float *in,float *out,int count,float dt,FieldLimits limits){
 if(!configure_grid(limits))return;
 int occupied_count=0;
 for(int i=0;i<count;i++){
  const float *p=in+i*STRIDE;
  if(p[10]<.5f)continue;
  if((int)p[11]&8)input_forward[i]=(Forward){sinf(p[6]),cosf(p[6])};
  output_forward[i]=input_forward[i];
  int c=cell(p[0],p[1]);
  if(heads[c]<0)occupied_cells[occupied_count++]=c;
  next_agent[i]=heads[c];heads[c]=i;
 }
 for(int i=0;i<count;i++){
  const float *p=in+i*STRIDE;float *r=out+i*STRIDE;if(p[10]<.5f||p[9]<-.5f)continue;
  float dx=p[4]-p[0],dz=p[5]-p[1],dist=sqrtf(dx*dx+dz*dz),vx=0,vz=0;
  if(p[9]>.5f&&dist>.08f){float speed=fminf(p[8],dist*2.8f);vx=dx/dist*speed;vz=dz/dist*speed;}
  if(p[9]>.5f){int c=cell(p[0],p[1]),cx=c%grid_width,cz=c/grid_width;float px=0,pz=0;
   for(int z=cz<2?0:cz-2;z<=cz+2&&z<grid_height;z++)for(int x=cx<2?0:cx-2;x<=cx+2&&x<grid_width;x++){
    for(int j=heads[z*grid_width+x];j>=0;j=next_agent[j]){if(i==j)continue;const float *o=in+j*STRIDE;
     float ax=p[0]-o[0],az=p[1]-o[1],d2=ax*ax+az*az;if(d2>8.41f)continue;
     int a=(int)p[11],b=(int)o[11];
     if(!((a|b)&8)){
      float reach=infantry_gap(a,b)+.24f+.4f;
      if(d2>reach*reach)continue;
     }
     if(d2<.00001f){ax=i>j?.01f:-.01f;az=0;d2=.0001f;}
     float d=sqrtf(d2),nx=ax/d,nz=az/d;
     float gap=contact_gap(p,o,input_forward[i],input_forward[j],nx,nz),comfort=gap+.24f;if(d>comfort+.4f)continue;
     float closing=(vx-o[2])*nx+(vz-o[3])*nz;
     float allowed=fmaxf(0,(d-gap-.03f)/fmaxf(dt,.01f));
     if(closing<-allowed){float correction=(-allowed-closing)*.65f;vx+=nx*correction;vz+=nz*correction;}
     // Pass on the right when marching into a neighbour instead of stopping nose-to-nose.
     // Fighters already facing an enemy keep their combat approach slot.
     if((!((int)p[11]&1)||((int)p[11]&32))&&closing<-.1f&&dist>.5f){float side=.9f*fmaxf(0,1.0f-d/(comfort+.4f));px+=nz*side;pz-=nx*side;}
     if(d<comfort){px+=nx*(comfort-d)*2.5f;pz+=nz*(comfort-d)*2.5f;}
    }
   }
   vx+=clampf(px,-1.4f,1.4f);vz+=clampf(pz,-1.4f,1.4f);
  }
  float speed=sqrtf(vx*vx+vz*vz);if(speed>p[8]&&speed>0){vx*=p[8]/speed;vz*=p[8]/speed;}
  float ax=vx-p[2],az=vz-p[3],acc=sqrtf(ax*ax+az*az);
  float limit=dt*((vx*vx+vz*vz < p[2]*p[2]+p[3]*p[3])?5.5f:3.0f);
  if(acc>limit&&acc>0){vx=p[2]+ax*limit/acc;vz=p[3]+az*limit/acc;}
  // A contact is a hard movement constraint, not another acceleration request.
  // Reserve half of the remaining gap for each participant before integration.
  if(vx!=0||vz!=0){int c=cell(p[0],p[1]),cx=c%grid_width,cz=c/grid_width;
   for(int z=cz<2?0:cz-2;z<=cz+2&&z<grid_height;z++)for(int x=cx<2?0:cx-2;x<=cx+2&&x<grid_width;x++){
    for(int j=heads[z*grid_width+x];j>=0;j=next_agent[j]){if(i==j)continue;const float *o=in+j*STRIDE;
     float nx=p[0]-o[0],nz=p[1]-o[1],d2=nx*nx+nz*nz;if(d2>=7.84f||d2<.000001f)continue;
     int a=(int)p[11],b=(int)o[11];
     if(!((a|b)&8)){
      float reach=infantry_gap(a,b)+.45f;
      if(d2>reach*reach)continue;
     }
     float d=sqrtf(d2);nx/=d;nz/=d;float gap=contact_gap(p,o,input_forward[i],input_forward[j],nx,nz);if(d>gap+.45f)continue;float toward=vx*nx+vz*nz,allowed=fmaxf(0,(d-gap)/(2*dt));
     if(toward<-allowed){vx-=nx*(toward+allowed);vz-=nz*(toward+allowed);}
    }
   }
  }
  r[2]=vx;r[3]=vz;r[0]=clampf(p[0]+vx*dt,-limits.x,limits.x);r[1]=clampf(p[1]+vz*dt,-limits.z,limits.z);
  float angle=p[7];if(!((int)p[11]&1)&&(vx*vx+vz*vz)>.0225f)angle=atan2f(-vx,-vz);
  float diff=remainderf(angle-p[6],6.28318530718f);r[6]=p[6]+clampf(diff,-(((int)p[11]&8)?1.8f:3.5f)*dt,(((int)p[11]&8)?1.8f:3.5f)*dt);
  if(((int)p[11]&8)&&r[6]!=p[6])output_forward[i]=(Forward){sinf(r[6]),cosf(r[6])};
 }
 // Short symmetric positional corrections prevent bodies passing through each other.
 for(int pass=0;pass<2;pass++)for(int i=0;i<count;i++){
  float *p=out+i*STRIDE;if(p[10]<.5f||p[9]<-.5f)continue;int c=cell(p[0],p[1]),cx=c%grid_width,cz=c/grid_width;
  for(int z=cz<2?0:cz-2;z<=cz+2&&z<grid_height;z++)for(int x=cx<2?0:cx-2;x<=cx+2&&x<grid_width;x++){
   for(int j=heads[z*grid_width+x];j>=0;j=next_agent[j]){if(i>=j)continue;float *o=out+j*STRIDE;float ax=p[0]-o[0],az=p[1]-o[1],d2=ax*ax+az*az;
    if(d2>=7.84f||d2<.000001f)continue;
    int a=(int)p[11],b=(int)o[11];
    if(!((a|b)&8)){
     float reach=infantry_gap(a,b)-.02f;
     if(d2>=reach*reach)continue;
    }
    float d=sqrtf(d2),gap=contact_gap(p,o,output_forward[i],output_forward[j],ax/d,az/d)-.02f;if(d>=gap)continue;
    float pdx=p[4]-p[0],pdz=p[5]-p[1],odx=o[4]-o[0],odz=o[5]-o[1];
    float shift=fminf(.04f,gap-d),wp=(p[9]>.5f&&pdx*pdx+pdz*pdz>.04f)?1.0f:.15f,wo=(o[9]>.5f&&odx*odx+odz*odz>.04f)?1.0f:.15f;
    if(o[9]<-.5f)wo=0;float total=wp+wo;ax=ax/d*shift;az=az/d*shift;
    p[0]+=ax*wp/total;p[1]+=az*wp/total;if(wo>0){o[0]-=ax*wo/total;o[1]-=az*wo/total;}
   }
  }
 }
 for(int i=0;i<count;i++){
  const float *p=in+i*STRIDE;float *r=out+i*STRIDE;if(p[9]<-.5f)continue;
  float px=clampf(p[0]+r[2]*dt,-limits.x,limits.x),pz=clampf(p[1]+r[3]*dt,-limits.z,limits.z);
  float dx=r[0]-px,dz=r[1]-pz,d=sqrtf(dx*dx+dz*dz),limit=.9f*dt;
  if(d>limit&&d>0){r[0]=px+dx*limit/d;r[1]=pz+dz*limit/d;}
  r[0]=clampf(r[0],-limits.x,limits.x);r[1]=clampf(r[1],-limits.z,limits.z);
 }
 // Clear only buckets that held soldiers, regardless of the map area.
 for(int i=0;i<occupied_count;i++)heads[occupied_cells[i]]=-1;
}
static void solve_stepped(const float *in,float *out,int count,float dt,FieldLimits limits){
 int steps=(int)ceilf(dt/.066667f);float step_dt=dt/steps;
 solve(in,out,count,step_dt,limits);
 for(int i=1;i<steps;i++){memcpy(substep_state,out,sizeof(float)*count*STRIDE);solve(substep_state,out,count,step_dt,limits);}
}
static void step_call(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 uint64_t input[8]={0},output[8]={0},size_v[8]={0};double delta=0;int64_t count=0;
 if(argc!=2&&argc!=4){err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;return;}
 FieldLimits limits=DEFAULT_LIMITS;
 if(argc==4){
  double x=0,z=0;
  to_float(&x,(void*)args[2]);to_float(&z,(void*)args[3]);
  if(isfinite(x)&&isfinite(z)&&x>0&&z>0){
   limits.x=(float)x;
   limits.z=(float)z;
  }
 }
 to_array(input,(void*)args[0]);to_float(&delta,(void*)args[1]);
 GDExtensionCallError call_error={0};variant_call((void*)args[0],size_name,NULL,0,size_v,&call_error);to_int(&count,size_v);destroy_variant(size_v);
 const GDExtensionConstTypePtr copy_args[]={input};copy_array(output,copy_args);
 if(count>0&&count%STRIDE==0&&count/STRIDE<=CAP&&delta>0&&delta<=.5){const float *src=index_ro(input,0);float *dst=index_rw(output,0);solve_stepped(src,dst,(int)(count/STRIDE),(float)delta,limits);}
 from_array(ret,output);destroy_array(output);destroy_array(input);err->error=GDEXTENSION_CALL_OK;
}
static int64_t array_size(GDExtensionConstVariantPtr v){
 uint64_t result[8]={0};int64_t n=0;GDExtensionCallError e={0};variant_call((void*)v,size_name,NULL,0,result,&e);to_int(&n,result);destroy_variant(result);return n;
}
#define ASSIGN_CAP 256
static double assignment_cost[ASSIGN_CAP*ASSIGN_CAP];
static void assign_slots(const float *points,float *out,int n){
 double u[ASSIGN_CAP+1]={0},v[ASSIGN_CAP+1]={0},minimum[ASSIGN_CAP+1];
 int p[ASSIGN_CAP+1]={0},way[ASSIGN_CAP+1]={0};unsigned char used[ASSIGN_CAP+1];
 for(int i=0;i<n;i++)for(int j=0;j<n;j++){
  double dx=(double)points[i*4]-points[j*4+2],dz=(double)points[i*4+1]-points[j*4+3];
  assignment_cost[i*n+j]=dx*dx+dz*dz;
 }
 for(int i=1;i<=n;i++){
  p[0]=i;int j0=0;memset(used,0,(size_t)n+1);
  for(int j=0;j<=n;j++)minimum[j]=INFINITY;
  do{
   used[j0]=1;int i0=p[j0],j1=0;double delta=INFINITY;
   for(int j=1;j<=n;j++)if(!used[j]){
    double cost=assignment_cost[(i0-1)*n+j-1]-u[i0]-v[j];
    if(cost<minimum[j]){minimum[j]=cost;way[j]=j0;}
    if(minimum[j]<delta){delta=minimum[j];j1=j;}
   }
   for(int j=0;j<=n;j++){if(used[j]){u[p[j]]+=delta;v[j]-=delta;}else minimum[j]-=delta;}
   j0=j1;
  }while(p[j0]);
  do{int j1=way[j0];p[j0]=p[j1];j0=j1;}while(j0);
 }
 for(int j=1;j<=n;j++)out[p[j]-1]=(float)(j-1);
}
static void assignment_call(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 if(argc!=1){err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;return;}
 uint64_t input[8]={0},output[8]={0};to_array(input,(void*)args[0]);
 const GDExtensionConstTypePtr copy_args[]={input};copy_array(output,copy_args);
 int64_t size=array_size(args[0]);
 // Input: interleaved actor X/Z and slot X/Z. Return indices in its first N entries.
 if(size>0&&size%4==0&&size/4<=ASSIGN_CAP)assign_slots(index_ro(input,0),index_rw(output,0),(int)(size/4));
 from_array(ret,output);destroy_array(output);destroy_array(input);err->error=GDEXTENSION_CALL_OK;
}

// Use the same two heightfield triangles as terrain.gd.
static float sample_ground(float x,float z,const float *grid,const float *terrain){
 int width=(int)terrain[0],depth=(int)terrain[1];
 float u=clampf((x+terrain[2])/terrain[4],0,width-1-.001f);
 float v=clampf((z+terrain[3])/terrain[5],0,depth-1-.001f);
 int column=(int)u,row=(int)v;
 u-=column;v-=row;
 const float *cell=grid+row*width+column;
 float a=cell[0],b=cell[1],c=cell[width],d=cell[width+1];
 return u+v<=1?a+(b-a)*u+(c-a)*v:d+(c-d)*(1-u)+(b-d)*(1-v);
}

static int valid_ground(const float *terrain,int64_t length){
 if(terrain[0]<2||terrain[0]>INT_MAX/2||terrain[1]<2||terrain[1]>INT_MAX/2||terrain[4]<=0||terrain[5]<=0)return 0;
 return isfinite(terrain[0])&&isfinite(terrain[1])&&(int64_t)(int)terrain[0]*(int)terrain[1]==length;
}

static void project_terrain(const float *positions,float *out,int count,const float *grid,const float *terrain,int obstacles){
 for(int i=0;i<count;i++){
  const float *position=positions+i*STRIDE;
  if(position[10]<.5f||position[9]<-.5f)continue;
  float x=position[0],z=position[1];
  for(int obstacle=0;obstacle<obstacles;obstacle++){
   const float *bounds=terrain+6+obstacle*3;
   float dx=x-bounds[0],dz=z-bounds[1],squared=dx*dx+dz*dz,radius=bounds[2];
   if(squared>=radius*radius)continue;
   if(squared>.001f){
    float scale=radius/sqrtf(squared);
    x=bounds[0]+scale*dx;
    z=bounds[1]+scale*dz;
   }else{
    x=bounds[0]+radius;
    z=bounds[1];
   }
  }
  out[i*3]=x;
  out[i*3+1]=sample_ground(x,z,grid,terrain);
  out[i*3+2]=z;
 }
}

static void terrain_call(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 if(argc!=3){err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;return;}
 int64_t length=array_size(args[0]),grid_size=array_size(args[1]),config_size=array_size(args[2]);
 uint64_t positions[8]={0},grid[8]={0},config[8]={0},out[8]={0};
 to_array(positions,(void*)args[0]);to_array(grid,(void*)args[1]);to_array(config,(void*)args[2]);
 int valid=0;
 if(length>0&&length%STRIDE==0&&length/STRIDE<=CAP&&config_size>=6&&(config_size-6)%3==0){
  const float *terrain=index_ro(config,0);
  if(valid_ground(terrain,grid_size)){
    const GDExtensionConstTypePtr copy_args[]={positions};copy_array(out,copy_args);
    project_terrain(index_ro(positions,0),index_rw(out,0),(int)(length/STRIDE),index_ro(grid,0),terrain,(int)((config_size-6)/3));
    valid=1;
  }
 }
 if(!valid)new_array(out,NULL);
 from_array(ret,out);destroy_array(out);destroy_array(config);destroy_array(grid);destroy_array(positions);
 err->error=GDEXTENSION_CALL_OK;
}

static void render_buffer(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 if(argc!=5&&argc!=6){err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;return;}
 uint64_t arrays[4][8]={{0}},output[8]={0},heights[8]={0};int64_t lengths[4];double alpha=1;
 for(int i=0;i<4;i++){to_array(arrays[i],(void*)args[i]);lengths[i]=array_size(args[i]);}
 const float *y=NULL;
 if(argc==6&&lengths[2]>0&&array_size(args[5])==2*(lengths[2]/STRIDE)){
  to_array(heights,(void*)args[5]);
  y=index_ro(heights,0);
 }
 const GDExtensionConstTypePtr copy_args[]={arrays[0]};copy_array(output,copy_args);
 to_float(&alpha,(void*)args[4]);float w=clampf((float)alpha,0,1);
 if(lengths[0]>0&&lengths[0]%20==0&&lengths[1]>=lengths[0]/20&&lengths[2]==lengths[3]&&lengths[2]>0&&lengths[2]%STRIDE==0){
  float *dst=index_rw(output,0);const float *ids=index_ro(arrays[1],0),*now=index_ro(arrays[2],0),*old=index_ro(arrays[3],0);
  for(int64_t slot=0;slot<lengths[0]/20;slot++){
   float *r=dst+slot*20;int id=(int)ids[slot];
   if(y&&id==-2)continue; // The slot already holds a static transform.
   if(id<0||id>=lengths[2]/STRIDE){memset(r,0,sizeof(float)*12);continue;}
   const float *a=old+id*STRIDE,*b=now+id*STRIDE;
   float yaw=a[6]+remainderf(b[6]-a[6],6.28318530718f)*w,s=sinf(yaw),c=cosf(yaw);
   // Godot MultiMesh stores Transform3D as three rows of four floats.
   r[0]=c;r[1]=0;r[2]=s;r[3]=a[0]+(b[0]-a[0])*w;
   r[4]=0;r[5]=1;r[6]=0;r[7]=y?y[2*id]+(y[2*id+1]-y[2*id])*w:0;
   r[8]=-s;r[9]=0;r[10]=c;r[11]=a[1]+(b[1]-a[1])*w;
  }
 }
 from_array(ret,output);destroy_array(output);for(int i=0;i<4;i++)destroy_array(arrays[i]);if(y)destroy_array(heights);err->error=GDEXTENSION_CALL_OK;
}
typedef struct {
 float transform[12];
 float plane_distance;
} RenderPose;
typedef struct {
 int64_t visible_count;
 int pose_count;
 RenderPose poses[CAP];
 float planes[24];
 int plane_count;
} CrowdInstance;

static float max_plane_distance(const float *planes,int count,float x,float y,float z){
 float distance=-INFINITY;
 for(int i=0;i<count;i++,planes+=4){
  float d=planes[0]*x+planes[1]*(y+1.0f)+planes[2]*z-planes[3];
  if(d>distance)distance=d;
 }
 return distance;
}

static void build_render_pose(RenderPose *pose,const float *now,const float *old,const float *y,float weight,
 const float *grid,const float *terrain,const float *planes,int plane_count){
 float x=old[0]+(now[0]-old[0])*weight;
 float z=old[1]+(now[1]-old[1])*weight;
 float height=y[0]+(y[1]-y[0])*weight;
 float yaw=old[6]+remainderf(now[6]-old[6],6.28318530718f)*weight;
 float s=sinf(yaw),c=cosf(yaw);
 float sp=0,cp=1,sr=0,cr=1;
 if(grid&&((int)now[11]&8)){
  float rise=sample_ground(x+s*1.25f,z+c*1.25f,grid,terrain)-sample_ground(x-s*1.25f,z-c*1.25f,grid,terrain);
  float cross=sample_ground(x+c*.65f,z-s*.65f,grid,terrain)-sample_ground(x-c*.65f,z+s*.65f,grid,terrain);
  float pitch=clampf(atan2f(rise,2.5f),-.383972435f,.383972435f);
  float roll=clampf(atan2f(cross,1.3f),-.209439510f,.209439510f);
  sp=-sinf(pitch);cp=cosf(pitch);sr=sinf(roll);cr=cosf(roll);
 }
 float *r=pose->transform;
 r[0]=c*cr+s*sp*sr;r[1]=-c*sr+s*sp*cr;r[2]=s*cp;r[3]=x;
 r[4]=cp*sr;r[5]=cp*cr;r[6]=-sp;r[7]=height;
 r[8]=-s*cr+c*sp*sr;r[9]=s*sr+c*sp*cr;r[10]=c*cp;r[11]=z;
 pose->plane_distance=max_plane_distance(planes,plane_count,x,height,z);
}

static void prepare_render_frame(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 if(argc!=7){err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;return;}
 CrowdInstance *instance=self;
 int64_t size=array_size(args[0]),plane_size=array_size(args[5]);
 instance->pose_count=0;
 instance->plane_count=0;
 if(size>0&&size%STRIDE==0&&size/STRIDE<=CAP&&array_size(args[1])==size&&array_size(args[2])==2*size/STRIDE){
  uint64_t arrays[6][8]={{0}};
  for(int i=0;i<6;i++)to_array(arrays[i],(void*)args[i]);
  if(plane_size>0&&plane_size<=24&&plane_size%4==0){
   memcpy(instance->planes,index_ro(arrays[5],0),sizeof(float)*plane_size);
   instance->plane_count=(int)(plane_size/4);
  }
  const float *terrain=array_size(args[4])>=6?index_ro(arrays[4],0):NULL;
  const float *grid=terrain&&valid_ground(terrain,array_size(args[3]))?index_ro(arrays[3],0):NULL;
  const float *now=index_ro(arrays[0],0),*old=index_ro(arrays[1],0),*heights=index_ro(arrays[2],0);
  double alpha=0;
  to_float(&alpha,(void*)args[6]);
  float weight=clampf((float)alpha,0,1);
  instance->pose_count=(int)(size/STRIDE);
  for(int i=0;i<instance->pose_count;i++)
   build_render_pose(instance->poses+i,now+i*STRIDE,old+i*STRIDE,heights+i*2,weight,grid,terrain,instance->planes,instance->plane_count);
  for(int i=0;i<6;i++)destroy_array(arrays[i]);
 }
 int64_t prepared=instance->pose_count;
 from_int(ret,&prepared);
 err->error=GDEXTENSION_CALL_OK;
}

static void assemble_render_batch(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 if(argc!=4){err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;return;}
 CrowdInstance *instance=self;
 int64_t slots=0,capacity=array_size(args[0])/20,visible=0;
 double margin=-1;
 to_int(&slots,(void*)args[2]);to_float(&margin,(void*)args[3]);
 uint64_t source[8]={0},indices[8]={0},output[8]={0};
 to_array(source,(void*)args[0]);to_array(indices,(void*)args[1]);
 const GDExtensionConstTypePtr copy_args[]={source};copy_array(output,copy_args);
 if(slots>capacity)slots=capacity;
 if(slots>array_size(args[1]))slots=array_size(args[1]);
 if(slots>0){
  const float *in=index_ro(source,0),*ids=index_ro(indices,0);
  float *dst=index_rw(output,0);
  for(int64_t slot=0;slot<slots;slot++){
   int id=(int)ids[slot];
   const float *entry=in+slot*20,*transform=entry;
   if(id>=0&&id<instance->pose_count){
    const RenderPose *pose=instance->poses+id;
    if(margin>=0&&pose->plane_distance>margin)continue;
    transform=pose->transform;
   }else if(id==-2){
    if(margin>=0&&max_plane_distance(instance->planes,instance->plane_count,entry[3],entry[7],entry[11])>margin)continue;
   }else continue;
   memcpy(dst+visible*20,transform,sizeof(float)*12);
   memcpy(dst+visible*20+12,entry+12,sizeof(float)*8);
   visible++;
  }
 }
 instance->visible_count=visible;
 from_array(ret,output);destroy_array(output);destroy_array(indices);destroy_array(source);
 err->error=GDEXTENSION_CALL_OK;
}

static int64_t compact_visible(float *buffer,int64_t slots,const float *planes,int64_t plane_count,float margin){
 int64_t visible=0;
 for(int64_t slot=0;slot<slots;slot++){
  float *entry=buffer+slot*20;
  if(entry[0]==0&&entry[1]==0&&entry[2]==0)continue;
  float x=entry[3],y=entry[7]+1.0f,z=entry[11];
  int outside=0;
  for(int64_t plane=0;plane<plane_count;plane++){
   const float *p=planes+plane*4;
   if(p[0]*x+p[1]*y+p[2]*z-p[3]>margin){outside=1;break;}
  }
  if(outside)continue;
  if(visible!=slot)memcpy(buffer+visible*20,entry,sizeof(float)*20);
  visible++;
 }
 return visible;
}
static void compact_call(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 if(argc!=4){err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;return;}
 uint64_t input[8]={0},output[8]={0},planes[8]={0};
 int64_t slots=0;
 double margin=0;
 to_array(input,(void*)args[0]);to_array(planes,(void*)args[1]);
 to_int(&slots,(void*)args[2]);to_float(&margin,(void*)args[3]);
 int64_t plane_size=array_size(args[1]),capacity=array_size(args[0])/20;
 const GDExtensionConstTypePtr copy_args[]={input};copy_array(output,copy_args);
 if(slots<0)slots=0;
 if(slots>capacity)slots=capacity;
 CrowdInstance *instance=self;
 instance->visible_count=slots;
 if(slots>0&&plane_size>0&&plane_size%4==0){
  instance->visible_count=compact_visible(index_rw(output,0),slots,index_ro(planes,0),plane_size/4,(float)margin);
 }
 from_array(ret,output);destroy_array(output);destroy_array(input);destroy_array(planes);
 err->error=GDEXTENSION_CALL_OK;
}
static void visible_count(void *u,GDExtensionClassInstancePtr self,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr ret,GDExtensionCallError *err){
 CrowdInstance *instance=self;
 from_int(ret,&instance->visible_count);
 err->error=GDEXTENSION_CALL_OK;
}
static GDExtensionObjectPtr create(void *u,GDExtensionBool notify){
 CrowdInstance *instance=calloc(1,sizeof(*instance));
 if(!instance)return NULL;
 GDExtensionObjectPtr obj=construct(parent_name);
 set_instance(obj,class_name,instance);
 return obj;
}
static void release(void *u,GDExtensionClassInstancePtr self){free(self);}
static void initialize(void *u,GDExtensionInitializationLevel level){
 if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
 make_name(class_name,"CrowdNative");make_name(parent_name,"RefCounted");make_name(size_name,"size");make_name(method_name,"step");make_name(empty_name,"");((GDExtensionInterfaceStringNewWithUtf8Chars)api("string_new_with_utf8_chars"))(empty_string,"");
 GDExtensionClassCreationInfo4 info={0};info.is_exposed=1;info.create_instance_func=create;info.free_instance_func=release;
 ((GDExtensionInterfaceClassdbRegisterExtensionClass4)api("classdb_register_extension_class4"))(library,class_name,parent_name,&info);
 GDExtensionPropertyInfo result={0},arguments[2]={{0},{0}};result.type=GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY;arguments[0].type=result.type;arguments[1].type=GDEXTENSION_VARIANT_TYPE_FLOAT;
 result.name=empty_name;result.class_name=empty_name;result.hint_string=empty_string;
 for(int i=0;i<2;i++){arguments[i].name=empty_name;arguments[i].class_name=empty_name;arguments[i].hint_string=empty_string;}
 GDExtensionClassMethodArgumentMetadata metadata[2]={GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE};
 GDExtensionClassMethodInfo method={0};method.name=method_name;method.call_func=step_call;method.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL;method.has_return_value=1;method.return_value_info=&result;method.argument_count=2;method.arguments_info=arguments;method.arguments_metadata=metadata;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(bounded_name,"step_bounded");
 GDExtensionPropertyInfo bounded_args[4]={arguments[0],arguments[1],arguments[1],arguments[1]};
 GDExtensionClassMethodArgumentMetadata bounded_meta[4]={metadata[0],metadata[1],metadata[1],metadata[1]};
 method.name=bounded_name;method.argument_count=4;method.arguments_info=bounded_args;method.arguments_metadata=bounded_meta;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(assignment_name,"assign_slots");
 method.name=assignment_name;method.call_func=assignment_call;method.argument_count=1;method.arguments_info=arguments;method.arguments_metadata=metadata;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(terrain_name,"project_terrain");
 GDExtensionPropertyInfo terrain_args[3]={arguments[0],arguments[0],arguments[0]};
 GDExtensionClassMethodArgumentMetadata terrain_meta[3]={metadata[0],metadata[0],metadata[0]};
 method.name=terrain_name;method.call_func=terrain_call;method.argument_count=3;method.arguments_info=terrain_args;method.arguments_metadata=terrain_meta;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(render_name,"render_buffer");
 GDExtensionPropertyInfo render_args[6];GDExtensionClassMethodArgumentMetadata render_meta[6];
 for(int i=0;i<6;i++){render_args[i]=arguments[i==4?1:0];render_meta[i]=i==4?GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE:GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;}
 method.name=render_name;method.call_func=render_buffer;method.argument_count=5;method.arguments_info=render_args;method.arguments_metadata=render_meta;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(grounded_render_name,"render_grounded_buffer");
 method.name=grounded_render_name;method.argument_count=6;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(compact_name,"compact_render_buffer");
 GDExtensionPropertyInfo compact_args[4]={arguments[0],arguments[0],arguments[0],arguments[1]};
 GDExtensionClassMethodArgumentMetadata compact_meta[4]={metadata[0],metadata[0],GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64,metadata[1]};
 compact_args[2].type=GDEXTENSION_VARIANT_TYPE_INT;
 method.name=compact_name;method.call_func=compact_call;method.argument_count=4;
 method.arguments_info=compact_args;method.arguments_metadata=compact_meta;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(visible_count_name,"visible_render_count");
 method.name=visible_count_name;method.call_func=visible_count;method.argument_count=0;
 method.arguments_info=NULL;method.arguments_metadata=NULL;
 result.type=GDEXTENSION_VARIANT_TYPE_INT;method.return_value_metadata=GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(prepare_render_name,"prepare_render_frame");
 GDExtensionPropertyInfo prepare_args[7];
 GDExtensionClassMethodArgumentMetadata prepare_meta[7];
 for(int i=0;i<7;i++){
  prepare_args[i]=arguments[i==6?1:0];
  prepare_meta[i]=metadata[i==6?1:0];
 }
 method.name=prepare_render_name;method.call_func=prepare_render_frame;method.argument_count=7;method.arguments_info=prepare_args;method.arguments_metadata=prepare_meta;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
 make_name(assemble_render_name,"assemble_render_batch");
 result.type=GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY;method.return_value_metadata=GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
 method.name=assemble_render_name;method.call_func=assemble_render_batch;method.argument_count=4;method.arguments_info=compact_args;method.arguments_metadata=compact_meta;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,class_name,&method);
}
static void deinitialize(void *u,GDExtensionInitializationLevel level){if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;((GDExtensionInterfaceClassdbUnregisterExtensionClass)api("classdb_unregister_extension_class"))(library,class_name);destroy_name(class_name);destroy_name(parent_name);destroy_name(size_name);destroy_name(method_name);destroy_name(bounded_name);destroy_name(render_name);destroy_name(grounded_render_name);destroy_name(compact_name);destroy_name(visible_count_name);destroy_name(prepare_render_name);destroy_name(assemble_render_name);destroy_name(assignment_name);destroy_name(terrain_name);destroy_name(empty_name);destroy_string(empty_string);free(heads);heads=NULL;grid_capacity=0;}
__declspec(dllexport) GDExtensionBool crowd_library_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init){
 api=get;library=lib;
 make_name=(GDExtensionInterfaceStringNameNewWithUtf8Chars)get("string_name_new_with_utf8_chars");construct=(GDExtensionInterfaceClassdbConstructObject2)get("classdb_construct_object2");set_instance=(GDExtensionInterfaceObjectSetInstance)get("object_set_instance");
 index_rw=(GDExtensionInterfacePackedFloat32ArrayOperatorIndex)get("packed_float32_array_operator_index");index_ro=(GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst)get("packed_float32_array_operator_index_const");
 GDExtensionInterfaceGetVariantToTypeConstructor to=(GDExtensionInterfaceGetVariantToTypeConstructor)get("get_variant_to_type_constructor");to_array=to(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);to_float=to(GDEXTENSION_VARIANT_TYPE_FLOAT);to_int=to(GDEXTENSION_VARIANT_TYPE_INT);
 from_array=((GDExtensionInterfaceGetVariantFromTypeConstructor)get("get_variant_from_type_constructor"))(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
 from_int=((GDExtensionInterfaceGetVariantFromTypeConstructor)get("get_variant_from_type_constructor"))(GDEXTENSION_VARIANT_TYPE_INT);
 GDExtensionInterfaceVariantGetPtrConstructor constructor=(GDExtensionInterfaceVariantGetPtrConstructor)get("variant_get_ptr_constructor");
 copy_array=constructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,1);
 new_array=constructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,0);
 GDExtensionInterfaceVariantGetPtrDestructor destructor=(GDExtensionInterfaceVariantGetPtrDestructor)get("variant_get_ptr_destructor");destroy_array=destructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);destroy_name=destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);destroy_string=destructor(GDEXTENSION_VARIANT_TYPE_STRING);
 variant_call=(GDExtensionInterfaceVariantCall)get("variant_call");destroy_variant=(GDExtensionInterfaceVariantDestroy)get("variant_destroy");
 init->initialize=initialize;init->deinitialize=deinitialize;init->userdata=NULL;init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;return 1;
}
