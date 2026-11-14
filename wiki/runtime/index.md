[Wiki](../index.md) › Runtime

# Runtime

Cancellation, cleanup, resources, networking, promises, test helpers.

- [The terminal keeps Rust to raw mode, text reads and writes; decoding lives in Manuscript](the-terminal-is-one-rust-core-with-per-os-backends-and-manuscript-escape-sequences.md): decoder, resize, escape sequences in `cli/terminal.ms`; the module sits in an import cycle, so no string or collections imports.
- [Image codecs are pure Manuscript and allocate only after validating the header](image-codecs-are-pure-manuscript-and-allocate-after-validating.md): `@std/image` PNG/JPEG/BMP/PPM with fuzzing; limits optional, sizes checked before allocation; pitfalls found.
- [BigInt power estimates do not prove a result fits](bigint-power-estimates-do-not-prove-a-result-fits.md): a lower bit-length bound rejects some oversized powers, but the computed result still needs its exact size checked.

- [Linux programs link glibc unless `--static` is asked](linux-programs-link-glibc-unless-static-is-asked.md): static musl's resolver misses mixed-case `/etc/hosts` names, so musl is opt-in; glibc programs link 2.28 stubs and run on any later glibc.
- [Streams wait in the source and stages pull directly](streams-wait-in-the-source-and-stages-pull-directly.md): one stream type; waiting happens inside `next`; stages are `Source`s that pull their input; no cells, no `read()` or `wait()`.
- [A deferred read runs on the waiter's stack, so its parks must honor the waiter's deadline](a-deferred-read-runs-on-the-waiters-stack-so-parks-must-honor-its-deadline.md): a promise limit on a stream read can only stop it through the work's own waits; socket natives clamp their parks to the waiter's deadline.
- [An inline blocking call starves posts from other threads](an-inline-blocking-call-starves-posts-from-other-threads.md): a 20 ms-per-read disk delayed a cross-thread wake by 111 to 135 ms; file reads keep the pool, #3638 reverted.
- [Cross-thread promise cost is the sleep and wake, not the mail lock](cross-thread-promise-cost-is-the-sleep-and-wake-not-the-mail-lock.md): lock-free wake path plus a short spin took a promise from 3.4 to 1.9 µs; removing locks alone made it worse.
- [Task stacks are 512 KiB slots in 256 MiB regions](task-stacks-are-512-kib-slots-in-256-mib-regions.md): one page per parked task, kernel guard regions, idle tasks hibernate to the heap, a recursion grows the task onto further guarded slots up to 256 MiB; the main task keeps a 256 MiB region.
- [A native signature change needs a regenerated table and a fresh runtime archive](a-native-signature-change-needs-a-regenerated-table-and-a-fre.md): lowering marshals native calls from the generated `crates/ms-lower/rt_symbols.txt`, not from the Rust source, and programs link `target/ms-native/libms_native.a`.
- [A dying receiver is taken by a MIR pass after `lastuse`](a-dying-receiver-is-taken-by-a-mir-pass-after-lastuse.md): `decode_utf8` of a `Bytes` and `trim`, `upper`, `lower`, `replace` of a `String` dropped at the call reuse the buffer (`// ms: takes_self`); `fresh` entries no longer extend a family through out-pointers.
- [A runtime builder makes compiler-laid-out values through a thunk, not a copy of the layout](a-runtime-builder-makes-compiler-laid-out-values-through-a-t.md): an untyped `parse` builds `JsonValue` in `ms_rt::tree::TreeBuilder` while the scanner runs, with no document.
- [The cancel sweep cancels each test at every park](cancel-sweep-cancels-every-park.md): `make cancel-sweep` cancels at each await and fails on live blocks.
- [Cancellation is a host-level flag, not a per-loop poll](cancellation-is-a-host-level-flag-not-a-per-loop-poll.md): cancellation is one global flag (set by signals, shutdown, and task-group cancellation; see the tasks and workers entries for scoped cancell…
- [Closeable.close() returns a Result](closeable-close-returns-a-result.md): there is one `Closeable` interface and `close()` returns `Unit!` (`Result[Unit, Error]`), so a failed flush or release is a value.
- [Collection order, failure modes, and stdio cancellation are decided](collection-order-failure-modes-and-stdio-cancellation-are-de.md): Map and Set iterate in insertion order, and keys use the `Hashable` interface with `Equal`.
- [Collections are constructed from lists, not chained mutation](collections-are-constructed-from-lists-not-chained-mutation.md): `Set[Int]([3, 1, 2])` and `Set([3, 1, 2])` build a Set from a list (insertion order kept, duplicates collapsed); migrate chained `.add` cons…
- [Native handles built on Rc are thread-bound and fault elsewhere](native-handles-built-on-rc-are-thread-bound-and-fault-elsewhere.md): `Bound` faults on cross-thread use; repo-check ratchets `Rc`/`RefCell` in `ms-std-*`.
- [Cross-thread cancellation metadata must use atomic accesses](cross-thread-cancellation-metadata-must-use-atomic-accesses.md): a volatile read of `Hdr.shield` raced with the owning task's writes through `Cell<u32>`.
- [CSV writer defaults can erase a single empty field](csv-writer-defaults-can-erase-a-single-empty-field.md): a naive CSV writer emits the same bare line ending for zero fields and one empty field, while a reader skips blank lines.
- [Faults and test failures reach the CLI as a record](faults-and-test-failures-reach-the-cli-as-a-record.md): the runtime writes a structured record to `MS_FAULT_RECORD`; the CLI never parses fault text.
- [Test helper rules](test-helper-rules.md): Test plans, fixtures, fault assertions and helpers that must not duplicate test blocks.
- [Host API names do not establish units or write guarantees](host-api-names-do-not-establish-units-or-write-guarantees.md): host uptime and Clock…
- [HTTP and networking rules](http-and-networking-rules.md): Content-type inference, field folding, redirects, transfer coding, rejected uploads, interruption and shutdown.
- [Cookie expiry uses cookie-date tokens](cookie-expiry-uses-cookie-date-tokens.md): legacy Expires dates must expire cookies, with calendar validation and Max-Age precedence retained.
- [Native constructor arguments need not be readable fields](native-constructor-arguments-need-not-be-readable-fields.md): `Bytes(values: List[Int])` has a dedicated constructor rule; declaring `values` as a field did not make native Bytes expose that field.
- [Native transformations need output implementation evidence](native-transformations-need-output-implementation-evidence.md): a generic native receiver's type name does not carry lexical Equal/Hashable selection.
- [Newer stdlib direction needs checkout reconciliation](newer-stdlib-direction-needs-checkout-reconciliation.md): the stdlib request calls for consolidated grouping and one spelling per operation; optional limits/timeouts honored when supplied; removal o…
- [Reactor progress must not depend on the scheduler going idle](reactor-progress-must-not-depend-on-the-scheduler-going-idle.md): tasks that keep each other ready through channels or yields can prevent `reactor_wait` from running indefinitely.
- [Flow control lives in `@std/concurrency/flow.ms`](flow-control-lives-in-concurrency-flow.md): retry, rate limiter, circuit breaker, `map_concurrent` and `Throttle` are plain `.ms` over promises.
- [`main` skips plain frees at exit, and the stack limit lives in the region](main-exit-skips-plain-frees-and-the-stack-limit-lives-in-the-region.md): the exit drops of plain memory wait on `msrt_exit_frees`; every writer of `Hdr::limit` must call `task::publish_limit()`.
- [Runtime guard exits skip native Rust destructors](runtime-guard-exits-skip-native-rust-destructors.md): production `msrt_guard_call` exits faults and cancellation with a jump, so a Rust `Drop` guard alone cannot release a response body's active read.
- [Small map slots are copied inline, not by `memcpy`](small-map-slots-are-copied-inline-not-by-memcpy.md): the map insert copied a 72-byte `JsonValue` slot through a `memcpy` call per entry; sizes up to ten words now copy inline (`copy_slot`).
- [Typed JSON is generated per type, like format and equality](typed-json-is-generated-per-type-like-format-and-equality.md): the owner asked for `json.parse` and `json.stringify` themselves to work with types, with no separate `decode` and no new syntax, and for Ja…
- [Promises live in per-thread slot tables; threads exchange events](promises-run-on-per-thread-slot-tables-and-schedulers.md): ids encode the creating thread; cross-thread work moves by events, I/O promises have no task.
- [One process heap: pages name their owner, an ended thread's heap is adopted](one-process-heap-pages-name-their-owner.md): all threads allocate from one reservation; any thread frees any block; the scalar-count string hint is gone.
- [Write operations take String; `_bytes` siblings take Bytes](write-operations-take-string-bytes-siblings-take-bytes.md): write APIs (`write`, `write_file`, `append_file`, `write_at`, on streams, files, connections, transports) accept `String`; raw bytes use a s…
- [YAML parser rules](yaml-parser-rules.md): plain colons, implicit keys, diagnostic origins, folding and blank lines, comments ending plain scalars.
- [Runtime and stdlib change checklist](runtime-and-stdlib-change-checklist.md): ownership, cancellation, cleanup, native binding, and stdlib API rules to check before editing runtime or stdlib code.
- [File locks poll in Manuscript, and best-effort cleanup binds its Result](file-locks-poll-in-manuscript-and-cleanup-results-are-bound.md): `try_lock` is the only native lock; waits are a cancellable sleep loop, and `Result.get(none)` on `Unit` faults.
- [Exclusive tree copies reject the destination before traversal](exclusive-tree-copies-reject-before-traversal.md): empty and disjoint destination directories expose missing replacement checks that colliding-leaf tests hide.
- [Text helpers: String methods in `.ms`, conversions in `@std/text.ms`](text-helpers-live-in-string-ms-methods-and-a-text-module.md): no new Rust; check for parallel unicode work first; `\u\{` needs escaped braces.
- [Concurrency is promises and pipes only](concurrency-is-promises-and-pipes-only.md): task groups, workers, channels, `Shared`, locks and caches are deleted; state has one owner and changes travel over pipes.
- [Large write payloads take a pool permit before the copy](large-write-payloads-take-a-pool-permit-before-the-copy.md): `pool::admit` parks the caller before a payload over 64 KiB is cloned, bounding in-flight copies by the pool size.
- [A Bytes view is a cap-zero borrow that is never freed](a-bytes-view-is-a-cap-zero-borrow-never-freed.md): `Bytes.view` lends the receiver without copying; `slice` still copies.
- [A pipe read needs no promise when a value is queued](a-pipe-read-needs-no-promise-when-a-value-is-queued.md): `PipeSource.next` takes a queued value or the end directly; a pipeline of 1M values went from 0.33 s to 0.14 s (Go 0.17 s).

- [XML comments validate content at every parser site](xml-comments-validate-content-at-every-parser-site.md)

- [Template numbers preserve exact JSON values](template-numbers-preserve-exact-json-values.md): compare normalized coefficients and decimal orders without Float rounding or expanding exponents.
- [A pinned stream keeps every promise on its thread, so workers must spread](a-pinned-stream-keeps-every-promise-on-its-thread-so-workers-must-spread.md): use `PromiseOptions(placement: Placement.Spread)` for per-core workers; check `top -H` for one busy thread.
- [Perf paths need a macOS and Windows equivalent](perf-paths-need-a-macos-and-windows-equivalent.md): the native standard library's global allocator was Linux-only; fixes are cross-platform, measuring may be Linux.
- [ChaCha and BLAKE2 stay in Manuscript](chacha-and-blake2-stay-in-manuscript.md): no Rust natives or SIMD for these ciphers and hashes for now.
