[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A request head is one buffer, ordered only when enumerated

Verified: a received head's headers cost the Manuscript server about 1.7k instructions per header against 120 for C. Most of it was per-header work no handler asked for: a `String` and a `Vec` per field, a canonical-name pass, a sort, a repeated scan per question. `Headers` is now a `Table` (`crates/ms-std-net/src/http/headers.rs`): the head's bytes copied once and one slot per field. A raw table keeps arrival order and the names as sent; lookups by name compare case-insensitively over the slots; `entries()`, `names()` and equality build the canonical sorted form once, on first use. `h1` helpers read raw pairs through `FieldList`, so they need neither form.

Numbers (callgrind, `MS_THREADS=1`, 10,000 requests, server only): six headers 206.2M to 171.9M, one header 150.0M to 146.0M (the guards `guard-http-request` and `guard-http-request-small`).

Rules that follow: an API that reads a received head by name must not enumerate it; a write to a raw table first builds the ordered one (`own`); a name's first spelling is kept for built tables, canonical for received ones. `std::thread::current()` clones an `Arc` per call (132 instructions), so a per-use thread check uses a counter (`bound.rs`).

Apply when: touching `Headers`, request parsing, or any per-request work in `ms-std-net`.
Evidence: headers.rs, [proposal](../../proposals/http-request-allocations.md).
Verify: `make perf-counts` guard-http-request and guard-http-request-small.
