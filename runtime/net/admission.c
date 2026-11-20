/* The request admission counter of ms_rt/xchg.h (AdmitH): how many requests of one server run at once, shared by the
 * tasks of every thread, so `max_requests` can turn the next one away. The count ends with its last handle. */
#include <stdatomic.h>

#include "../std/abi.h"
#include "ms_rt/alloc.h"
#include "ms_rt/obj.h"
#include "ms_rt/xchg.h"

typedef struct Admission {
    atomic_uint handles;
    atomic_int_least64_t running;
    int64_t limit; /* negative: no limit */
} Admission;

typedef struct AdmitHandle {
    MsObj header;
    Admission *state;
} AdmitHandle;

static void handle_drop(MsObj *object) {
    AdmitHandle *handle = (AdmitHandle *)object;
    if (atomic_fetch_sub(&handle->state->handles, 1) == 1) {
        msrt_free(handle->state);
    }
    msrt_free(handle);
}

static MsObj *handle_new(Admission *state) {
    AdmitHandle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->state = state;
    return &handle->header;
}

void *msstd_admit_new(uint8_t has_max, int64_t max) {
    Admission *state = msrt_alloc(sizeof *state);
    atomic_init(&state->handles, 1);
    atomic_init(&state->running, 0);
    state->limit = has_max != 0 ? max : -1;
    return handle_new(state);
}

void *msstd_admit_share(const void *handle) {
    Admission *state = ((const AdmitHandle *)handle)->state;
    atomic_fetch_add(&state->handles, 1);
    return handle_new(state);
}

uint8_t msstd_admit_enter(const void *handle) {
    Admission *state = ((const AdmitHandle *)handle)->state;
    const int64_t before = atomic_fetch_add(&state->running, 1);
    if (state->limit >= 0 && before >= state->limit) {
        atomic_fetch_sub(&state->running, 1);
        return STATUS_LIMIT_EXCEEDED;
    }
    return STATUS_OK;
}

void msstd_admit_leave(const void *handle) {
    atomic_fetch_sub(&((const AdmitHandle *)handle)->state->running, 1);
}
