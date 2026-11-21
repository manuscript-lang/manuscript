/* Datagram sockets: the natives of ms_rt/net.h that bind a UDP socket and send and receive whole datagrams. A socket
 * is a core (descriptor, handle and end counts) behind handle objects like the connection object's. Close ends the
 * use at once; the descriptor itself is released when the last call using it returns, so a call blocked in a wait
 * never sees a recycled descriptor. Addresses are literals ("1.2.3.4:80"); names are resolved by the caller. */
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "addr_text.h"
#include "ms_rt/alloc.h"
#include "ms_rt/net.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "status.h"

enum { DATAGRAM_MAX = 65535 };

typedef struct Core {
    atomic_uint handles; /* handles that refer to the core */
    atomic_uint ends;    /* socket ends still open */
    atomic_uint busy;    /* calls using the descriptor */
    atomic_bool closed;
    atomic_flag released;
    MsSock fd;
} Core;

typedef struct Handle {
    MsObj header;
    Core *core;
} Handle;

/* Closes the descriptor once, when the socket is closed and no call is using it. */
static void release_if_idle(Core *core) {
    if (atomic_load(&core->closed) && atomic_load(&core->busy) == 0 && !atomic_flag_test_and_set(&core->released)) {
        msrt_task_forget_fd((int32_t)core->fd); /* see conn_io.c: a watched descriptor is forgotten before it closes */
        ms_sys_net_close(core->fd);
    }
}

static void core_close(Core *core) {
    atomic_store(&core->closed, true);
    release_if_idle(core);
}

static void handle_drop(MsObj *object) {
    Handle *handle = (Handle *)object;
    Core *core = handle->core;
    msrt_free(handle);
    if (atomic_fetch_sub(&core->handles, 1) == 1) {
        core_close(core);
        msrt_free(core);
    }
}

static void *handle_new(Core *core) {
    Handle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->core = core;
    return handle;
}

static Core *core_of(const void *handle) { return ((const Handle *)handle)->core; }

/* Enters a call: false when the socket is closed. Every true result is paired with `leave`. */
static bool enter(Core *core) {
    atomic_fetch_add(&core->busy, 1);
    if (atomic_load(&core->closed)) {
        atomic_fetch_sub(&core->busy, 1);
        release_if_idle(core);
        return false;
    }
    return true;
}

static void leave(Core *core) {
    atomic_fetch_sub(&core->busy, 1);
    release_if_idle(core);
}

uint8_t msstd_dgram_bind(const MsStr *address, void **out, MsStr *err) {
    ms_net_clear_text(err); /* the caller reads the slot for every failure status; only STATUS_FAILED sets text */
    MsAddr local;
    if (!ms_net_addr_parse(msrt_str_bytes(address), &local)) {
        return STATUS_INVALID_INPUT;
    }
    MsSock fd = MS_SOCK_INVALID;
    if (ms_sys_net_udp_bind(&local, &fd) != MS_SYS_OK) {
        return ms_net_finish(MS_NET_FAILED, ms_sys_net_error(), err);
    }
    Core *core = msrt_alloc_zeroed(sizeof *core);
    atomic_init(&core->handles, 1);
    atomic_init(&core->ends, 1);
    atomic_init(&core->busy, 0);
    atomic_init(&core->closed, false);
    atomic_flag_clear(&core->released);
    core->fd = fd;
    *out = handle_new(core);
    return STATUS_OK;
}

void msstd_dgram_address(const void *handle, MsStr *out) {
    Core *core = core_of(handle);
    MsAddr address;
    if (enter(core)) {
        const bool known = ms_sys_net_local_addr(core->fd, &address) == MS_SYS_OK;
        leave(core);
        if (known) {
            ms_net_write_address(out, &address);
            return;
        }
    }
    msrt_string_from_bytes(NULL, 0, out);
}

void msstd_dgram_close(const void *handle) { core_close(core_of(handle)); }

