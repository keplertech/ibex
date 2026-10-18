#include "Vt.h"
#include <cstdio>
int main(){ Vt m; for (int p=0;p<4;p++){ m.priv=p; m.eval(); printf("priv=%d fail=%d expected=%d\n",p,m.fail,p!=3);} }
