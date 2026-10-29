# Benchmarks and performance lessons

Two unrelated benchmarks exist; never mix their results. Lowering and runtime trade-offs are in [compiler.md](compiler.md) and [runtime.md](runtime.md).

### Performance and agent benchmarks are separate

Decision: `bench/perf/` measures compiler/runtime speed (`stdlib/` ns per operation, `programs/` and `kernels/` whole-program comparisons); `bench/agent/` measures how well agents solve the same challenges in TypeScript, Go, Rust, and Manuscript (hidden tests, tokens, turns, time, cost). Each README points at the other, and their results never share a table. Keep agent-bench transcripts out of git.

Apply when: reporting numbers, adding a benchmark, or moving either directory.
Evidence: [bench/perf](../bench/perf/README.md), [bench/agent](../bench/agent/README.md), [maintenance skill](../skills/repository-maintenance/SKILL.md).
Verify: `make agent-bench-check` (oracle plus unit tests) passes; every path in the Makefile, docs, and skills resolves after a move (`make repo-check`).

### Benchmarks are a profiling guide, not a gate

Verified: results are only comparable on one machine and revision; record the commit and machine with the table, as the result files do. Use best-of-N or median of repeats, alternate before/after order, exclude build and warm-up, and require a deterministic checksum so a wrong program cannot look fast. Do not add a CI threshold.

Apply when: claiming a speedup or regression.
Evidence: [program results](../bench/perf/programs/results.md).
Verify: before/after run on the same host with `make stdlib-bench BENCHREPEATS=5 BENCHFILTER=<case>` or `bench/perf/programs/run.sh 7`.

### A win needs a baseline comparison, not just a smaller number

Verified: keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution of each source operation. Checked arithmetic is language behavior, so a control that omits overflow checks diagnoses cost but does not change the baseline. Reject a candidate that moves a material gap into another workload, and retain its measurements. Prefer removing unobservable work and allocations over placement tuning.

Apply when: optimizing a helper, a lowering path, or a runtime routine.
Evidence: [program results](../bench/perf/programs/results.md), [kernel baselines](../bench/perf/kernels/README.md).
Verify: time and allocation counts before and after on one machine; behavior tests unchanged.

Verified (2026-10-29, regex templates): reusing a temporary string cut allocation
calls but raised logical peak live allocation by 33% when a large first expansion
was followed by many small ones. Expanding directly into the result removed the
temporary and lowered that peak instead. Include changing-size output cases when
reusing scratch capacity; allocation counts alone do not establish a memory win.
The [regex report](../bench/perf/stdlib/regex-results-2026-10-29.md) and its external
counting probe distinguish logical capacity from generated-program RSS.

### Shared collection helpers need conversion and union controls

Verified (2026-10-29): eliminating a redundant lookup in `List.distinct` reduced
instructions but common-case wall timings remained inconsistent; the List change
was not retained. A shared copy-helper refactor also added roughly five
instructions per new key to List-to-Set conversion. Keep union and conversion
as controls when changing a Set helper, and distinguish fewer hash calls from a
wall-clock claim. The retained Set-only change skips a check only when one
input's uniqueness proves that a fresh output cannot already contain the key.

Apply when: changing a shared collection lookup or copy helper.
Evidence: [collection-copy measurements and rejected variants](../bench/perf/list-distinct/README.md).
Verify: paired unique/duplicate and small/large workloads, exact producer status
and checksums, whole-producer instruction counts, and the Set hash-count regression.

Verified (2026-10-29, BitSet predicates): Boolean relation queries previously
built a full temporary algebra result before checking emptiness. Direct word
comparisons preserve arbitrary exposed word arrays and allow early exit. Keep
the algebra methods' representations intact: shortening their output can change
observable `words`, even when set membership is unchanged. The
[BitSet report](../bench/perf/bitset-relations/README.md) records full-scan,
early-answer and empty/small controls; the source fixture compares against the
unchanged algebra across unequal lengths, trailing zeros and signed high bits.

### Consume library checksums and separate allocation phase from local cost

Verified: a returned checksum that the harness discards is not evidence that the work stayed observable. Consume each result with `keep` from `@std/bench.ms` so the work stays observable, and reject missing, duplicate, failed, or changed cases and operation counts on every trial (`compare_stdlib.py` validates all stdlib cases from `ms bench --json`). Changing an earlier allocating workload can move later allocation costs, so an apparent unrelated regression in a full-suite run may not reproduce when the same cases run repeatedly in separate focused processes. Keep both results and state the distinction; do not silently replace the full run.

Apply when: retaining a benchmark win or diagnosing a nominal unrelated slowdown.
Evidence: [stdlib validator](../bench/perf/compare_stdlib.py), [program measurements](../bench/perf/programs/results.md).
Verify: balanced process order, identical tool flags and inputs, no simultaneous CPU work, raw samples plus source and binary hashes, and focused controls for regressions. Identical instructions can vary when relocated across alignment boundaries; preserve assembly and reject arbitrary padding or lucky-placement tuning.

Verified: matching checksums among the rows that happen to be present cannot establish complete work. The kernel and competence wrappers check the producer before filtering its output, append a trial boundary only after success, and the shared reporter requires the suite's full kernel and version identities exactly once per trial and the requested trial count before printing any rows. A missing kernel in every version, duplicate row, failed producer with plausible output, or late checksum mismatch must fail without a partial comparison.
Evidence: [kernel reporter](../bench/perf/table.py), [producer and evidence regressions](../bench/perf/test_kernel_trials.py).
Verify: `python3 -m unittest discover -s bench/perf -p test_kernel_trials.py` exercises both actual shell runners with controlled producers and requires zero report output on failure.

