/* The DNS natives, declared here until the standard library switches to them: the switch moves these declarations to
 * ms_rt/net.h and lists the symbols in runtime/symbols/net.txt (the symbols check would reject them before then). */
#ifndef MS_NET_DNS_QUERY_H
#define MS_NET_DNS_QUERY_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* Asks `server` ("1.2.3.4:53") for the records of `type` (the DNS number: A 1, NS 2, CNAME 5, PTR 12, MX 15, TXT 16,
 * AAAA 28, SRV 33) of `name`. On STATUS_OK, `values` is a list of Str (an address, a host name with its final dot, or
 * the text) and `numbers` a list of Int, three a record: priority (MX preference), weight, port. STATUS_NONE: the name
 * does not exist or has no data of the type. Another server error is STATUS_FAILED. Without a timeout the wait ends
 * after 5 seconds. */
/* ms-sig: msstd_dns_query(server: *const StrVal, name: *const StrVal, kind: i64, has_timeout: HasRaw, timeout: i64, values: *mut VecVal, numbers: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_dns_query(const MsStr *server, const MsStr *name, int64_t type, uint8_t has_timeout, int64_t timeout,
                        MsVec *values, MsVec *numbers, MsStr *err);

/* The host's resolver: servers as "ip:53" text (the loopback pair when it names none), the search suffixes, ndots. */
/* ms-sig: msstd_dns_config(servers: *mut VecVal, search: *mut VecVal, ndots: *mut i64) -> u8 @domain=network */
uint8_t msstd_dns_config(MsVec *servers, MsVec *search, int64_t *ndots);

#endif
