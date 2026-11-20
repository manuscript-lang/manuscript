/* The natives' shared helpers (status.h). */
#include "status.h"

#include <string.h>

#include "../std/abi.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"

void ms_net_write_text(MsStr *out, const char *text) {
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), out);
}

/* Maps a connection status to the runtime's. A cancelled wait ends the native through the scheduler; the caller has
 * released everything it holds before this runs. */
uint8_t ms_net_finish(MsNetStatus status, int code, MsStr *err) {
    switch (status) {
    case MS_NET_OK: return STATUS_OK;
    case MS_NET_CLOSED: return STATUS_CLOSED;
    case MS_NET_TIMEOUT: return STATUS_TIMED_OUT;
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

