#include "codec.h"
#include <stdlib.h>
#include <string.h>
#include <limits.h>
static Result bad(int k) { return (Result){NULL,0,k==1?"EINVAL":k==2?"EOVERFLOW":"EBADMSG",k==1?"encoding: invalid input":k==2?"encoding: limit exceeded":"encoding: invalid data"}; }
static void *alloc(size_t n) {void *p=malloc(n?n:1);if(!p) abort();return p;}
static Result good(size_t n){return(Result){alloc(n+1),n,"OK",""};}
Result hex(const unsigned char *p,size_t n,int64_t limit){
 (void)limit;if(n>(SIZE_MAX-1)/2)abort();Result r=good(n*2);
 static const char digits[]="0123456789abcdef";
 for(size_t i=0;i<n;i++){r.p[2*i]=digits[p[i]/16];r.p[2*i+1]=digits[p[i]%16];}r.p[r.n]=0;return r;
}
Result hexgrow(const unsigned char *p,size_t n,int64_t limit){
 (void)limit;if(n>(SIZE_MAX-1)/2)abort();size_t cap=0,len=0;unsigned char *out=NULL;
 static const char digits[]="0123456789abcdef";
 for(size_t i=0;i<n;i++)for(size_t j=0;j<2;j++){
   if(len+1>=cap){size_t next=cap?cap*2:16;if(next<cap)abort();void *q=realloc(out,next);if(!q)abort();out=q;cap=next;}
   out[len++]=digits[j?p[i]%16:p[i]/16];
 }
 if(!out){out=alloc(1);}out[len]=0;return(Result){out,len,"OK",""};
}
Result b64(const unsigned char *p,size_t n,int64_t limit){
 (void)limit;if(n>(SIZE_MAX-4)/4*3)abort();size_t len=(n/3+(n%3!=0))*4;Result r=good(len);size_t o=0;
 static const char table[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
 for(size_t i=0;i<n;i+=3){size_t rem=n-i;uint32_t v=(uint32_t)p[i]*65536+(rem>1?(uint32_t)p[i+1]*256:0)+(rem>2?p[i+2]:0);
 r.p[o++]=table[v/262144%64];r.p[o++]=table[v/4096%64];r.p[o++]=rem>1?table[v/64%64]:'=';r.p[o++]=rem>2?table[v%64]:'=';
 }r.p[len]=0;return r;
}
static int digit(unsigned char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;}
Result unhex(const unsigned char *p,size_t n,int64_t limit){
 if(limit<0){return bad(1);}if(n/2>(uint64_t)limit)return bad(2);if(n%2)return bad(3);Result r=good(n/2);
 for(size_t i=0;i<n/2;i++){int hi=digit(p[i*2]),lo=digit(p[i*2+1]);if(hi<0||lo<0){free(r.p);return bad(3);}r.p[i]=(unsigned char)(hi*16+lo);}r.p[r.n]=0;return r;
}
static Result utf16(const unsigned char *p,size_t n,int64_t limit,int little){
 if(limit<0){return bad(1);}if(n%2)return bad(3);size_t num=n/2;if(num>SIZE_MAX/8)abort();
 // Same staged algorithm as Manuscript: units, checked scalars, UTF-8 construction.
 uint64_t *units=alloc(num*8),*scalars=alloc(num*8);
 for(size_t i=0;i<num;i++)units[i]=little?p[2*i]+p[2*i+1]*256:p[2*i]*256+p[2*i+1];
 size_t total=0,used=0;
 for(size_t i=0;i<num;){uint64_t c=units[i++];if(c>=56320&&c<57344){free(units);free(scalars);return bad(3);}
 if(c>=55296&&c<56320){if(i>=num||units[i]<56320||units[i]>=57344){free(units);free(scalars);return bad(3);}c=65536+(c-55296)*1024+(units[i++]-56320);}
 size_t width=c<128?1:c<2048?2:c<65536?3:4;
 if(width>(uint64_t)limit-total){free(units);free(scalars);return bad(2);}total+=width;scalars[used++]=c;
 }
 Result r=good(total);size_t o=0;
 for(size_t i=0;i<used;i++){uint32_t c=scalars[i];if(c<128)r.p[o++]=c;else if(c<2048){r.p[o++]=0xc0|(c>>6);r.p[o++]=0x80|(c&63);}else if(c<65536){r.p[o++]=0xe0|(c>>12);r.p[o++]=0x80|((c>>6)&63);r.p[o++]=0x80|(c&63);}else{r.p[o++]=0xf0|(c>>18);r.p[o++]=0x80|((c>>12)&63);r.p[o++]=0x80|((c>>6)&63);r.p[o++]=0x80|(c&63);}}
 r.p[total]=0;free(units);free(scalars);return r;
}
Result utf16le(const unsigned char *p,size_t n,int64_t l){return utf16(p,n,l,1);}
Result utf16be(const unsigned char *p,size_t n,int64_t l){return utf16(p,n,l,0);}

static void append(unsigned char **out,size_t *length,size_t *capacity,unsigned char c){
 if(*length+1>=*capacity){size_t next=*capacity?*capacity*2:16;if(next<*capacity)abort();void *p=realloc(*out,next);if(!p)abort();*out=p;*capacity=next;}
 (*out)[(*length)++]=c;
}
Result b64grow(const unsigned char *p,size_t n,int64_t limit){
 (void)limit;if(n>(SIZE_MAX-4)/4*3)abort();unsigned char *out=NULL;size_t length=0,capacity=0;
 static const char table[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
 for(size_t i=0;i<n;i+=3){size_t rem=n-i;uint32_t v=(uint32_t)p[i]*65536+(rem>1?(uint32_t)p[i+1]*256:0)+(rem>2?p[i+2]:0);
 append(&out,&length,&capacity,table[v/262144%64]);append(&out,&length,&capacity,table[v/4096%64]);append(&out,&length,&capacity,rem>1?table[v/64%64]:'=');append(&out,&length,&capacity,rem>2?table[v%64]:'=');
 }
 if(!out){out=alloc(1);}out[length]=0;return(Result){out,length,"OK",""};
}
