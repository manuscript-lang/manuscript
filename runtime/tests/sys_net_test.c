#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/sys sockets (POSIX): listen on a free port, connect, accept, move bytes both ways in
   non-blocking mode, see end of file, a refused connection, and the address round trip. */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "../sys/net.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

static void nap(void) { struct timespec t = {0, 1000000}; nanosleep(&t, NULL); }

int main(void) {
    ms_addr lo = {4, {127, 0, 0, 1}, 0, 0}, bound, peer;
    ms_sock l, c, s;
    CHECK(ms_sys_tcp_listen(&lo, 8, &l) == MS_SYS_OK);
    CHECK(ms_sys_local_addr(l, &bound) == MS_SYS_OK && bound.family == 4 && bound.port != 0 && bound.ip[0] == 127);
    CHECK(ms_sys_accept(l, &s, NULL) == MS_SYS_AGAIN); /* nothing waiting, no block */

    int rc = ms_sys_tcp_connect(&bound, &c);
    CHECK(rc == MS_SYS_OK || rc == MS_SYS_INPROGRESS);
    int got = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && got == MS_SYS_AGAIN; i++) { got = ms_sys_accept(l, &s, &peer); if (got == MS_SYS_AGAIN) nap(); }
    CHECK(got == MS_SYS_OK && peer.family == 4 && peer.ip[3] == 1);
    CHECK(ms_sys_connect_done(c) == MS_SYS_OK);

    char buf[16]; size_t n = 0;
    CHECK(ms_sys_read(s, buf, sizeof buf, &n) == MS_SYS_AGAIN); /* empty socket: would block */
    CHECK(ms_sys_write(c, "hello", 5, &n) == MS_SYS_OK && n == 5);
    int r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = ms_sys_read(s, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_OK && n == 5 && !memcmp(buf, "hello", 5));
    CHECK(ms_sys_write(s, "world!", 6, &n) == MS_SYS_OK && n == 6);
    r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = ms_sys_read(c, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_OK && n == 6 && !memcmp(buf, "world!", 6));

    /* peer address matches, half close shows as end of file, then a write to a closed peer fails without a signal */
    CHECK(ms_sys_peer_addr(c, &peer) == MS_SYS_OK && peer.port == bound.port);
    CHECK(ms_sys_shutdown(c, 1) == MS_SYS_OK);
    r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = ms_sys_read(s, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_EOF && n == 0);
    ms_sys_close(c);
    int w = MS_SYS_OK;
    for (int i = 0; i < 200 && w == MS_SYS_OK; i++) { w = ms_sys_write(s, "x", 1, &n); nap(); }
    CHECK(w == MS_SYS_ERROR && ms_sys_error() != 0);
    ms_sys_close(s);
    ms_sys_close(l);

    /* nobody listens there now: the connection fails, at once or after the wait */
    rc = ms_sys_tcp_connect(&bound, &c);
    if (rc == MS_SYS_INPROGRESS) {
        int d = MS_SYS_OK;
        for (int i = 0; i < 2000; i++) { d = ms_sys_connect_done(c); if (d == MS_SYS_ERROR) break; nap(); }
        CHECK(d == MS_SYS_ERROR);
        ms_sys_close(c);
    } else CHECK(rc == MS_SYS_ERROR);

    /* IPv6 loopback, when the machine has it */
    ms_addr lo6 = {6, {0}, 0, 0}; lo6.ip[15] = 1;
    ms_sock l6;
    if (ms_sys_tcp_listen(&lo6, 4, &l6) == MS_SYS_OK) {
        CHECK(ms_sys_local_addr(l6, &bound) == MS_SYS_OK && bound.family == 6 && bound.ip[15] == 1 && bound.port != 0);
        ms_sys_close(l6);
    }
    if (!failed) printf("sys net ok\n");
    return failed;
}
