/* The Unix domain socket natives, declared here until the standard library switches to them: the switch moves these
 * declarations to ms_rt/net.h and lists the symbols in runtime/symbols/net.txt (the symbols check would reject them
 * before then). Policy (a restricted Network refuses Unix sockets) is standard-library code. */
#ifndef MS_NET_UNIX_H
#define MS_NET_UNIX_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* Connects to the Unix domain socket at `path` and gives a plain connection. The connect itself blocks only while the
 * listener's queue is full. An empty path or one with a NUL byte is STATUS_INVALID_INPUT; one longer than the system's
 * limit is STATUS_FAILED. The connection's own addresses are empty text. */
/* ms-sig: msstd_net_dial_unix(path: *const StrVal, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_dial_unix(const MsStr *path, void **out, MsStr *err);

/* Listens on a new Unix domain socket at `path`; accept and close are the listener natives of ms_rt/net.h, its address
 * is `path`, and the file is removed when the listener is dropped. An existing file at `path` fails the bind. */
/* ms-sig: msstd_net_listen_unix(path: *const StrVal, out: *mut *mut ObjCell<ListenerH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_listen_unix(const MsStr *path, void **out, MsStr *err);

#endif
