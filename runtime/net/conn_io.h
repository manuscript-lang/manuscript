/* Byte I/O on a connection row, plain or TLS: the one place that moves bytes between a socket and a task.
 *
 * A call parks the running task on the row's descriptor (msrt_task_wait_fd), so a stop request interrupts it and
 * other tasks run meanwhile. TLS is the sans-io pump of tls.h: this layer feeds it ciphertext from the socket and
 * writes what it produces, so callers see plaintext only and never branch on TLS.
 *
 * Every function takes the table and a row id; a stale id gives MS_NET_CLOSED, never a crash. `deadline_ns` is an
 * absolute ms_sys_monotonic_ns time, or negative for none. A write, handshake or shutdown that is interrupted after
 * some ciphertext was produced leaves the row broken: later calls give MS_NET_CLOSED, and the caller closes it.
 */
#ifndef MS_NET_CONN_IO_H
#define MS_NET_CONN_IO_H

#include <stddef.h>
#include <stdint.h>

#include "conn.h"
#include "tls.h"

typedef enum MsNetStatus {
    MS_NET_OK = 0,
    MS_NET_CLOSED = -1,    /* a stale id, a closed or broken row */
    MS_NET_TIMEOUT = -2,
    MS_NET_CANCELLED = -3, /* a stop request ended the wait */
    MS_NET_RESET = -4,     /* the peer reset the connection; ms_conn_error_code has the system code */
    MS_NET_FAILED = -5     /* any other failure; ms_conn_error_text says which */
} MsNetStatus;

/* The state hung off a row's `ext`: cold, absent while a plain connection is idle. */
typedef struct MsConnExt {
    MsTls *tls;                /* owned; NULL for a plain connection */
    void *app;                 /* owned by whoever set it (the h2 driver), released with app_free */
    void (*app_free)(void *app);
    int error_code;            /* the system code of the last failure, 0 when none */
    uint8_t broken;            /* an interrupted write left the ciphertext stream torn */
    uint8_t *unread;           /* owned: bytes a reader took ahead and gave back; ms_conn_read serves them first */
    size_t unread_length;
    uint16_t refusal;          /* the status the HTTP/1 server refused the last request head with, 0 for none */
} MsConnExt;

/* Gives the row a TLS session (the row owns it from now on). */
MsNetStatus ms_conn_set_tls(MsConnTable *table, MsConnId id, MsTls *tls);
/* Lets a protocol driver keep its state on the row; `app_free` runs once when the row closes. */
MsNetStatus ms_conn_set_app(MsConnTable *table, MsConnId id, void *app, void (*app_free)(void *app));
/* The driver's state, or NULL. */
void *ms_conn_app(MsConnTable *table, MsConnId id);
MsTls *ms_conn_tls(MsConnTable *table, MsConnId id);

/* Reads up to `capacity` plaintext bytes. On MS_NET_OK `*count` is 0 at the end of the stream. */
MsNetStatus ms_conn_read(MsConnTable *table, MsConnId id, uint8_t *buffer, size_t capacity, int64_t deadline_ns,
                         size_t *count);
/* The status a server's last request head on the row was refused with (0 when it was not): kept on the row so the loop
 * that answers it needs no other state. */
void ms_conn_set_refusal(MsConnTable *table, MsConnId id, uint16_t status);
uint16_t ms_conn_refusal(MsConnTable *table, MsConnId id);
/* Gives back bytes the caller read ahead of what it consumed, so the next ms_conn_read (whoever calls it) returns them
 * first. Later pushes go in front of earlier ones. MS_NET_FAILED when out of memory (nothing is kept). */
MsNetStatus ms_conn_unread(MsConnTable *table, MsConnId id, const uint8_t *data, size_t length);
/* Writes all `length` bytes. */
MsNetStatus ms_conn_write(MsConnTable *table, MsConnId id, const uint8_t *data, size_t length, int64_t deadline_ns);
/* Parks until the peer has ended its side or the connection broke, without taking any bytes: MS_NET_CLOSED when the
 * peer closed or half-closed, MS_NET_RESET on an error, MS_NET_CANCELLED when the task is cancelled. Bytes the peer
 * sent ahead (a pipelined request) stay queued and are polled for the end at a low rate. Once `*handed_on` (may be NULL)
 * is set, another owner reads the connection and the poll asks the system whether the peer ended its side
 * (ms_sys_net_peer_ended) instead of looking at the queued bytes. */
MsNetStatus ms_conn_wait_gone(MsConnTable *table, MsConnId id, const uint8_t *handed_on);
/* Runs a TLS handshake to the end (client or server, as the session was made). */
MsNetStatus ms_conn_handshake(MsConnTable *table, MsConnId id, int64_t deadline_ns);
/* Half-closes the write side; on TLS it sends close_notify first. */
MsNetStatus ms_conn_shutdown_write(MsConnTable *table, MsConnId id, int64_t deadline_ns);
/* Ends the connection: a best-effort close_notify, then the descriptor and the row. A stale id gives MS_NET_CLOSED. */
MsNetStatus ms_conn_close_io(MsConnTable *table, MsConnId id);

/* The system code of the last failure on the row (0 when none), and a short text for the last status. */
int ms_conn_error_code(MsConnTable *table, MsConnId id);
const char *ms_net_status_text(MsNetStatus status);

#endif
