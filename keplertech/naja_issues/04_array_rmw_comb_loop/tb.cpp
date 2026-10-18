#include "Vt.h"
#include <cstdio>
int main(){ Vt m; int bad=0; for(int b=0;b<16;b++){ m.bits=b; m.eval(); int e=__builtin_popcount(b);
 if(m.cnt!=e){bad++; printf("bits=%x cnt=%d expected=%d <-- WRONG\n",b,m.cnt,e);} } printf("%d wrong\n",bad); return bad!=0; }
