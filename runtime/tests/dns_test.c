/* Tests for runtime/net/dns.c and dns_query.c: the wire format against hand-built messages, the resolv.conf reader,
 * and queries over loopback against a server thread that answers every kind (and sends a truncated answer over UDP and
 * the full one over TCP). The task wait is a test double on poll(2) (WSAPoll on Windows). */
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

#include "../net/dns.h"
#include "../net/dns_query.h"
#include "../std/abi.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

__attribute__((weak)) bool ms_sched_cancel_pending(void) { return false; }
void ms_sched_cancel_return(void) {}

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    PollFd p = {.fd = (PollHandle)fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    if (poll_sockets(&p, 1, ms) == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

#define LITERAL(text) ms_bytes_of((const uint8_t *)(text), sizeof(text) - 1)

static void drop_lists(MsVec *values, MsVec *numbers) {
    msrt_list_drop(values, &msrt_desc_string);
    msrt_list_drop(numbers, &msrt_desc_int);
}

static MsStr str(const char *s) { MsStr out; msrt_string_from_bytes((const uint8_t *)s, strlen(s), &out); return out; }
static bool is_str(const MsVec *list, size_t i, const char *want) {
    const MsStr *items = list->ptr;
    return i < list->len && msrt_str_len(&items[i]) == strlen(want) && memcmp(msrt_str_data(&items[i]), want, strlen(want)) == 0;
}
static int64_t number(const MsVec *list, size_t i) { return ((const int64_t *)list->ptr)[i]; }

/* ---- a fake server ---- */

typedef struct Server {
    MsSock udp;
    MsSock tcp; /* invalid unless the answer is sent truncated and repeated over TCP */
    int queries;
} Server;

/* Appends the answer of `type` for the question in query[0, qend) to out[at]; returns the new length. */
static size_t answer(uint8_t *out, size_t at, const uint8_t *query, size_t qend, uint16_t type, bool truncated) {
    memcpy(out, query, 2);
    memcpy(out + 2, truncated ? "\x83\x80" : "\x81\x80", 2); /* QR RD RA, and TC for a truncated one */
    memcpy(out + 4, truncated ? "\0\1\0\0\0\0\0\0" : "\0\1\0\1\0\0\0\0", 8);
    memcpy(out + 12, query + 12, qend - 12);
    at = qend;
    if (truncated) return at;
    memcpy(out + at, "\xC0\x0C", 2); at += 2;
    out[at++] = (uint8_t)(type >> 8); out[at++] = (uint8_t)type;
    memcpy(out + at, "\0\1\0\0\0\x1E", 6); at += 6;
    static const uint8_t mx[] = {0, 10, 4, 'm', 'a', 'i', 'l', 4, 't', 'e', 's', 't', 0};
    static const uint8_t srv[] = {0, 1, 0, 2, 1, 0xBB, 7, 's', 'e', 'r', 'v', 'i', 'c', 'e', 4, 't', 'e', 's', 't', 0};
    static const uint8_t host[] = {2, 'n', 's', 4, 't', 'e', 's', 't', 0};
    static const uint8_t txt[] = {5, 'h', 'e', 'l', 'l', 'o', 2, ' ', 'w'};
    static const uint8_t a[] = {127, 0, 0, 1};
    static const uint8_t aaaa[] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
    const uint8_t *data = a; size_t size = sizeof a;
    switch (type) {
    case MS_DNS_AAAA: data = aaaa; size = sizeof aaaa; break;
    case MS_DNS_MX: data = mx; size = sizeof mx; break;
    case MS_DNS_SRV: data = srv; size = sizeof srv; break;
    case MS_DNS_TXT: data = txt; size = sizeof txt; break;
    case MS_DNS_NS: case MS_DNS_CNAME: case MS_DNS_PTR: data = host; size = sizeof host; break;
    default: break;
    }
    out[at++] = (uint8_t)(size >> 8); out[at++] = (uint8_t)size;
    memcpy(out + at, data, size);
    return at + size;
}

static size_t question_end(const uint8_t *query, size_t length) {
    size_t at = 12;
    while (at < length && query[at] != 0) at += (size_t)query[at] + 1;
    return at + 5;
}

static void serve(void *argument) {
    Server *server = argument;
    for (int served = 0; served < server->queries; served++) {
        uint8_t query[512], out[600];
        MsAddr from;
        size_t count = 0;
        while (ms_sys_net_udp_recv(server->udp, query, sizeof query, &count, &from) == MS_SYS_AGAIN) {
            PollFd p = {.fd = (PollHandle)server->udp, .events = POLLIN};
            poll_sockets(&p, 1, 100);
        }
        const size_t qend = question_end(query, count);
        const uint16_t type = (uint16_t)((query[qend - 4] << 8) | query[qend - 3]);
        const bool over_tcp = server->tcp != MS_SOCK_INVALID && type == MS_DNS_TXT;
        size_t length = answer(out, 0, query, qend, type, over_tcp);
        size_t sent = 0;
        (void)ms_sys_net_udp_send(server->udp, out, length, &from, &sent);
        if (over_tcp) { /* the same question again, over TCP, answered in full */
            MsSock peer = MS_SOCK_INVALID;
            while (ms_sys_net_accept(server->tcp, &peer, NULL) == MS_SYS_AGAIN) {
                PollFd p = {.fd = (PollHandle)server->tcp, .events = POLLIN};
                poll_sockets(&p, 1, 100);
            }
            uint8_t framed[600];
            size_t got = 0;
            while (got < 2 || got < 2 + (size_t)((framed[0] << 8) | framed[1])) {
                size_t done = 0;
                if (ms_sys_net_read(peer, framed + got, sizeof framed - got, &done) == MS_SYS_AGAIN) {
                    PollFd p = {.fd = (PollHandle)peer, .events = POLLIN};
                    poll_sockets(&p, 1, 100);
                } else {
                    got += done;
                }
            }
            length = answer(out + 2, 0, framed + 2, question_end(framed + 2, got - 2), type, false);
            out[0] = (uint8_t)(length >> 8); out[1] = (uint8_t)length;
            (void)ms_sys_net_write(peer, out, length + 2, &sent);
            ms_sys_net_close(peer);
        }
    }
}

static MsStr server_text(MsSock udp) {
    MsAddr bound; char text[64]; MsStr out;
    CHECK(ms_sys_net_local_addr(udp, &bound) == MS_SYS_OK);
    snprintf(text, sizeof text, "127.0.0.1:%u", bound.port);
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &out);
    return out;
}

int main(void) {
    /* the query a resolver sends */
    uint8_t query[MS_DNS_QUERY_MAX];
    const size_t length = ms_dns_build_query(query, 0x1234, LITERAL("a.example.test."), MS_DNS_MX);
    static const uint8_t want[] = {0x12, 0x34, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 'a', 7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 4, 't', 'e', 's', 't', 0, 0, 15, 0, 1};
    CHECK(length == sizeof want && memcmp(query, want, length) == 0);
    CHECK(ms_dns_build_query(query, 1, LITERAL("a..b"), MS_DNS_A) == 0);
    CHECK(ms_dns_build_query(query, 1, LITERAL("0123456789012345678901234567890123456789012345678901234567890123456.x"), MS_DNS_A) == 0);
    CHECK(ms_dns_build_query(query, 1, LITERAL("."), MS_DNS_A) == 17); /* the root */

    /* a response with a compressed name, an MX and a hostile pointer loop */
    {
        static const uint8_t message[] = {0, 1, 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0, 1, 'x', 0, 0, 15, 0, 1,
                                          0xC0, 12, 0, 15, 0, 1, 0, 0, 0, 30, 0, 7, 0, 5, 2, 'm', 'x', 0xC0, 12};
        MsDnsResponse response;
        CHECK(ms_dns_parse_response(ms_bytes_of(message, sizeof message), &response));
        CHECK(response.rcode == 0 && !response.truncated && response.count == 1);
        CHECK(response.records[0].type == MS_DNS_MX && response.records[0].priority == 5 && strcmp(response.records[0].value, "mx.x.") == 0);
        ms_dns_response_free(&response);
        uint8_t loop[sizeof message];
        memcpy(loop, message, sizeof message);
        loop[sizeof message - 2] = 0xC0; loop[sizeof message - 1] = (uint8_t)(sizeof message - 2);
        CHECK(!ms_dns_parse_response(ms_bytes_of(loop, sizeof loop), &response));
        CHECK(!ms_dns_parse_response(ms_bytes_of(message, 20), &response));
        CHECK(!ms_dns_parse_response(LITERAL("\0\1\0\0\0\0\0\0\0\0\0\0"), &response)); /* not a response */
    }

    /* resolv.conf */
    {
        MsDnsConfig config;
        ms_dns_config_parse(LITERAL("# c\nnameserver 10.0.0.1 ; x\nnameserver ::1\nnameserver bad\ndomain old.test\nsearch a.test. b.test\noptions ndots:3 timeout:1\n"), &config);
        CHECK(config.server_count == 2 && config.servers[0].family == 4 && config.servers[0].port == 53 && config.servers[1].family == 6);
        CHECK(config.search_count == 2 && strcmp(config.search[0], "a.test") == 0 && strcmp(config.search[1], "b.test") == 0 && config.ndots == 3);
        ms_dns_config_parse(LITERAL("domain only.test\n"), &config);
        CHECK(config.server_count == 2 && config.search_count == 1 && strcmp(config.search[0], "only.test") == 0 && config.ndots == 1);
    }

    /* queries against the fake server */
    {
        Server server = {.tcp = MS_SOCK_INVALID, .queries = 8};
        MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
        CHECK(ms_sys_net_udp_bind(&loopback, &server.udp) == MS_SYS_OK);
        CHECK(ms_sys_net_local_addr(server.udp, &bound) == MS_SYS_OK);
        CHECK(ms_sys_net_tcp_listen(&bound, 2, &server.tcp) == MS_SYS_OK); /* the same port number over TCP */
        MsSysThread *thread = ms_sys_thread_spawn(1 << 20, serve, &server);
        CHECK(thread != NULL);
        const MsStr at = server_text(server.udp), name = str("test.");
        MsVec values, numbers;
        MsStr err = str("");
        CHECK(msstd_dns_query(&at, &name, MS_DNS_A, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "127.0.0.1"));
        drop_lists(&values, &numbers);
        CHECK(msstd_dns_query(&at, &name, MS_DNS_AAAA, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "::1"));
        drop_lists(&values, &numbers);
        CHECK(msstd_dns_query(&at, &name, MS_DNS_MX, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "mail.test.") && number(&numbers, 0) == 10);
        drop_lists(&values, &numbers);
        CHECK(msstd_dns_query(&at, &name, MS_DNS_SRV, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "service.test.") &&
              number(&numbers, 0) == 1 && number(&numbers, 1) == 2 && number(&numbers, 2) == 443);
        drop_lists(&values, &numbers);
        CHECK(msstd_dns_query(&at, &name, MS_DNS_NS, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "ns.test."));
        drop_lists(&values, &numbers);
        CHECK(msstd_dns_query(&at, &name, MS_DNS_CNAME, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "ns.test."));
        drop_lists(&values, &numbers);
        CHECK(msstd_dns_query(&at, &name, MS_DNS_PTR, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "ns.test."));
        drop_lists(&values, &numbers);
        CHECK(msstd_dns_query(&at, &name, MS_DNS_TXT, 1, 3000000000, &values, &numbers, &err) == STATUS_OK && is_str(&values, 0, "hello w")); /* truncated over UDP, whole over TCP */
        drop_lists(&values, &numbers);
        ms_sys_thread_join(thread);
        ms_sys_net_close(server.udp);
        ms_sys_net_close(server.tcp);

        /* nobody answers: the deadline ends it; a bad server, name or type is refused first */
        MsAddr silent_at; MsSock silent;
        CHECK(ms_sys_net_udp_bind(&loopback, &silent) == MS_SYS_OK && ms_sys_net_local_addr(silent, &silent_at) == MS_SYS_OK);
        const MsStr silent_text = server_text(silent), bad = str("not-an-address");
        CHECK(msstd_dns_query(&silent_text, &name, MS_DNS_A, 1, 100000000, &values, &numbers, &err) == STATUS_TIMED_OUT);
        CHECK(msstd_dns_query(&bad, &name, MS_DNS_A, 0, 0, &values, &numbers, &err) == STATUS_INVALID_INPUT);
        CHECK(msstd_dns_query(&at, &name, 99, 0, 0, &values, &numbers, &err) == STATUS_INVALID_INPUT);
        const MsStr hole = str("a..b");
        CHECK(msstd_dns_query(&at, &hole, MS_DNS_A, 0, 0, &values, &numbers, &err) == STATUS_INVALID_INPUT);
        ms_sys_net_close(silent);
        ms_str_release(&at); ms_str_release(&name); ms_str_release(&err); ms_str_release(&silent_text); ms_str_release(&bad); ms_str_release(&hole);
    }

    /* the host's configuration always names a server */
    {
        MsVec servers, search;
        int64_t ndots = 0;
        CHECK(msstd_dns_config(&servers, &search, &ndots) == STATUS_OK && servers.len >= 1 && ndots >= 0);
        msrt_list_drop(&servers, &msrt_desc_string);
        msrt_list_drop(&search, &msrt_desc_string);
    }

    if (!failed) printf("dns ok\n");
    return failed;
}
