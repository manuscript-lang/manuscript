#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
int64_t bfs(int w,int h){char*seen=calloc(w*h,1);int64_t*dist=calloc(w*h,8);int64_t*q=malloc(8*(size_t)w*h);size_t qh=0,qt=0;q[qt++]=0;seen[0]=1;int64_t far=0;
while(qh<qt){int64_t p=q[qh++];int64_t x=p%w,y=p/w;far=dist[p];
if(x+1<w&&!seen[p+1]&&(x*7+y*13)%11!=0){seen[p+1]=1;dist[p+1]=dist[p]+1;q[qt++]=p+1;}
if(y+1<h&&!seen[p+w]){seen[p+w]=1;dist[p+w]=dist[p]+1;q[qt++]=p+w;}
if(x>0&&!seen[p-1]&&(x*5+y*3)%7!=0){seen[p-1]=1;dist[p-1]=dist[p]+1;q[qt++]=p-1;}}return far;}
int64_t heap(int n){int64_t*hp=malloc(8*(size_t)n);size_t len=0;int64_t seed=12345,s=0;for(int i=0;i<n;i++){seed=(seed*1103515245+12345)%2147483648;int64_t v=seed%100000;size_t k=len++;hp[k]=v;while(k>0){size_t par=(k-1)/2;if(hp[par]<=hp[k])break;int64_t t=hp[par];hp[par]=hp[k];hp[k]=t;k=par;}
if(i%3==2){s+=hp[0];hp[0]=hp[--len];size_t j=0;for(;;){size_t l=2*j+1,r=l+1,m=j;if(l<len&&hp[l]<hp[m])m=l;if(r<len&&hp[r]<hp[m])m=r;if(m==j)break;int64_t t=hp[m];hp[m]=hp[j];hp[j]=t;j=m;}}}return s;}
int main(){printf("%lld %lld\n",(long long)bfs(1500,1500),(long long)heap(2000000));}
