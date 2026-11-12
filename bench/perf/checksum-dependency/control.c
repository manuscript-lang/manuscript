#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
static uint32_t table[8][256];
static void init(void){for(unsigned i=0;i<256;i++){uint32_t c=i;for(int k=0;k<8;k++)c=(c>>1)^((c&1)?0xedb88320u:0);table[0][i]=c;}for(int j=1;j<8;j++)for(unsigned i=0;i<256;i++){uint32_t c=table[j-1][i];table[j][i]=table[0][c&255]^(c>>8);}}
static uint32_t crc(uint32_t seed,const unsigned char *p,size_t n){uint32_t c=~seed;while(n>=8){uint32_t w=(uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);c^=w;c=table[7][c&255]^table[6][(c>>8)&255]^table[5][(c>>16)&255]^table[4][c>>24]^table[3][p[4]]^table[2][p[5]]^table[1][p[6]]^table[0][p[7]];p+=8;n-=8;}while(n--){c=table[0][(c^*p++)&255]^(c>>8);}return ~c;}
/* Same RFC1950 recurrence and 5552-byte reduction boundary as production.
   An explicit 16-byte unroll exposes independent byte loads without substituting algorithms. */
static uint32_t adler(uint32_t seed,const unsigned char *p,size_t n){uint32_t a=seed&65535,b=seed>>16;while(n){size_t size=n<5552?n:5552;n-=size;while(size>=16){
#define STEP(i) a+=p[i]; b+=a;
STEP(0) STEP(1) STEP(2) STEP(3) STEP(4) STEP(5) STEP(6) STEP(7) STEP(8) STEP(9) STEP(10) STEP(11) STEP(12) STEP(13) STEP(14) STEP(15)
#undef STEP
p+=16;size-=16;}while(size--){a+=*p++;b+=a;}a%=65521;b%=65521;}return (b<<16)|a;}
static uint64_t now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000000000+t.tv_nsec;}
typedef uint32_t (*hash_fn)(uint32_t,const unsigned char*,size_t);
static uint32_t chunks(hash_fn f,const unsigned char*p,size_t n,uint32_t seed,size_t chunk){for(size_t at=0;at<n;){size_t size=n-at<chunk?n-at:chunk;seed=f(seed,p+at,size);at+=size;}return f(seed,p,0);}
int main(int argc,char **argv){if(argc!=7)return 2;init();hash_fn f=!strcmp(argv[1],"crc")?crc:adler;size_t n=strtoull(argv[2],0,10),chunk=strtoull(argv[3],0,10);uint32_t seed=strtoul(argv[4],0,10);size_t count=strtoull(argv[5],0,10);uint32_t expected=strtoul(argv[6],0,10);unsigned char *p=malloc(n?n:1);if(!p)return 3;for(size_t i=0;i<n;i++)p[i]=(unsigned char)((i*73+i/7+seed)%256);uint32_t initial=chunk?seed:(!strcmp(argv[1],"crc")?0:1);for(int i=0;i<100;i++){uint32_t got=chunk?chunks(f,p,n,initial,chunk):f(initial,p,n);if(got!=expected)return 4;}uint64_t sum=0,start=now();for(size_t i=0;i<count;i++){__asm__ __volatile__("" : : "r"(p) : "memory");uint32_t got=chunk?chunks(f,p,n,initial,chunk):f(initial,p,n);if(got!=expected)return 5;sum+=got;}uint64_t elapsed=now()-start;printf("%llu %llu %u\n",(unsigned long long)elapsed,(unsigned long long)sum,expected);free(p);return 0;}
