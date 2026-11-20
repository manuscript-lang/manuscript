/* Sockets on Windows (Winsock 2): the interface of ms_rt/sys_net.h. Sockets are non-blocking and not inherited by child
   processes. Winsock starts lazily on the first call that needs it, so a program that never opens a socket never
   loads it. Compiled and run by the Windows legs only; PR checks are Linux. */
#include "ms_rt/sys_net.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include <string.h>

#ifndef SIO_UDP_CONNRESET
#define SIO_UDP_CONNRESET _WSAIOW(IOC_VENDOR, 12) /* mswsock.h */
#endif

static volatile LONG started; /* 0 not yet, 1 started, -1 failed */

static int startup(void) {
    if (started > 0) return 0;
    if (started < 0) return -1;
    WSADATA data;
    int rc = WSAStartup(MAKEWORD(2, 2), &data);
    InterlockedExchange(&started, rc == 0 ? 1 : -1); /* concurrent first calls both start it; Winsock counts the calls */
    if (rc) { WSASetLastError(rc); return -1; }
    return 0;
}

static int would_block(int e) { return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS; }

static int to_sockaddr(const MsAddr *a, SOCKADDR_STORAGE *ss) {
    memset(ss, 0, sizeof *ss);
    if (a->family == 4) {
        SOCKADDR_IN *s = (SOCKADDR_IN *)ss;
        s->sin_family = AF_INET;
        s->sin_port = htons(a->port);
        memcpy(&s->sin_addr, a->ip, 4);
        return (int)sizeof *s;
    }
    SOCKADDR_IN6 *s = (SOCKADDR_IN6 *)ss;
    s->sin6_family = AF_INET6;
    s->sin6_port = htons(a->port);
    memcpy(&s->sin6_addr, a->ip, 16);
    s->sin6_scope_id = a->scope;
    return (int)sizeof *s;
}

static void from_sockaddr(const SOCKADDR_STORAGE *ss, MsAddr *a) {
    memset(a, 0, sizeof *a);
    if (ss->ss_family == AF_INET) {
        const SOCKADDR_IN *s = (const SOCKADDR_IN *)ss;
        a->family = 4; a->port = ntohs(s->sin_port);
        memcpy(a->ip, &s->sin_addr, 4);
    } else {
        const SOCKADDR_IN6 *s = (const SOCKADDR_IN6 *)ss;
        a->family = 6; a->port = ntohs(s->sin6_port); a->scope = s->sin6_scope_id;
        memcpy(a->ip, &s->sin6_addr, 16);
    }
}

static int fail_close(SOCKET s) {
    int e = WSAGetLastError();
    closesocket(s);
    WSASetLastError(e);
    return MS_SYS_ERROR;
}

static int prepare(SOCKET s) {
    u_long on = 1;
    if (ioctlsocket(s, FIONBIO, &on) != 0) return -1;
    SetHandleInformation((HANDLE)s, HANDLE_FLAG_INHERIT, 0);
    return 0;
}

static int new_socket(const MsAddr *a, SOCKET *out) {
    if (startup()) return MS_SYS_ERROR;
    SOCKET s = WSASocketW(a->family == 4 ? AF_INET : AF_INET6, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
    if (s == INVALID_SOCKET) return MS_SYS_ERROR;
    if (prepare(s) < 0) return fail_close(s);
    *out = s;
    return MS_SYS_OK;
}

int ms_sys_net_tcp_socket(const MsAddr *addr, MsSock *out) {
    SOCKET s;
    if (new_socket(addr, &s)) return MS_SYS_ERROR;
    *out = (MsSock)s;
    return MS_SYS_OK;
}

int ms_sys_net_tcp_listen(const MsAddr *addr, int backlog, MsSock *out) {
    SOCKET s;
    if (new_socket(addr, &s)) return MS_SYS_ERROR;
    SOCKADDR_STORAGE ss;
    int len = to_sockaddr(addr, &ss);
    BOOL on = TRUE; /* not SO_REUSEADDR: on Windows it would let another process take the port */
    setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char *)&on, sizeof on);
    if (addr->family == 6) { /* dual stack explicitly: Windows defaults to IPv6 only */
        DWORD off = 0;
        setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, (const char *)&off, sizeof off);
    }
    if (bind(s, (SOCKADDR *)&ss, len) != 0 || listen(s, backlog) != 0) return fail_close(s);
    *out = (MsSock)s;
    return MS_SYS_OK;
}

int ms_sys_net_udp_bind(const MsAddr *addr, MsSock *out) {
    if (startup()) return MS_SYS_ERROR;
    SOCKET s = WSASocketW(addr->family == 4 ? AF_INET : AF_INET6, SOCK_DGRAM, IPPROTO_UDP, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
    if (s == INVALID_SOCKET) return MS_SYS_ERROR;
    if (prepare(s) < 0) return fail_close(s);
    BOOL reset = FALSE; /* a datagram to a closed port must not make the next receive fail (WSAECONNRESET) */
    DWORD returned = 0;
    WSAIoctl(s, SIO_UDP_CONNRESET, &reset, sizeof reset, NULL, 0, &returned, NULL, NULL);
    if (addr->family == 6) {
        DWORD off = 0;
        setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, (const char *)&off, sizeof off);
    }
    SOCKADDR_STORAGE ss;
    int len = to_sockaddr(addr, &ss);
    if (bind(s, (SOCKADDR *)&ss, len) != 0) return fail_close(s);
    *out = (MsSock)s;
    return MS_SYS_OK;
}

