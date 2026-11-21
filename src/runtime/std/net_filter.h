/* runtime/std/net_filter.h: which hosts and addresses a network may reach. A filter is a list of levels, one per
 * `restrict` call, and a request must pass every level, so a level can only narrow the ones before it. A filter is
 * immutable and counted; NULL means unrestricted. */
#ifndef MS_RUNTIME_STD_NET_FILTER_H
#define MS_RUNTIME_STD_NET_FILTER_H

#include <uv.h>

#include "base/list.h"
#include "base/safe.h"

typedef struct MsNetFilter MsNetFilter;

/* A filter that is `base` (NULL: unrestricted) with one more level that allows the host names and IP literals of
 * `hosts` (a list of strings, compared lower-case without one trailing dot) and the ranges of `cidrs` ("10.0.0.0/8").
 * NULL when a range is not valid. The result has one reference. */
MS_NODISCARD MsNetFilter *ms_net_filter_narrow(const MsNetFilter *base, const MsList *hosts, const MsList *cidrs);
MsNetFilter *ms_net_filter_retain(MsNetFilter *filter);
void ms_net_filter_release(MsNetFilter *filter);

/* Whether `host` (a name, or an IP literal without brackets) may be dialed: every level lists it, or holds a range
 * that contains it when it is a literal. */
bool ms_net_filter_host_allowed(const MsNetFilter *filter, MsSpan host);
/* Whether a resolved address may be used: every level has a range that contains it, or has no ranges but lists a
 * host. */
bool ms_net_filter_address_allowed(const MsNetFilter *filter, const struct sockaddr *address);

#endif
