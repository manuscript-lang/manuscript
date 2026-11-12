#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include <limits.h>
typedef struct { unsigned char *p; size_t n,cap; } Bytes;
typedef struct { Bytes input,expected; int64_t start,fields,count; uint64_t want; double real; int op; bool error, custom_range; const char *message; } Args;
static void fail(const char *s){fputs(s,stderr);fputc('\n',stderr);exit(1);}
static Bytes load(const char *path){FILE*f=fopen(path,"rb");if(!f)fail("open");if(fseek(f,0,SEEK_END))fail("seek");long n=ftell(f);if(n<0)fail("size");rewind(f);Bytes b={malloc((size_t)n+1),(size_t)n,0};if(!b.p||fread(b.p,1,b.n,f)!=b.n)fail("read");fclose(f);return b;}
static uint64_t now(void){struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))fail("clock");return(uint64_t)t.tv_sec*1000000000+t.tv_nsec;}
static inline uint64_t word(const unsigned char*p,int width,int little){
    uint64_t x=0;
    if(width==1)return *p;
    if(width==2){uint16_t v;memcpy(&v,p,2);x=v;}
    if(width==4){uint32_t v;memcpy(&v,p,4);x=v;}
    if(width==8)memcpy(&x,p,8);
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    int swap=!little;
#else
    int swap=little;
#endif
    if(swap){if(width==2)x=__builtin_bswap16((uint16_t)x);if(width==4)x=__builtin_bswap32((uint32_t)x);if(width==8)x=__builtin_bswap64(x);}
    return x;
}
static inline void append(Bytes*b,uint64_t x,int width,int little){
    if((size_t)width>SIZE_MAX-b->n)fail("capacity overflow");
    size_t needed=b->n+(size_t)width;
    if(needed>b->cap){size_t cap=b->cap?b->cap:32;while(cap<needed){if(cap>SIZE_MAX/2){cap=needed;break;}cap*=2;}unsigned char*p=realloc(b->p,cap);if(!p)fail("alloc");b->p=p;b->cap=cap;}
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    int swap=!little;
#else
    int swap=little;
#endif
    if(swap){if(width==2)x=__builtin_bswap16((uint16_t)x);if(width==4)x=__builtin_bswap32((uint32_t)x);if(width==8)x=__builtin_bswap64(x);}
    if(width==1)b->p[b->n]=(unsigned char)x;
    if(width==2){uint16_t v=(uint16_t)x;memcpy(b->p+b->n,&v,2);}
    if(width==4){uint32_t v=(uint32_t)x;memcpy(b->p+b->n,&v,4);}
    if(width==8)memcpy(b->p+b->n,&x,8);
    b->n=needed;
}
static inline uint64_t float_roundtrip(uint64_t x,int width){
    if(width==4){uint32_t bits=(uint32_t)x;float f;memcpy(&f,&bits,4);volatile double widened=(double)f;volatile float narrowed=(float)widened;float result=narrowed;memcpy(&bits,&result,4);return bits;}
    return x;
}
static inline bool equal_real(uint64_t x,int width,double want){
    if(width==4){uint32_t bits=(uint32_t)x;float f;memcpy(&f,&bits,4);return (double)f==want;}
    double d;memcpy(&d,&x,8);return d==want;
}
/* The memory barrier prevents repeated-operation read verification being hoisted.
   It emits no instruction and does not remove checks or change actual values. */
