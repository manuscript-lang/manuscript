[Wiki](../index.md) › [Runtime](index.md)

# A listener serves on its own thread unless connections are accepted unbound

Verified (perf bash, 2026-11-18): a `Connection` and the `Listener` that made it are handles bound to one thread, so `accept` then `promise(() => handle(conn))` keeps every handler on the listener's core. `serve` avoids that by accepting a raw socket handle (`accept_raw`) and adopting it on a worker thread (`take_raw_handle`).

`Listener.accept_pending` returns the same raw handle wrapped in `PendingConnection`, and `adopt()` on the serving thread builds the `Connection` on the root network. A handler promise with `Placement.Spread` does the adopt. The wrapper closes an unadopted socket (the table of outstanding handles would otherwise leak it) and refuses a TLS listener.

Measured on 4 vCPUs: 20k empty-handler connections 843 to 766 ms (Go 493, the rest is user time per connection and the kernel), 1k connections with real work each 1758 to 1229 ms. A second function-value copy per connection is not possible (function values have one owner), which is why the API hands over a value and not a handler.

See [the results page](../../../bench/perf/perf-bash-2026-11-18-concurrency.md).
