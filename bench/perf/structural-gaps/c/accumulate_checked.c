#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
typedef struct{int64_t hits,sum;}Cell; typedef struct{Cell*cells;size_t len;int64_t total;}Grid;
#define ADD(a,b) ({int64_t r; if(__builtin_add_overflow((a),(b),&r)) abort(); r;})
__attribute__((noinline)) void bump(Grid*g,int n){for(int r=0;r<n;r++)for(size_t i=0;i<g->len;i++){g->cells[i].hits=ADD(g->cells[i].hits,1);g->cells[i].sum=ADD(g->cells[i].sum,(int64_t)i);g->total=ADD(g->total,1);}}
int main(){Grid g={calloc(1000,sizeof(Cell)),1000,0};bump(&g,400000);printf("%lld %lld\n",(long long)g.total,(long long)g.cells[7].sum);}
