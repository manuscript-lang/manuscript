[Wiki](../index.md) › [Runtime](index.md)

# DNS resolution is Manuscript over one-query C natives; IpAddress and Cidr are C objects

Verified (2026-11-20): `src/stdlib/net/dns.ms` holds what the Rust `dns.rs`/`net.rs` resolver did: the search list and `ndots`, server order, reverse names for PTR, `max_records`, the time budget and the policy check. `Network` carries a `resolver` (`ip:port`, empty for the system). The C natives are `msstd_dns_query` (one query to one server, UDP then TCP when truncated, returns a `List[DnsRecord]`; the kind crosses as the `DnsKind` case index) and `msstd_dns_config` (a `DnsConfig` record), in `src/runtime/net/dns_query.c`. `IpAddress` and `Cidr` are objects in `src/runtime/net/ip.c` over `addr_text.c`; it also holds the JSON readers `msstd_json_dec_ip` and `msstd_json_dec_cidr`.

- A literal and `localhost` (and `*.localhost`) answer in Manuscript without a lookup; every other name with the system resolver goes to `msstd_net_lookup`, which parks on the libuv reactor (`ms_io_resolve`). Until the event loop runs on libuv that call never returns under the Rust runtime (a datagram sent to a host name hangs the same way); `net.ms` fixtures therefore use literals, `localhost` and a fake UDP server.
- Native dialing still resolves in Rust (`Network::lookup_ips`), so `with_resolver` keeps its native call and `Network.resolver` repeats the address for the Manuscript lookups; delete the native one with the connect move.
- A native with an `err: ErrSlot` must write the slot on every path that can fail: the caller reads it for any nonzero status, and a slot that was never written (or was read by an earlier loop pass) is garbage, so a timeout crashed in `ms_utf8_count`. `msrt_string_from_bytes(NULL, 0, err)` first thing is the fix; the lowering should zero the slot instead.
- A function whose `T` parameter follows an optional one, or a string consumed by a list literal in a loop, fails the checker only when something calls it: `ms test` of the fixture is what type-checks a new stdlib function.

Apply when: changing name resolution, adding a record kind, or moving connect/dial to Manuscript.
Evidence: [dns.ms](../../src/stdlib/net/dns.ms), [dns_query.c](../../src/runtime/net/dns_query.c), [ip.c](../../src/runtime/net/ip.c), [ip_test.c](../../src/runtime/tests/ip_test.c) (the Rust vectors).
Verify: `make c-test` (`dns_test`, `ip_test`) and `ms test tests/conformance/fixtures/e2e/stdlib/net.ms`.
