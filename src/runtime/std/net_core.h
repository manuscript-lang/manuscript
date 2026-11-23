/* runtime/std/net_core.h: the socket behind the handles of @std/net (a connection, a listener or a datagram socket).
 *
 * A NetCore wraps one libuv handle of the network loop (net_loop.h). Every field after `closed` belongs to the loop
 * thread alone. Manuscript handles (NetHandle) count references on the core; the libuv handle holds one more, released
 * when libuv has closed it, and the last release frees the core. */
#ifndef MS_RUNTIME_STD_NET_CORE_H
#define MS_RUNTIME_STD_NET_CORE_H

#include <stdatomic.h>
#include <uv.h>

#include "abi/status.h"
#include "base/desc.h"
#include "base/string.h"
#include "runtime/std/net_loop.h"
#include "runtime/std/net_tls.h"

typedef enum MsNetKind { MS_NET_CONNECTION, MS_NET_LISTENER, MS_NET_DATAGRAM } MsNetKind;

typedef struct MsNetCore {
  union {
    uv_handle_t handle;
    uv_stream_t stream;
    uv_tcp_t tcp;
    uv_pipe_t pipe;
    uv_udp_t udp;
  } h;
  MsNetKind kind;
  bool is_pipe;           /* a Unix domain (or named pipe) socket */
  atomic_uint references; /* handles, plus one for the libuv handle */
  atomic_uint handles;    /* the Manuscript handles alive; the last drop closes the socket */
  atomic_uint ends;       /* ends of the object still open (share / close_if_last) */
  atomic_bool closed;
  atomic_uint generation; /* bumped when an upgrade (TLS) consumes the handles made before it */
  atomic_bool stealable; /* a server lets another thread take this connection's ready idle read (net_conn.c) */
  atomic_int steal_lock; /* a spin lock over `open_read` */
  atomic_uint writing;   /* write operations posted and not yet freed: a write goes straight to the socket only when none is */
  atomic_uint reads_posted; /* read operations posted and not yet freed: a read goes straight to the socket only when none is */
  atomic_uint edge_waiting; /* tasks parked on the poller of their thread for this socket's bytes (net_conn.c) */
  uint64_t id;           /* names this connection to its thread's poller, which registers descriptor numbers that get reused */
  bool drained;          /* the reading task's last read took everything the socket held, so the next one waits for an edge first */
  atomic_uint direct;    /* threads inside a direct socket call; the loop closes the handle only when none is (net_conn.c) */
  void *open_read;       /* the idle read in flight, with a reference of its own; set under steal_lock */
  MsString local; /* the addresses as text, set before the core is shared */
  MsString peer;
  char *path;               /* a Unix listener's file, removed when the core closes */
  uint8_t *stash;           /* loop thread: bytes read ahead of a reader that gave up */
  size_t stash_length;
  bool eof;                 /* loop thread: the peer ended its side */
  atomic_bool broken;       /* a write was abandoned, so the stream is torn (set on the loop thread, read by direct reads) */
  void *reading;            /* loop thread: the read or receive in progress */
  void *accepting;          /* loop thread: accept operations waiting, oldest first */
  struct MsNetOp *close_wait; /* loop thread: the explicit close that waits for libuv to release the descriptor */
  void *ready;              /* loop thread: accepted connections nobody took yet, oldest first */
  MsNetTls *tls;            /* loop thread: the session of a TLS connection, NULL for plain */
  MsNetTlsCtx *tls_ctx;     /* a TLS listener's context, shared by the connections it accepts */
} MsNetCore;

/* The object a Manuscript program holds: a reference on a core. */
typedef struct MsNetHandle {
  MsObj header;
  MsNetCore *core;
  unsigned generation; /* the core's generation when this handle was made; a later one means it was consumed */
} MsNetHandle;

/* A core of `kind` with one reference (the libuv handle's), not yet initialised on the loop. */
MsNetCore *ms_net_core_new(MsNetKind kind, bool is_pipe);
void ms_net_core_unref(MsNetCore *core);
/* A handle holding a new reference on `core`. */
MsObj *ms_net_handle_new(MsNetCore *core);
MsNetCore *ms_net_handle_core(const MsObj *handle);
/* A new handle on the core of `handle` that consumes every handle made on it so far: they find a closed connection
 * from now on (an upgrade to TLS in place). */
MsObj *ms_net_handle_upgraded(const MsObj *handle);
/* Closes the socket once (ends operations in flight, closes the libuv handle). Safe from any thread. */
void ms_net_core_close(MsNetCore *core);
/* Loop thread: records the socket's own and peer address as text, from the libuv handle. */
void ms_net_core_name(MsNetCore *core);
/* The text of a socket address: ip and port, bracketed for IPv6. */
void ms_net_address_text(const struct sockaddr *address, MsString *out);

/* Ends the waits of tasks parked on the poller for this connection's bytes, so a close does not wait for them (any
 * thread; they wake with the end of the stream). */
void ms_net_conn_wake_readers(MsNetCore *core);

/* Marks the connection as one whose idle read another thread may take over (see ms_net_core_steal_read). */
void ms_net_core_set_stealable(MsNetCore *core, bool stealable);
/* Takes the bytes of a finished read that its waiter has not collected yet, ending that wait: the waiter then gets
 * MS_STATUS_CLOSED and must not touch the connection (the caller serves it). False when no such read exists, it has
 * not finished, or it carries no bytes (an end of stream or an error stays with its waiter). Any thread. */
bool ms_net_core_steal_read(MsNetCore *core, MsBytes *out);

/* Handle natives shared by the three kinds. */
/* Another handle on the same end (alias) and on a new end (share). */
MsObj *ms_net_handle_alias(const MsObj *handle);
MsObj *ms_net_handle_share(const MsObj *handle);
void ms_net_handle_close(const MsObj *handle);
void ms_net_handle_close_if_last(const MsObj *handle);

/* Loop thread: the ends of the per-kind work (net_conn.c, net_listen.c, net_dgram.c). */
void ms_net_conn_close_ops(MsNetCore *core);
void ms_net_listen_close_ops(MsNetCore *core);
void ms_net_dgram_close_ops(MsNetCore *core);


/* Ends a native: the status for how a wait ended and the libuv `status` of the operation, with `err` filled for a
 * failure ("<operation>: <reason>"). A stop request cancels the task and does not return. */
uint8_t ms_net_finish(MsNetWait wait, int status, const char *operation, MsString *err);
/* Loop thread, TLS: collects the ciphertext the session has queued into a new buffer (`*length` 0 for none). */
void ms_net_cipher_collect(MsNetCore *core, uint8_t **data, size_t *length);
/* Loop thread, TLS: writes the queued ciphertext. 1 when a write was started (`done` runs with its status), 0 when
 * there was nothing, a negative status when it could not start. `done` may be NULL. */
int ms_net_cipher_flush(MsNetCore *core, void (*done)(void *argument, int status), void *argument);
/* Loop thread: closes a core that was never handed to a handle. */
void ms_net_core_discard(MsNetCore *core);

#endif
