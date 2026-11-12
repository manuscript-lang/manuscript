#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <limits.h>
typedef struct {
    unsigned char *p;
    size_t n;
} Buf;
static void die(void) {
    fputs("control failed\n",stderr);
    exit(1);
}

static Buf readall(const char *path) {
    FILE*f=fopen(path,"rb");
    if(!f)die();
    if(fseek(f,0,SEEK_END))die();
    long n=ftell(f);
    if(n<0)die();
    rewind(f);
    Buf b= {
        malloc((size_t)n+1),(size_t)n
    };
    if(!b.p||fread(b.p,1,b.n,f)!=b.n)die();
    fclose(f);
    return b;
}

static int quotes(Buf b,unsigned char d) {
    if(!b.n)return 0;
    if (memchr(b.p, '"', b.n) || memchr(b.p, '\r', b.n) ||
        memchr(b.p, '\n', b.n) || memchr(b.p, d, b.n)) return 1;
    unsigned char f=b.p[0];
    return f==' '||(f>=9&&f<=13)||(b.n==2&&f=='\\'&&b.p[1]=='.');
}

static Buf encode(Buf b,unsigned char d,int crlf) {
    int q=quotes(b,d);
    if (!q) {
        Buf plain = {malloc(b.n ? b.n : 1), b.n};
        if (!plain.p) die();
        memcpy(plain.p, b.p, b.n);
        return plain;
    }
    if(b.n>(SIZE_MAX-3)/2)die();
    Buf o= {
        malloc(b.n*2+3),0
    };
    if(!o.p)die();
    if(q)o.p[o.n++]='"';
    for(size_t i=0;i<b.n;i++) {
        unsigned char c=b.p[i];
        if(q&&crlf&&c=='\r'&&i+1<b.n&&b.p[i+1]=='\n')continue;
        if(q&&crlf&&c=='\n')o.p[o.n++]='\r';
        o.p[o.n++]=c;
        if(q&&c=='"')o.p[o.n++]='"';
    }
    if(q)o.p[o.n++]='"';
    return o;
}

/* Same supported row and error precedence; allocating fields and final output. */
static Buf stringify(Buf b,const char*d,int crlf,int64_t limit,const char **err,const char **message) {
    *err="OK";
    *message="";
    if(limit<0) {
        *err="EINVAL";
        *message="CSV: invalid input";
        return (Buf) {
            0
        };
    }
    size_t dn=strlen(d);
    if(dn!=1||(unsigned char)d[0]>=128||!d[0]||d[0]=='"'||d[0]=='\r'||d[0]=='\n') {
        *err="EINVAL";
        *message="CSV: invalid input";
        return (Buf) {
            0
        };
    }
    Buf a=encode(b,d[0],crlf),t=encode((Buf) {
        (unsigned char*)"tail",4
    },d[0],crlf);
    if(a.n>SIZE_MAX-t.n-3)die();
    size_t n=a.n+1+t.n+(crlf?2:1);
    Buf o= {
        malloc(n?n:1),n
    };
    if(!o.p)die();
    memcpy(o.p,a.p,a.n);
    o.p[a.n]=d[0];
    memcpy(o.p+a.n+1,t.p,t.n);
    if(crlf)o.p[n-2]='\r';
    o.p[n-1]='\n';
    free(a.p);
    free(t.p);
    if(n>(uint64_t)limit) {
        free(o.p);
        *err="EOVERFLOW";
        *message="CSV: limit exceeded";
        return (Buf) {
            0
        };
    }
    return o;
}

static uint64_t work(Buf b,Buf expected,const char*d,int crlf,const char*kind,int64_t limit,int64_t count) {
    uint64_t sum=0;
    for(int64_t i=0;i<count;i++) {
        const char*err;
        const char*message;
        Buf o=stringify(b,d,crlf,limit,&err,&message);
        if(strcmp(kind,err))die();
        if(!strcmp(kind,"OK")) {
            if(o.n!=expected.n||memcmp(o.p,expected.p,o.n))die();
            sum+=o.n+1;
        } else {
            const char*want=!strcmp(kind,"EOVERFLOW")?"CSV: limit exceeded":"CSV: invalid input";
            if(strcmp(message,want))die();
            sum++;
        }
        free(o.p);
    }
    return sum;
}

static uint64_t now(void) {
    struct timespec t;
    if(clock_gettime(CLOCK_MONOTONIC,&t))die();
    return (uint64_t)t.tv_sec*1000000000+t.tv_nsec;
}

int main(int argc,char**argv) {
    if(argc!=8)die();
    Buf b=readall(argv[1]),expected=readall(argv[2]);
    for(size_t i=0;i<b.n;i++)if(b.p[i]>=128)die();
    int64_t limit=strtoll(argv[6],0,10),count=strtoll(argv[7],0,10);
    if(count<1)die();
    int crlf=!strcmp(argv[4],"crlf");
    uint64_t warm=work(b,expected,argv[3],crlf,argv[5],limit,count/10?count/10:1),start=now();
    uint64_t sum=work(b,expected,argv[3],crlf,argv[5],limit,count),elapsed=now()-start;
    printf("%lld,%llu,%llu,%llu\n",(long long)count,(unsigned long long)elapsed,(unsigned long long)sum,(unsigned long long)warm);
    free(b.p);
    free(expected.p);
}