void *msstd_dgram_alias(const void *handle) {
    Core *core = core_of(handle);
    atomic_fetch_add(&core->handles, 1);
    return handle_new(core);
}

void *msstd_dgram_share(const void *handle) {
    Core *core = core_of(handle);
    atomic_fetch_add(&core->ends, 1);
    atomic_fetch_add(&core->handles, 1);
    return handle_new(core);
}

void msstd_dgram_close_if_last(const void *handle) {
    Core *core = core_of(handle);
    if (atomic_fetch_sub(&core->ends, 1) == 1) {
        core_close(core);
    }
}

/* The datagram that fits `capacity` bytes, with its sender. A datagram longer than the limit is dropped and reported:
 * the buffer holds one byte more than the limit so that a longer one is seen as such. */
uint8_t msstd_dgram_receive(const void *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout,
                            MsNetDatagram *out, MsStr *err) {
    ms_net_clear_text(err); /* the caller reads the slot for every failure status; only STATUS_FAILED sets text */
    Core *core = core_of(handle);
    if (has_max != 0 && (max < 1 || max > DATAGRAM_MAX)) {
        return STATUS_INVALID_INPUT;
    }
    const size_t limit = has_max != 0 ? (size_t)max : DATAGRAM_MAX;
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    uint8_t *buffer = malloc(limit + 1);
    if (buffer == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    if (!enter(core)) {
        free(buffer);
        return STATUS_CLOSED;
    }
    MsNetStatus status = MS_NET_OK;
    int code = 0;
    size_t count = 0;
    bool too_big = false;
    MsAddr from;
    for (;;) {
        const int result = ms_sys_net_udp_recv(core->fd, buffer, limit + 1, &count, &from);
        if (result == MS_SYS_OK) {
            too_big = count > limit;
            break;
        }
        if (result == MS_SYS_TOO_BIG) {
            too_big = true;
            break;
        }
        if (result == MS_SYS_ERROR) {
            status = MS_NET_FAILED;
            code = ms_sys_net_error();
            break;
        }
        status = ms_net_wait_fd(core->fd, MS_WAIT_READ, deadline);
        if (status != MS_NET_OK) {
            break;
        }
    }
    leave(core);
    if (status == MS_NET_OK && !too_big) {
        msrt_write_bytes(&out->data, buffer, count);
        ms_net_write_address(&out->sender, &from);
    }
    free(buffer);
    return too_big ? STATUS_LIMIT_EXCEEDED : ms_net_finish(status, code, err);
}

uint8_t msstd_dgram_send(const void *handle, const MsVec *data, const MsStr *address, uint8_t has_timeout, int64_t timeout,
                         MsStr *err) {
    ms_net_clear_text(err); /* the caller reads the slot for every failure status; only STATUS_FAILED sets text */
    Core *core = core_of(handle);
    MsAddr target;
    if (!ms_net_addr_parse(msrt_str_bytes(address), &target)) {
        return STATUS_INVALID_INPUT;
    }
    if (data->len > DATAGRAM_MAX) {
        return STATUS_LIMIT_EXCEEDED;
    }
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    if (!enter(core)) {
        return STATUS_CLOSED;
    }
    MsNetStatus status = MS_NET_OK;
    int code = 0;
    bool too_big = false;
    for (;;) {
        size_t sent = 0;
        const int result = ms_sys_net_udp_send(core->fd, data->ptr, data->len, &target, &sent);
        if (result == MS_SYS_OK) {
            break;
        }
        if (result == MS_SYS_TOO_BIG) {
            too_big = true;
            break;
        }
        if (result == MS_SYS_ERROR) {
            status = MS_NET_FAILED;
            code = ms_sys_net_error();
            break;
        }
        status = ms_net_wait_fd(core->fd, MS_WAIT_WRITE, deadline);
        if (status != MS_NET_OK) {
            break;
        }
    }
    leave(core);
    return too_big ? STATUS_LIMIT_EXCEEDED : ms_net_finish(status, code, err);
}
