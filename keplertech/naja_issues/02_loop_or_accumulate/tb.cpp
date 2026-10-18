#include "Vt.h"
#include <cstdio>
int main(){ Vt m; int bad=0; unsigned ds[]={0xa9d454ba,0x12345678,0xffff0000};
 for(unsigned d:ds) for(int a=0;a<4;a++){ m.data=d; m.addr=a; m.eval(); unsigned exp=(a&2)?(d>>16):(d&0xffff);
  printf("data=%08x addr=%d lo=%04x expected=%04x %s\n",d,a,m.lo,exp,m.lo==exp?"":"<-- WRONG"); bad+=m.lo!=exp;} return bad!=0; }
