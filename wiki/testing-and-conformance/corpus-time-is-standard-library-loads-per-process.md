[Wiki](../index.md) › [Testing and conformance](index.md)

# Corpus time is standard-library loads per process

Verified: every `ms check` of a file that parses loads and checks the standard library first, about 55 of its 60 ms (callgrind: `ms_check::stdlib::ensure_standard` 53%), and the corpus starts one `ms` per fixture and phase. The parse phase used `ms check --json` only to keep its parse diagnostics; `ms fmt --check --json` reports the same diagnostics without the load and cut the phase from 187 s to 24 s of fixture time with all 1559 fixtures unchanged. Pick the cheapest command that observes what a phase compares, and batch inputs into one process where the output can still be split per fixture (`ms check a.ms b.ms` is 7x faster than two processes per file over 40 files). The check phase reads the terminal output from the same `ms check --json --with-text` run instead of a second process (check fixture time 449 s to 228 s). A second pass with another backend runs only `run` and `test`: check and parse do not reach a code generator, and skipping them cut the Cranelift corpus from 153 s to 124 s.

Apply when: adding a conformance phase, a fixture runner, or a test that loops over `ms` invocations.
Evidence: [observe.rs](../../crates/ms-conform/src/observe.rs), [standard library loading](../../crates/ms-check/src/stdlib.rs).
Verify: `ms-conform run --phase parse` prints fixture time per phase and the slowest fixtures.
