[Wiki](../index.md) › [Standard-library design](index.md)

# Net is split by seam; duplex ends and promise captures still need a shared handle

Decision (2026-11-05, owner approved breaking renames, no aliases): `net/net.ms` is `ip.ms` (addresses, CIDR, DNS types), `url.ms`, `tls.ms`, `websocket.ms` and `net.ms` (TCP, UDP, Unix, `Network`, `serve`). `connect(address, tls: TlsOptions? = none, timeout: Duration? = none)` replaces `connect_tls` and `connect_tls_config`; `Raw*` handle wrappers are gone (`NativeConnection` etc. are the only handle types). Functions past three parameters take a `<Thing>Options` record (`RequestOptions`, `DnsOptions`, `WebSocketOptions` with `headers` and `subprotocols`), and `timeout: Duration? = none` comes last.

Findings that stop further removal (verified on `80fd348b`):
- `share` and `close_if_last` stay. A `Connection` hands `input` and `output` to different tasks, so two owners need one socket; with `close_if_last` removed, `client.close()` only half-closed and `tests/conformance/fixtures/e2e/stdlib/net-broken-pipe.ms` never saw the peer's write fail.
- A promise started in a `return` owns what it captures (#2686), and `owned_task` takes a job closure that owns clones, so no `*Args` record or `owned_promise` remains.

Apply when: touching connection, listener, datagram or WebSocket ends, or trying to drop an `*Args` record.
Evidence: [net.ms](../../stdlib/net/net.ms), [net-broken-pipe.ms](../../tests/conformance/fixtures/e2e/stdlib/net-broken-pipe.ms).
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/{net,tls,net-broken-pipe}.ms`.
