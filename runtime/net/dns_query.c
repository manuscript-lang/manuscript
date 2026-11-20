/* The DNS natives: one query to one server (UDP, then TCP when the answer is truncated) and the host's resolver
 * configuration. Which servers to ask, the search list and the policy checks around them are standard-library code.
 * Waits park the task (ms_net_wait_fd), so a stop request ends them. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "addr_text.h"
#include "dns.h"
#include "dns_query.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "status.h"

enum { UDP_MESSAGE = 4096, TCP_MESSAGE = 65535, CONFIG_TEXT = 8192 };

static const int64_t default_timeout_ns = 5000000000LL;

static bool same_server(const MsAddr *a, const MsAddr *b) {
    return a->family == b->family && a->port == b->port && memcmp(a->ip, b->ip, a->family == 4 ? 4 : 16) == 0;
}

/* Sends `query` to `server` and waits for the answer that carries `id`. */
static MsNetStatus exchange_udp(const MsAddr *server, const uint8_t *query, size_t length, uint16_t id, int64_t deadline_ns,
                                uint8_t *reply, size_t *reply_length, int *code) {
    MsAddr any = {.family = server->family};
    MsSock fd = MS_SOCK_INVALID;
    if (ms_sys_net_udp_bind(&any, &fd) != MS_SYS_OK) {
        *code = ms_sys_net_error();
        return MS_NET_FAILED;
    }
    MsNetStatus status = MS_NET_OK;
    size_t sent = 0;
    if (ms_sys_net_udp_send(fd, query, length, server, &sent) != MS_SYS_OK) {
        *code = ms_sys_net_error();
        status = MS_NET_FAILED;
    }
    while (status == MS_NET_OK) {
        MsAddr from;
        size_t count = 0;
        const int result = ms_sys_net_udp_recv(fd, reply, UDP_MESSAGE, &count, &from);
        if (result == MS_SYS_OK && count >= 2 && same_server(&from, server) && ((reply[0] << 8) | reply[1]) == id) {
            *reply_length = count;
            break;
        }
        if (result == MS_SYS_AGAIN) {
            status = ms_net_wait_fd(fd, MS_WAIT_READ, deadline_ns);
        } else if (result == MS_SYS_ERROR) {
            *code = ms_sys_net_error();
            status = MS_NET_FAILED;
        }
    }
    ms_sys_net_close(fd);
    return status;
}

/* Writes all of data[length] to the stream. */
static MsNetStatus write_all(MsSock fd, const uint8_t *data, size_t length, int64_t deadline_ns, int *code) {
    for (size_t sent = 0; sent < length;) {
        size_t done = 0;
        const int result = ms_sys_net_write(fd, data + sent, length - sent, &done);
        if (result == MS_SYS_OK) {
            sent += done;
        } else if (result == MS_SYS_AGAIN) {
            const MsNetStatus waited = ms_net_wait_fd(fd, MS_WAIT_WRITE, deadline_ns);
            if (waited != MS_NET_OK) {
                return waited;
            }
        } else {
            *code = ms_sys_net_error();
            return MS_NET_FAILED;
        }
    }
    return MS_NET_OK;
}

/* Reads exactly `length` bytes. */
static MsNetStatus read_all(MsSock fd, uint8_t *data, size_t length, int64_t deadline_ns, int *code) {
    for (size_t got = 0; got < length;) {
        size_t done = 0;
        const int result = ms_sys_net_read(fd, data + got, length - got, &done);
        if (result == MS_SYS_OK) {
            got += done;
        } else if (result == MS_SYS_AGAIN) {
            const MsNetStatus waited = ms_net_wait_fd(fd, MS_WAIT_READ, deadline_ns);
            if (waited != MS_NET_OK) {
                return waited;
            }
        } else {
            *code = result == MS_SYS_EOF ? 0 : ms_sys_net_error();
            return MS_NET_FAILED;
        }
    }
    return MS_NET_OK;
}

/* The same exchange over TCP, for an answer that did not fit a datagram: a two-byte length before each message. */
static MsNetStatus exchange_tcp(const MsAddr *server, const uint8_t *query, size_t length, int64_t deadline_ns,
                                uint8_t *reply, size_t *reply_length, int *code) {
    MsSock fd = MS_SOCK_INVALID;
    const int started = ms_sys_net_tcp_connect(server, &fd);
    if (started == MS_SYS_ERROR) {
        *code = ms_sys_net_error();
        return MS_NET_FAILED;
    }
    MsNetStatus status = MS_NET_OK;
    if (started == MS_SYS_INPROGRESS) {
        status = ms_net_wait_fd(fd, MS_WAIT_WRITE, deadline_ns);
        if (status == MS_NET_OK && ms_sys_net_connect_done(fd) != MS_SYS_OK) {
            *code = ms_sys_net_error();
            status = MS_NET_FAILED;
        }
    }
    uint8_t prefix[2] = {(uint8_t)(length >> 8), (uint8_t)length};
    if (status == MS_NET_OK) {
        status = write_all(fd, prefix, 2, deadline_ns, code);
    }
    if (status == MS_NET_OK) {
        status = write_all(fd, query, length, deadline_ns, code);
    }
    if (status == MS_NET_OK) {
        status = read_all(fd, prefix, 2, deadline_ns, code);
    }
    const size_t size = (size_t)((prefix[0] << 8) | prefix[1]);
    if (status == MS_NET_OK) {
        status = read_all(fd, reply, size, deadline_ns, code);
        *reply_length = size;
    }
    ms_sys_net_close(fd);
    return status;
}

