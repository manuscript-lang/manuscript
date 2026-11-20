#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/sys sockets (POSIX): listen on a free port, connect, accept, move bytes both ways in
   non-blocking mode, see end of file, a refused connection, and the address round trip. */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "ms_rt/sys_net.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

static void nap(void) { struct timespec t = {0, 1000000}; nanosleep(&t, NULL); }

int main(void) {
    ms_addr lo = {4, {127, 0, 0, 1}, 0, 0}, bound, peer;
    ms_sock l, c, s;
    CHECK(mssys_net_tcp_listen(&lo, 8, &l) == MS_SYS_OK);
    CHECK(mssys_net_local_addr(l, &bound) == MS_SYS_OK && bound.family == 4 && bound.port != 0 && bound.ip[0] == 127);
    CHECK(mssys_net_accept(l, &s, NULL) == MS_SYS_AGAIN); /* nothing waiting, no block */

    int rc = mssys_net_tcp_connect(&bound, &c);
    CHECK(rc == MS_SYS_OK || rc == MS_SYS_INPROGRESS);
    int got = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && got == MS_SYS_AGAIN; i++) { got = mssys_net_accept(l, &s, &peer); if (got == MS_SYS_AGAIN) nap(); }
    CHECK(got == MS_SYS_OK && peer.family == 4 && peer.ip[3] == 1);
    CHECK(mssys_net_connect_done(c) == MS_SYS_OK);

    char buf[16]; size_t n = 0;
    CHECK(mssys_net_read(s, buf, sizeof buf, &n) == MS_SYS_AGAIN); /* empty socket: would block */
    CHECK(mssys_net_write(c, "hello", 5, &n) == MS_SYS_OK && n == 5);
    int r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = mssys_net_read(s, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_OK && n == 5 && !memcmp(buf, "hello", 5));
    CHECK(mssys_net_write(s, "world!", 6, &n) == MS_SYS_OK && n == 6);
    r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = mssys_net_read(c, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_OK && n == 6 && !memcmp(buf, "world!", 6));

    /* peer address matches, half close shows as end of file, then a write to a closed peer fails without a signal */
    CHECK(mssys_net_peer_addr(c, &peer) == MS_SYS_OK && peer.port == bound.port);
    CHECK(mssys_net_shutdown(c, 1) == MS_SYS_OK);
    r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = mssys_net_read(s, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_EOF && n == 0);
    mssys_net_close(c);
    int w = MS_SYS_OK;
    for (int i = 0; i < 200 && w == MS_SYS_OK; i++) { w = mssys_net_write(s, "x", 1, &n); nap(); }
    CHECK(w == MS_SYS_ERROR && mssys_net_error() != 0);
    mssys_net_close(s);
    mssys_net_close(l);

    /* nobody listens there now: the connection fails, at once or after the wait */
    rc = mssys_net_tcp_connect(&bound, &c);
    if (rc == MS_SYS_INPROGRESS) {
        int d = MS_SYS_OK;
        for (int i = 0; i < 2000; i++) { d = mssys_net_connect_done(c); if (d == MS_SYS_ERROR) break; nap(); }
        CHECK(d == MS_SYS_ERROR);
        mssys_net_close(c);
    } else CHECK(rc == MS_SYS_ERROR);

    /* IPv6 loopback, when the machine has it */
    ms_addr lo6 = {6, {0}, 0, 0}; lo6.ip[15] = 1;
    ms_sock l6;
    if (mssys_net_tcp_listen(&lo6, 4, &l6) == MS_SYS_OK) {
        CHECK(mssys_net_local_addr(l6, &bound) == MS_SYS_OK && bound.family == 6 && bound.ip[15] == 1 && bound.port != 0);
        mssys_net_close(l6);
    }
    /* a listener on :: accepts IPv4 clients too (dual stack), when the machine has IPv6 */
    ms_addr any6 = {6, {0}, 0, 0}, v4;
    ms_sock d, dc, da;
    if (mssys_net_tcp_listen(&any6, 4, &d) == MS_SYS_OK) {
        CHECK(mssys_net_local_addr(d, &bound) == MS_SYS_OK);
        v4 = lo; v4.port = bound.port;
        rc = mssys_net_tcp_connect(&v4, &dc);
        CHECK(rc == MS_SYS_OK || rc == MS_SYS_INPROGRESS);
        got = MS_SYS_AGAIN;
        for (int i = 0; i < 2000 && got == MS_SYS_AGAIN; i++) { got = mssys_net_accept(d, &da, &peer); if (got == MS_SYS_AGAIN) nap(); }
        CHECK(got == MS_SYS_OK);
        mssys_net_close(da); mssys_net_close(dc); mssys_net_close(d);
    }
    if (!failed) printf("sys net ok\n");
    return failed;
}
