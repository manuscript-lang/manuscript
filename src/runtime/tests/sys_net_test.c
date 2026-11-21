#define _POSIX_C_SOURCE 200809L
/* Unit tests for src/runtime/sys sockets (POSIX): listen on a free port, connect, accept, move bytes both ways in
   non-blocking mode, see end of file, a refused connection, and the address round trip. */
#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <time.h>
#include "ms_rt/sys_net.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

static void nap(void) { struct timespec t = {0, 1000000}; nanosleep(&t, NULL); }

int main(void) {
    MsAddr lo = {4, {127, 0, 0, 1}, 0, 0}, bound, peer;
    MsSock l, c, s;
    CHECK(ms_sys_net_tcp_listen(&lo, 8, &l) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(l, &bound) == MS_SYS_OK && bound.family == 4 && bound.port != 0 && bound.ip[0] == 127);
    CHECK(ms_sys_net_accept(l, &s, NULL) == MS_SYS_AGAIN); /* nothing waiting, no block */

    int rc = ms_sys_net_tcp_connect(&bound, &c);
    CHECK(rc == MS_SYS_OK || rc == MS_SYS_INPROGRESS);
    int got = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && got == MS_SYS_AGAIN; i++) { got = ms_sys_net_accept(l, &s, &peer); if (got == MS_SYS_AGAIN) nap(); }
    CHECK(got == MS_SYS_OK && peer.family == 4 && peer.ip[3] == 1);
    CHECK(ms_sys_net_connect_done(c) == MS_SYS_OK);

    char buf[16]; size_t n = 0;
    CHECK(ms_sys_net_read(s, buf, sizeof buf, &n) == MS_SYS_AGAIN); /* empty socket: would block */
    CHECK(ms_sys_net_write(c, "hello", 5, &n) == MS_SYS_OK && n == 5);
    int r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = ms_sys_net_read(s, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_OK && n == 5 && !memcmp(buf, "hello", 5));
    CHECK(ms_sys_net_write(s, "world!", 6, &n) == MS_SYS_OK && n == 6);
    r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = ms_sys_net_read(c, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_OK && n == 6 && !memcmp(buf, "world!", 6));

    /* peer address matches, half close shows as end of file, then a write to a closed peer fails without a signal */
    CHECK(ms_sys_net_peer_addr(c, &peer) == MS_SYS_OK && peer.port == bound.port);
    CHECK(ms_sys_net_shutdown(c, 1) == MS_SYS_OK);
    r = MS_SYS_AGAIN;
    for (int i = 0; i < 2000 && r == MS_SYS_AGAIN; i++) { r = ms_sys_net_read(s, buf, sizeof buf, &n); if (r == MS_SYS_AGAIN) nap(); }
    CHECK(r == MS_SYS_EOF && n == 0);
    ms_sys_net_close(c);
    int w = MS_SYS_OK;
    for (int i = 0; i < 200 && w == MS_SYS_OK; i++) { w = ms_sys_net_write(s, "x", 1, &n); nap(); }
    CHECK(w == MS_SYS_ERROR && ms_sys_net_error() != 0);
    ms_sys_net_close(s);
    ms_sys_net_close(l);

    /* nobody listens there now: the connection fails, at once or after the wait */
    rc = ms_sys_net_tcp_connect(&bound, &c);
    if (rc == MS_SYS_INPROGRESS) {
        int d = MS_SYS_OK;
        for (int i = 0; i < 2000; i++) { d = ms_sys_net_connect_done(c); if (d == MS_SYS_ERROR) break; nap(); }
        CHECK(d == MS_SYS_ERROR);
        ms_sys_net_close(c);
    } else CHECK(rc == MS_SYS_ERROR);

    /* IPv6 loopback, when the machine has it */
    MsAddr lo6 = {6, {0}, 0, 0}; lo6.ip[15] = 1;
    MsSock l6;
    if (ms_sys_net_tcp_listen(&lo6, 4, &l6) == MS_SYS_OK) {
        CHECK(ms_sys_net_local_addr(l6, &bound) == MS_SYS_OK && bound.family == 6 && bound.ip[15] == 1 && bound.port != 0);
        ms_sys_net_close(l6);
    }
    /* a listener on :: accepts IPv4 clients too (dual stack), when the machine has IPv6 */
    MsAddr any6 = {6, {0}, 0, 0}, v4;
    MsSock d, dc, da;
    if (ms_sys_net_tcp_listen(&any6, 4, &d) == MS_SYS_OK) {
        CHECK(ms_sys_net_local_addr(d, &bound) == MS_SYS_OK);
        v4 = lo; v4.port = bound.port;
        rc = ms_sys_net_tcp_connect(&v4, &dc);
        CHECK(rc == MS_SYS_OK || rc == MS_SYS_INPROGRESS);
        got = MS_SYS_AGAIN;
        for (int i = 0; i < 2000 && got == MS_SYS_AGAIN; i++) { got = ms_sys_net_accept(d, &da, &peer); if (got == MS_SYS_AGAIN) nap(); }
        CHECK(got == MS_SYS_OK);
        ms_sys_net_close(da); ms_sys_net_close(dc); ms_sys_net_close(d);
    }
    /* resolver addresses: IPv4 and IPv6 sockaddrs read back, a short or foreign one refused */
    struct sockaddr_in raw4 = {0};
    raw4.sin_family = AF_INET; raw4.sin_port = htons(8080); raw4.sin_addr.s_addr = htonl(0x7f000001);
    MsAddr parsed;
    CHECK(ms_sys_net_addr_from_raw(&raw4, sizeof raw4, &parsed) == 0 && parsed.family == 4 && parsed.port == 8080);
    CHECK(parsed.ip[0] == 127 && parsed.ip[3] == 1);
    struct sockaddr_in6 raw6 = {0};
    raw6.sin6_family = AF_INET6; raw6.sin6_port = htons(443); raw6.sin6_addr.s6_addr[15] = 1; raw6.sin6_scope_id = 3;
    CHECK(ms_sys_net_addr_from_raw(&raw6, sizeof raw6, &parsed) == 0 && parsed.family == 6 && parsed.port == 443);
    CHECK(parsed.ip[15] == 1 && parsed.scope == 3);
    CHECK(ms_sys_net_addr_from_raw(&raw6, sizeof raw4, &parsed) == -1); /* an IPv6 address cut short */
    raw4.sin_family = AF_UNIX;
    CHECK(ms_sys_net_addr_from_raw(&raw4, sizeof raw4, &parsed) == -1);
    CHECK(ms_sys_net_addr_from_raw(&raw4, 1, &parsed) == -1);
    if (!failed) printf("sys net ok\n");
    return failed;
}
