/* runtime/std/net_dns.h: the DNS client behind Network.resolve_dns and with_resolver. net_dns.c is the wire format
 * without any I/O (a recursive query out, the answers of one kind in); net_dns_client.c asks the servers over the UDP
 * and TCP natives, applies the search list, and fills the natives' records. The record kinds are the ones DnsKind has:
 * A, AAAA, CNAME, MX, NS, TXT, PTR, SRV. */
#ifndef MS_RUNTIME_STD_NET_DNS_H
#define MS_RUNTIME_STD_NET_DNS_H

#include "abi/status.h"
#include "base/list.h"
#include "base/strbuild.h"
#include "base/string.h"

enum {
  MS_DNS_A = 1,
  MS_DNS_NS = 2,
  MS_DNS_CNAME = 5,
  MS_DNS_PTR = 12,
  MS_DNS_MX = 15,
  MS_DNS_TXT = 16,
  MS_DNS_AAAA = 28,
  MS_DNS_SRV = 33,
  MS_DNS_QUERY_MAX = 512, /* the largest query ms_dns_build_query writes */
  MS_DNS_RCODE_NAME_ERROR = 3,
  MS_DNS_KIND_A = 0, /* DnsKind case indexes */
  MS_DNS_KIND_AAAA = 1,
  MS_DNS_KIND_PTR = 6
};

/* One answer at the layout of `DnsRecord`: `kind` is the DnsKind case index, `priority` an MX preference or SRV
 * priority; weight and port are SRV's. `value` is an address, a host name with its final dot, or the TXT text. */
typedef struct MsDnsRecord {
  int64_t kind;
  MsString value;
  int64_t priority;
  int64_t weight;
  int64_t port;
} MsDnsRecord;

/* The DNS type of a DnsKind case index (A, AAAA, CNAME, MX, NS, TXT, PTR, SRV); 0 for an index out of range. */
uint16_t ms_dns_type_of_kind(int64_t kind);

/* Writes a recursive query for `name` (a final dot is allowed) of `type`, class IN, into `out` (MS_DNS_QUERY_MAX
 * bytes). Returns its length, or 0 for a name with an empty or over-long label or over 253 bytes. */
size_t ms_dns_build_query(uint8_t *out, uint16_t id, MsSpan name, uint16_t type);

typedef struct MsDnsAnswer {
  uint16_t id;
  bool truncated;
  uint8_t rcode;
  MsList records; /* MsDnsRecord of the wanted type; the caller drops them */
} MsDnsAnswer;

/* Reads a response message: false for a malformed one. Keeps the records of `type`, as kind `kind`. */
MS_NODISCARD bool ms_dns_parse(MsSpan message, uint16_t type, int64_t kind, MsDnsAnswer *out);
void ms_dns_answer_free(MsDnsAnswer *answer);

/* The reverse name of an IP literal ("1.2.3.4" is "4.3.2.1.in-addr.arpa", an IPv6 address is its nibbles under
 * ip6.arpa); false when `text` is not an address. */
MS_NODISCARD bool ms_dns_reverse_name(MsSpan text, MsStrBuild *out);

/* The host's resolver settings (resolv.conf text): the servers as "ip:port", the search suffixes and ndots. */
typedef struct MsDnsConfig {
  MsList servers; /* MsString */
  MsList search;  /* MsString, without dots at the ends */
  int ndots;
} MsDnsConfig;

void ms_dns_config_parse(MsSpan text, MsDnsConfig *out);
void ms_dns_config_free(MsDnsConfig *config);

/* Looks up the records of DnsKind `kind` for `name` through the server "ip:port" (an empty `server`: the host's
 * servers and search list). `timeout_ns` bounds the whole query (negative: five seconds). A name that does not exist is
 * MS_STATUS_FAILED, a kind with no data an empty list. The records belong to the caller (ms_dns_records_free). */
uint8_t ms_dns_resolve(MsSpan server, MsSpan name, int64_t kind, int64_t timeout_ns, MsList *out, MsString *err);
void ms_dns_records_free(MsList *records);

#endif
