/* Network scopes: the natives of ms_rt/net.h behind `Network.close`. A scope remembers the sockets opened through a
 * network and the scopes of the networks derived from it; closing it closes them all, and a scope that is closed
 * refuses new ones. A scope holds its own handle on each socket, so a socket the program closed stays small until the
 * scope closes. */
#include <stdatomic.h>
#include <stdlib.h>

#include "conn_object.h"
#include "listener.h"
#include "ms_rt/alloc.h"
#include "ms_rt/net.h"

typedef struct Scope Scope;

static void drop_handle(MsObj *object) { object->drop(object); }

typedef enum Kind { KIND_SCOPE, KIND_DGRAM, KIND_CONN, KIND_LISTENER, KIND_CLIENT } Kind;

typedef struct Member {
    MsObj *handle;
    Kind kind;
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
            drop_handle(scope->members[i].handle);
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

static void close_member(const Member *member) {
    switch (member->kind) {
    case KIND_SCOPE: msstd_scope_close(member->handle); break;
    case KIND_DGRAM: msstd_dgram_close(member->handle); break;
    case KIND_CONN: ms_netconn_close(member->handle); break;
    case KIND_LISTENER: ms_listener_close(ms_listener_of(member->handle)); break;
    case KIND_CLIENT: msstd_client_close(member->handle); break;
    }
}

/* Records a member; false when the scope is closed or the table cannot grow. */
static bool add(Scope *scope, MsObj *handle, Kind kind) {
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
            scope->members[scope->count++] = (Member){handle, kind};
            added = true;
        }
    }
    unlock(scope);
    return added;
}

void *msstd_scope_share(const void *handle) { return handle_new(scope_of(handle)); }

void *msstd_scope_child(const void *handle) {
    ScopeHandle *child = msstd_scope_new();
    ScopeHandle *held = handle_new(child->scope);
    if (!add(scope_of(handle), &held->header, KIND_SCOPE)) {
        drop_handle(&held->header);
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

/* Records `held`, an alias of an object; when the scope is closed the object is closed and 0 returned. */
static uint8_t track(const void *handle, MsObj *held, Kind kind) {
    if (add(scope_of(handle), held, kind)) {
        return 1;
    }
    close_member(&(Member){held, kind});
    drop_handle(held);
    return 0;
}

uint8_t msstd_scope_track_dgram(const void *handle, const void *socket) {
    return track(handle, msstd_dgram_alias(socket), KIND_DGRAM);
}

uint8_t msstd_scope_track_conn(const void *handle, const void *connection) {
    return track(handle, ms_netconn_alias(connection), KIND_CONN);
}

uint8_t msstd_scope_track_client(const void *handle, const void *client) {
    return track(handle, msstd_client_share(client), KIND_CLIENT);
}

uint8_t msstd_scope_untrack_client(const void *handle, const void *client) {
    Scope *scope = scope_of(handle);
    MsObj *found = NULL;
    lock(scope);
    for (size_t i = 0; i < scope->count && found == NULL; i++) {
        if (scope->members[i].kind == KIND_CLIENT && ms_client_same(scope->members[i].handle, client)) {
            found = scope->members[i].handle;
            scope->members[i] = scope->members[--scope->count];
        }
    }
    unlock(scope);
    if (found != NULL) {
        drop_handle(found);
    }
    return found != NULL;
}

uint8_t msstd_scope_track_listener(const void *handle, const void *listener) {
    return track(handle, ms_listener_share(listener), KIND_LISTENER);
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
        close_member(&members[i]);
        drop_handle(members[i].handle);
    }
    free(members);
}
