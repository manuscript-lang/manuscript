/* Network restriction: which hosts and addresses a client may reach (src/stdlib/net/policy.ms is the contract). A filter
 * is a list of levels, one per `restrict` call, and a request must pass every level, so a level can only narrow the
 * ones before it. A filter with no level allows everything. Pure functions over text and addresses; no I/O. */
#ifndef MS_NET_FILTER_H
#define MS_NET_FILTER_H

#include <stdbool.h>
#include <stddef.h>

#include "ms_rt/safe.h"
#include "ms_rt/sys_net.h"

typedef struct MsNetFilter MsNetFilter;

MsNetFilter *ms_net_filter_new(void);
void ms_net_filter_free(MsNetFilter *filter);

/* Adds a level that allows `hosts` (names, compared lower-case without one trailing dot, and IP literals) and the
 * CIDR ranges `cidrs` ("10.0.0.0/8", "::1/128"). False, changing nothing, for a CIDR that is not valid or when out of
 * memory. */
MS_NODISCARD bool ms_net_filter_narrow(MsNetFilter *filter, const MsBytes *hosts, size_t host_count, const MsBytes *cidrs,
                                       size_t cidr_count);

/* Whether any level was added. */
bool ms_net_filter_restricted(const MsNetFilter *filter);

/* Whether `host` (a name, or an IP literal without brackets) may be dialed: every level lists it, or holds a range
 * that contains it when it is a literal. */
bool ms_net_filter_host_allowed(const MsNetFilter *filter, MsBytes host);

/* Whether a resolved address may be used: every level has a range that contains it, or has no ranges but lists a host. */
bool ms_net_filter_address_allowed(const MsNetFilter *filter, const MsAddr *address);

#endif
