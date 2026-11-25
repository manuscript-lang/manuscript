[Wiki](../index.md) › [Runtime](index.md)

# The process entry names no optional module

Verified (2026-11-23, x86-64 Linux, release `ms`): a program that only prints linked the HTTP client, TLS and BigInt code and was 14.4 MB; it is 2.9 MB now. `start.c` called each module's release function and the HTTP waiter install, and `shape_text.c` called the BigInt formatter, so the linker kept libcurl, nghttp2 and 784 OpenSSL members for every program.

- A module that holds process-wide state calls `ms_release_at_exit(release)` (`runtime/core/release.h`) the first time it makes that state; `start.c` only runs `ms_release_run()`. The HTTP waiter installs on the first client handle. The BigInt text hook installs when the first `BigInt` is made.
- Shared code reaches an optional module through a hook it installs, never by a direct call. Check a change with `ld.lld --why-extract` on a hello build: nothing from `libcurl`, `libssl` or `libcrypto` should appear.
- Still linked into a program that decodes typed JSON (`parse[T]`, 8.6 MB): `shape_json_read.c` parses BigInt digits. No BigInt exists yet when it runs, so the install point is the compiler (a hook it emits for BigInt shapes), not a first-use call.
