/* The natives' shared helpers (status.h). */
#include "status.h"

#include <string.h>

#include "../std/abi.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"

void ms_net_write_text(MsStr *out, const char *text) {
    if (out == NULL) {
        return;
    }
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), out);
}

/* Maps a connection status to the runtime's. A cancelled wait ends the native through the scheduler; the caller has
 * released everything it holds before this runs. */
uint8_t ms_net_finish(MsNetStatus status, int code, MsStr *err) {
    if (err != NULL && status != MS_NET_OK) {
        msrt_string_from_bytes(NULL, 0, err); /* the caller reads the text whatever the status */
    }
    switch (status) {
    case MS_NET_OK: return STATUS_OK;
    case MS_NET_CLOSED:
        ms_net_write_text(err, "");
        return STATUS_CLOSED;
    case MS_NET_TIMEOUT:
        ms_net_write_text(err, ""); /* the error carries a text slot, read whatever the status */
        return STATUS_TIMED_OUT;
    case MS_NET_CANCELLED:
        ms_sched_cancel_return();
        return STATUS_OK;
    case MS_NET_RESET:
    case MS_NET_FAILED:
        break;
    }
    if (err != NULL) {
        char text[160];
        const size_t length = code != 0 ? ms_sys_fs_error_text(code, text, sizeof text) : 0;
        if (length > 0) {
            msrt_string_from_bytes((const uint8_t *)text, length, err);
        } else {
            ms_net_write_text(err, ms_net_status_text(status));
        }
    }
    return STATUS_FAILED;
}

/* The absolute deadline for a relative timeout, or none. */
int64_t ms_net_deadline_of(uint8_t has_timeout, int64_t timeout) {
    if (has_timeout == 0 || timeout < 0) {
        return -1;
    }
    const int64_t now = ms_sys_monotonic_ns();
    return timeout > INT64_MAX - now ? INT64_MAX : now + timeout;
}


MsNetStatus ms_net_wait_fd(MsSock fd, uint32_t events, int64_t deadline_ns) {
    /* Work a promise defers to its waiter runs on the waiter's stack, and only waits that look at the waiter's
     * limit (a `with(timeout:)`) end by it: narrow the deadline to it. */
    const int64_t waiter_at = ms_sched_defer_deadline();
    if (waiter_at != INT64_MAX && (deadline_ns < 0 || waiter_at < deadline_ns)) {
        deadline_ns = waiter_at;
    }
    int64_t timeout_ns = -1;
    if (deadline_ns >= 0) {
        timeout_ns = deadline_ns - ms_sys_monotonic_ns();
        if (timeout_ns <= 0) {
            return MS_NET_TIMEOUT;
        }
    }
    const uint32_t got = msrt_task_wait_fd((int32_t)fd, events, timeout_ns);
    if ((got & MS_WAIT_CANCELLED) != 0) {
        return MS_NET_CANCELLED;
    }
    if ((got & MS_WAIT_TIMEOUT) != 0 && (got & (MS_WAIT_READ | MS_WAIT_WRITE | MS_WAIT_HUP)) == 0) {
        return MS_NET_TIMEOUT;
    }
    return MS_NET_OK;
}
