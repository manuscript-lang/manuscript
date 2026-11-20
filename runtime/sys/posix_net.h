/* Sockets on POSIX systems; included by sys/linux/net.c and sys/darwin/net.c so the two cannot drift. */
#include "ms_rt/sys_net.h"
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#ifdef MSG_NOSIGNAL
#define MS_SEND_FLAGS MSG_NOSIGNAL
#else
#define MS_SEND_FLAGS 0 /* macOS: SO_NOSIGPIPE is set on every socket instead */
#endif

static int again(int e) { return e == EAGAIN || e == EWOULDBLOCK; }

static socklen_t to_sockaddr(const MsAddr *a, struct sockaddr_storage *ss) {
    memset(ss, 0, sizeof *ss);
    if (a->family == 4) {
        struct sockaddr_in *s = (struct sockaddr_in *)ss;
        s->sin_family = AF_INET;
        s->sin_port = htons(a->port);
        memcpy(&s->sin_addr, a->ip, 4);
        return sizeof *s;
    }
    struct sockaddr_in6 *s = (struct sockaddr_in6 *)ss;
    s->sin6_family = AF_INET6;
    s->sin6_port = htons(a->port);
    memcpy(&s->sin6_addr, a->ip, 16);
    s->sin6_scope_id = a->scope;
    return sizeof *s;
}

static void from_sockaddr(const struct sockaddr_storage *ss, MsAddr *a) {
    memset(a, 0, sizeof *a);
    if (ss->ss_family == AF_INET) {
        const struct sockaddr_in *s = (const struct sockaddr_in *)ss;
        a->family = 4; a->port = ntohs(s->sin_port);
        memcpy(a->ip, &s->sin_addr, 4);
    } else {
        const struct sockaddr_in6 *s = (const struct sockaddr_in6 *)ss;
        a->family = 6; a->port = ntohs(s->sin6_port); a->scope = s->sin6_scope_id;
        memcpy(a->ip, &s->sin6_addr, 16);
    }
}

/* Marks a descriptor non-blocking and close-on-exec (and signal-free writes on macOS). */
static int prepare(int fd) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl < 0 || fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) return -1;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) return -1;
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
    return 0;
}

static int fail_close(int fd) { int e = errno; close(fd); errno = e; return MS_SYS_ERROR; }

static int new_socket(const MsAddr *a, int *fd) {
    int s = socket(a->family == 4 ? AF_INET : AF_INET6, SOCK_STREAM, 0);
    if (s < 0) return MS_SYS_ERROR;
    if (prepare(s) < 0) return fail_close(s);
    *fd = s;
    return MS_SYS_OK;
}

int ms_sys_net_tcp_socket(const MsAddr *addr, MsSock *out) {
    int fd;
    if (new_socket(addr, &fd)) return MS_SYS_ERROR;
    *out = fd;
    return MS_SYS_OK;
}

int ms_sys_net_tcp_listen(const MsAddr *addr, int backlog, MsSock *out) {
    int fd;
    if (new_socket(addr, &fd)) return MS_SYS_ERROR;
    int one = 1;
    struct sockaddr_storage ss;
    socklen_t len = to_sockaddr(addr, &ss);
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (addr->family == 6) { /* dual stack explicitly: some systems default to IPv6 only */
        int off = 0;
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &off, sizeof off);
    }
    if (bind(fd, (struct sockaddr *)&ss, len) < 0 || listen(fd, backlog) < 0) return fail_close(fd);
    *out = fd;
    return MS_SYS_OK;
}

static int unix_address(const char *path, struct sockaddr_un *sun) {
    memset(sun, 0, sizeof *sun);
    sun->sun_family = AF_UNIX;
    const size_t length = strlen(path);
    if (length == 0 || length >= sizeof sun->sun_path) { /* an empty path would autobind an abstract address */
        errno = length == 0 ? EINVAL : ENAMETOOLONG;
        return -1;
    }
    memcpy(sun->sun_path, path, length);
    return 0;
}

int ms_sys_net_unix_listen(const char *path, int backlog, MsSock *out) {
    struct sockaddr_un sun;
    if (unix_address(path, &sun) < 0) return MS_SYS_ERROR;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return MS_SYS_ERROR;
    if (prepare(fd) < 0) return fail_close(fd);
    if (bind(fd, (struct sockaddr *)&sun, sizeof sun) < 0 || listen(fd, backlog) < 0) return fail_close(fd);
    *out = fd;
    return MS_SYS_OK;
}

int ms_sys_net_unix_connect(const char *path, MsSock *out) {
    struct sockaddr_un sun;
    if (unix_address(path, &sun) < 0) return MS_SYS_ERROR;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return MS_SYS_ERROR;
    int r;
    do r = connect(fd, (struct sockaddr *)&sun, sizeof sun); while (r < 0 && errno == EINTR);
    if (r < 0 || prepare(fd) < 0) return fail_close(fd); /* blocking until here, so a full queue waits */
    *out = fd;
    return MS_SYS_OK;
}

int ms_sys_net_udp_bind(const MsAddr *addr, MsSock *out) {
    int fd = socket(addr->family == 4 ? AF_INET : AF_INET6, SOCK_DGRAM, 0);
    if (fd < 0) return MS_SYS_ERROR;
    if (prepare(fd) < 0) return fail_close(fd);
    struct sockaddr_storage ss;
    const socklen_t len = to_sockaddr(addr, &ss);
    if (addr->family == 6) {
        int off = 0;
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &off, sizeof off);
    }
    if (bind(fd, (struct sockaddr *)&ss, len) < 0) return fail_close(fd);
    *out = fd;
    return MS_SYS_OK;
}

