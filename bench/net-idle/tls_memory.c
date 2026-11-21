/* Where an OpenSSL connection's memory goes: creates N server and client MsTls objects over the memory BIOs of
 * src/runtime/net/tls.c, runs the handshakes in process and prints the malloc growth per object (glibc mallinfo2).
 * Usage: tls_memory <cert.pem> <key.pem>; run.sh builds and runs it. */
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/ssl.h>
#include "../../src/runtime/net/tls.h"
static size_t used(void){ struct mallinfo2 m=mallinfo2(); return m.uordblks; }
static char *slurp(const char*p,size_t*n){FILE*f=fopen(p,"rb");char*b=calloc(1,65536);*n=fread(b,1,65535,f);fclose(f);return b;}
int main(int argc,char**argv){
  size_t cn,kn; char*c=slurp(argv[1],&cn),*k=slurp(argv[2],&kn);
  MsTlsCtx*sctx=ms_tls_ctx_new(1,c,cn,k,kn,NULL,0);
  MsTlsCtx*cctx=ms_tls_ctx_new(0,NULL,0,NULL,0,c,cn);
  enum{N=200}; MsTls*srv[N],*cli[N]; char buf[16384];
  size_t a=used();
  for(int i=0;i<N;i++){ srv[i]=ms_tls_new(sctx,NULL); }
  size_t b=used();
  for(int i=0;i<N;i++){ cli[i]=ms_tls_new(cctx,"localhost"); }
  /* handshake */
  size_t before=used();
  for(int i=0;i<N;i++){
    for(int r=0;r<10;r++){
      ms_tls_handshake(cli[i]); long n=ms_tls_outgoing(cli[i],buf,sizeof buf); if(n>0) ms_tls_incoming(srv[i],buf,n);
      int s=ms_tls_handshake(srv[i]); n=ms_tls_outgoing(srv[i],buf,sizeof buf); if(n>0) ms_tls_incoming(cli[i],buf,n);
      if(s==MS_TLS_DONE) break;
    }
    ms_tls_handshake(cli[i]);
  }
  size_t after=used();
  printf("server SSL_new: %zu B each; both sides after handshake: %zu B/pair (client+server)\n",(b-a)/N,(after-before)/N+ (b-a)/N);
  for(int i=0;i<N;i++){ms_tls_free(cli[i]);}
  size_t freed=used();
  printf("after freeing clients: server side total %zu B each\n",(freed-a)/N);
}
