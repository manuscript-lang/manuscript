[Wiki](../index.md) › [Runtime](index.md)

# A dying receiver is taken by a MIR pass after `lastuse`

Decision (track 2 of [c-parity-structure](../../proposals/c-parity-structure.md)): a runtime call whose owned receiver is dropped right after it may reuse the receiver's storage. `bytetake` rewrites `bytes_decode_utf8(b, out); drop b` to `msrt_bytes_decode_utf8_take`, which turns the `Bytes` buffer into the `String` (NUL at `len`, realloc only when `cap == len`) and frees nothing. A `Bytes` view has `cap == 0` and borrows its bytes, so the take copies and frees nothing.

Verified: the pass only fired after `lastuse` treated the decode as `fresh`. The family rule used to add every call's out-pointer slot to a value's family regardless of `fresh`, so the drop sat after the string's last use and was never adjacent to the call. A `// ms: fresh` function now extends no family through its out-pointers either; declare it only for entries whose result copies.

Evidence: grep on 22 MB, 56 ms to 39 ms; logstats 98 ms to 88 ms ([structural gaps](../../bench/perf/structural-gaps/README.md)). Callgrind instruction counts barely move (the saved work is a 2 MB memcpy and page faults), so judge this change by wall time and allocated bytes.

Extended to `String` edits: `trim`, `trim_start`, `trim_end`, `upper`, `lower` and `replace` declare `// ms: leaf fresh takes_self`, and `msrt_string_<name>_take` edits a heap-owned receiver in place (ASCII case mapping, a trim that moves the kept bytes to the front, a `replace` whose new text is no longer than the old, written left to right). Inline, static and view receivers, and a growing `replace`, fall back to the copying call and release the input. A result that fits inline is rebuilt inline and the buffer freed, because equal inline strings must have equal words. These results are `fresh` because `cloned` copies a view and shares only static and inline strings. Text edits on 300k lines: 954M to 554M instructions, 39 to 28 ms ([structural gaps](../../bench/perf/structural-gaps/README.md)).

Apply when: adding another take entry (`to_bytes`, `sorted`): mark the copying entry `// ms: takes_self` (and `fresh` when its result copies), write `<name>_take` with `// ms: leaf`, run `cargo xtask symbols`, and add a case to [opt_bytetake](../../crates/ms-mir/tests/opt_bytetake.rs) and a fixture that covers inline, heap, non-ASCII and borrowed receivers. After changing a flag, rebuild the runtime with `cargo xtask runtime`: a stale embedded runtime links without the twin.
