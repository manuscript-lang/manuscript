/* Sockets on macOS: the POSIX implementation shared with Linux. */
#define _DARWIN_C_SOURCE 1
#include "../posix_net.h"
#include <sys/event.h>
#include <sys/time.h>

/* A one-shot kqueue read filter reports EV_EOF once the peer's FIN arrived, whatever is still queued. */
int ms_sys_net_peer_ended(MsSock s) {
    const int queue = kqueue();
    if (queue < 0) {
        return 0;
    }
    struct kevent change;
    struct kevent seen;
    const struct timespec none = {0, 0};
    EV_SET(&change, (uintptr_t)s, EVFILT_READ, EV_ADD | EV_ONESHOT, 0, 0, NULL);
    const int count = kevent(queue, &change, 1, &seen, 1, &none);
    close(queue);
    return count > 0 && (seen.flags & EV_EOF) != 0;
}
