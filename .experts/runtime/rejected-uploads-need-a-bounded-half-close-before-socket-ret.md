[Wiki](../index.md) › [Runtime](index.md)

# Rejected uploads need a bounded half-close before socket retirement

Verified: closing both TCP halves immediately after writing an HTTP/1 rejection can reset a
connection whose peer is still uploading, hiding the response on Windows. Flush the response,
half-close output, and discard input without buffering until peer FIN or a fixed drain deadline.
Check the deadline during read retries as well as the reactor's timeout sweep.

Apply when: changing HTTP rejection responses or connection retirement.
Evidence: [rejection drain and socket regressions](../../crates/ms-std-net/src/http/server.rs),
[source header-cap regression](../../tests/e2e/testdata/stdlib/http-limits.ms).
Verify: a 2 MB header upload receives the complete 431 response without a reset; a peer that
keeps its write half open cannot retain the rejected connection indefinitely.

---
Topics: [Networking and HTTP](../topics/networking-and-http.md)
