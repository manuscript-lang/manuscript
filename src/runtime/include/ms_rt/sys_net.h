/* ms_rt/sys_net.h: sockets, the only door to the operating system's network calls. Every socket here is non-blocking and
   close-on-exec; a call that would block returns MS_SYS_AGAIN and the reactor (src/runtime/io) says when to retry.
   Implemented per platform: sys/posix_net.h (Linux and macOS) and sys/windows/net.c. */
#ifndef MS_RT_SYS_NET_H
#define MS_RT_SYS_NET_H
#include <stddef.h>
#include <stdint.h>

typedef intptr_t MsSock; /* a descriptor, or a SOCKET on Windows */
#define MS_SOCK_INVALID ((MsSock)-1)

typedef struct {
    uint8_t family;   /* 4 or 6 */
    uint8_t ip[16];   /* the first 4 bytes for IPv4 */
    uint16_t port;    /* host order */
    uint32_t scope;   /* IPv6 scope id, else 0 */
} MsAddr;

enum {
    MS_SYS_OK = 0,
    MS_SYS_AGAIN = 1,      /* would block: wait for readiness and call again */
    MS_SYS_EOF = 2,        /* read: the peer closed its side */
    MS_SYS_INPROGRESS = 3, /* connect started: wait for writability, then ms_sys_net_connect_done */
    MS_SYS_TOO_BIG = 4,    /* a datagram larger than the buffer (Windows refuses it; elsewhere it is truncated, so
                              callers read one byte more than they accept and compare) */
    MS_SYS_ERROR = -1      /* see ms_sys_net_error() */
};

/* A new non-blocking TCP socket of the family of `addr`, not bound or connected. For a library that connects the
 * socket itself (libcurl's open-socket callback). */
int ms_sys_net_tcp_socket(const MsAddr *addr, MsSock *out);
/* A listening Unix domain socket bound to the NUL-terminated `path` (an existing file there is an error, as for bind;
 * a path longer than the system's limit fails with its error code). The caller removes the file when it closes. */
int ms_sys_net_unix_listen(const char *path, int backlog, MsSock *out);
/* A connected Unix domain stream socket to `path`. The connect itself may block while the listener's queue is full. */
int ms_sys_net_unix_connect(const char *path, MsSock *out);
/* A listening socket on `addr` (port 0 picks one; read it back with ms_sys_net_local_addr). */
int ms_sys_net_tcp_listen(const MsAddr *addr, int backlog, MsSock *out);
/* Starts a connection: OK when connected at once, INPROGRESS otherwise. */
int ms_sys_net_tcp_connect(const MsAddr *addr, MsSock *out);
/* After INPROGRESS and writability: OK when connected, ERROR (ms_sys_net_error is the cause) when it failed. */
int ms_sys_net_connect_done(MsSock s);
/* A UDP socket bound to `addr` (port 0 picks one; read it back with ms_sys_net_local_addr). IPv6 sockets accept IPv4
 * too, as with the TCP listener. */
int ms_sys_net_udp_bind(const MsAddr *addr, MsSock *out);
/* Receives one datagram into buf[n], its sender to *from (may be NULL); the byte count goes to *done. AGAIN when none is
 * waiting; TOO_BIG when the system refused one longer than the buffer. */
int ms_sys_net_udp_recv(MsSock s, void *buf, size_t n, size_t *done, MsAddr *from);
/* Sends one datagram to `to`: OK with the whole of it in *done, AGAIN when the buffer is full. */
int ms_sys_net_udp_send(MsSock s, const void *buf, size_t n, const MsAddr *to, size_t *done);
/* The next pending connection of a listener; `peer` may be NULL. AGAIN when none is waiting. */
int ms_sys_net_accept(MsSock listener, MsSock *out, MsAddr *peer);
/* One read or write; the byte count goes to *done. A read of 0 bytes returns EOF. Writes never raise SIGPIPE. */
int ms_sys_net_read(MsSock s, void *buf, size_t n, size_t *done);
int ms_sys_net_write(MsSock s, const void *buf, size_t n, size_t *done);
/* Like ms_sys_net_read but leaves the bytes queued: whether the peer has ended its side shows without consuming data. */
int ms_sys_net_peek(MsSock s, void *buf, size_t n, size_t *done);
/* Whether the peer has ended its side even when unread bytes are queued ahead of the end (peek sees only the bytes):
 * 1 when it has, 0 when it has not or the system cannot tell (Windows has no such query). */
int ms_sys_net_peer_ended(MsSock s);
/* The socket's own and peer address. MS_SYS_ERROR for a Unix domain socket, which has no MsAddr. */
int ms_sys_net_local_addr(MsSock s, MsAddr *out);
int ms_sys_net_peer_addr(MsSock s, MsAddr *out);
/* Half-closes the write side (how = 1) or both (how = 2). */
int ms_sys_net_shutdown(MsSock s, int how);
void ms_sys_net_close(MsSock s);
/* Another descriptor for the same socket (dup, close-on-exec; WSADuplicateSocket on Windows): both end the connection's
 * use only when each is closed, so one thread can register a socket with its reactor while another still holds it. */
int ms_sys_net_duplicate(MsSock s, MsSock *out);
/* The operating system's code for the last MS_SYS_ERROR on this thread (errno, or WSAGetLastError). */
int ms_sys_net_error(void);
/* Reads an IPv4 or IPv6 socket address, as the resolver returns it, into `out`. -1 for another family or a short one. */
int ms_sys_net_addr_from_raw(const void *sockaddr, size_t length, MsAddr *out);

/* The host's resolver configuration as resolv.conf text, written to out[capacity]; returns its length (0 when there is
 * none). On Windows it is made from the DNS servers and suffixes of the operational adapters. */
size_t ms_sys_net_dns_config(char *out, size_t capacity);

#endif
