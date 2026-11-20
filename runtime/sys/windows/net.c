/* Sockets on Windows (Winsock 2): the interface of ms_rt/sys_net.h. Sockets are non-blocking and not inherited by child
   processes. Winsock starts lazily on the first call that needs it, so a program that never opens a socket never
   loads it. Compiled and run by the Windows legs only; PR checks are Linux. */
#include "ms_rt/sys_net.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include <afunix.h>
#include <iphlpapi.h>
#include <stdio.h>
#include <stdlib.h>
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

static int unix_address(const char *path, SOCKADDR_UN *sun) {
    memset(sun, 0, sizeof *sun);
    sun->sun_family = AF_UNIX;
    const size_t length = strlen(path);
    if (length == 0 || length >= sizeof sun->sun_path) { /* an empty path would autobind an abstract address */
        WSASetLastError(length == 0 ? WSAEINVAL : WSAENAMETOOLONG);
        return -1;
    }
    memcpy(sun->sun_path, path, length);
    return 0;
}

static int new_unix_socket(SOCKET *out) {
    if (startup()) return MS_SYS_ERROR;
    SOCKET s = WSASocketW(AF_UNIX, SOCK_STREAM, 0, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
    if (s == INVALID_SOCKET) return MS_SYS_ERROR;
    *out = s;
    return MS_SYS_OK;
}

int ms_sys_net_unix_listen(const char *path, int backlog, MsSock *out) {
    SOCKADDR_UN sun;
    SOCKET s;
    if (unix_address(path, &sun) < 0 || new_unix_socket(&s)) return MS_SYS_ERROR;
    if (prepare(s) < 0 || bind(s, (SOCKADDR *)&sun, (int)sizeof sun) != 0 || listen(s, backlog) != 0) return fail_close(s);
    *out = (MsSock)s;
    return MS_SYS_OK;
}

int ms_sys_net_unix_connect(const char *path, MsSock *out) {
    SOCKADDR_UN sun;
    SOCKET s;
    if (unix_address(path, &sun) < 0 || new_unix_socket(&s)) return MS_SYS_ERROR;
    if (connect(s, (SOCKADDR *)&sun, (int)sizeof sun) != 0 || prepare(s) < 0) return fail_close(s); /* blocking until here */
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

/* WinSock reports a peer's end only through a read that reaches it, so queued bytes hide it: no answer here. */
int ms_sys_net_peer_ended(MsSock s) {
    (void)s;
    return 0;
}

int ms_sys_net_peek(MsSock s, void *buf, size_t n, size_t *done) {
    int want = n > 0x40000000 ? 0x40000000 : (int)n;
    int r = recv((SOCKET)s, (char *)buf, want, MSG_PEEK);
    if (r == SOCKET_ERROR) {
        int e = WSAGetLastError();
        if (e == WSAEMSGSIZE) { *done = n; return MS_SYS_OK; }
        return would_block(e) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    }
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
    if (ss.ss_family != AF_INET && ss.ss_family != AF_INET6) { WSASetLastError(WSAEAFNOSUPPORT); return MS_SYS_ERROR; }
    from_sockaddr(&ss, out);
    return MS_SYS_OK;
}

int ms_sys_net_peer_addr(MsSock s, MsAddr *out) {
    SOCKADDR_STORAGE ss;
    int len = (int)sizeof ss;
    if (getpeername((SOCKET)s, (SOCKADDR *)&ss, &len) != 0) return MS_SYS_ERROR;
    if (ss.ss_family != AF_INET && ss.ss_family != AF_INET6) { WSASetLastError(WSAEAFNOSUPPORT); return MS_SYS_ERROR; }
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

/* ---- resolver configuration ---- */

/* Appends printf-style text to out[capacity] at *used; text that does not fit is dropped whole. */
static void append_text(char *out, size_t capacity, size_t *used, const char *format, const char *value) {
    char line[1200];
    const int n = snprintf(line, sizeof line, format, value);
    if (n > 0 && (size_t)n < sizeof line && *used + (size_t)n <= capacity) {
        memcpy(out + *used, line, (size_t)n);
        *used += (size_t)n;
    }
}

/* Windows lists the site-local placeholders fec0:0:0:ffff::1-3 for adapters without IPv6 DNS; they never answer. */
static int site_local_placeholder(const SOCKADDR_IN6 *a) {
    const unsigned char *b = a->sin6_addr.s6_addr;
    static const unsigned char prefix[14] = {0xfe, 0xc0, 0, 0, 0, 0, 0, 0xff, 0xff, 0, 0, 0, 0, 0};
    return memcmp(b, prefix, 14) == 0 && b[14] == 0 && b[15] >= 1 && b[15] <= 3;
}

size_t ms_sys_net_dns_config(char *out, size_t capacity) {
    const ULONG flags = GAA_FLAG_SKIP_UNICAST | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_FRIENDLY_NAME;
    ULONG length = 16 * 1024;
    IP_ADAPTER_ADDRESSES *list = NULL;
    ULONG result = ERROR_BUFFER_OVERFLOW;
    for (int attempt = 0; attempt < 4 && result == ERROR_BUFFER_OVERFLOW; attempt++) {
        free(list);
        list = malloc(length);
        if (list == NULL) return 0;
        result = GetAdaptersAddresses(AF_UNSPEC, flags, NULL, list, &length);
    }
    size_t used = 0;
    if (result == NO_ERROR) {
        char seen[8][64]; /* servers written so far, as text */
        size_t seen_count = 0;
        for (const IP_ADAPTER_ADDRESSES *a = list; a != NULL; a = a->Next) {
            if (a->OperStatus != IfOperStatusUp) continue;
            for (const IP_ADAPTER_DNS_SERVER_ADDRESS *d = a->FirstDnsServerAddress; d != NULL; d = d->Next) {
                char text[64];
                const SOCKADDR *sa = d->Address.lpSockaddr;
                if (sa == NULL) continue;
                if (sa->sa_family == AF_INET && d->Address.iSockaddrLength >= (INT)sizeof(SOCKADDR_IN)) {
                    if (inet_ntop(AF_INET, &((const SOCKADDR_IN *)sa)->sin_addr, text, sizeof text) == NULL) continue;
                } else if (sa->sa_family == AF_INET6 && d->Address.iSockaddrLength >= (INT)sizeof(SOCKADDR_IN6)) {
                    if (site_local_placeholder((const SOCKADDR_IN6 *)sa)) continue;
                    if (inet_ntop(AF_INET6, &((const SOCKADDR_IN6 *)sa)->sin6_addr, text, sizeof text) == NULL) continue;
                } else {
                    continue;
                }
                int duplicate = 0;
                for (size_t i = 0; i < seen_count; i++) duplicate |= strcmp(seen[i], text) == 0;
                if (duplicate || seen_count == sizeof seen / sizeof seen[0]) continue;
                memcpy(seen[seen_count++], text, strlen(text) + 1);
                append_text(out, capacity, &used, "nameserver %s\n", text);
            }
        }
        char suffixes[1024] = ""; /* one search line: resolv.conf keeps the last one */
        for (const IP_ADAPTER_ADDRESSES *a = list; a != NULL; a = a->Next) {
            char suffix[256];
            if (a->OperStatus != IfOperStatusUp || a->DnsSuffix == NULL || a->DnsSuffix[0] == 0) continue;
            const int n = WideCharToMultiByte(CP_UTF8, 0, a->DnsSuffix, -1, suffix, (int)sizeof suffix, NULL, NULL);
            const size_t length = strlen(suffixes);
            if (n <= 1 || length + (size_t)n + 2 >= sizeof suffixes) continue;
            const size_t gap = length != 0 ? 1 : 0;
            if (gap != 0) suffixes[length] = ' ';
            memcpy(suffixes + length + gap, suffix, (size_t)n); /* n counts the terminating NUL */
        }
        if (suffixes[0] != 0) append_text(out, capacity, &used, "search %s\n", suffixes);
    }
    free(list);
    return used;
}
