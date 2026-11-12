#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef struct{int kind;int64_t v;}Tok;
int main(){const char*p="(12 + 345) * 6 + (7 * (89 + 10)) ";size_t l=strlen(p),n=l*20000;char*t=malloc(n+1);for(int i=0;i<20000;i++)memcpy(t+i*l,p,l);t[n]=0;
Tok*out=malloc(16);size_t cap=1,len=0;size_t i=0;
while(i<n){char c=t[i];Tok k;if(c==' '){i++;continue;}else if(c=='+'){k.kind=1;i++;}else if(c=='*'){k.kind=2;i++;}else if(c=='('){k.kind=3;i++;}else if(c==')'){k.kind=4;i++;}else{int64_t v=0;while(i<n&&t[i]>='0'&&t[i]<='9'){v=v*10+(t[i]-'0');i++;}k.kind=0;k.v=v;}
if(len==cap){cap*=2;out=realloc(out,cap*sizeof(Tok));}out[len++]=k;}
int64_t nums=0,ops=0;for(size_t j=0;j<len;j++){if(out[j].kind==0)nums+=out[j].v;else ops++;}printf("%zu %lld %lld\n",len,(long long)nums,(long long)ops);}
