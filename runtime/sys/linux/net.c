/* Sockets on Linux: the POSIX implementation shared with macOS. */
#define _GNU_SOURCE 1
#include "../posix_net.h"
#include <poll.h>

int ms_sys_net_peer_ended(MsSock s) {
    struct pollfd probe = {.fd = (int)s, .events = POLLRDHUP};
    int ready;
    do ready = poll(&probe, 1, 0); while (ready < 0 && errno == EINTR);
    return ready > 0 && (probe.revents & (POLLRDHUP | POLLHUP | POLLERR)) != 0;
}
