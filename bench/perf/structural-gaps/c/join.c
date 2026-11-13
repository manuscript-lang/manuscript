#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(){long total=0;for(int i=0;i<300000;i++){char a[32],d[32];snprintf(a,32,"id%d",i);snprintf(d,32,"%d",i*7);const char*p[5]={a,"name","city",d,"zz"};char*row=malloc(128);size_t n=0;for(int k=0;k<5;k++){if(k)row[n++]=',';size_t l=strlen(p[k]);memcpy(row+n,p[k],l);n+=l;}row[n]=0;total+=n;free(row);}printf("%ld\n",total);}