#define WORK(NAME,WIDTH,LITTLE,FLOATING) \
static uint64_t NAME(const Args*a,int64_t count){ \
    uint64_t sum=0; \
    for(int64_t k=0;k<count;k++){ \
        __asm__ volatile("" : : "r"(a->input.p) : "memory"); \
        Bytes output={0}; \
        for(int64_t i=0;i<a->fields;i++){ \
            uint64_t x=a->want; \
            if(a->op!=1){ \
                if(i>INT64_MAX/(WIDTH))fail("offset arithmetic outside harness"); \
                int64_t delta=i*(WIDTH); \
                if(a->start>INT64_MAX-delta)fail("offset arithmetic outside harness"); \
                int64_t at=a->start+delta; \
                bool valid=at>=0 && (uint64_t)at<=a->input.n && (size_t)(WIDTH)<=a->input.n-(size_t)at; \
                if(!valid){ \
                    const char*kind="ERANGE";const char*message=a->custom_range?"binary: out of range":"binary: value out of range"; \
                    if(!a->error||strcmp(kind,"ERANGE")||strcmp(message,a->message))fail("wrong range error"); \
                    sum++;continue; \
                } \
                if(a->error)fail("expected range error"); \
                x=word(a->input.p+(size_t)at,WIDTH,LITTLE); \
                if(FLOATING)x=float_roundtrip(x,WIDTH); \
                if(a->op==0){ \
                    if(FLOATING){if(!equal_real(x,WIDTH,a->real))fail("wrong float");} \
                    else if(x!=a->want)fail("wrong integer"); \
                    sum++; \
                } \
            } \
            if(a->op!=0)append(&output,x,WIDTH,LITTLE); \
        } \
        if(a->op!=0){ \
            if(output.n!=a->expected.n||(output.n&&memcmp(output.p,a->expected.p,output.n)))fail("wrong packed output"); \
            sum+=output.n+1;free(output.p); \
        } \
    } \
    return sum; \
}
WORK(w1,1,1,0)
WORK(w2le,2,1,0) WORK(w2be,2,0,0)
WORK(w4le,4,1,0) WORK(w4be,4,0,0)
WORK(w8le,8,1,0) WORK(w8be,8,0,0)
WORK(f4le,4,1,1) WORK(f4be,4,0,1)
WORK(f8le,8,1,1) WORK(f8be,8,0,1)
int main(int argc,char**argv){
    if(argc!=10)fail("OP TYPE INPUT EXPECTED START FIELDS COUNT WANT KIND");
    Args a={0};a.input=load(argv[3]);a.expected=load(argv[4]);a.start=strtoll(argv[5],NULL,10);a.fields=strtoll(argv[6],NULL,10);a.count=strtoll(argv[7],NULL,10);a.error=!strcmp(argv[9],"ERANGE");
    if(strcmp(argv[9],"OK")&&!a.error)fail("unsupported kind");
    if(a.fields<0||a.count<1)fail("unsupported counts");
    if(!strcmp(argv[1],"read"))a.op=0;else if(!strcmp(argv[1],"pack"))a.op=1;else if(!strcmp(argv[1],"roundtrip"))a.op=2;else fail("unsupported op");
    if(a.error&&a.op!=0)fail("error control only supported by read");
    const char*t=argv[2];int width=0,little=1,floating=t[0]=='f';
    if(!strcmp(t,"i8")||!strcmp(t,"u8"))width=1;
    else if((t[0]=='i'||t[0]=='u'||t[0]=='f')&&strlen(t)==5){
        if(!strncmp(t+1,"16",2)&&!floating)width=2;
        if(!strncmp(t+1,"32",2))width=4;
        if(!strncmp(t+1,"64",2))width=8;
        if(!strcmp(t+3,"be"))little=0;else if(strcmp(t+3,"le"))fail("endian");
    }
    if(!width)fail("type");
    a.custom_range=t[0]=='u'&&width==8;
    a.message=a.custom_range?"binary: out of range":"binary: value out of range";
    if(floating){a.real=strtod(argv[8],NULL);if(width==4){float f=(float)a.real;a.real=(double)f;uint32_t bits;memcpy(&bits,&f,4);a.want=bits;}else memcpy(&a.want,&a.real,8);}
    else if(t[0]=='u'&&width==8){char*colon;uint64_t hi=strtoull(argv[8],&colon,10);if(*colon!=':')fail("uint64 expects hi:lo");uint64_t lo=strtoull(colon+1,NULL,10);if(hi>UINT32_MAX||lo>UINT32_MAX)fail("uint64 halves");a.want=(hi<<32)|lo;}
    else {a.want=(uint64_t)strtoll(argv[8],NULL,10);if(width<8)a.want&=(UINT64_C(1)<<(width*8))-1;}
    uint64_t(*work)(const Args*,int64_t)=width==1?w1:width==2?(little?w2le:w2be):width==4?(floating?(little?f4le:f4be):(little?w4le:w4be)):(floating?(little?f8le:f8be):(little?w8le:w8be));
    uint64_t warm=work(&a,a.count/10?a.count/10:1),start=now(),sum=work(&a,a.count),elapsed=now()-start;
    printf("%lld,%llu,%llu,%llu\n",(long long)a.count,(unsigned long long)elapsed,(unsigned long long)sum,(unsigned long long)warm);
    free(a.input.p);free(a.expected.p);
}
