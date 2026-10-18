#include "Vt.h"
#include <cstdio>
int main(){ Vt m; int bad=0; unsigned xs[]={0xc7dc1766,0xffffffff,0x12345678};
 for(unsigned x:xs) for(int s=0;s<16;s+=3){ m.x=x; m.sh=s; m.eval(); unsigned e=(x>>s)&0x1ff;
  if(m.y!=e){bad++; printf("x=%08x sh=%2d y=%03x expected=%03x <-- WRONG\n",x,s,m.y,e);} }
 printf("%d wrong\n",bad); return bad!=0; }
