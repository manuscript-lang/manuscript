# Runtime lessons

### Measure collection wrappers with ordinary caller inlining

Verified: on the pinned Go 1.25.1 toolchain, `b.Loop` suppresses inlining of
`String_Split` in its benchmark body, adding an escaping List wrapper that an
ordinary local caller avoids. Passing the result pointer to `b.Fatal` also
forces it to escape. Use an observable result check without passing the wrapper
and a `b.N` loop when measuring this optimization against handwritten Go.

Apply when: measuring small runtime wrappers or collection allocation parity.
Evidence: [split benchmarks](../pkg/runtime/bench_vs_go_test.go) and
[inlineable split wrapper](../pkg/runtime/string.go).
Verify: run `BenchmarkStringSplitLimited` with `-benchmem`; both local-use
controls allocate one 48-byte backing slice on linux/amd64. Confirm caller inlining with
`-gcflags=-m=2` when changing the wrapper or benchmark.

Verified: keep cold fault capture out of line. Inlining `Raise` made
`Optional_Get`/`Result_Get` exceed Go 1.25.1's budget (93/94 versus 80);
outlining it lowers their costs to 75/76. The older List.at/Optional.get chain
then inlined; current List.get has its own index/default contract and cost.
StringBuilder's pointer-only, sealed lifetime also
permits direct byte storage and immutable zero-copy freeze, removing the
redundant strings.Builder value-copy guard. Supported Go callers must not copy
the implementation value after use. Evidence: [fault helper](../pkg/runtime/fault.go),
[builder invariants](../pkg/runtime/string.go), [alias/GC/cancellation tests](../pkg/runtime/string_builder_test.go),
and [retained allocation/runtime comparison](../bench/perf/programs/results.md).
Verify native fault locations as well as allocation counts; registered source
frames must remain intact when cold helpers stop inlining.

Verified: after the indexing API change, List_Get costs 99 inline points.
Keeping the nonnegative in-range path in the public wrapper lowers it to 80,
with unchanged normalization/default/fault handling in a private slow helper.
Ordinary caller benchmarks measure roughly 2.18 -> 0.64 ns with zero allocations.
Variable negative indices pay about 0.3 ns for the guard; report that tradeoff
and measure the fallback paths as well. Test original-index diagnostics at
MinInt/MaxInt, empty lists, and reference/default identity.
Evidence: [list reads](../pkg/runtime/list.go),
[boundary tests](../pkg/runtime/list_get_test.go), and
[path benchmarks](../pkg/runtime/list_get_bench_test.go).

Verified: a private out-of-line cancellation call only inside Poll/PollIndex
reduces their Go 1.25.1 inline costs from 91/86 to 71/66. Native traversal
call sites then inline their counters and predicates. Keep direct CheckCancelled
calls unchanged: globally outlining it regressed generated-loop workloads.
Poll still queries exactly every 64th iteration, including uint32 wrap; nil
Execution, cancellation identity and shielded cleanup keep their behavior.
Evidence: [polling boundary](../pkg/runtime/exec.go),
[phase/query/wrap tests](../pkg/runtime/exec_poll_test.go), and
[isolated and whole-change measurements](../bench/perf/programs/results.md).
Verify actual call-site inlining and balanced full-workload results on Go upgrades;
a lower inline cost alone does not establish a performance improvement.

Verified: keeping List construction in small exported String wrappers also removes
the temporary heap List for local `chars`, `lines`, and `scalar_values` callers.
The traversal remains in private slice-returning helpers, preserving its order,
cancellation checks, and fresh mutable result storage. Empty local-use calls
allocate nothing; nonempty calls save the 24-byte wrapper on linux/amd64.
Evidence: [String collection benchmarks](../pkg/runtime/string_collections_bench_test.go),
[String implementation](../pkg/runtime/string.go), and the native String fixtures.

### Prepared queries must preserve callback-visible list mutations

Verified: `glob_entries` retains the include/exclude slice descriptors before
traversal, but callbacks can still replace elements in those backing slices.
Reusing parsed patterns must compare the current element with its original text
and retain ordinary matching for changed elements. Copying or freezing the lists
would change existing behavior; validation still occurs before traversal.

Apply when: preparing filesystem patterns or caching queries over mutable inputs
that callbacks can reach.
Evidence: [query preparation](../pkg/runtime/fs_copy.go),
[callback mutation regressions](../pkg/runtime/glob_test.go), and
[called source fixture](../tests/e2e/testdata/stdlib/fs.ms).
Verify: changing an include or exclude element during the root callback changes
subsequent matching; invalid initial patterns still return `InvalidInput`.

