#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#define N 4096
#define NOINL __attribute__((noinline))
NOINL void k_fma(const float*a,const float*b,float*o,long n){for(long i=0;i<n;i++)o[i]=a[i]*b[i]+1.5f;}
NOINL void k_scale64(const double*a,double*o,long n){for(long i=0;i<n;i++)o[i]=a[i]*2.0;}
NOINL void k_intadd(const long*a,const long*b,long*o,long n){for(long i=0;i<n;i++)o[i]=a[i]+b[i];}
NOINL void k_stencil(const float*a,float*o,long n){for(long i=0;i<n-1;i++)o[i]=a[i]+a[i+1];}
NOINL void k_base(const float*w,const float*x,float*o,long base,long n){for(long i=0;i<n;i++)o[i]=w[base+i]*x[i];}
NOINL void k_clamp(const float*a,float*o,long n){for(long i=0;i<n;i++){float v=a[i];o[i]=v<0.0f?0.0f:(v>1.0f?1.0f:v);}}
NOINL void k_conv(const long*a,double*o,long n){for(long i=0;i<n;i++)o[i]=(double)a[i]*0.5;}
NOINL float k_dot(const float*a,const float*b,long n){float s=0;for(long i=0;i<n;i++)s+=a[i]*b[i];return s;}
static double now(){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1e9+t.tv_nsec;}
#define TIME(name,flops,call) {double t=now();for(long r=0;r<100000;r++){call;__asm__ volatile(""::"r"(o32):"memory");}printf("%s %f\n",name,(double)(flops)*100000/(now()-t));}
int main(){
 float*f1=malloc(4*(N+8)),*f2=malloc(4*(N+8)),*o32=malloc(4*(N+8));double*d1=malloc(8*(N+8)),*d2=malloc(8*(N+8));long*i1=malloc(8*(N+8)),*i2=malloc(8*(N+8)),*io=malloc(8*(N+8));
 for(long k=0;k<N+8;k++){f1[k]=(k%7)*0.25f-0.5f;f2[k]=(k%5)*0.5f;o32[k]=0;d1[k]=(k%7)*0.25;d2[k]=0;i1[k]=k%11;i2[k]=k%13;io[k]=0;}
 float s=0;
 TIME("fma32",2*N,k_fma(f1,f2,o32,N));
 TIME("scale64",N,k_scale64(d1,d2,N));
 TIME("intadd",N,k_intadd(i1,i2,io,N));
 TIME("stencil",N,k_stencil(f1,o32,N));
 TIME("base",N,k_base(f1,f2,o32,8,N));
 TIME("clamp",N,k_clamp(f1,o32,N));
 TIME("conv",N,k_conv(i1,d2,N));
 TIME("dot32",2*N,s+=k_dot(f1,f2,N));
 printf("check %g %g %ld %g\n",o32[5],d2[5],io[5],s);
}
