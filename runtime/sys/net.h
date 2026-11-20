/* Sockets: the only door to the operating system's network calls. Every socket here is non-blocking and
   close-on-exec; a call that would block returns MS_SYS_AGAIN and the reactor (runtime/io) says when to retry.
   Implemented per platform: sys/posix_net.h (Linux and macOS) and sys/windows/net.c. */
#ifndef MS_SYS_NET_H
#define MS_SYS_NET_H
#include <stddef.h>
#include <stdint.h>

typedef intptr_t ms_sock; /* a descriptor, or a SOCKET on Windows */
#define MS_SOCK_INVALID ((ms_sock)-1)

typedef struct {
    uint8_t family;   /* 4 or 6 */
    uint8_t ip[16];   /* the first 4 bytes for IPv4 */
    uint16_t port;    /* host order */
    uint32_t scope;   /* IPv6 scope id, else 0 */
} ms_addr;

enum {
    MS_SYS_OK = 0,
    MS_SYS_AGAIN = 1,      /* would block: wait for readiness and call again */
    MS_SYS_EOF = 2,        /* read: the peer closed its side */
    MS_SYS_INPROGRESS = 3, /* connect started: wait for writability, then ms_sys_connect_done */
    MS_SYS_ERROR = -1      /* see ms_sys_error() */
};

/* A listening socket on `addr` (port 0 picks one; read it back with ms_sys_local_addr). */
int ms_sys_tcp_listen(const ms_addr *addr, int backlog, ms_sock *out);
/* Starts a connection: OK when connected at once, INPROGRESS otherwise. */
int ms_sys_tcp_connect(const ms_addr *addr, ms_sock *out);
/* After INPROGRESS and writability: OK when connected, ERROR (ms_sys_error is the cause) when it failed. */
int ms_sys_connect_done(ms_sock s);
/* The next pending connection of a listener; `peer` may be NULL. AGAIN when none is waiting. */
int ms_sys_accept(ms_sock listener, ms_sock *out, ms_addr *peer);
/* One read or write; the byte count goes to *done. A read of 0 bytes returns EOF. Writes never raise SIGPIPE. */
int ms_sys_read(ms_sock s, void *buf, size_t n, size_t *done);
int ms_sys_write(ms_sock s, const void *buf, size_t n, size_t *done);
int ms_sys_local_addr(ms_sock s, ms_addr *out);
int ms_sys_peer_addr(ms_sock s, ms_addr *out);
/* Half-closes the write side (how = 1) or both (how = 2). */
int ms_sys_shutdown(ms_sock s, int how);
void ms_sys_close(ms_sock s);
/* The operating system's code for the last MS_SYS_ERROR on this thread (errno, or WSAGetLastError). */
int ms_sys_error(void);

#endif
