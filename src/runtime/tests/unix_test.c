/* Tests for the Unix domain socket natives (src/runtime/net/unix.c) and the listener over one: listen, dial, accept, a
 * message each way, the listener's address, the file removed with the listener, and the refused paths. The task wait is
 * a test double on poll(2) (WSAPoll on Windows). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <process.h>
#include <winsock2.h>
#define poll_sockets(fds, count, ms) WSAPoll((fds), (ULONG)(count), (ms))
#define current_pid _getpid
typedef WSAPOLLFD PollFd;
typedef SOCKET PollHandle;
#else
#include <poll.h>
#include <unistd.h>
#define poll_sockets(fds, count, ms) poll((fds), (nfds_t)(count), (ms))
#define current_pid getpid
typedef struct pollfd PollFd;
typedef int PollHandle;
#endif

#include "../net/conn_object.h"
#include "../net/listener.h"
#include "ms_rt/net.h"
#include "../std/abi.h"
#include "ms_rt/net.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

__attribute__((weak)) bool ms_sched_cancel_pending(void) { return false; }
__attribute__((weak)) int64_t ms_sched_defer_deadline(void) { return INT64_MAX; }
void ms_sched_cancel_return(void) {}

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    PollFd p = {.fd = (PollHandle)fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    if (poll_sockets(&p, 1, ms) == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

static MsStr str(const char *s) { MsStr out; msrt_string_from_bytes((const uint8_t *)s, strlen(s), &out); return out; }
static bool is_str(const MsStr *s, const char *want) { return msrt_str_len(s) == strlen(want) && memcmp(msrt_str_data(s), want, strlen(want)) == 0; }

/* The natives with their error text released, since each failure writes one. */
static uint8_t listen_at(const MsStr *path, void **out) {
    MsStr err = str("");
    const uint8_t status = msstd_net_listen_unix(path, out, &err);
    ms_str_release(&err);
    return status;
}

static uint8_t dial_at(const MsStr *path, void **out) {
    MsStr err = str("");
    const uint8_t status = msstd_net_dial_unix(path, out, &err);
    ms_str_release(&err);
    return status;
}

static bool exists(const char *path) {
    MsSysStat info;
    return ms_sys_fs_stat(path, false, &info) == 0;
}

int main(void) {
    char path[64];
    snprintf(path, sizeof path, "ms_unix_test_%d.sock", (int)current_pid()); /* relative: sun_path is short */
    const MsSysError stale = ms_sys_fs_unlink(path); /* a file left by an earlier run */
    (void)stale;
    MsStr where = str(path), err = str("");
    (void)err;
    void *listener = NULL, *client = NULL, *server = NULL, *again = NULL;

    CHECK(listen_at(&where, &listener) == STATUS_OK && listener != NULL);
    CHECK(exists(path));
    MsStr address; msstd_listener_address(listener, &address);
    CHECK(is_str(&address, path));
    CHECK(listen_at(&where, &again) == STATUS_FAILED); /* the file is there */

    CHECK(dial_at(&where, &client) == STATUS_OK && client != NULL);
    CHECK(msstd_listener_accept(listener, 1, 3000000000, &server, &err) == STATUS_OK && server != NULL);

    const MsNetConn *from_client = ms_netconn_of(client);
    const MsNetConn *at_server = ms_netconn_of(server);
    CHECK(ms_conn_write(ms_netconn_table(from_client), ms_netconn_id(from_client), (const uint8_t *)"ping", 4, -1) == MS_NET_OK);
    uint8_t buffer[16];
    size_t count = 0;
    CHECK(ms_conn_read(ms_netconn_table(at_server), ms_netconn_id(at_server), buffer, sizeof buffer, ms_sys_monotonic_ns() + 3000000000LL, &count) == MS_NET_OK);
    CHECK(count == 4 && memcmp(buffer, "ping", 4) == 0);
    CHECK(ms_conn_shutdown_write(ms_netconn_table(from_client), ms_netconn_id(from_client), -1) == MS_NET_OK);
    CHECK(ms_conn_read(ms_netconn_table(at_server), ms_netconn_id(at_server), buffer, sizeof buffer, ms_sys_monotonic_ns() + 3000000000LL, &count) == MS_NET_OK && count == 0); /* the end of the stream */

    ((MsObj *)server)->drop(server);
    ((MsObj *)client)->drop(client);
    ((MsObj *)listener)->drop(listener);
    CHECK(!exists(path)); /* removed with the listener */
    CHECK(dial_at(&where, &client) == STATUS_FAILED); /* nobody is there */

    /* refused paths */
    MsStr empty = str("");
    MsStr too_long = str("this_path_is_much_longer_than_any_system_allows_for_a_unix_domain_socket_path_so_it_must_fail_to_bind_or_connect_both.sock");
    CHECK(listen_at(&empty, &listener) == STATUS_INVALID_INPUT);
    CHECK(dial_at(&empty, &client) == STATUS_INVALID_INPUT);
    CHECK(listen_at(&too_long, &listener) == STATUS_FAILED);
    CHECK(dial_at(&too_long, &client) == STATUS_FAILED);

    ms_str_release(&where); ms_str_release(&address); ms_str_release(&empty); ms_str_release(&too_long); ms_str_release(&err);
    if (!failed) printf("unix ok\n");
    return failed;
}
