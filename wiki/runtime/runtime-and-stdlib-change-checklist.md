[Wiki](../index.md) › [Runtime](index.md)

# Runtime and stdlib change checklist

Verified: rules gathered from past runtime and standard-library work; the linked lessons carry the evidence.

Apply when: changing `crates/ms-rt`, `ms-rt-abi`, `ms-std-*`, `ms-native`, `stdlib/*.ms`, or lowering that changes execution.

Use for `crates/ms-rt`, `ms-rt-abi`, `ms-std-*`, `ms-native`, `stdlib/*.ms`, or lowering that changes execution. Read [runtime lessons](index.md), [cleanup](../../documentation/core-language/cleanup/_index.md).

- State observable result/error identity, evaluation order, aliasing, cancellation, close, join, and use-after-close behavior before editing.
- Keep value ownership and external resource lifetime separate. Borrowing does not extend a resource lifetime; moves and exclusive mutation must satisfy the checker. Do not carry shared-reference or synchronization assumptions from the retired runtime into native code.
- Trace admission → acquisition → delivery → scope exit/cancellation → close. Cancelled undelivered acquisitions release resources; stale guards/aliases cannot access reused handles. Consult newer stdlib direction before retaining APIs scheduled for removal.
- Exercise return/error/fault/cancellation/break/continue across cleanup scopes. Close does not deadlock callbacks or reentry.
- Use ownership and borrowing from `crates/ms-check/OWNERSHIP.md`: mutation requires `var`, and `.clone()` makes a deep value copy; `Clonable` is the bound for generic copying. Native resource handles cannot be cloned. Guard validation covers actual operations and reads where required.
- Native I/O remains interruptible after descriptor metadata access. Completeness includes blocked I/O, concurrent close, bounded streaming, and shutdown, beyond successful return values. Process `stdin`/`stdout` reads and writes need not be cancellable (the user dropped that item).
- Concurrency is promises and pipes: see [concurrency is promises and pipes only](concurrency-is-promises-and-pipes-only.md); extend `@std/concurrency/promise.ms`, not new groups or locks.
- Map and Set are hash-indexed and iterate in insertion order. Key and element types must be `Hashable`; an unhashable key type is a compile error, never a linear-scan fallback. `Equal` and `Hashable` are ordinary source interfaces.
- User code binds a native symbol with `extern fn name(...) T` (symbol is the function name, linked with `--link`; may return `Result` with a payload-free error type; not generic, not a method). Stdlib natives are `extern fn` declarations wrapped by ordinary functions; the few generic natives are bodiless and named in `ms-lower/src/rtcall.rs`. `extern type` and source-level `Shared[T]`, `Weak[T]`, `Arena[T]` are planned, not shipped.
- Preserve declared error types/cases/causes and checked binding identities.
- Pure-`.ms` standard modules: `@std/internal/*` holds natives only (helpers there are not importable), imports cannot be renamed and exported names collide across modules, so give each type's constructors distinct names (`rat_of_int`, `parse_big_float`); avoid `from_` in new names, which floods the LSP `from_` completion snapshot. A built-in `to_string` on every value wins over a user method of that name; use `format`. Shared private helpers belong in the one public module that needs them (`math/big.ms` holds BigRat and BigFloat).
- A native parameter named `d` is read by lowering (`rtcall.rs`) as a type descriptor and gets one injected instead of your argument; name handle parameters `decoder`, `encoder`, `handle`. The symptom is a segfault inside the native on its first argument.
- Format stream steps are private `Transform`s behind one exported step (`json_reader`, `csv_rows`, `sse_events`, `compressed`, `tar_entries`, `multipart_parts`); the module that imports `@std/bytes.ms` through `@std/math/math.ms` cannot import `@std/io/stream.ms` (cyclic standard source), which is why the encoding steps live in `data/encoding_stream.ms`. Codec natives expose push `feed`/`end` only; Rust never calls back into a Manuscript stream. A `Transform` writes to `var out: WriteStream[B]` (`step`/`finish`); `through` collects into the writer's own list, so a step allocates nothing per item.
- `make repo-check` rejects an exported `next`, `receive`, `feed` or `write_bytes` outside the stream modules (`ms-repo-check/src/stream_names.rs`); `stream-names-allowed.txt` lists the old ones and fails when an entry's method is gone, so delete the line in the change that removes the method.
- A type error in a bundled module that is checked in a group (for example `data/json.ms` with `internal/json.ms`) can surface as an index panic in `recursion.rs` (`finite_type_applications`) instead of the diagnostic: the failed group is checked again and its declarations register twice. Print the `ensure_source` error to see the real message.
- A primitive's native operations come from its own `<Type>Operations` interface in `stdlib/intrinsics.ms` plus the generic family interfaces (`IntegerOperations[T]`, `SignedIntegerOperations[T]`), listed in `SHARED_OPERATIONS` (`ms-check/src/stdlib.rs`); `T` is the receiver. Put an operation every integer has in the family interface, and one specific to a type in its own.
- `make repo-check` fails an `extern fn` in `stdlib/internal/*.ms` that no other `stdlib` file names (`ms-repo-check/src/internal_externs.rs`). Remove the declaration, the Rust function and its `rt_symbols.txt` line (`cargo xtask symbols`) in the change that drops the last use.
- New native sources are embedded through `ms-native`; verify built programs as well as crate tests. See [runtime conventions](../../documentation/contributing/runtime-conventions.md).
- Run affected crate tests (`cargo nextest run -p <crate>`) and `make conform`; lifetime changes need bounded cancellation/shutdown cases. Report material untested platform limits.