/* Fills the native's lists from the records of one kind: the values, and three numbers a record (priority, weight,
 * port). */
static void write_records(const MsDnsResponse *response, uint16_t type, MsVec *values, MsVec *numbers) {
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)response->count, values);
    msrt_list_with_capacity(&msrt_desc_int, (int64_t)response->count * 3, numbers);
    for (size_t i = 0; i < response->count; i++) {
        const MsDnsRecord *record = &response->records[i];
        if (record->type != type) {
            continue;
        }
        MsStr text;
        msrt_string_from_bytes((const uint8_t *)record->value, record->length, &text);
        msrt_list_push(values, &msrt_desc_string, (const uint8_t *)&text);
        const int64_t three[3] = {record->priority, record->weight, record->port};
        for (size_t k = 0; k < 3; k++) {
            msrt_list_push(numbers, &msrt_desc_int, (const uint8_t *)&three[k]);
        }
    }
}

static bool wanted_type(int64_t type) {
    return type == MS_DNS_A || type == MS_DNS_AAAA || type == MS_DNS_CNAME || type == MS_DNS_MX || type == MS_DNS_NS ||
           type == MS_DNS_PTR || type == MS_DNS_SRV || type == MS_DNS_TXT;
}

uint8_t msstd_dns_query(const MsStr *server, const MsStr *name, int64_t type, uint8_t has_timeout, int64_t timeout,
                        MsVec *values, MsVec *numbers, MsStr *err) {
    ms_net_clear_text(err);
    MsAddr target;
    const MsBytes name_bytes = msrt_str_bytes(name);
    if (!ms_net_addr_parse(msrt_str_bytes(server), &target) ||
        !wanted_type(type)) {
        return STATUS_INVALID_INPUT;
    }
    const uint16_t id = (uint16_t)ms_sys_fs_random();
    uint8_t query[MS_DNS_QUERY_MAX];
    const size_t length = ms_dns_build_query(query, id, name_bytes, (uint16_t)type);
    if (length == 0) {
        return STATUS_INVALID_INPUT;
    }
    int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    if (deadline < 0) {
        deadline = ms_sys_monotonic_ns() + default_timeout_ns; /* a lost datagram must not wait forever */
    }
    uint8_t *reply = malloc(TCP_MESSAGE);
    if (reply == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    size_t reply_length = 0;
    int code = 0;
    MsNetStatus status = exchange_udp(&target, query, length, id, deadline, reply, &reply_length, &code);
    MsDnsResponse response = {0};
    bool parsed = status == MS_NET_OK && ms_dns_parse_response(ms_bytes_of(reply, reply_length), &response);
    if (parsed && response.truncated) {
        ms_dns_response_free(&response);
        status = exchange_tcp(&target, query, length, deadline, reply, &reply_length, &code);
        parsed = status == MS_NET_OK && ms_dns_parse_response(ms_bytes_of(reply, reply_length), &response);
    }
    free(reply);
    if (status != MS_NET_OK) {
        return ms_net_finish(status, code, err);
    }
    if (!parsed) {
        ms_net_write_text(err, "malformed DNS response");
        return STATUS_FAILED;
    }
    uint8_t result = STATUS_OK;
    if (response.rcode == 3) {
        result = STATUS_NONE;
    } else if (response.rcode != 0) {
        char text[300];
        (void)snprintf(text, sizeof text, "cannot resolve host \"%.*s\"", (int)name_bytes.len > 200 ? 200 : (int)name_bytes.len,
                       (const char *)name_bytes.ptr);
        ms_net_write_text(err, text);
        result = STATUS_FAILED;
    } else {
        write_records(&response, (uint16_t)type, values, numbers);
        if (values->len == 0) { /* records of other kinds only */
            msrt_list_drop(values, &msrt_desc_string);
            msrt_list_drop(numbers, &msrt_desc_int);
            result = STATUS_NONE;
        }
    }
    ms_dns_response_free(&response);
    return result;
}

uint8_t msstd_dns_config(MsVec *servers, MsVec *search, int64_t *ndots) {
    char *text = malloc(CONFIG_TEXT);
    MsDnsConfig *config = malloc(sizeof *config);
    if (text == NULL || config == NULL) {
        free(text);
        free(config);
        return STATUS_FAILED;
    }
    const size_t length = ms_sys_net_dns_config(text, CONFIG_TEXT);
    ms_dns_config_parse(ms_bytes_of((const uint8_t *)text, length), config);
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)config->server_count, servers);
    for (size_t i = 0; i < config->server_count; i++) {
        char address[MS_NET_ADDR_TEXT_MAX];
        size_t used = 0;
        MsStr item;
        if (ms_net_addr_format(&config->servers[i], address, sizeof address, &used)) {
            msrt_string_from_bytes((const uint8_t *)address, used, &item);
            msrt_list_push(servers, &msrt_desc_string, (const uint8_t *)&item);
        }
    }
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)config->search_count, search);
    for (size_t i = 0; i < config->search_count; i++) {
        MsStr item;
        msrt_string_from_bytes((const uint8_t *)config->search[i], strlen(config->search[i]), &item);
        msrt_list_push(search, &msrt_desc_string, (const uint8_t *)&item);
    }
    *ndots = config->ndots;
    free(text);
    free(config);
    return STATUS_OK;
}
