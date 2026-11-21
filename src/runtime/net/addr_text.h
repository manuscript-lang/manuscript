/* Socket addresses as text: "1.2.3.4:80" and "[::1]:80" (an IPv6 scope id is "%scope"). The policy and the standard
 * library handle addresses as text; these two functions are the whole conversion to and from MsAddr. IPv6 text
 * follows RFC 5952 (lower case, the longest run of two or more zero groups becomes "::"). No system call is made.
 */
#ifndef MS_NET_ADDR_TEXT_H
#define MS_NET_ADDR_TEXT_H

#include <stdbool.h>
#include <stddef.h>

#include "ms_rt/safe.h"
#include "ms_rt/sys_net.h"

/* The longest text ms_net_addr_format writes, with its terminating NUL: "[ffff:...:ffff%4294967295]:65535". */
enum { MS_NET_ADDR_TEXT_MAX = 64 };

/* Writes `address` to `out` (NUL-terminated) and sets *length to the text length. False when `capacity` is too small. */
MS_NODISCARD bool ms_net_addr_format(const MsAddr *address, char *out, size_t capacity, size_t *length);

/* Reads "host:port" or "[v6]:port" into `out`. The host must be an IP literal; a name is false, as is a missing or
 * out-of-range port. */
MS_NODISCARD bool ms_net_addr_parse(MsBytes text, MsAddr *out);

/* Reads a bare IP literal ("1.2.3.4", "::1", "fe80::1%2") with port 0. */
MS_NODISCARD bool ms_net_ip_parse(MsBytes text, MsAddr *out);

#endif
