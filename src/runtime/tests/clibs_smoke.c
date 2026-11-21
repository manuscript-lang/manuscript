/* Links libuv, llhttp, nghttp2 and OpenSSL and uses each once: a loop runs a timer, llhttp parses a request,
   nghttp2 starts a session, and OpenSSL hashes and opens a TLS context. Exit 0 and a line per library on success. */
#include <stdio.h>
#include <string.h>
#include <uv.h>
#include <llhttp.h>
#include <nghttp2/nghttp2.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>

static int fired;
static void on_timer(uv_timer_t *t) { fired = 1; uv_close((uv_handle_t *)t, NULL); }
static int on_url(llhttp_t *p, const char *at, size_t n) { (void)p; (void)at; (void)n; return 0; }
static ssize_t send_cb(nghttp2_session *s, const uint8_t *d, size_t n, int f, void *u) { (void)s; (void)d; (void)f; (void)u; return (ssize_t)n; }

int main(void) {
    uv_loop_t loop; uv_timer_t timer;
    uv_loop_init(&loop); uv_timer_init(&loop, &timer); uv_timer_start(&timer, on_timer, 1, 0);
    uv_run(&loop, UV_RUN_DEFAULT); uv_loop_close(&loop);
    if (!fired) return 1;
    printf("libuv %s ok\n", uv_version_string());

    llhttp_t parser; llhttp_settings_t settings;
    llhttp_settings_init(&settings); settings.on_url = on_url;
    llhttp_init(&parser, HTTP_REQUEST, &settings);
    const char *req = "GET /x HTTP/1.1\r\nHost: a\r\n\r\n";
    if (llhttp_execute(&parser, req, strlen(req)) != HPE_OK || parser.method != HTTP_GET) return 2;
    printf("llhttp %d.%d.%d ok\n", LLHTTP_VERSION_MAJOR, LLHTTP_VERSION_MINOR, LLHTTP_VERSION_PATCH);

    nghttp2_session_callbacks *cb; nghttp2_session *sess;
    nghttp2_session_callbacks_new(&cb); nghttp2_session_callbacks_set_send_callback(cb, send_cb);
    if (nghttp2_session_server_new(&sess, cb, NULL) != 0 || nghttp2_session_send(sess) != 0) return 3;
    nghttp2_session_del(sess); nghttp2_session_callbacks_del(cb);
    printf("nghttp2 %s ok\n", nghttp2_version(0)->version_str);

    unsigned char md[32]; unsigned int mdl = 0;
    if (!EVP_Digest("abc", 3, md, &mdl, EVP_sha256(), NULL) || md[0] != 0xba || md[1] != 0x78) return 4;
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method()); if (!ctx) return 5; SSL_CTX_free(ctx);
    printf("%s ok\n", OpenSSL_version(OPENSSL_VERSION));
    return 0;
}