## Rust runtime

The runtime is `crates/ms-rt`, `ms-rt-abi`, and one `crates/ms-std-*` crate per native module, embedded through `ms-native`; `unsafe` is confined to the listed locations (`make repo-check`, [development](../../documentation/contributing/development.md#rust-unsafe-boundary)). Values are owned and moved, not shared; see [differences](../../documentation/contributing/rust-toolchain.md#differences-users-can-see). Native standard identities come from `stdlib/*.ms`; a signature change reaches the declaration and the `ms-std-*` crate.

## Standard library

For standard APIs (intrinsic/native members, design), read [declaration ownership](../../stdlib/intrinsics.ms), [contracts](../../stdlib/intrinsics.ms), [runtime lessons](index.md), and [taste](../../skills/language-design/SKILL.md#taste).

- Inspect [newer stdlib direction](newer-stdlib-direction-needs-checkout-reconciliation.md) and current source first. Distinguish requested changes from shipped interfaces/bounds, removals, optional limits, and scheduling consolidation.
- Give each operation one appropriate module/spelling. Cover units, defaults, errors, streaming, mutation, edge cases, and cancellation; use Manuscript's execution model.
- Pick the failure mode by the [one rule](../../stdlib/intrinsics.ms): absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults with operation, argument, and valid range. Mutators take verbs (`set`, `remove`, `add`); copies keep past-tense or noun names. Do not restore the removed copy-sounding aliases (`with_value`, `without`, `with_entry`).
- Every standard type and function carries a doc comment, and a type's comment includes a short usage example; it appears in the generated reference.
- Audit omitted, `none`, valid, and invalid explicit limits/timeouts. The latest direction makes them optional and honored when supplied; do not impose mandatory limits without new direction. Document resource consequences and errors.
- Checked `.ms` source owns public signatures. Trace declaration → binding → checker call/receiver rules → native dispatch → called source tests → editor information → generated reference.
- Use domain-specific expected errors, preserving causes/concrete interface receivers. Generic boundaries use explicit matching/views; do not silently flatten Results or recreate convenience error-mapping APIs.
- Rename/removal covers imports, constructors, methods, aliases, bindings, dispatch, fixtures, virtual documents, generated pages/downloads, and guides. Respect the user's removal scope for historical/rejection mentions.
- Keep collection, synchronization, scheduling, and cleanup contracts explicit. Defaults agree across source metadata, native arity, function values, completion, and docs.
- Verify declaration/native ABI comparisons and called conformance, including invalid inputs/edges. Pair with the [tooling checklist](../tooling-and-docs/tooling-change-checklist.md); run `make docs-check` and applicable [documentation checks](../../skills/documentation/SKILL.md).
- A native that declares `; err: ErrOut` can explain any failure status, not only `Failed`: text it sets (a path, a program, a line and column) is appended after the status words, `JSON: invalid data: line 1, column 7: ...`. Regenerate the signature table with `cargo xtask symbols` whenever a native's parameters change; a stale table makes the call omit the slot and the native writes through garbage.
- A typed JSON decoder (`ms-lower/src/json.rs`) returns `none` on a mismatch; `jfail` first records the node and reason in the document (`msstd_json_mismatch`) and the caller builds `at $.a[0].b: ...` from it (`msstd_json_mismatch_text`). A parent that only propagates a child's `none` sets `jwhy = (-1, ..)` so it does not overwrite the child's record.
