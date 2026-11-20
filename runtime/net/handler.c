/* The request handler of a server, shared by every thread (HandlerH): the program's `fn() Void` closure that serves
 * one request, built once by `serve` and called by the connection tasks of every thread. The closure reads what it
 * captured and never changes it, so threads call it at once; it leaves its argument and its result in the calling
 * thread's slots, which it takes (`take`) and sets (`keep`) before any park, so tasks sharing a thread never mix
 * them. The closure ends with the last handle. */
#include <stdatomic.h>

#include "../std/abi.h"
#include "ms_rt/alloc.h"
#include "status.h"
#include "ms_rt/obj.h"
#include "ms_rt/xchg.h"

typedef struct HandlerClosure {
    MsObj header;
    void (*code)(struct HandlerClosure *);
} HandlerClosure;

typedef struct HandlerState {
    atomic_uint handles;
    HandlerClosure *closure;
} HandlerState;

typedef struct HandlerHandle {
    MsObj header;
    HandlerState *state;
} HandlerHandle;

static _Thread_local const void *request_slot; /* the exchange handle the call in flight serves */
static _Thread_local uint8_t keep_slot;

static void handle_drop(MsObj *object) {
    HandlerHandle *handle = (HandlerHandle *)object;
    if (atomic_fetch_sub(&handle->state->handles, 1) == 1) {
        msrt_obj_drop(&handle->state->closure->header);
        msrt_free(handle->state);
    }
    msrt_free(handle);
}

static MsObj *handle_new(HandlerState *state) {
    HandlerHandle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->state = state;
    return &handle->header;
}

void *msstd_handler_new(void *run) {
    HandlerState *state = msrt_alloc(sizeof *state);
    atomic_init(&state->handles, 1);
    state->closure = run;
    return handle_new(state);
}

void *msstd_handler_share(const void *handle) {
    HandlerState *state = ((const HandlerHandle *)handle)->state;
    atomic_fetch_add(&state->handles, 1);
    return handle_new(state);
}

uint8_t msstd_handler_call(const void *handle, const void *exchange, uint8_t *keep, MsStr *err) {
    ms_net_clear_text(err);
    HandlerClosure *closure = ((const HandlerHandle *)handle)->state->closure;
    request_slot = exchange;
    keep_slot = 0;
    closure->code(closure); /* leaves by a jump when the handler task faults or is cancelled; nothing here is owned */
    request_slot = NULL;
    *keep = keep_slot;
    return STATUS_OK;
}

void *msstd_handler_take(void) {
    const void *exchange = request_slot;
    request_slot = NULL;
    return exchange == NULL ? NULL : msstd_xchg_share(exchange);
}

void msstd_handler_keep(uint8_t keep) { keep_slot = keep; }
