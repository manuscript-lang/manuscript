/* Connection rows. A connection is one 64-byte row in a flat table, addressed by a 64-bit handle (row index in the
   low half, generation in the high half). The row holds only what an idle connection needs; the partial-input
   stash, the TLS object and the protocol state hang off it and exist only while in use. An idle plain connection
   owns its row and nothing else. Stale handles (a closed row, or a row reused since) resolve to NULL. */
#ifndef MS_NET_CONN_H
#define MS_NET_CONN_H
#include <stddef.h>
#include <stdint.h>
#include "http1.h"

enum { MS_CONN_NONE = 0, MS_CONN_HTTP1 = 1, MS_CONN_WS = 2, MS_CONN_H2 = 3 };

typedef struct {
    int32_t fd;
    uint32_t gen;          /* bumped on free; 0 is never a live generation */
    uint16_t owner;        /* scheduler thread that owns the poll handle */
    uint8_t proto, state;
    uint16_t flags;
    uint16_t spare;
    uint32_t timer;        /* timer wheel slot; the next free row while the row is free */
    uint32_t stash_len;    /* bytes of input kept from a short read */
    uint8_t *stash;        /* heap, NULL when idle */
    uint8_t *wpend;        /* output the socket did not take yet */
    uint32_t wlen, wcap;
    void *ext;             /* TLS object, h2 session, ...: cold state, NULL when idle */
    uint64_t waiter;       /* the handler or task parked on this row */
} MsConn;

_Static_assert(sizeof(MsConn) == 64, "an idle connection row is one cache line");

typedef struct MsConnTable MsConnTable;
typedef uint64_t MsConnId;

MsConnTable *ms_conn_table_new(uint32_t capacity);
void ms_conn_table_free(MsConnTable *t); /* releases every row's heap state */
/* A fresh row; 0 when the table is full. */
MsConnId ms_conn_open(MsConnTable *t, int fd, uint8_t proto);
MsConn *ms_conn_get(MsConnTable *t, MsConnId id);
/* Frees the row's heap state and bumps the generation. Returns 0, or -1 for a stale handle. */
int ms_conn_close(MsConnTable *t, MsConnId id);
uint32_t ms_conn_live(const MsConnTable *t);

/* HTTP/1 input. Feed bytes read from the socket (or TLS plaintext), or n == 0 to parse bytes already kept (a
   pipelined request). The result says what the connection needs:
   - MS_CONN_NEED_MORE: nothing complete yet; the bytes are kept in the row's stash.
   - MS_CONN_REQUEST: a request head is complete. `*base` points at the bytes it spans (the caller's buffer or the
     stash) and `*avail` is how many bytes are there; req's offsets are relative to `*base`. Valid until
     ms_conn_request_done. `fields` is the caller's storage for `cap` header fields.
   - MS_CONN_BAD: refuse with req->status and close. */
enum { MS_CONN_NEED_MORE = 0, MS_CONN_REQUEST = 1, MS_CONN_BAD = 2 };
int ms_conn_h1_feed(MsConn *c, const uint8_t *buf, size_t n, size_t head_limit, MsH1Field *fields, uint32_t cap,
                    MsH1Request *req, const uint8_t **base, size_t *avail);
/* The request is finished after `consumed` bytes of `base` (head plus any body bytes the caller used). Bytes beyond
   that, a pipelined next request, are kept in the row; when none remain the stash is freed. Returns the bytes kept. */
size_t ms_conn_request_done(MsConn *c, const uint8_t *base, size_t avail, size_t consumed);

#endif
