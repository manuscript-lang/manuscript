/* The DNS wire format, without any I/O: building a recursive query and reading a response, and reading the host's
 * resolver configuration in resolv.conf form. The record kinds are the ones the standard library exposes: A, AAAA,
 * CNAME, MX, NS, PTR, SRV and TXT (others in an answer are skipped). dns_query.c sends the queries. */
#ifndef MS_NET_DNS_H
#define MS_NET_DNS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/safe.h"
#include "ms_rt/sys_net.h"

enum {
    MS_DNS_A = 1,
    MS_DNS_NS = 2,
    MS_DNS_CNAME = 5,
    MS_DNS_PTR = 12,
    MS_DNS_MX = 15,
    MS_DNS_TXT = 16,
    MS_DNS_AAAA = 28,
    MS_DNS_SRV = 33,
    MS_DNS_QUERY_MAX = 512,    /* the largest query ms_dns_build_query writes */
    MS_DNS_MAX_RECORDS = 256,  /* answers kept from one response */
    MS_DNS_MAX_SERVERS = 8,
    MS_DNS_MAX_SEARCH = 8,
    MS_DNS_SEARCH_TEXT = 256   /* the longest search suffix kept, with its NUL */
};

/* One answer, reduced to what DnsRecord exposes. `value` is UTF-8 text (an address, a host name with its final dot,
 * or TXT text); priority, weight and port are 0 where the kind has none. */
typedef struct MsDnsRecord {
    uint16_t type;
    uint16_t priority;
    uint16_t weight;
    uint16_t port;
    char *value;
    size_t length;
} MsDnsRecord;

typedef struct MsDnsResponse {
    uint16_t id;
    bool truncated;
    uint8_t rcode; /* 0 no error, 3 the name does not exist */
    MsDnsRecord *records;
    size_t count;
} MsDnsResponse;

/* Writes a recursive query for `name` (a final dot is allowed) of `type`, class IN. Returns its length, or 0 for a
 * name with an empty or over-long label or more than 253 bytes. `out` holds MS_DNS_QUERY_MAX bytes. */
MS_NODISCARD size_t ms_dns_build_query(uint8_t *out, uint16_t id, MsBytes name, uint16_t type);

/* Reads a response message (QR set). False for a malformed one. Release `*out` with ms_dns_response_free. */
MS_NODISCARD bool ms_dns_parse_response(MsBytes message, MsDnsResponse *out);
void ms_dns_response_free(MsDnsResponse *response);

typedef struct MsDnsConfig {
    MsAddr servers[MS_DNS_MAX_SERVERS]; /* port 53; the loopback pair when the text names none */
    size_t server_count;
    char search[MS_DNS_MAX_SEARCH][MS_DNS_SEARCH_TEXT]; /* suffixes without a final dot */
    size_t search_count;
    int64_t ndots;
} MsDnsConfig;

/* Reads resolv.conf text: nameserver, search, domain and options ndots lines; comments start with # or ;. */
void ms_dns_config_parse(MsBytes text, MsDnsConfig *out);

#endif
