/* Network scopes: the natives of ms_rt/net.h behind `Network.close`. A scope remembers the sockets opened through a
 * network and the scopes of the networks derived from it; closing it closes them all, and a scope that is closed
 * refuses new ones. A scope holds its own handle on each socket, so a socket the program closed stays small until the
 * scope closes. */
#include <stdatomic.h>
#include <stdlib.h>

#include "ms_rt/alloc.h"
#include "ms_rt/net.h"
#include "ms_rt/obj.h"

typedef struct Scope Scope;

typedef struct Member {
    MsObj *handle;
    uint8_t is_scope;
} Member;

struct Scope {
    atomic_uint handles;
    atomic_flag lock;
    bool closed;
    Member *members;
    size_t count;
    size_t capacity;
};

typedef struct ScopeHandle {
    MsObj header;
    Scope *scope;
} ScopeHandle;

static void lock(Scope *scope) {
    while (atomic_flag_test_and_set_explicit(&scope->lock, memory_order_acquire)) {
    }
}

static void unlock(Scope *scope) { atomic_flag_clear_explicit(&scope->lock, memory_order_release); }

static void handle_drop(MsObj *object) {
    ScopeHandle *handle = (ScopeHandle *)object;
    Scope *scope = handle->scope;
    msrt_free(handle);
    if (atomic_fetch_sub(&scope->handles, 1) == 1) {
        for (size_t i = 0; i < scope->count; i++) {
            msrt_obj_drop(scope->members[i].handle);
        }
        free(scope->members);
        msrt_free(scope);
    }
}

static ScopeHandle *handle_new(Scope *scope) {
    ScopeHandle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->scope = scope;
    atomic_fetch_add(&scope->handles, 1);
    return handle;
}

static Scope *scope_of(const void *handle) { return ((const ScopeHandle *)handle)->scope; }

void *msstd_scope_new(void) {
    Scope *scope = msrt_alloc_zeroed(sizeof *scope);
    atomic_init(&scope->handles, 0);
    atomic_flag_clear(&scope->lock);
    return handle_new(scope);
}

/* Records a member; false when the scope is closed or the table cannot grow. */
static bool add(Scope *scope, MsObj *handle, uint8_t is_scope) {
    lock(scope);
    bool added = false;
    if (!scope->closed) {
        if (scope->count == scope->capacity) {
            const size_t capacity = scope->capacity == 0 ? 8 : scope->capacity * 2;
            Member *grown = realloc(scope->members, capacity * sizeof *grown);
            if (grown != NULL) {
                scope->members = grown;
                scope->capacity = capacity;
            }
        }
        if (scope->count < scope->capacity) {
            scope->members[scope->count++] = (Member){handle, is_scope};
            added = true;
        }
    }
    unlock(scope);
    return added;
}

void *msstd_scope_child(const void *handle) {
    ScopeHandle *child = msstd_scope_new();
    ScopeHandle *held = handle_new(child->scope);
    if (!add(scope_of(handle), &held->header, 1)) {
        msrt_obj_drop(&held->header);
        msstd_scope_close(child);
    }
    return child;
}

uint8_t msstd_scope_open(const void *handle) {
    Scope *scope = scope_of(handle);
    lock(scope);
    const bool open = !scope->closed;
    unlock(scope);
    return open;
}

uint8_t msstd_scope_track_dgram(const void *handle, const void *socket) {
    MsObj *held = msstd_dgram_alias(socket);
    if (add(scope_of(handle), held, 0)) {
        return 1;
    }
    msstd_dgram_close(socket);
    msrt_obj_drop(held);
    return 0;
}

void msstd_scope_close(const void *handle) {
    Scope *scope = scope_of(handle);
    lock(scope);
    const bool first = !scope->closed;
    scope->closed = true;
    Member *members = scope->members;
    const size_t count = scope->count;
    scope->members = NULL;
    scope->count = 0;
    scope->capacity = 0;
    unlock(scope);
    if (!first) {
        return;
    }
    for (size_t i = 0; i < count; i++) {
        if (members[i].is_scope) {
            msstd_scope_close(members[i].handle);
        } else {
            msstd_dgram_close(members[i].handle);
        }
        msrt_obj_drop(members[i].handle);
    }
    free(members);
}