int ms_sys_net_udp_recv(MsSock s, void *buf, size_t n, size_t *done, MsAddr *from) {
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    ssize_t r;
    do r = recvfrom((int)s, buf, n, 0, (struct sockaddr *)&ss, &len); while (r < 0 && errno == EINTR);
    if (r < 0) return again(errno) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    if (from) from_sockaddr(&ss, from);
    return MS_SYS_OK;
}

int ms_sys_net_udp_send(MsSock s, const void *buf, size_t n, const MsAddr *to, size_t *done) {
    struct sockaddr_storage ss;
    const socklen_t len = to_sockaddr(to, &ss);
    ssize_t r;
    do r = sendto((int)s, buf, n, MS_SEND_FLAGS, (struct sockaddr *)&ss, len); while (r < 0 && errno == EINTR);
    if (r < 0) return again(errno) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    return MS_SYS_OK;
}

int ms_sys_net_tcp_connect(const MsAddr *addr, MsSock *out) {
    int fd;
    if (new_socket(addr, &fd)) return MS_SYS_ERROR;
    int one = 1;
    struct sockaddr_storage ss;
    socklen_t len = to_sockaddr(addr, &ss);
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    if (connect(fd, (struct sockaddr *)&ss, len) == 0) { *out = fd; return MS_SYS_OK; }
    if (errno == EINPROGRESS || errno == EINTR) { *out = fd; return MS_SYS_INPROGRESS; }
    return fail_close(fd);
}

int ms_sys_net_connect_done(MsSock s) {
    int err = 0;
    socklen_t len = sizeof err;
    if (getsockopt((int)s, SOL_SOCKET, SO_ERROR, &err, &len) < 0) return MS_SYS_ERROR;
    if (err) { errno = err; return MS_SYS_ERROR; }
    return MS_SYS_OK;
}

int ms_sys_net_accept(MsSock listener, MsSock *out, MsAddr *peer) {
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    int fd;
    do fd = accept((int)listener, (struct sockaddr *)&ss, &len); while (fd < 0 && errno == EINTR); // NOLINT(android-cloexec-accept): macOS has no accept4; prepare() sets close-on-exec
    if (fd < 0) return again(errno) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    if (prepare(fd) < 0) return fail_close(fd);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    if (peer) from_sockaddr(&ss, peer);
    *out = fd;
    return MS_SYS_OK;
}

int ms_sys_net_read(MsSock s, void *buf, size_t n, size_t *done) {
    ssize_t r;
    do r = recv((int)s, buf, n, 0); while (r < 0 && errno == EINTR);
    if (r < 0) return again(errno) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    return r == 0 && n > 0 ? MS_SYS_EOF : MS_SYS_OK;
}

int ms_sys_net_peek(MsSock s, void *buf, size_t n, size_t *done) {
    ssize_t r;
    do r = recv((int)s, buf, n, MSG_PEEK); while (r < 0 && errno == EINTR);
    if (r < 0) return again(errno) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    return r == 0 && n > 0 ? MS_SYS_EOF : MS_SYS_OK;
}

int ms_sys_net_write(MsSock s, const void *buf, size_t n, size_t *done) {
    ssize_t r;
    do r = send((int)s, buf, n, MS_SEND_FLAGS); while (r < 0 && errno == EINTR);
    if (r < 0) return again(errno) ? MS_SYS_AGAIN : MS_SYS_ERROR;
    *done = (size_t)r;
    return MS_SYS_OK;
}

int ms_sys_net_local_addr(MsSock s, MsAddr *out) {
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    if (getsockname((int)s, (struct sockaddr *)&ss, &len) < 0) return MS_SYS_ERROR;
    if (ss.ss_family != AF_INET && ss.ss_family != AF_INET6) { errno = EAFNOSUPPORT; return MS_SYS_ERROR; }
    from_sockaddr(&ss, out);
    return MS_SYS_OK;
}

int ms_sys_net_peer_addr(MsSock s, MsAddr *out) {
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    if (getpeername((int)s, (struct sockaddr *)&ss, &len) < 0) return MS_SYS_ERROR;
    if (ss.ss_family != AF_INET && ss.ss_family != AF_INET6) { errno = EAFNOSUPPORT; return MS_SYS_ERROR; }
    from_sockaddr(&ss, out);
    return MS_SYS_OK;
}

int ms_sys_net_shutdown(MsSock s, int how) { return shutdown((int)s, how == 1 ? SHUT_WR : SHUT_RDWR) < 0 ? MS_SYS_ERROR : MS_SYS_OK; }
void ms_sys_net_close(MsSock s) { close((int)s); }
int ms_sys_net_error(void) { return errno; }

int ms_sys_net_addr_from_raw(const void *sockaddr, size_t length, MsAddr *out) {
    struct sockaddr_storage ss;
    if (length < sizeof(sa_family_t) || length > sizeof ss) return -1;
    memset(&ss, 0, sizeof ss);
    memcpy(&ss, sockaddr, length);
    const size_t need = ss.ss_family == AF_INET ? sizeof(struct sockaddr_in) : sizeof(struct sockaddr_in6);
    if ((ss.ss_family != AF_INET && ss.ss_family != AF_INET6) || length < need) return -1;
    from_sockaddr(&ss, out);
    return 0;
}

size_t ms_sys_net_dns_config(char *out, size_t capacity) {
    const int fd = open("/etc/resolv.conf", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    size_t used = 0;
    while (used < capacity) {
        const ssize_t r = read(fd, out + used, capacity - used);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        used += (size_t)r;
    }
    close(fd);
    return used;
}