Verified: a Python launcher's inherited high-water mark can dominate Linux `wait4` RSS for small child executables. Use a small native launcher that forks after its own exec for separate RSS trials; distinguish maximum single-process RSS in a waited process tree from simultaneous aggregate memory. Keep timing trials separate and label empty extraction caches separately from cold OS page caches.
Evidence: [isolated RSS helper](../bench/perf/representative/rss.c), [measurement protocol](../bench/perf/representative/README.md).
Verify: a trivial native program's reported RSS must not merely equal the Python launcher's RSS; retain the original raw measurements when correcting the measurement method.

### Source-size gap versus TypeScript is lines and I/O ceremony, not syntax noise

Verified (2026-10-22, o200k_base): `bench/agent/tokens.py` puts the hand-written reference solutions at ms 12.2k, rust 10.1k, go 10.1k, ts 8.3k tokens, so Manuscript is not below Rust (1.21x) or TypeScript (1.48x); the old ms references predate `xs[i]`, `+=`, and inline suites, so they overstate it. Agent-written ms was 1.30x TypeScript. Newlines and indentation account for about 40% of the gap (ms programs run about 1.75x the lines), and agents ignore forms the cheat sheet never showed: `xs[i]`, one-line `if c: return x`, no `flush()`. Reading stdin and the `run()`/`main()` match ceremony cost about 100 tokens per program. Blank lines are free (`\n\n` replaces `\n`). Open options, not decisions: `main` returning `Result`, `try` on `Optional`, a less vertical formatter for call arguments.

Apply when: judging a syntax or stdlib change by its token effect; measure with `tokens.py` and a rerun, not intuition.
Evidence: [tokens.py](../bench/agent/tokens.py), [cheat sheet](../crates/ms-tooling/src/guide/data/cheatsheet.md), [streams.read_lines](../stdlib/streams.ms).
Verify: `python3 bench/agent/tokens.py` prints the per-language totals; rerun the small challenges and compare `llm_tokens` of passing ms and ts runs.

### Compare instruction counts first; a low-IPC gap points at libc

Verified: wall-clock on a shared VM moves by 2x between runs, so compare `valgrind --tool=callgrind` instruction counts of one kernel built in Manuscript and Rust (`rustc -C opt-level=3 -C overflow-checks=on`) before chasing code generation. Most kernels executed fewer instructions than Rust. `text_1M` ran 0.77x Rust's instructions but 3x its time: the program spent its cycles in musl's `memcpy` (`rep movsq` startup on every short copy) and byte-at-a-time `memcmp`. `crates/ms-rt/src/mem.rs` now defines them, and `ms_rt::alloc::StdHeap` replaces musl's malloc for the Rust std natives. Low IPC with modest instruction counts means look at `objdump` of the hottest libc function.

Apply when: a Manuscript program is slower than Rust with similar or fewer instructions, or before replacing a libc routine.
Evidence: [mem routines](../crates/ms-rt/src/mem.rs), [std heap](../crates/ms-rt/src/alloc.rs).
Verify: callgrind totals and a wall-clock min of at least five runs before and after; the unit tests in `mem.rs`; no self-call in the disassembly of the replaced symbols.

### Real programs lose to Rust on collection call counts, not codegen
Verified: on c13-inventory-orders (2026-10-23) Manuscript made ~1.0M map calls where the Rust reference made ~342k, at a lower per-call cost than Rust's SipHash map; the count was the whole 1.55x instruction gap. It came from idioms the library made cheapest to write: `keys()` then `get` per key (because `entries()` copied every value) and `get` then `add` (because `if var x = m.get(k)` lowered to four map calls). After walking maps in place in `for` headers and making `if var` on a map one lookup, the same program written with those idioms ran 184-216 ms against Rust's 173-206 ms. Adding `memory(read)`/`nounwind` attributes to pure runtime lookups in the LLVM declarations changed nothing: the competence binary was byte-identical and c13 moved +0.5% instructions, because LLVM already inlines user code into one function and the remaining cost is the calls themselves.

Apply when: a workload is slower than Rust or Go; before tuning a runtime call or the LLVM input.
Evidence: `tests/e2e/testdata/accept/map-in-place.ms`, `crates/ms-lower/src/stmt.rs` (`map_walk_loop`), `crates/ms-lower/src/alias.rs` (`AStep::Key`).
Verify: count runtime calls per source operation with callgrind (`calls=` per callee) on the Manuscript and Rust builds before comparing per-call costs.

### Count page faults before tuning a native that builds big buffers

Verified (2026-10-24, `bench/perf/json`): building a parsed JSON document ran 2x slower through `ms` than in a Rust test of the same code, with identical instruction counts. The Linux `ru_minflt` of the process grew by about 270 faults per call (the size of the document's vectors), because `StdHeap::dealloc` handed every non-arena block to musl's `free`, which unmaps it, while `alloc` took large blocks from the runtime's cache. A large block freed from Rust now goes through `ms_rt::alloc::free`, so the cache sees it; the faults per call fell to about zero and the call took 0.63 ms instead of 1.10 ms. Instruction counts and sampling profiles cannot show this.

Apply when: a native that allocates blocks of hundreds of KiB per call is slower than the same code run in a Rust test.
Evidence: [std heap](../crates/ms-rt/src/alloc.rs), [JSON benchmark](../bench/perf/json/README.md).
Verify: `getrusage(RUSAGE_CHILDREN).ru_minflt` for a one-second run of `ms run bench/perf/json/ms.toml -- twitter:doc` stays within a few thousand, not hundreds of thousands.
