/* runtime/std/net_ip.h: numeric IP addresses and CIDR ranges as plain values (net_ip.c), and the host:port
 * text helpers (net_addr.c). The natives over them are in net.c. */
#ifndef MS_RUNTIME_STD_NET_IP_H
#define MS_RUNTIME_STD_NET_IP_H

#include <stdbool.h>
#include <stdint.h>

#include "base/safe.h"
#include "base/strbuild.h"

/* An address: four bytes in b[0..3] when v6 is false, sixteen otherwise; unused bytes are zero. */
typedef struct MsIp {
  bool v6;
  uint8_t b[16];
} MsIp;

typedef struct MsCidr {
  MsIp addr; /* masked */
  uint8_t bits;
} MsCidr;

/* Strict text: no zone, no space, no leading zero in a decimal octet. An IPv4-mapped IPv6 address stays IPv6;
 * ms_ip_normalize maps it to IPv4. */
MS_NODISCARD bool ms_ip_parse(MsSpan text, MsIp *out);
void ms_ip_normalize(MsIp *ip);
/* RFC 5952 text; an IPv4-mapped address prints as ::ffff:a.b.c.d. */
void ms_ip_text(const MsIp *ip, MsStrBuild *out);
/* Keeps the first `bits` bits. */
void ms_ip_mask(MsIp *ip, unsigned bits);

/* `addr/bits` with the address masked; the bits are decimal without a leading zero. */
MS_NODISCARD bool ms_cidr_parse(MsSpan text, MsCidr *out);
void ms_cidr_text(const MsCidr *cidr, MsStrBuild *out);
/* The families must match exactly. */
bool ms_cidr_contains(const MsCidr *cidr, const MsIp *ip);

/* host:port: `[v6]:port` loses its brackets, a bare host holds no colon, the port may be empty. */
MS_NODISCARD bool ms_split_host_port(MsSpan text, MsSpan *host, MsSpan *port);
/* Digits only, 0 through 65535. */
MS_NODISCARD bool ms_parse_port(MsSpan text, uint16_t *out);
/* Appends host:port with a host that holds a colon in brackets. */
void ms_join_host_port(MsSpan host, uint16_t port, MsStrBuild *out);

#endif
