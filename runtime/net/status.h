/* What the natives of ms_rt/net.h share: the mapping of a connection status to the runtime's status codes, the
 * absolute deadline for a relative timeout and writing a message. */
#ifndef MS_NET_STATUS_H
#define MS_NET_STATUS_H

#include "addr_text.h"
#include "conn_io.h"
#include "ms_rt/string.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"
#include "ms_rt/sys_net.h"

/* The runtime status for a connection status; `code` is the system error behind a failure (0 for none), whose text
 * goes to *err (or the status's own text). A cancelled wait ends the native through the scheduler, so the caller has
 * released everything it holds before this runs. */
uint8_t ms_net_finish(MsNetStatus status, int code, MsStr *err);
/* The absolute monotonic deadline for a relative timeout in nanoseconds; -1 for none. */
int64_t ms_net_deadline_of(uint8_t has_timeout, int64_t timeout);
void ms_net_write_text(MsStr *out, const char *text);
/* An empty text in the `err` slot. The caller reads the slot for every failure status, so a native sets it on entry and
 * only STATUS_FAILED replaces it. */
static inline void ms_net_clear_text(MsStr *err) {
    if (err != NULL) {
        msrt_string_from_bytes(NULL, 0, err);
    }
}
/* The text of `address` into *out; an empty string when it does not format. */
static inline void ms_net_write_address(MsStr *out, const MsAddr *address) {
    char text[MS_NET_ADDR_TEXT_MAX];
    size_t length = 0;
    if (ms_net_addr_format(address, text, sizeof text, &length)) {
        msrt_string_from_bytes((const uint8_t *)text, length, out);
    } else {
        msrt_string_from_bytes(NULL, 0, out);
    }
}
/* The nanoseconds a park may take before `deadline_ns`: -1 for no deadline, 0 once it has passed. */
static inline int64_t ms_net_time_left(int64_t deadline_ns) {
    if (deadline_ns < 0) {
        return -1;
    }
    const int64_t left = deadline_ns - ms_sys_monotonic_ns();
    return left > 0 ? left : 0;
}
/* The connection status of a finished wait's result flags (MS_WAIT_CANCELLED, MS_WAIT_TIMEOUT). */
static inline MsNetStatus ms_net_wait_status(uint32_t result) {
    if ((result & MS_WAIT_CANCELLED) != 0) {
        return MS_NET_CANCELLED;
    }
    return (result & MS_WAIT_TIMEOUT) != 0 ? MS_NET_TIMEOUT : MS_NET_OK;
}
/* Parks the task until `fd` is ready for `events` (MS_WAIT_READ, MS_WAIT_WRITE) or the absolute deadline passes
 * (negative for none): MS_NET_OK, MS_NET_TIMEOUT or MS_NET_CANCELLED. */
MsNetStatus ms_net_wait_fd(MsSock fd, uint32_t events, int64_t deadline_ns);

#endif
