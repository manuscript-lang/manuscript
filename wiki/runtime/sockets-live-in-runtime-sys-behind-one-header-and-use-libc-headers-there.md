# Sockets live in runtime/sys behind one header, and sys may include the platform's socket headers

Decision (2026-11-20, OS-layer review): `runtime/include/ms_rt/sys_net.h` is the only socket interface (`mssys_net_*`, plain `ms_addr`, no libc type in the header). Linux and macOS share `runtime/sys/posix_net.h`; Windows has `runtime/sys/windows/net.c`. Every socket is non-blocking and not inherited; a call that would block returns `MS_SYS_AGAIN`.

Rules: `runtime/sys` is the exception to "freestanding headers only": it includes `<sys/socket.h>` or `<winsock2.h>`, and nothing above it does. IPv6 listeners set `IPV6_V6ONLY` to 0 explicitly (Windows defaults to 1). Windows listeners use `SO_EXCLUSIVEADDRUSE`, never `SO_REUSEADDR` (it lets another process take the port). A connect call sets its output socket only on OK or INPROGRESS. Winsock starts lazily on the first socket call.

Apply when: adding a system call to the socket layer or porting it to another platform. Evidence: `runtime/tests/sys_net_test.c`.
