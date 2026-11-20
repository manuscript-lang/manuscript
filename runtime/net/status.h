/* What the natives of ms_rt/net.h share: the mapping of a connection status to the runtime's status codes, the
 * absolute deadline for a relative timeout and writing a message. */
#ifndef MS_NET_STATUS_H
#define MS_NET_STATUS_H

#include "conn_io.h"
#include "ms_rt/string.h"

/* The runtime status for a connection status; `code` is the system error behind a failure (0 for none), whose text
 * goes to *err (or the status's own text). A cancelled wait ends the native through the scheduler, so the caller has
 * released everything it holds before this runs. */
uint8_t ms_net_finish(MsNetStatus status, int code, MsStr *err);
/* The absolute monotonic deadline for a relative timeout in nanoseconds; -1 for none. */
int64_t ms_net_deadline_of(uint8_t has_timeout, int64_t timeout);
void ms_net_write_text(MsStr *out, const char *text);

#endif