### HTTP field folding must not erase map entries

Verified: source Map keys use exact equality, while HTTP field names fold ASCII case. Passing case-equivalent outgoing entries through `Header.Set` silently replaces earlier values, including separate `Set-Cookie` fields. Append in source insertion order after validating all fields. `Header.Values(key)` also canonicalizes lookup: when converting an existing host map, index its exact key to avoid substituting another spelling's values.

Apply when: changing HTTP adapters, repeated fields, or header representation bridges.
Evidence: header regressions, [called source checks](../tests/e2e/testdata/stdlib/http-headers.ms), and [header contracts](../pkg/stdlib/http.ms).
Verify: both insertion orders retain every duplicate/cookie; host maps with noncanonical keys lose no values. Keep buffered raw-byte acceptance, streaming/client UTF-8 rejection, transport framing validation and domain errors distinct. The #171 migration uses indexed ASCII header groups and shared list membership: cache received conversions once, test alias/mutation/remove/clone semantics, and measure common lookup/proxy paths. Do not impose a blanket copy-on-read or membership-copy guarantee; explicit text extraction and clone are distinct operations.

### Empty cleanup omission needs callable ownership evidence

Verified: lexical cleanup lists return to empty after lowering a `with` scope;
their final length cannot prove that a callable needs no stack. Track whether
lowering emitted a registration owned by that source callable. Default expressions
and generated match closures share its stack; nested source functions/closures
save independent state. With no registration, `Unwind` only recovers and rethrows,
so omitting it preserves the surrounding source tracing, return/propagation and
cancellation wrappers.

Apply when: changing generated cleanup setup or adding lowering scopes.
Evidence: callable lowering,
ownership tests,
native cancellation/fault checks,
and [runtime unwind](../pkg/runtime/program.go).
Verify: conditional/default/match registrations retain stacks; a nested source
closure does not force an unused parent stack; return, propagation, fault and
cancellation retain cleanup and frame behavior.

### Concurrency is removed pending a ground-up redesign

Decision: the user removed the concurrency features (TaskGroup, Task, Scheduler, Synchronized, BlockingQueue, `check_cancelled`, `yield_now`, and their lowering, runtime, tooling, tests, examples, and documentation) because concurrency should be rebuilt correctly from the ground up. Do not restore the old APIs or add channels, locks, or tasks without a new user direction. Host-level cancellation (SIGINT/SIGTERM), `with` cleanup, and the hidden execution context remain. Queue stays a single-threaded FIFO.

Apply when: a task proposes concurrent work, locks, task handles, or revives the removed APIs.
Evidence: the user's removal request in the "Manuscript agent feedback and experience" project thread; [runtime conventions](../documentation/contributing/runtime-conventions.md).
Verify: no `@std/tasks.ms` or `@std/sync.ms`; `BlockingQueue` is absent from `queues.ms`.

### Attribute profiling at execution boundaries

Verified: allocating pprof labels, derived executions, and trace regions for every source call can dominate a call-heavy program and create enormous traces. Source boundaries follow immutable context inheritance. Nested calls keep source mapping in CPU sample stacks while reusing the boundary context. CPU labels and trace tasks/regions must follow their independently requested collectors; heap-only capture needs neither.

Verified: attribution runs on the same execution and goroutine. Preserve the full execution state when changing its context; the work-inheritance helper can intentionally start new call accounting. Resetting that state for source labels changes admission at the depth limit and fault-frame bookkeeping. The profiling depth-limit regression distinguishes these cases.