int ms_sys_net_udp_recv(MsSock s, void *buf, size_t n, size_t *done, MsAddr *from) {
    SOCKADDR_STORAGE ss;
    int len = (int)sizeof ss;
    int want = n > 0x40000000 ? 0x40000000 : (int)n;
    int r = recvfrom((SOCKET)s, (char *)buf, want, 0, (SOCKADDR *)&ss, &len);
    if (r == SOCKET_ERROR) {
        const int e = WSAGetLastError();
        if (e == WSAEMSGSIZE) return MS_SYS_TOO_BIG;
        return would_block(e) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    }
    *done = (size_t)r;
    if (from) from_sockaddr(&ss, from);
    return MS_SYS_OK;
}

int ms_sys_net_udp_send(MsSock s, const void *buf, size_t n, const MsAddr *to, size_t *done) {
    SOCKADDR_STORAGE ss;
    int len = to_sockaddr(to, &ss);
    int want = n > 0x40000000 ? 0x40000000 : (int)n;
    int r = sendto((SOCKET)s, (const char *)buf, want, 0, (SOCKADDR *)&ss, len);
    if (r == SOCKET_ERROR) return would_block(WSAGetLastError()) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    return MS_SYS_OK;
}

int ms_sys_net_tcp_connect(const MsAddr *addr, MsSock *out) {
    SOCKET s;
    if (new_socket(addr, &s)) return MS_SYS_ERROR;
    SOCKADDR_STORAGE ss;
    int len = to_sockaddr(addr, &ss);
    BOOL on = TRUE;
    setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&on, sizeof on);
    if (connect(s, (SOCKADDR *)&ss, len) == 0) { *out = (MsSock)s; return MS_SYS_OK; }
    if (would_block(WSAGetLastError())) { *out = (MsSock)s; return MS_SYS_INPROGRESS; }
    return fail_close(s);
}

int ms_sys_net_connect_done(MsSock s) {
    int err = 0, len = (int)sizeof err;
    if (getsockopt((SOCKET)s, SOL_SOCKET, SO_ERROR, (char *)&err, &len) != 0) return MS_SYS_ERROR;
    if (err) { WSASetLastError(err); return MS_SYS_ERROR; }
    return MS_SYS_OK;
}

int ms_sys_net_accept(MsSock listener, MsSock *out, MsAddr *peer) {
    SOCKADDR_STORAGE ss;
    int len = (int)sizeof ss;
    SOCKET s = accept((SOCKET)listener, (SOCKADDR *)&ss, &len);
    if (s == INVALID_SOCKET) return would_block(WSAGetLastError()) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    if (prepare(s) < 0) return fail_close(s);
    BOOL on = TRUE;
    setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&on, sizeof on);
    if (peer) from_sockaddr(&ss, peer);
    *out = (MsSock)s;
    return MS_SYS_OK;
}

int ms_sys_net_read(MsSock s, void *buf, size_t n, size_t *done) {
    int want = n > 0x40000000 ? 0x40000000 : (int)n;
    int r = recv((SOCKET)s, (char *)buf, want, 0);
    if (r == SOCKET_ERROR) return would_block(WSAGetLastError()) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    return r == 0 && n > 0 ? MS_SYS_EOF : MS_SYS_OK;
}

int ms_sys_net_write(MsSock s, const void *buf, size_t n, size_t *done) {
    int want = n > 0x40000000 ? 0x40000000 : (int)n;
    int r = send((SOCKET)s, (const char *)buf, want, 0);
    if (r == SOCKET_ERROR) return would_block(WSAGetLastError()) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    return MS_SYS_OK;
}

int ms_sys_net_local_addr(MsSock s, MsAddr *out) {
    SOCKADDR_STORAGE ss;
    int len = (int)sizeof ss;
    if (getsockname((SOCKET)s, (SOCKADDR *)&ss, &len) != 0) return MS_SYS_ERROR;
    from_sockaddr(&ss, out);
    return MS_SYS_OK;
}

int ms_sys_net_peer_addr(MsSock s, MsAddr *out) {
    SOCKADDR_STORAGE ss;
    int len = (int)sizeof ss;
    if (getpeername((SOCKET)s, (SOCKADDR *)&ss, &len) != 0) return MS_SYS_ERROR;
    from_sockaddr(&ss, out);
    return MS_SYS_OK;
}

int ms_sys_net_shutdown(MsSock s, int how) { return shutdown((SOCKET)s, how == 1 ? SD_SEND : SD_BOTH) != 0 ? MS_SYS_ERROR : MS_SYS_OK; }
void ms_sys_net_close(MsSock s) { closesocket((SOCKET)s); }
int ms_sys_net_error(void) { return WSAGetLastError(); }

int ms_sys_net_addr_from_raw(const void *sockaddr, size_t length, MsAddr *out) {
    SOCKADDR_STORAGE ss;
    if (length < sizeof(ADDRESS_FAMILY) || length > sizeof ss) return -1;
    memset(&ss, 0, sizeof ss);
    memcpy(&ss, sockaddr, length);
    const size_t need = ss.ss_family == AF_INET ? sizeof(SOCKADDR_IN) : sizeof(SOCKADDR_IN6);
    if ((ss.ss_family != AF_INET && ss.ss_family != AF_INET6) || length < need) return -1;
    from_sockaddr(&ss, out);
    return 0;
}
