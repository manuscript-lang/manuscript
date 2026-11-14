[Wiki](../index.md) › [Runtime](index.md)

# Runtime and stdlib change checklist

Verified: rules gathered from past runtime and standard-library work; the linked lessons carry the evidence.

Apply when: changing `crates/ms-rt`, `ms-rt-abi`, `ms-std-*`, `ms-native`, `stdlib/*.ms`, or lowering that changes execution.

Use for `crates/ms-rt`, `ms-rt-abi`, `ms-std-*`, `ms-native`, `stdlib/*.ms`, or lowering that changes execution. Read [runtime lessons](index.md), [cleanup](../../documentation/core-language/cleanup/_index.md).

- Stdlib module order: imports, then the public API (each type followed by its impls), then private helper functions at the end, so a reader meets the contract first. A private `fn` before the first `export` moves to the end of the module.
- State observable result/error identity, evaluation order, aliasing, cancellation, close, join, and use-after-close behavior before editing.
- Keep value ownership and external resource lifetime separate. Borrowing does not extend a resource lifetime; moves and exclusive mutation must satisfy the checker. Do not carry shared-reference or synchronization assumptions from the retired runtime into native code.
- Trace admission → acquisition → delivery → scope exit/cancellation → close. Cancelled undelivered acquisitions release resources; stale guards/aliases cannot access reused handles. Consult newer stdlib direction before retaining APIs scheduled for removal.
- Exercise return/error/fault/cancellation/break/continue across cleanup scopes. Close does not deadlock callbacks or reentry.
- Use ownership and borrowing from `crates/ms-check/OWNERSHIP.md`: mutation requires `var`, and `.clone()` makes a deep value copy; `Clonable` is the bound for generic copying. Native resource handles cannot be cloned. Guard validation covers actual operations and reads where required.
- Native I/O remains interruptible after descriptor metadata access. Completeness includes blocked I/O, concurrent close, bounded streaming, and shutdown, beyond successful return values. Process `stdin`/`stdout` reads and writes need not be cancellable (the user dropped that item).
- UDP DNS responses must match the configured resolver's full source socket address and query ID. Matching only its IP accepts an answer from another source port; `dns::tests::ignores_udp_answers_from_a_different_source_port` exercises this with two real sockets and no ordering sleeps (#3275).
- HTTP redirects remove literal dot segments from encoded paths using RFC 3986, including absolute `Location` URLs. Server path cleaning collapses repeated slashes and loses final-dot directory slashes, so it cannot resolve redirects. Keep percent escapes and empty segments intact; `http/url.rs`'s RFC examples and `redirects_preserve_the_resolved_request_target` in `http/client.rs` cover these distinctions (#3290).
- HTTP authorities such as `:80` are nonempty but have no host. Reject the empty host after splitting the authority, before transport setup; `http/url.rs` tests initial and redirected URLs, and `http-paths.ms` checks EINVAL through both HTTP client APIs. A valid host with an empty optional port remains accepted.
- Concurrency is promises and pipes: see [concurrency is promises and pipes only](concurrency-is-promises-and-pipes-only.md); extend `@std/concurrency/promise.ms`, not new groups or locks.
- Line streams buffer unfinished fragments once and join only at newline/EOF (#3212). Keep whole-chunk decoding direct; test split CRLF, empty chunks, UTF-8 and exact byte limits without rescanning or copying the growing prefix.
- Empty `List.repeated` must not traverse the repetition count (#3204), but
  validate negative counts before the empty return. Keep a nonempty nested-copy
  control so a fast path does not weaken cloning or output order.
- Deque growth must move ring-buffer slots, including nested resource owners.
  Unwrap in place with `List.rotate`; `take`, `drop` and `concat` copy values and
  can close the same resource repeatedly. `deque-resource-growth.ms` checks both
  ends, wrapped/unwrapped growth, optional payloads and error/fault cleanup (#3339).
- Map and Set are hash-indexed and iterate in insertion order. Key and element types must be `Hashable`; an unhashable key type is a compile error, never a linear-scan fallback. `Equal` and `Hashable` are ordinary source interfaces.
- TOML dotted-key traversal defines existing implicit parents as well as new
  tables. Persist the `dotted` flag so a later header cannot redefine them;
  ordinary header traversal must still leave untouched implicit parents
  promotable. `toml.ms` tests both paths, quoted keys and table arrays (#3297).
- User code binds a native symbol with `extern fn name(...) T` (symbol is the function name, linked with `--link`; may return `Result` with a payload-free error type; not generic, not a method). Stdlib natives are `extern fn` declarations wrapped by ordinary functions; the few generic natives are bodiless and named in `ms-lower/src/rtcall.rs`. `extern type` and source-level `Shared[T]`, `Weak[T]`, `Arena[T]` are planned, not shipped.
- `environment()` skips entries that are not valid UTF-8. Failing the whole map made the test runner (which reads `MS_TEST_RESULTS` from it) exit 0 without running tests and made `which` find nothing whenever one such variable existed; `control.rs` has the unit test.
- Preserve declared error types/cases/causes and checked binding identities.
- Filesystem prechecks must keep the same error kind as the equivalent host failure. `Directory::open` used a generic `EIO` for a regular file while `open_directory` promises `EINVAL`; `fs-kinds-and-sources.ms` checks file, missing-path, non-directory ancestor and valid-directory controls through the public API.
- Rational powers must propagate fallible integer powers: numeric defaults turn a size-limit error into a successful but wrong fraction. `big-rat-power-limits.ms` checks oversized numerator/denominator powers with either exponent sign and retains zero/unit controls (#3334).
- Modular square-root nonresidue searches cannot use a fixed attempt cutoff:
  valid primes can have no nonresidue among the first thousand candidates.
  Continue on Euler result +1, stop on -1, and reject other results as composite
  witnesses. `bigint-number-theory.ms` certifies a prime whose least nonresidue
  is 1013 and checks signed squares and composite-search exits (#3391).
- Interpolation of finite endpoints must not overflow solely in their difference. Use a weighted blend when the finite endpoint span overflows, retaining the existing finite-span formula for tiny/subnormal rounding and existing nonfinite-input behavior; For median, halve finite neighbors only when their sum overflows; always halving loses subnormal precision. `statistics.ms` tests these boundaries (#2955, #2956).
- A finite-input mean can overflow in its sum although the average is representable. Preserve the ordinary finite-sum path and nonfinite-input behavior; an exact rational overflow fallback keeps cancellation residuals that rescaling or per-term division can lose. `statistics.ms` exercises exact binary64 boundary cases (#2957).
- Subnormal histogram bin widths can underflow or round enough to move interior values. For finite inputs, use exact rational positions and floor before converting the index; keep ordinary widths and nonfinite behavior unchanged. `statistics.ms` covers signed/shifted integer-grid boundaries (#2967).
- Standard deviation can fit when variance cannot. Preserve ordinary rounding and nonfinite behavior; normalize unsafe finite squared ranges before square root. Population deviation is bounded by max input magnitude; sample overflow near Float.max requires an exact squared-midpoint comparison, not unconditional clamping. `statistics.ms` exercises scale and boundary controls (#2971).
- Complex inverse tangent loses small imaginary components when it subtracts nearly equal log magnitudes. Use a scaled `log1p` ratio away from the poles, keep separate logs near them, and avoid a multiply-by-four/divide-by-four round trip for subnormal components. `complex.ms` checks tiny phases, huge components, conjugates and poles with relative component assertions (#3331).
- A percentile rank must come from an exact product: `percent * (n - 1) / 100`, not `percent / 100 * (n - 1)`, whose early rounding put 29% of 101 values at 28.999999999999996. `quantiles` splits `i * (n - 1)` by `parts` in integers. A differential over 0..100 at n = 101 catches this (#3122).
- `Histogram.percentile` follows the same rule: `ceil(p * total / 100.0)`, not `p / 100.0 * total` (#3156). A String operation that needs only a prefix (`take`, `drop`, a char-set trim, `find_char`) walks that prefix with `utf8::advance` or reads doubling windows; counting scalars or calling `chars()` on the whole text made `take(16)` 24 ms and a no-op `trim_chars` 160 ms on 8M scalars (#3162).
- HTML numeric references accumulate with saturation above U+10FFFF (never `wrapping_*`, which turned `&#4294967361;` into `A`) and count digits explicitly; a single decimal digit without `;` still decodes (`&#9F` is a tab then `F`). The tokenizer lives in `stdlib/data/html.ms` and is checked against the recorded Go trees in the `html-oracle` fixture; its one quirk is that a digitless `&#x;` decodes to U+FFFD in `parse` while `unescape` keeps it literal (#3140).
- MIME multipart receivers accept only ASCII SP/HT transport padding before a delimiter line CRLF (RFC 2046); do not trim headers or payloads. Keep the streaming raw-section budget unchanged and test delimiter padding across chunk splits (`mime.ms`, `multipart-stream.ms`, #2975).
- WebSocket compression permits RSV1 only on a message's first Text/Binary frame, never a continuation or control frame. Validate minimal payload-length encodings and distinguish empty Close payloads from malformed one-byte status codes. Keep both-role incremental decoder and socket close-1002 regressions in `ws/frame.rs` and `ws/socket.rs` (#3269–#3271).
- JWT claim validation first requires an object after verifying its signature. `JsonValue.get` returns none for nonobjects, so member checks alone accept signed scalars and arrays as claim-free JWTs. Match the root case without cloning its map and cover raw and typed result paths (`jwt.ms`, #3341).
- JWT NumericDate comparisons use retained JSON decimals, not Float: adjacent integers above 2^53 and subsecond dates at Unix magnitudes otherwise become equal. Compare against exact `moment +/- leeway` (which may exceed Int), preserve strict expiration/inclusive not-before, and bound exponent work by token length rather than expanding powers of ten (`jwt.ms`, #3345).
- JWT protected headers must reject every present `crit` while no critical extensions are supported, including explicit null and malformed lists. Reject `b64:false` and non-Boolean encoding flags; unknown noncritical fields and the default encoded payload remain accepted. Independently signed headers in `jwt.ms` pin presence checks and algorithm-error ordering (#3417).
- Float interval validation must reject NaN explicitly or use positive interval membership (`not (p >= low and p <= high)`), not only `p < low or p > high`. Check invalid inputs before empty-container shortcuts; `metrics-histogram.ms` covers NaN, infinities, finite bounds, and empty/populated controls (#2953).
- Pure-`.ms` standard modules: `@std/internal/*` holds natives only (helpers there are not importable), imports cannot be renamed and exported names collide across modules, so give each type's constructors distinct names (`rat_of_int`, `parse_big_float`); avoid `from_` in new names, which floods the LSP `from_` completion snapshot. A built-in `to_string` on every value wins over a user method of that name; use `format`. Shared private helpers belong in the one public module that needs them (`math/big.ms` holds BigRat and BigFloat).
- A native parameter named `d` is read by lowering (`rtcall.rs`) as a type descriptor and gets one injected instead of your argument; name handle parameters `decoder`, `encoder`, `handle`. The symptom is a segfault inside the native on its first argument.
- Format stream steps are private `Transform`s behind one exported step (`json_reader`, `csv_rows`, `sse_events`, `compressed`, `tar_entries`, `multipart_parts`); the module that imports `@std/bytes.ms` through `@std/math/math.ms` cannot import `@std/io/stream.ms` (cyclic standard source), which is why the encoding steps live in `data/encoding_stream.ms`. Codec natives expose push `feed`/`end` only; Rust never calls back into a Manuscript stream. A `Transform` writes to `var out: WriteStream[B]` (`step`/`finish`); `through` collects into the writer's own list, so a step allocates nothing per item.
- One-shot codec calls are the streaming codec run over the slice (`decompress_bytes` runs `Decoder`), never a second implementation; `compress_stream.rs` compares them under random chunk splits. Raw deflate decoding is `ms-inflate` (shared by the `Decoder`, zip and the HTTP client's gunzip); framing and checksums stay with the caller, and the `Decoder` keeps a 32 KiB history window whose start is the limit of a legal distance (#3036 family: a wrapping dictionary accepted back-references before the start of the output). Compression still uses miniz.
- GZIP must reject any reserved FLG bit (`0xe0`) in every member before optional fields are processed. Test fragmented and concatenated headers alongside all 32 legal flag combinations, including valid optional-field CRCs (`compress_stream.rs`, #3284).
- `make repo-check` rejects an exported `next`, `receive`, `feed` or `write_bytes` outside the stream modules (`ms-repo-check/src/stream_names.rs`); `stream-names-allowed.txt` lists the old ones and fails when an entry's method is gone, so delete the line in the change that removes the method.
- A type error in a bundled module that is checked in a group (for example `data/json.ms` with `internal/json.ms`) can surface as an index panic in `recursion.rs` (`finite_type_applications`) instead of the diagnostic: the failed group is checked again and its declarations register twice. Print the `ensure_source` error to see the real message.
- A primitive's native operations come from its own `<Type>Operations` interface in `stdlib/core/intrinsics.ms` plus the generic family interfaces (`IntegerOperations[T]`, `SignedIntegerOperations[T]`), listed in `SHARED_OPERATIONS` (`ms-check/src/stdlib.rs`); `T` is the receiver. Put an operation every integer has in the family interface, and one specific to a type in its own.
- `make repo-check` fails an `extern fn` in `stdlib/internal/*.ms` that no other `stdlib` file names (`ms-repo-check/src/internal_externs.rs`). Remove the declaration, the Rust function and its `rt_symbols.txt` line (`cargo xtask symbols`) in the change that drops the last use.
- New native sources are embedded through `ms-native`; verify built programs as well as crate tests. See [runtime conventions](../../documentation/contributing/runtime-conventions.md).
- Run affected crate tests (`cargo nextest run -p <crate>`) and `make conform`; lifetime changes need bounded cancellation/shutdown cases. Report material untested platform limits.

- Complex asymptotic trig must not overflow a finite phase while evaluating double-angle sine. Beyond half Float.max, use the bounded sine/cosine identity; test the tiny component with relative accuracy rather than a fixed tolerance that accepts zero (`complex.ms`, #3196).
- Complex exponentials can have finite components after their radius overflows. Multiply the trig components by four quarter-exponential factors; a half-exponential split still overflows for tiny phases near real part 1450. Check each component relatively, including minimum-subnormal phases (`complex.ms`, #3298).
- Complex sin/cos/sinh/cosh need the same range care when a standalone hyperbolic factor overflows. Grow the trig component through three quarter-exponential factors and a final quarter-exponential factor divided by two; halving a subnormal phase first loses it, while halving only after overflow is too late. Retain the direct finite/nonfinite path and signed-zero controls (`complex.ms`, #3337).

## Rust runtime

The runtime is `crates/ms-rt`, `ms-rt-abi`, and one `crates/ms-std-*` crate per native module, embedded through `ms-native`; `unsafe` is confined to the listed locations (`make repo-check`, [development](../../documentation/contributing/development.md#rust-unsafe-boundary)). Values are owned and moved, not shared; see [differences](../../documentation/contributing/rust-toolchain.md#differences-users-can-see). Native standard identities come from `stdlib/*.ms`; a signature change reaches the declaration and the `ms-std-*` crate.

## Standard library

For standard APIs (intrinsic/native members, design), read [declaration ownership](../../stdlib/core/intrinsics.ms), [contracts](../../stdlib/core/intrinsics.ms), [runtime lessons](index.md), and [taste](../../skills/language-design/SKILL.md#taste).

- Inspect [newer stdlib direction](newer-stdlib-direction-needs-checkout-reconciliation.md) and current source first. Distinguish requested changes from shipped interfaces/bounds, removals, optional limits, and scheduling consolidation.
- Give each operation one appropriate module/spelling. Cover units, defaults, errors, streaming, mutation, edge cases, and cancellation; use Manuscript's execution model.
- Pick the failure mode by the [one rule](../../stdlib/core/intrinsics.ms): absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults with operation, argument, and valid range. Mutators take verbs (`set`, `remove`, `add`); copies keep past-tense or noun names. Do not restore the removed copy-sounding aliases (`with_value`, `without`, `with_entry`).
- Every standard type and function carries a doc comment, and a type's comment includes a short usage example; it appears in the generated reference.
- Audit omitted, `none`, valid, and invalid explicit limits/timeouts. The latest direction makes them optional and honored when supplied; do not impose mandatory limits without new direction. Document resource consequences and errors.
- Checked `.ms` source owns public signatures. Trace declaration → binding → checker call/receiver rules → native dispatch → called source tests → editor information → generated reference.
- Use domain-specific expected errors, preserving causes/concrete interface receivers. Generic boundaries use explicit matching/views; do not silently flatten Results or recreate convenience error-mapping APIs.
- Rename/removal covers imports, constructors, methods, aliases, bindings, dispatch, fixtures, virtual documents, generated pages/downloads, and guides. Respect the user's removal scope for historical/rejection mentions.
- Keep collection, synchronization, scheduling, and cleanup contracts explicit. Defaults agree across source metadata, native arity, function values, completion, and docs.
- Verify declaration/native ABI comparisons and called conformance, including invalid inputs/edges. Pair with the [tooling checklist](../tooling-and-docs/tooling-change-checklist.md); run `make docs-check` and applicable [documentation checks](../../skills/documentation/SKILL.md).
- A native that declares `; err: ErrOut` can explain any failure status, not only `Failed`: text it sets (a path, a program, a line and column) is appended after the status words, `JSON: invalid data: line 1, column 7: ...`. Regenerate the signature table with `cargo xtask symbols` whenever a native's parameters change; a stale table makes the call omit the slot and the native writes through garbage.
- A typed JSON decoder (`ms-lower/src/json.rs`) returns `none` on a mismatch; `jfail` first records the node and reason in the document (`msstd_json_mismatch`) and the caller builds `at $.a[0].b: ...` from it (`msstd_json_mismatch_text`). A parent that only propagates a child's `none` sets `jwhy = (-1, ..)` so it does not overwrite the child's record.
- Tests do not sleep to order events. A handler or task under test announces readiness (a stdout line, a promise, a file) and the test waits on that; a sleep stays only where elapsed time is the behavior (timers, cooldowns, deadlines, polling an OS facility with no wait primitive such as `flock`).
- Calendar-to-timestamp conversion must resolve the actual local fields through the timezone's civil offset API. Fixed +/-one-day probes miss short POSIX DST intervals (#3454). Inspect Jiff's raw ambiguous offset and choose the pre-transition offset in gaps/folds; constructing its narrower Timestamp would reject supported year-9999 fields. `short_dst.rs` isolates TZ in a child process, while core tests cover range limits, date-line jumps and half-hour overlaps.
- Timestamp fields can be constructed directly, so `shift` must still normalize raw nanoseconds and seconds outside the calendar range when the result fits. An overflowing nanos-plus-duration sum can also produce a valid timestamp. Keep the wide-integer differential oracle and called raw-field cases in `time.ms` when changing arithmetic; performance controls belong in `bench/perf/time-shift/`.
- Timestamp format token widths are minimums, including the sign: raw negative years
  and wide nanosecond fields must not be truncated. Keep the integer-format oracle,
  extended-year/zone comparisons and public raw-field assertion when optimizing
  numeric tokens (`core_time.rs`, `stdlib/time.ms` conformance fixture).
- Ticker overruns must retain the original period grid, not replace a deadline with the current clock reading. Advance by the remaining part of a period and drop whole missed periods without multiplying a tick count. `sync-timers-errors.ms` checks exact timestamp alignment and skipped intervals without tight elapsed-time upper bounds (#3330).
- Deque rotation reduces signed counts before choosing moves. Small negative
  turns use back-to-front moves; near-whole negative turns keep the shorter
  forward route. Test wrapped and partially filled rings, half-turn boundaries,
  and Int limits; a faster negative-unit case must not regress near-size counts.
- CSV quoted-cell decoding scans for its closing quote before decoding the span.
  Do not concatenate a growing prefix for every doubled quote: it makes a large
  valid field quadratic (#3197). Keep zero/single-escape, Unicode, CRLF and
  malformed-termination controls alongside the many-escape workload.
- CSV stream EOF must validate options even when its buffered tail is empty. The
  empty return formerly accepted invalid delimiters and line endings on empty
  input; `csv-rows.ms` covers no chunks, empty chunks and nonempty controls.
- CSV streams retain unfinished chunks and join only at completion/EOF (#3362).
  Update buffered fragments and quote state together before returning a record
  budget error: callers can continue reading, so stale fragments would corrupt
  later rows. Recheck nonempty EOF tails before parsing: a previously rejected
  oversized tail must not become a successful row on a continued read. Keep the
  continued-read regression alongside exact-limit tests.

- Weighted selection normalizes finite nonnegative weights by their largest entry when the raw total overflows or is subnormal. Reuse the validated normal total and preserve its direct selection loop. Raw sums can overflow, and raw subnormal draw points round equal weights into unequal bins. Keep secure and seeded selection on the same scale, exclude zero weights, and use fixed-seed comparisons across huge/subnormal and ordinary equivalent ratios (`random-weight-ranges.ms`, #3348). Do not multiply by a reciprocal: a minimum-subnormal scale has an infinite reciprocal.

- HTTP response metadata is copied: `ClientResponse.metadata` clones its head and `RawResponse.metadata` clones native headers, including after close. Do not describe either accessor as borrowing or aliasing. `reference-contracts.ms` checks independent metadata mutation without an extra caller-side clone.

- TOML serialization classifies a nonempty all-table array as a section; empty and
  mixed arrays stay inline. Classification needs only a predicate, not copied
  table payloads. Keep exact output/order and byte-limit controls when changing
  this decision (`toml.ms`, `bench/perf/toml-classification/`).

- Fixed-width UInt64 readers retain their own `binary: out of range` preflight; other fixed-width readers report native `binary: value out of range`. Reusing `unsigned_word` after one full-width read must preserve that guard and every bit of the unsigned upper half. Keep the full-range, nested-view, short-input and extreme-offset cases in `varint.ms`; see the [binary-word measurements](../../bench/perf/binary-words/README.md).

- `stdlib/core/` holds the files that need no import (`core.ms`, `intrinsics.ms`, and the `String` methods in `string.ms`); `build.rs` flattens it, so the public paths stay `@std/core.ms` and `@std/string.ms`. `StringBuilder` and `Regex` live in `string_builder.ms` and `regex.ms` and need an import. A path or module-size change can break the `ms-tooling` error-length cap and the LSP `none` reference pin.
