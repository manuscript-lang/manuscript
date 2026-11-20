/* Tests for runtime/net/datagram.c over loopback: bind, send and receive between two sockets, the size limits, a
 * timeout, a bad address and close. The task wait is a test double that polls, since there is no scheduler. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#define poll_sockets(fds, count, ms) WSAPoll((fds), (ULONG)(count), (ms))
typedef WSAPOLLFD PollFd;
typedef SOCKET PollHandle;
#else
#include <poll.h>
#define poll_sockets(fds, count, ms) poll((fds), (nfds_t)(count), (ms))
typedef struct pollfd PollFd;
typedef int PollHandle;
#endif

#include "../std/abi.h"
#include "ms_rt/net.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

__attribute__((weak)) bool ms_sched_cancel_pending(void) { return false; }
__attribute__((weak)) int64_t ms_sched_defer_deadline(void) { return INT64_MAX; }
void ms_sched_cancel_return(void) {}

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    PollFd p = {.fd = (PollHandle)fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    const int r = poll_sockets(&p, 1, ms);
    if (r == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

static MsStr text(const char *s) { MsStr out; msrt_string_from_bytes((const uint8_t *)s, strlen(s), &out); return out; }

static void *bind_loopback(void) {
    MsStr any = text("127.0.0.1:0"), err = text("");
    void *socket = NULL;
    CHECK(msstd_dgram_bind(&any, &socket, &err) == STATUS_OK);
    return socket;
}

int main(void) {
    void *a = bind_loopback(), *b = bind_loopback();
    MsStr err = text("");
    MsStr to_b; msstd_dgram_address(b, &to_b);
    CHECK(msrt_str_len(&to_b) > 10 && memcmp(msrt_str_data(&to_b), "127.0.0.1:", 10) == 0);

    /* a datagram arrives whole, with the sender's address */
    MsVec payload; msrt_write_bytes(&payload, (const uint8_t *)"hello", 5);
    CHECK(msstd_dgram_send(a, &payload, &to_b, 0, 0, &err) == STATUS_OK);
    MsNetDatagram got;
    CHECK(msstd_dgram_receive(b, 0, 0, 1, 2000000000, &got, &err) == STATUS_OK);
    CHECK(got.data.len == 5 && memcmp(got.data.ptr, "hello", 5) == 0);
    msrt_free(got.data.ptr);
    MsStr from_a; msstd_dgram_address(a, &from_a);
    CHECK(msrt_str_len(&got.sender) == msrt_str_len(&from_a) && memcmp(msrt_str_data(&got.sender), msrt_str_data(&from_a), msrt_str_len(&from_a)) == 0);

    /* an empty datagram is a datagram */
    MsVec empty; msrt_write_bytes(&empty, NULL, 0);
    CHECK(msstd_dgram_send(a, &empty, &to_b, 0, 0, &err) == STATUS_OK);
    CHECK(msstd_dgram_receive(b, 0, 0, 1, 2000000000, &got, &err) == STATUS_OK && got.data.len == 0);

    /* a datagram over the limit is dropped and reported; the next one is read */
    CHECK(msstd_dgram_send(a, &payload, &to_b, 0, 0, &err) == STATUS_OK);
    CHECK(msstd_dgram_receive(b, 1, 4, 1, 2000000000, &got, &err) == STATUS_LIMIT_EXCEEDED);
    CHECK(msstd_dgram_send(a, &payload, &to_b, 0, 0, &err) == STATUS_OK);
    CHECK(msstd_dgram_receive(b, 1, 5, 1, 2000000000, &got, &err) == STATUS_OK && got.data.len == 5);
    msrt_free(got.data.ptr);
    CHECK(msstd_dgram_receive(b, 1, 0, 0, 0, &got, &err) == STATUS_INVALID_INPUT);
    CHECK(msstd_dgram_receive(b, 1, 65536, 0, 0, &got, &err) == STATUS_INVALID_INPUT);

    /* nothing to read ends by the timeout */
    CHECK(msstd_dgram_receive(b, 0, 0, 1, 50000000, &got, &err) == STATUS_TIMED_OUT);

    /* a bad address and an oversize payload are refused before anything is sent */
    MsStr name = text("example.test:80"), nothing = text("");
    CHECK(msstd_dgram_send(a, &payload, &name, 0, 0, &err) == STATUS_INVALID_INPUT);
    CHECK(msstd_dgram_bind(&nothing, &(void *){NULL}, &err) == STATUS_INVALID_INPUT);
    uint8_t *big = calloc(65536, 1);
    MsVec huge; msrt_write_bytes(&huge, big, 65536);
    free(big);
    CHECK(msstd_dgram_send(a, &huge, &to_b, 0, 0, &err) == STATUS_LIMIT_EXCEEDED);
    msrt_free(huge.ptr);

    /* ends: the socket stays open until the last end closes; close ends all use */
    void *a2 = msstd_dgram_share(a);
    msstd_dgram_close_if_last(a);
    CHECK(msstd_dgram_send(a2, &payload, &to_b, 0, 0, &err) == STATUS_OK);
    msstd_dgram_close_if_last(a2);
    CHECK(msstd_dgram_send(a2, &payload, &to_b, 0, 0, &err) == STATUS_CLOSED);
    msstd_dgram_close(b);
    CHECK(msstd_dgram_receive(b, 0, 0, 0, 0, &got, &err) == STATUS_CLOSED);
    MsStr closed; msstd_dgram_address(b, &closed);
    CHECK(msrt_str_len(&closed) == 0);

    msrt_free(payload.ptr);
    ((MsObj *)a)->drop(a);
    ((MsObj *)a2)->drop(a2);
    ((MsObj *)b)->drop(b);
    if (!failed) printf("datagram ok\n");
    return failed;
}
