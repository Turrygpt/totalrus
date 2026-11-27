#include "crowd_native.c"
#include <stdio.h>
int main(void){
 float state[24]={0,0,0,0,10,0,0,0,3.6,1,1,0,2,0,0,0,-10,0,0,0,3.6,1,1,0};
 float result[24];float minimum=2;
 for(int i=0;i<200;i++){
  memcpy(result,state,sizeof(state));solve(state,result,2,.05f,DEFAULT_LIMITS);memcpy(state,result,sizeof(state));
  float dx=state[12]-state[0],dz=state[13]-state[1],d=sqrtf(dx*dx+dz*dz);
  if(d<minimum){minimum=d;if(d<.5f)printf("overlap at %d %.6f, velocity %.3f %.3f\n",i,d,state[2],state[3]);}
 }
 printf("minimum %.6f final %.3f %.3f | %.3f %.3f\n",minimum,state[0],state[1],state[12],state[13]);
 return minimum>=.5f&&state[0]>2&&state[12]<0?0:1;
}
