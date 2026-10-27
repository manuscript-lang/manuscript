#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#define N 4096
static int64_t A[N], B[N], O[N];
__attribute__((noinline)) int checked(const int64_t*a,const int64_t*b,int64_t*o,long n){
  for(long i=0;i<n;i++){int64_t r; if(__builtin_add_overflow(a[i],b[i],&r)) return 1; o[i]=r;} return 0;}
__attribute__((noinline)) int versioned(const int64_t*a,const int64_t*b,int64_t*o,long n){
  int64_t bad=0;
  for(long i=0;i<n;i++){int64_t r=(int64_t)((uint64_t)a[i]+(uint64_t)b[i]); bad |= ((a[i]^r)&(b[i]^r));}
  if(bad<0) return checked(a,b,o,n);
  for(long i=0;i<n;i++) o[i]=(int64_t)((uint64_t)a[i]+(uint64_t)b[i]);
  return 0;}
__attribute__((noinline)) int unchecked(const int64_t*a,const int64_t*b,int64_t*o,long n){
  for(long i=0;i<n;i++) o[i]=a[i]+b[i]; return 0;}
static double t(int (*f)(const int64_t*,const int64_t*,int64_t*,long)){
  double best=1e9; for(int r=0;r<9;r++){struct timespec s,e;clock_gettime(CLOCK_MONOTONIC,&s);
   for(int k=0;k<20000;k++){f(A,B,O,N); __asm__ volatile(""::"r"(O):"memory");}
   clock_gettime(CLOCK_MONOTONIC,&e);double d=(e.tv_sec-s.tv_sec)+(e.tv_nsec-s.tv_nsec)*1e-9; if(d<best)best=d;}
  return 20000.0*N/best/1e9;}
int main(){for(int i=0;i<N;i++){A[i]=i;B[i]=2*i;}
 printf("checked %.2f versioned %.2f unchecked %.2f GFLOPS\n",t(checked),t(versioned),t(unchecked));}