Apply when: changing source-call wrappers, profiling, work-context inheritance, or capture defaults.
Evidence: [profiling implementation](../pkg/runtime/profile.go), [boundary/allocation and repeated-run regressions](../pkg/runtime/profile_test.go), [native exit/flush checks](../pkg/build/profile_test.go), and [profiling contract](../documentation/developer-tooling/implementation.md#debugging-and-profiling).
Verify: measure unprofiled execution separately from capture setup/flush; repeat CPU/heap/trace modes. Preserve cancellation/lifetime and caller-label restoration, including faults. Validate all requested outputs with bundled viewers and keep default artifact changes explicit in help, docs, and manifest tests.

### Newer stdlib direction needs checkout reconciliation

Decision: the stdlib request calls for consolidated grouping and one spelling per operation; optional limits/timeouts honored when supplied; removal of the speculative resource-pooling API; equality and hashing interfaces; and a priority queue. This supersedes the older derived-only equality preference. The combined scheduling service is `Scheduler`, with one lifecycle for immediate and timed work.

Verified: canonical declarations, runtime dispatch, checker rules, conformance, and generated references now implement this direction. Optional also has presence and extraction methods; keep routine absence handling available without requiring a match.

Apply when: changing library signatures, bounds/interfaces, queue APIs, scheduling, grouping, examples, or documentation.
Evidence: [current declarations](../pkg/stdlib/intrinsics.ms); [stdlib contract](../pkg/stdlib/intrinsics.ms); runtime regressions; [compiled Optional methods](../tests/e2e/testdata/accept/optional-methods.ms).
Verify: inspect current declarations and called behavior against the latest direction. Preserve omitted/none/explicit-limit behavior, custom equality/hash coherence. Do not restore removed APIs from older documentation or another branch.

### Networking completeness includes interruption and shutdown

Decision: the networking request explicitly required finishing networking rather than deferring gaps, with HTTP/3 excluded for that task. Public signatures alone did not meet the requested scope; cancellation, close, bounded streaming, and shutdown were part of the behavior.

Apply when: adding native network APIs or declaring a networking change complete.
Evidence: [network coverage and limits](../documentation/contributing/architecture.md#standard-library-and-runtime); network regression cases.
Verify: run relevant native and compiled cases for blocked I/O cancellation, concurrent close, bounded input/output, and shutdown joining. Check the actual request's protocol scope; retain implementation limits explicitly when a path remains uncooperative.

### Standard-library errors describe their domain

Decision: return more specific standard-library errors instead of the shared `LibraryError`. Public error types live with their package and contain domain-relevant cases. All standard errors explicitly implement the ordinary `Error` operation contract. The newer simplification lets implementing errors pass directly into Error boundaries and propagate with `try`; the concrete receiver and fields are retained for specific handling.

Decision: keep typed diagnostic information in ordinary domain error fields. The request to simplify error handling supersedes the extra details wrapper introduced earlier in this chat. Records and alternative case payloads already support fields of different types; `Result[T, E]` and `try` retain them. Add a cause field only when the domain needs it. Ordinary errors reuse their original runtime value at an Error boundary; local implementations and generic receivers retain scoped dispatch evidence. See [error details](../pkg/stdlib/intrinsics.ms), [compiled typed errors](../tests/e2e/testdata/accept/library-errors.ms), and [cross-module error dispatch](../tests/e2e/testdata/projects/error_boundaries/main.ms).

Apply when: adding or changing fallible standard APIs, native adapters, or error propagation.
Evidence: [error contracts](../pkg/stdlib/intrinsics.ms); native identity and stream-cause regressions; [compiled matching and mapping](../tests/e2e/testdata/accept/library-errors.ms).
Verify: native error values carry the declared Result's error identity; unrelated domains cannot propagate implicitly; stream helpers preserve the original IoError case and payload.

### Host API names do not establish units or write guarantees

Verified: ProcessControl.monotonic_time returns time.Since(runtime initialization) as nanoseconds and shares the process uptime origin; host uptime and Clock instants have different origins/domains. FileHandle count-returning writes loop to complete the input, just like Unit-returning native stream writes. A count result does not imply partial success, and failures do not retain a prefix count. The file stream adapter preserves Closed/InvalidInput but translates other filesystem cases to IoError.Failed.

Apply when: documenting host contracts or proposing typed time, flag, stream, or error adapters. Trace validator/conversion/result code before inferring semantics from names or result shapes; retain explicit migration decisions for public replacements.
Evidence: [host contracts](../pkg/stdlib/intrinsics.ms), [process accounting](../pkg/stdlib/process.ms), nanosecond bracketing, and [called host contracts](../tests/e2e/testdata/stdlib/host-contracts.ms).
Verify: bracket raw monotonic readings against elapsed nanoseconds; check multi-chunk byte counts, sequential/positional EOF, shared adapter close and concrete domain errors in compiled tests.

### Native constructor arguments need not be readable fields

Verified: `Bytes(values: List[Int])` has a dedicated constructor rule; declaring `values` as a field did not make native Bytes expose that field. Removing the bogus field without preserving `ConstructorSignature` also loses editor constructor parameters. Checking and editor queries now share that constructor signature separately from the native `values() List[Int]` operation, which uses the existing free function's implementation. Constructor inputs and extracted lists copy byte values, preserving Bytes immutability.

Apply when: describing native schemas or replacing bogus native fields with operations. Preserve dedicated constructor arguments separately from receiver declarations and bindings.
Evidence: [constructor signatures](../pkg/checker/types.go), [constructor checking](../pkg/checker/calls.go), [byte declarations](../pkg/stdlib/bytes.ms), [native receiver identities](../internal/nativeabi/receivers.go), [editor signature regressions](../pkg/tooling/lsp/features_test.go), and [called extraction and constructor regressions](../tests/e2e/testdata/stdlib/string-bytes.ms).
Verify: named and positional Bytes construction and direct, stored, and free extraction calls execute; mutating the input or extracted list leaves Bytes unchanged. Editor signature help retains the required values List; generated metadata must list `values` as an operation, with no data field.

### Borrowing file descriptors must preserve pollable I/O

Verified: `os.File.Fd()` can switch a pollable descriptor into blocking mode. Native metadata and sync helpers that use it can make later cancellation fail even though ordinary file tests pass. The host bridge borrows descriptors with `SyscallConn.Control` instead, preserving the runtime's deadline/cancellation behavior.

Apply when: implementing native descriptor operations alongside cancellable file or stream adapters.
Evidence: [native descriptor bridge](../internal/hostos/hostos.go), metadata and file operations, and pipe cancellation regression.
Verify: `TestExpandedHandleCancellationAndStreamAdapters` and runtime race checks, including cancellation after descriptor metadata access and closure through a shared adapter.

### Validate compression completion before publishing tools

Verified: tar EOF can precede the gzip trailer. A complete tar payload with a truncated trailer must not become a ready toolchain. Extraction now drains the compressed reader before publication, validating truncation and checksum; retries retain no partial cache.

Apply when: changing SDK extraction or cache publication.
Evidence: [extractor](../pkg/build/toolchain_cache.go), [interrupted archive and concurrent publication tests](../pkg/build/toolchain_test.go).
Verify: truncated archives fail, leave no published/staging cache, and permit a complete retry; concurrent valid callers reuse one immutable result.

### Native option adapters must respect declared parameter types

Verified: a required Int delegated to an Optional[Int] operation needs the
explicit Some representation when preserving its public negative-limit fault.
The optional adapter rejects negative payloads inside Some; a raw negative Int
can reach a distinct primitive fault instead. String.replace_n deliberately
adapts its required cap before calling replace's prepared body. Evidence:
[negative diagnostic/frame parity](../tests/e2e/replace_n_test.go) and
required-cap adapter.
Verify zero/positive caps, negative empty/nonempty/direct/bound calls, required
source arity and declared ABI shape together; preserving the raw algorithm alone
does not preserve preparation semantics.

Verified: normalizing every runtime record recognized as an options record corrupts generic payloads. An Optional fallback containing JsonLimits must retain Optional fields and shared storage; it is not a limits argument to an I/O adapter. Normalize only a concrete declared parameter matching the record identity, including a concrete Optional parameter after its outer wrapper is removed.

Apply when: changing native argument normalization or generic receiver methods.
Evidence: normalization boundary, runtime Optional regression, and [compiled record fallback](../tests/e2e/testdata/accept/optional-methods.ms).
Verify: get(default) returns a JsonLimits record with negative and absent Optional fields unchanged and mutations retain its identity; concrete limits passed to their native operations remain validated.

### CSV writer defaults can erase a single empty field

Verified: Go's CSV writer emits the same bare line ending for zero fields and one empty field, while its reader skips blank lines. Manuscript must explicitly quote the sole empty field to retain that row, including the quotes in the output budget. Empty rows still serialize as skipped blank lines; changing reader behavior would alter that contract.

Apply when: changing CSV adapters or relying on a host codec's round-trip behavior.
Evidence: CSV implementation, [called CSV regressions](../tests/e2e/testdata/stdlib/csv.ms), and [CSV contract](../pkg/stdlib/json.ms).
Verify: round-trip consecutive single empty fields with LF/CRLF and alternate delimiters; check distinct empty-row output and exact byte, row, and cell budgets.

### Native transformations need output implementation evidence

Verified: a generic native receiver's type name does not carry lexical Equal/Hashable selection. Set.map and Map.map_keys deduplicate output elements/keys, whose scope can differ from the input element/key scope. Lower both the receiver scope and the mapped result scope, including explicit specialization and bound methods; use output evidence for deduplication. Keep Map/Set callback membership snapshots at the native invocation boundary and payload references shallow.

Apply when: adding native transformations with output bounds or changing receiver specialization.
Evidence: receiver lowering, [native dispatch](../pkg/runtime/collections.go), [cross-module output evidence](../tests/e2e/testdata/projects/core_parity/main.ms), and [callback mutation conformance](../tests/e2e/testdata/stdlib/core-parity.ms).
Verify: a generic input forwarded from another module still maps to a set deduplicated by the defining output module's equality; two modules can select different implementations for the same type. A bound specialized method retains its defining module, and callback removals or clearing do not alter the traversal's original membership.

### YAML folding must retain physical blank lines until decoding

Verified: stripping continuation lines before joining loses paragraph breaks and can misclassify comment markers inside an open quote. Quoted and plain folding remove the first break before empty lines; folded blocks do so only between ordinary lines, preserving breaks around more-indented content. Chomping also needs to know whether the final physical line had a terminator.

Apply when: changing YAML scalar gathering, comment removal, whitespace handling, folding, or chomping.
Evidence: [YAML parser](../pkg/stdlib/yaml.ms), [called scalar regressions](../tests/e2e/testdata/stdlib/yaml.ms), [YAML contract](../pkg/stdlib/json.ms), and [YAML 1.2 folding](https://yaml.org/spec/1.2.2/#65-line-folding).
Verify: run all five issue examples plus escaped continuations, whitespace-only blank lines, more-indented blocks, all chomping modes, and missing final terminators under LF/CRLF/CR normalization.

### List traversal follows the captured Go slice header

Decision: the user's later instruction explicitly supersedes List membership
snapshot/COW guarantees. Capture the slice and initial length once, expose writes
to shared backing elements, and never extend a traversal on append. Reallocation
leaves the running traversal on its original array. No traversal-driven List copy
or hidden shared flag is needed. Map/Set snapshots, closure variable capture,
explicit shallow clone/slice storage and synchronization contracts remain distinct.

Decision: shrinking boxed List mutations use non-clearing Go copy/append and
reslice semantics. Vacated cells keep prior valid values; captured ranges can
observe shifted/repeated tails. Full splice-to-empty shortens the header, preserving
backing capacity; an explicit header reset releases that receiver's backing.
Removed references can remain retained until overwritten/reallocated/released.

Verified: nil clearing in the earlier draft caused an unframed Int conversion
panic. A `[]Value` nil oracle and a native loop ignoring its binding both missed
typed-consumption safety. Parent approved non-clearing behavior without implicit
copies or invented zero values. Evidence: typed Go oracles,
[called consumers](../tests/e2e/testdata/accept/list-shrink-consumers.ms),
[original reproducer now succeeding](../bench/lists/repro-cleared-tail.ms),
and [fix/retention review](../bench/lists/go-range-review.md#non-clearing-shrink).

Apply when: changing List traversal, callbacks, writers or typed numeric storage.
Evidence: range/mutation oracle,
[called native Go-range cases](../tests/e2e/testdata/accept/list-go-range.ms),
[loop contract](../documentation/core-language/control-flow/loops.md#iterable-types-and-binding),
and [measured no-copy follow-on](../bench/lists/go-range-review.md).
Verify: capture once, mutate in place, append with/without growth, shrink, reverse
and self-splice; observed reads match ordinary Go backing-array behavior. Explicit
clones stay separate and append-only callbacks visit only the initial length.
Also consume yielded values after shrink in called native/standalone regressions,
checking types, source fault frames, cancellation, explicit clone independence,
and retained memory after clearing/reusing/releasing backing capacity.

Verified: a mutating predicate can shift/replace the current List cell. `find`
and `find_last` must capture the element before invoking the predicate and return
that same shallow value when it matches; index variants return the captured index.
Reloading the cell afterward returned an element the predicate never matched.
Body-versus-dispatch comparisons share the bug, so use independent expected values
and Go operation oracles. Evidence: search regression
and [called search/view/alias consumers](../tests/e2e/testdata/accept/list-shrink-consumers.ms).

Verified: List equality must capture both outer headers before checking lengths
and invoking element Equal. Reloading live length/cells let user Equal skip a
mismatch after left shrink, panic after right shrink, extend membership on append,
or switch arrays after reallocation. Capture retains visible backing writes and
shallow payload references; eager cloning would also change the contract.
Evidence: independent equality mutation oracle
and [native/standalone user Equal consumers](../tests/e2e/testdata/accept/list-equality-mutation.ms).
Verify both operands under shrink, append with spare capacity, forced growth and
replacement of later cells, including callback counts and differing tail values.

Verified: primitive storage keeps the mutable slice header on the authoritative
`*List`, with two allocations for fresh nonempty backing. A captured `ListRange`
is a traversal header, not another mutable owner. `Items` is only legacy boxed
construction; typed consumers use storage-aware methods. Dynamic Optional reads
still allocate at the value boundary, so benchmark the compiler's typed access
and comparator consumers together with storage. Typed comparator constructors
accept raw bodies and install exactly one guarded admission; passing an already
guarded body doubles accounting. Evidence: storage migration,
primitive Go oracles and allocation/guard tests,
and [measured storage/access paths](../bench/lists/typed-storage.md).
Verify: fresh constructors and effectful sized initialization use two allocations,
typed `get`/index reads use none, generic forwarding retains identity, and comparator
profiling/returns/cancellation/depth/fault frames match ordinary source calls.

Verified: private map/filter result construction must preserve `NewList`'s boxed
fallback when a primitive-labelled List holds nonmatching dynamic payloads.
Convert the partial result to boxed storage before storing such a payload;
the ordinary typed path remains direct. Evidence: the four primitive map/filter
cases in the fallback regression.
Verify accepted payload order, fresh outer storage, Optional payloads and live
endpoint/length reads after mutation.

Verified: source-return consumption can be shared, but recovery must run directly
in a deferred function. Boxed returns retain nil Values without a type assertion;
typed comparator returns still assert Int and check delivery cancellation before
releasing call depth. A generic payload assertion would reject the boxed nil case.
Evidence: call boundaries,
boxed return regressions, and
typed return cancellation.
Verify those guard cases and allocation assertions; use
`BenchmarkSourceDirectDispatch` for the source wrapper, since the raw method-site
benchmark does not exercise it.

Verified: primitive sized initializers must use direct matching typed writes
after fresh-state/kind/bounds checks. Routing known typed construction through
generic Len/Set made each initializer non-inlineable (Go 1.25.1 cost 118); the
strict checks inline at cost 31 and preserve two construction allocations.
Evidence: strict initialization safety/allocation tests,
[approved runtime mitigation](https://github.com/manuscript-lang/manuscript/pull/315#issuecomment-6157742485).
Verify actual effectful generated literals as well as this runtime control;
inlining alone does not establish construction performance parity.

Decision: the approved borrowed argument ABI is restricted to generated bodies
that copy parameter Values and cannot retain/expose their incoming slice.
`NewCompiledSourceFunction` delegates the ordinary source guard once; `for_each`
reuses one buffer per invocation only for exact labels and this proof. Recursion
must have independent buffers, unmarked callbacks may retain fresh arrays, and
adapters conservatively drop the marker. Individual Value captures retain identity.
Evidence: [approved contract](https://github.com/manuscript-lang/manuscript/pull/315#issuecomment-6157745861),
retention/reentry/checkpoint/guard/allocation tests.
Verify actual emitted ordinary callbacks against the prior boxed baseline; a
runtime marked-body control does not establish compiler proof or payload parity.

### Collection order, failure modes, and stdio cancellation are decided

Decision: Map and Set iterate in insertion order, and keys use the `Hashable` interface with `Equal`. Pick a failure mode by cause: absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults. Mutators use verbs (`add`, `remove`, `clear`) and return the receiver; do not reintroduce removed alias spellings (#358). Blocking stdin/stdout reads are not made cancellable; do not add runtime machinery to interrupt them.

Apply when: adding or renaming collection, standard-library, or I/O members; choosing between Optional, Result, and a fault.
Evidence: [failure-mode rule](../pkg/stdlib/intrinsics.ms), [collection order and mutation](../documentation/core-language/types/collections.md), and [equality interfaces](../documentation/core-language/types/equality-and-hashing.md).
Verify: iteration after removals and re-adds keeps insertion order for the remaining keys; a new member documents its failure mode and has a doc comment with an example.

### Test plans distinguish declarations from executions

Verified: listing and fail-fast complete a plan with unrun entries; repeat creates
separate indexed executions of one declaration. Reader completion must account
for skip and intentional unrun outcomes without masking an active incomplete test.

Apply when: changing test options, event reporting, or testing helpers.
Evidence: [event reader checks](../internal/cli/test_result_test.go),
[native runner checks](../tests/e2e/testing_runner_test.go), and
[helper contracts](../pkg/stdlib/testing.ms).
Verify: list executes no bodies, fail-fast retains later not_run entries, repeated
names retain indices, and fault assertions propagate cancellation and skip.
Standalone builds combine runtime imports into one file: alias math/rand as
mathrand so shuffle does not collide with crypto/rand. Run the existing native
Standalone regressions when adding runtime imports; ordinary package builds
do not expose this collision.

### Testing helpers do not duplicate test blocks

Decision: the user removed `describe` and `it` callback helpers because wrapping
those steps in an existing `test` block duplicates grouping without creating
independently selectable or reported cases. Keep assertions directly usable in
ordinary test blocks; do not restore these wrappers without a new direction.

Apply when: adding BDD helpers or test suite grouping.
Evidence: the user's explicit removal request in this conversation;
[testing declarations](../pkg/stdlib/testing.ms).
Verify: standard testing exports contain assertions, fail and skip, with no
callback suite wrappers.

### File fixtures own a separate lifetime from each test

Decision: the user chose an ordinary local make_fixture() convention and a
concrete return type implementing TestHooks; tests use the implicit fixture
binding, while hooks use self. No additional declaration or nesting is required.
Omitted hooks are no-ops elaborated only for the canonical standard interface;
written hooks retain ordinary signature checking and dispatch.

Verified: file roots retain fixture resources while each test uses independent
hosts and work scopes. Listing performs no setup. Unjoined fixture work poisons
further use and suppresses owner teardown; closing resources concurrently with
that work would race the resource owner. Cooperative cancellation runs teardown
with a fresh bounded cleanup context.

Apply when: changing fixture injection, runner hook ordering, or default hooks.
Evidence: [checked fixtures](../pkg/checker/test_fixture.go),
[lifecycle regressions](../tests/e2e/test_fixture_test.go),
[owner lifetime checks](../pkg/runtime/test_fixture_test.go).
Verify: no setup for --list, one construction across repetitions, per-file
isolation, ordinary interface calls to omitted hooks, and failure/cancellation
cleanup with preserved machine outcomes.

### Typed JSON is generated per type, like format and equality

Decision: the owner asked for `json.parse` and `json.stringify` themselves to work with types, with no separate `decode` and no new syntax, and for JavaScript's `JSON.stringify` behavior: every type is accepted and nothing is rejected at compile time. Two interfaces customize shapes: `JsonEncode.to_json` exists; the `JsonDecode` counterpart is undecided (a record implementing it was proposed because contracts have no static operations). Typed lowering (#531) removed the dynamic value model the first designs walked, so the lowerer generates `json_enc_T` and `json_dec_T` helpers per concrete type (the `format` pattern) and `nativeCall` passes them to `Json_Stringify[T]` and `Json_Parse[T]`; `stdgen` checks the extra parameter.

Verified: `try` gives its operand no backward context (core-language fixture cl-14), so write `try parse[T](text)`. A record decode builds the struct through `defaultArgument`, so field defaults run in the record's module with earlier fields in scope; an absent `Optional` field without a default is `none`. Map keys are parsed per key type, and two members that read as one key (`"1"`, `"01"`) are `InvalidData`. A cycle is found by tracking pointer-typed containers only for types that can reach themselves (`mayCycle`). Interface values have no JSON form: a view's concrete type is unknown to the encoder, and giving every view an encoder would pull JSON into every program that uses a contract.

Apply when: adding a standard value type with its own text or number form (extend `JsonEncNative` and `JsonDecNative` together), changing the encoding, or adding typed YAML/TOML encoding.
Evidence: [declarations and guide](../pkg/stdlib/json.ms), [generator](../pkg/lower/json.go), [runtime helpers](../pkg/runtime/json_codec.go), [accepted forms](../pkg/checker/json_parse_test.go), [native conformance](../tests/e2e/testdata/stdlib/json.ms).
Verify: a record with a function field and a `none` field encodes without them; `Wrapper[Wrapper[String]]` with a defaulted field decodes; a round trip through `stringify` returns identical text.

### O(1) runtime helpers do not poll for cancellation
Verified: `Optional_Get`, `Result_Get`, `Result_Err` (then named `*_Unwrap*`) and `StringBuilder_Append` used to call `CheckCancelled`, which reads `ctx.Err()` (a mutex-guarded context lookup) on every call. Loops already poll every 64 iterations through the lowered back edge, so these only added per-operation cost: removing them took `match` from 7.5 to 6.1 ns/op and `string_append` from 9.2 to 7.1 ns/op. The trade-off is that straight-line code with no loop, such as deep recursion that only unwraps, reaches a cancellation point later.

Apply when: adding a helper that runs in constant time, or deciding where a runtime function should be a cancellation point. Keep the check in helpers that loop, wait, or call user callbacks.
Evidence: `pkg/runtime/optional.go`, `pkg/runtime/result.go`, `pkg/runtime/string.go`, `pkg/lower/stmt.go` (`loopStatements`).
Verify: compare `bench/perf/programs/run.sh` before and after; the loop-cancellation tests in `tests/e2e` must still pass.

### ReadLine slices a buffered line under one lock
Verified: `Io_ReadLine` used two mutex round trips, a closure pair and an intermediate `append` copy per line. When the read-ahead buffer already holds a full line shorter than the limit, it is now sliced out under one lock and copied once into the result string (136 to 95 ns/line on 200k lines; hand-written Go 73). Lines that cross a refill, exceed the limit, or come from streams without read-ahead take the original path, so limit and invalid-UTF-8 behavior are unchanged.

Apply when: changing `Io_ReadLine`, `readAhead`, or stream buffering.
Evidence: `pkg/runtime/io.go`, `tests/e2e/testdata/stdlib/io.ms`.
Verify: `go test ./pkg/runtime ./tests/e2e` and `bench/perf/programs/run.sh` (`read_line`).

### Write operations take String; `_bytes` siblings take Bytes
Decision: write APIs (`write`, `write_file`, `append_file`, `write_at`, on streams, files, connections, transports) accept `String`; raw bytes use a sibling named `<name>_bytes` (`write_bytes`, `write_file_bytes`). Network sends follow the same shape: `DatagramSocket.send`/`send_bytes`, `WebSocket.send`/`send_bytes(data, text: false)`, `ping`/`ping_bytes`, and `request`/`request_bytes` for the body. Interface operations cannot be generic or overloaded, so two names express the choice. Any source `impl` of `WriteStream` or `Transport` must declare both; implementing `write` as `self.write_bytes(data.to_bytes())` keeps one body.

Apply when: adding or changing a write-like standard operation, or implementing `WriteStream`/`Transport` in source.
Evidence: user request in the project thread; `pkg/stdlib/io.ms`, `pkg/stdlib/fs.ms`, `tests/e2e/testdata/stdlib/support/streams.ms`.
Verify: `make stdlib-check`; `stdout().write("text")` and `write_bytes(bytes)` both type-check.

### Collections are constructed from lists, not chained mutation

Decision: `Set[Int]([3, 1, 2])` and `Set([3, 1, 2])` build a Set from a list (insertion order kept, duplicates collapsed); migrate chained `.add` construction in tests and examples. Do not add a second construction spelling (variadic, literal) without a new decision.

Apply when: adding collection constructors or writing fixtures that need a populated Set.
Evidence: [Set declaration](../pkg/stdlib/collections.ms), [constructor uses](../tests/e2e/testdata/stdlib/preferred-names.ms), commit c025937b.
Verify: duplicates collapse, first-seen order is kept, and `Set[Int]([])` is empty.


### Keep checked arithmetic's cold fault eager

Verified: passing the fixed overflow function into a private checked add/multiply
helper lowers Go's call-site inline cost while retaining the exact predicates,
including signed Mul64 correction and the 32-bit fallback. This is an implementation
boundary, not deferred fault capture. Other arithmetic is unchanged. Match native
source frames, message, panic identity and cleanup at extreme/sign cases; rerun
inline-cost and whole-program controls when the Go toolchain changes.
Evidence: [numeric helpers](../pkg/runtime/numeric.go),
[source-frame tests](../tests/e2e/fault_locations_test.go),
[measured alternatives](../bench/perf/programs/parity-plan.md).

Verified: the compiler-only presence mode of read_line omits only the final String
materialization after the same checks and buffer consumption. It adds no
cancellation query to an already-buffered line and keeps custom byte-stream
fallback behavior. Interleave ordinary text reads when testing this mode; checking
only the Bool can miss lost read-ahead bytes. See `pkg/runtime/io_line_test.go` and
`read-line-presence-tail.ms`.
