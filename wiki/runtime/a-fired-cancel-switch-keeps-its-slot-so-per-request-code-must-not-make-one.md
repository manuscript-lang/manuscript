[Wiki](../index.md) › [Runtime](index.md)

# A fired cancel switch keeps its slot, so per-request code must not make one

Decision: code that runs once per request, stream or connection never creates a `cancel_switch()` to stop one promise. Cancel the promise itself: `wait_first([work, watcher])` cancels the loser, and `promise.cancel()` frees everything.

Reason: `Signal` reads as cancelled for good, even after its `Cancel` is dropped, so `release` in `runtime/core/cancel.c` never recycles the slot of a fired switch: its 40-byte record stays in the owner's array. A cancelled HTTP request fired one, leaking about 65 bytes per cancelled stream (`http2-cancelled-requests` allowed 64 and passed); an unfired switch is recycled, so completed requests showed nothing. A probe that fires 10,000 switches shows it with no networking, and a fixture limit well above the real leak hides it, so keep leak limits near the noise (16 bytes per request).

Apply when: a handler, connection or stream needs "stop this work when that event happens".
Evidence: [serve.ms run_handler](../../stdlib/net/serve.ms), [fixture](../../tests/conformance/fixtures/e2e/stdlib/http2-cancelled-requests.ms), [cancel.c release](../../runtime/core/cancel.c).
Verify: `memory_usage().heap_used` over several thousand cancelled requests stays flat.
