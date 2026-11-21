[Wiki](../index.md) › [Compiler and build](index.md)

# C MIR passes: shallow clones share arrays, the build is one unit, allocations are not zeroed

Verified (port of `crates/ms-mir/src/opt` to `compiler/src/opt/opt_*.c`, 2026-11): every pass and both pipelines were byte-identical to Rust on the corpus under ASan/UBSan. The Rust optimizer is deleted; `sh compiler/tests/mir-pass-frozen.sh` checks each pass (`opt-<pass>` goldens) and both pipelines on the repository's verified `.mir` files, and `MS_MIR_REFRESH=1` rewrites a golden after a deliberate change. The goldens cover 197 modules, not the conformance corpus, so run `make conform` for a pass change. `MS_EMIT_OPT=1 ms emit` prints the C optimizer's output.

- `mir_func_clone` shares operand arrays, target args and switch cases; a pass that edits a clone's instructions in place must use `mir_func_deep_clone` (`opt_inline.c`), which copies cases before targets. Anything new on `MirFunc` (scopes, names, noalias) must be added to both clones and to the substitution and inlining remaps, or it silently goes stale.
- `libms.c` includes every `.c`, so file-scope statics need a file prefix (`il_`, `ic_`, `op_`, `sm_`...).
- `MS_NEW_N` does not zero. Use a zeroing helper wherever a field is read before it is written; the analyzer reports the symptom as a null or uninitialised read.
- A fixture added under `compiler/tests` must pass `ms fmt` (run `ms fmt compiler/tests` before pushing), or the Rust fixture-format test fails.
- Perf check (2026-11-20): the whole speed pipeline takes about 3 ms and 13 MB on the largest corpus module, so the optimiser is not a perf or memory target.

Apply when: adding or changing a C MIR pass or a `MirFunc` field.
Evidence: `compiler/tests/mir-diff.sh`, `compiler/src/opt/opt_inline.c`, issue #4816.
Verify: `mir-diff.sh` shows no FAIL.

- The Rust `depth`, `exit_drops`, `count_ops`, `cancel_edges`, `unwind` passes and the table, debug-type, debug-file and slot-scope code are deleted (2026-11-21); their C ports are checked by the frozen goldens in `compiler/tests/mir/frozen` (`sh compiler/tests/mir-pass-frozen.sh`). Rust `elaborate` (with `cancel_exit`, `persist` and the few `unwind` analyses it uses), `expand`, `expand_owned`, `glue`, `frames` and `copies` stay while `ms-lower` is Rust (it runs `elaborate`) and the interpreter oracle runs `expand`/`glue`; `mir-pass-diff.sh` still diffs those against C. Delete them with `ms-lower` and `ms-mir`.
