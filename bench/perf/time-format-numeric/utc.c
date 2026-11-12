#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <locale.h>
static uint64_t now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000000000+t.tv_nsec;}
static const size_t keylen[]={4,2,2,2,2,2,3,2,4};
static const char*keys[]={"YYYY","MM","DD","HH","mm","ss","SSS","ZZ","zone"};
static char *format(time_t stamp,int nanos,const char *pattern,int mode,size_t*outlen,char*reused,size_t capacity){
 struct tm tm;if(!gmtime_r(&stamp,&tm))abort();
 if(tm.tm_year< -1899||tm.tm_year>8099)abort();
 size_t n=strlen(pattern),cap=mode?capacity:n+16,len=0;
 char *out=mode?reused:malloc(cap);if(!out)abort();
 char values[8][32]={{0}};size_t sizes[8]={0};
 for(size_t i=0;i<n;){
  int k;for(k=0;k<9;k++){size_t z=keylen[k];if(n-i>=z&&!memcmp(pattern+i,keys[k],z))break;}
  const char*text;size_t size;
  if(k==9){text=pattern+i;size=1;i++;}
  else{
   i+=keylen[k];
   if(k==8){text="UTC";size=3;}
   else{
    if(!sizes[k]){
     int num=k==0?tm.tm_year+1900:k==1?tm.tm_mon+1:k==2?tm.tm_mday:k==3?tm.tm_hour:k==4?tm.tm_min:k==5?tm.tm_sec:nanos/1000000;
     if(k==7){memcpy(values[k],"+00:00",6);sizes[k]=6;}
     else{size_t width=k==0?4:k==6?3:2;sizes[k]=width;for(size_t at=width;at>0;){values[k][--at]=(char)('0'+num%10);num/=10;}}

    }text=values[k];size=sizes[k];
   }
  }
  if(len+size>cap){if(mode)abort();size_t next=cap*2;if(next<len+size)next=len+size;char*q=realloc(out,next);if(!q)abort();out=q;cap=next;}
  memcpy(out+len,text,size);len+=size;
 }
 *outlen=len;return out;
}
// Keep the returned owned bytes observable to the optimizer, without timing a second hash loop.
static size_t consume(char*p,size_t n){__asm__ volatile("" : : "r"(p),"r"(n) : "memory");return n;}
int main(int argc,char**argv){if(argc<4)return 2;setlocale(LC_ALL,"C");const char*pattern=argv[1];time_t stamp=(time_t)strtoll(argv[2],0,10);size_t reps=strtoull(argv[3],0,10);int mode=argc>4?atoi(argv[4]):0;int nanos=argc>5?atoi(argv[5]):123456789;if(nanos<0||nanos>=1000000000)return 2;
 size_t capacity=strlen(pattern)*6+64;char*reuse=mode?malloc(capacity):NULL;size_t len=0;char*expected=format(stamp,nanos,pattern,0,&len,NULL,0);fwrite(expected,1,len,stderr);fputc('\n',stderr);free(expected);
 uint64_t sum=0,start=now();for(size_t i=0;i<reps;i++){char*out=format(stamp,nanos,pattern,mode,&len,reuse,capacity);sum+=consume(out,len);if(!mode)free(out);}uint64_t elapsed=now()-start;
 printf("%llu %llu\n",(unsigned long long)elapsed,(unsigned long long)sum);free(reuse);return 0;}
