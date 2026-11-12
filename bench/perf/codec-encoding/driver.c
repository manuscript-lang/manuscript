#define _POSIX_C_SOURCE 200809L
#include "codec.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
typedef Result (*Operation)(const unsigned char*,size_t,int64_t);
static uint64_t now(void){struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))abort();return(uint64_t)t.tv_sec*1000000000+t.tv_nsec;}
static unsigned char *readall(const char *path,size_t *n){FILE *f=fopen(path,"rb");if(!f)abort();if(fseek(f,0,SEEK_END))abort();long z=ftell(f);if(z<0)abort();*n=z;rewind(f);unsigned char *p=malloc(*n+1);if(!p||fread(p,1,*n,f)!=*n)abort();p[*n]=0;fclose(f);return p;}
static uint64_t batch(Operation op,const unsigned char *p,size_t n,const unsigned char *expected,size_t en,uint64_t count,const char *kind,int64_t limit){
 uint64_t checksum=0;for(uint64_t i=0;i<count;i++){Result r=op(p,n,limit);
 if(strcmp(r.kind,kind))abort();
 if(strcmp(kind,"OK")){const char *m=!strcmp(kind,"EINVAL")?"encoding: invalid input":!strcmp(kind,"EOVERFLOW")?"encoding: limit exceeded":"encoding: invalid data";if(strcmp(r.message,m))abort();checksum++;}
 else{if(r.n!=en||memcmp(r.p,expected,en))abort();checksum+=r.n+1;}free(r.p);
 }return checksum;
}
int main(int argc,char **argv){if(argc!=7)return 2;Operation op=NULL;
 if(!strcmp(argv[1],"hex"))op=hex;else if(!strcmp(argv[1],"hexgrow"))op=hexgrow;else if(!strcmp(argv[1],"b64"))op=b64;else if(!strcmp(argv[1],"unhex"))op=unhex;else if(!strcmp(argv[1],"utf16le"))op=utf16le;else if(!strcmp(argv[1],"utf16be"))op=utf16be;if(!strcmp(argv[1],"b64grow"))op=b64grow;if(!op)return 3;
 size_t n,en;unsigned char *p=readall(argv[2],&n),*expected=readall(argv[3],&en);uint64_t count=strtoull(argv[4],NULL,10),warm=count/10?count/10:1;int64_t limit=strtoll(argv[6],NULL,10);
 uint64_t ws=batch(op,p,n,expected,en,warm,argv[5],limit);uint64_t start=now(),sum=batch(op,p,n,expected,en,count,argv[5],limit),elapsed=now()-start;
 printf("%llu,%llu,%llu,%llu\n",(unsigned long long)count,(unsigned long long)elapsed,(unsigned long long)sum,(unsigned long long)ws);free(p);free(expected);return 0;
}
