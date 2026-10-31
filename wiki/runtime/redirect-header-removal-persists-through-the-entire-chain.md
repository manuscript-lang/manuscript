[Wiki](../index.md) › [Runtime](index.md)

# Redirect header removal persists through the entire chain

Verified: rebuilding each redirect from the original request restores credentials after a
cross-origin hop stripped them, and restores entity headers when a 302 drops a body before
a 307 preserves the now-empty body. Filter the previous hop's headers instead. Recompute
automatic Referer on every hop so carrying headers forward cannot leak a prior origin's URL.


Apply when: changing redirect policy or outgoing request header propagation.
Evidence: [loopback redirect regressions](../../crates/ms-std-net/src/http/client.rs), [called fetch chain regression](../../tests/e2e/testdata/stdlib/fetch.ms).
Verify: a cross-origin redirect followed by a same-origin redirect sends no original credentials; a 302 then 307 sends neither a body nor its original entity headers; automatic Referer stays local.
