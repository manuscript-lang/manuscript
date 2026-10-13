# Residual #147 Release literal investigation

Debug #272 is merged and complete. This bounded follow-on changes **no
production compiler/runtime/API**. #238 remains held; #147 remains open.
The completed investigation rules out the tested root-free boxed factories and
records a precise typed-storage constructor dependency for later work. No
production representation or chunk size is selected here. Parent performance
review remains required before any Release change.

## Authoritative snapshots and width limits

Independent source baseline: main
`c80bdb2a68a5e8e45bffcb4a22a431b426162ed4`, including #234's default source/profile
boundaries, bundled Go1.25.1, Linux amd64. `main.go` calls the unchanged compiler's
ordinary CompileSource, preserving actual source-call wrappers, Type keys and
boxed List ABI. Candidate compiler/runtime files are unchanged. Original #238
and pre-AST golden files/hashes are untouched. The retained baseline source,
Go/ELF hashes and section sizes are in [provenance.json](results/provenance.json).

Published width snapshot #280 at `bd45f92a` adds explicit `Int64`/`Float64`,
contextual wide literals and host groundwork. Its default Int/Float are still
64-bit; later owner correspondence reports actual default32 edits locally,
awaiting publication/validation. Do not interpret this experiment as that
migration. Current literal emission chooses Int64/Float64 from checked type ID
and uses distinct runtime named types. A future typed constructor must use the
owner's exact mapping and already-rounded checked constants, without truncation,
implicit promotion, binary64 intermediates for binary32, or an invented suffix.
The typed32 cases below are **synthetic Go layout/copy controls only**; they do
not validate future default32 source semantics, arithmetic, native ABI or DAP.

#142/#278 owns shared-handle typed storage and traversal policy. Its current plan
keeps one canonical *List identity with an authoritative backing object, replaces
Items at cutover, and forbids a mutable boxed mirror. That broader cutover is not
implemented by this investigation. #278 then #266 shared-file merge ordering is
preserved. No traversal/cleared-tail/numeric/equality/source-call ABI edits occur.

## Root-free boxed factory sweep

Instead of an eager package-global interface table, each bounded factory returns
`[K]rt.Value` by value. A fresh `[N]rt.Value` destination receives each part and
exposes its slice to the existing List header. Primitive constants retain their
original checked Go expressions; factories contain no source effects or mutable
objects. K=64/256/1024 are measured alternatives, not arbitrary production chunks.
One variant declares separate part temporaries; another reuses one `[K]` stack
part to reduce frame and stack-map pressure. Native tests check all elements,
mutate one evaluation and verify another remains fresh. Neither form is
promoted: its extra stack/heap copy and call boundaries cost runtime even when
no additional permanent GC roots are present.

Bundled Go Release app builds use `-tags=ms_lean -trimpath -ldflags="-s -w"`,
GOMAXPROCS2, CPU2,3. Every baseline/factory build changes a comment to invalidate
Go's application cache. The first16K baseline (5.588s) includes cold work and is
retained but excluded from warm comparisons. The baseline100K has two samples;
reused controls have one exploratory build each, so these are scale observations,
not confidence estimates. Go test binaries for runtime loops use normal optimized
Go, same source wrapper/runtime, excluding compilation/startup/initialize.

| 100K source | Build seconds | Peak compile/link RSS KiB | Release app bytes |
| --- | --- | --- | --- |
| Ordinary baseline | 12.838 / 12.699 | 1,942,204 / 1,916,112 | 9,687,332 |
| Distinct part64 | 2.900 / 2.704 | 407,684 / 413,568 | 9,007,396 |
| Distinct part256 | 2.486 / 2.601 | 398,812 / 364,688 | 18,514,212 |
| Distinct part1024 | 2.606 / 2.571 | 424,804 / 399,432 | 11,125,028 |
| Reused part64 | 2.752 | 377,924 | 8,933,668 |
| Reused part256 | 2.355 | 330,504 | 8,782,116 |
| Reused part1024 | 2.801 | 405,744 | 8,724,772 |

The distinct256 caller has much larger read-only stack/GC metadata; reusing its
part reduces binary size. All measured boxed forms allocate2 objects and the
same bytes as the baseline:262,192B at16K and1,605,680B at100K. ELF `.data`/`.bss`
are identical to the baseline: there is no new package interface-root table.
That isolation does **not** remove the runtime regression.

Paired runtime method: fixed seed147 randomizes order within each pair,
CPU0/GOMAXPROCS1, GOGC100/50 plus bounded200x GC-off controls. Ratios are
candidate/baseline geometric means with10,000 paired-log bootstrap resamples.
Eight400ms pairs at16K; twelve500ms pairs at100K. Intervals describe this
host/workload, not all applications.

| 16K boxed shape | GOGC100 ratio [95%CI] | GOGC50 | GC off |
| --- | --- | --- | --- |
| Distinct64 | 1.709 [1.647,1.796] | 1.421 [1.357,1.475] | 1.222 [1.180,1.266] |
| Distinct256 | 1.582 [1.502,1.703] | 1.313 [1.276,1.353] | 1.261 [1.215,1.306] |
| Distinct1024 | 1.506 [1.416,1.595] | 1.347 [1.287,1.394] | 1.199 [1.163,1.230] |
| Reused64 | 1.551 [1.498,1.609] | 1.471 [1.414,1.537] | 1.162 [1.104,1.222] |
| Reused256 | 1.400 [1.355,1.453] | 1.372 [1.337,1.405] | 1.268 [1.203,1.342] |
| Reused1024 | 1.430 [1.386,1.479] | 1.344 [1.310,1.373] | 1.335 [1.125,1.750] |

At100K reused256 is1.602 [1.499,1.700] /1.620 [1.554,1.678] under GC100/50;
reused1024 is1.614 [1.562,1.673] /1.610 [1.554,1.662]. Every paired normal-GC
sample is slower. GC-off also remains slower (1.311 /1.190). Therefore neither
removing global roots nor reducing stack temporaries meets the Release runtime
criterion. This is evidence about tested forms, not a proof that every possible
boxed representation is impossible. Effects/mixed literals retain the separate
historical held-helper findings; this constant-only sweep does not establish
ordered control-transfer/source-map compatibility for effectful helper lowering.

## Two-allocation typed owner control and precise dependency

The older typed-list smoke prototype allocated List+backing owner+array separately
(three objects). This test-only control embeds its canonical handle in the typed
owner and returns the handle's interior pointer. The storage interface points
back to that same owner. It uses ordinary Go GC, without unsafe layout tricks.
Source-style box aliases, a saved typed projection and saved append method see
updates/growth through one owner. A second evaluation gets a different owner and
array. This proves that the *constructor shape* can retain two allocations; it
is **not** a production List ABI implementation or full generic/native parity.

The source call wrapper stays the same, but returns the prototype handle into
the test harness. Existing production List operations cannot consume that handle;
typed controls are therefore benchmark-only, and their unused source main is
never called. A real backend must preserve actual *rt.List identity/Type key,
native dispatch, lexical evidence, equality/cycles, DAP and source semantics.

| 100K control | GOGC100 ratio [95%CI] | GOGC50 | GC off | B/op / allocations |
| --- | --- | --- | --- | --- |
| Synthetic typed64 | 0.173 [0.166,0.180] | 0.173 [0.167,0.178] | 0.513 [0.489,0.534] | 802,880 /2 |
| Synthetic typed32 | 0.079 [0.074,0.084] | 0.111 [0.107,0.115] | 0.254 [0.242,0.265] | 401,472 /2 |
| Current boxed baseline | 1 | 1 | 1 | 1,605,680 /2 |

These controls justify a concrete next dependency, not a future32 language speed
claim. They use pointer-free static numeric arrays copied into fresh typed backing.
Only the16-byte interface overhead is removed; source width changes alone leave
boxed Value arrays16B/element and pointer-copy work intact.

Before a Release primitive-table patch can be accepted:

1. #271 publishes/reviews the authoritative checked Int/Int64/Float/Float64→Go
   representation, literal range/rounding and exact nominal-type mapping. Include
   named wide values and signed-zero handling. No independent width conversion.
2. #142 supplies an allocation-neutral fresh typed backing constructor behind
   one canonical List handle. An embedded-owner shape is a measurable option:
   two objects, stable aliases/projections across append/reallocation, no boxed
   mirror. Header bytes, cyclic owner retention, generic boxing and empty/small
   lists must be measured. Storage owner decides the production design.
3. All List constructors/read/write/growth/traversal/native/format/equality/view/
   closure/Optional/Result/debugger consumers move through that authoritative
   layer before Items cutover. No isolated literal fake ABI or implicit copies.
4. This lane then emits only exact checked primitive constants into immutable
   pointer-free tables, with fresh owned storage per evaluation. Ordered mixed
   elements, unary/Decimal/reference values retain ordinary lowering until their
   separate measured semantics are supported. Re-run actual compiled-language
   zero/one/repeat, GC100/50, build/RSS/binary and alias/source-location tests
   after the real backend and width changes; original goldens stay frozen.

## Fresh-process zero/one/repeat memory controls

One100K constructor, five randomized fresh-process pairs per0/1/64 call case,
CPU1/GOMAXPROCS1, GOGC100/50. Last result remains live; two forced GCs release
transient buffers. Heap stats exclude static segments; child /proc VmRSS,
VmHWM/RssAnon/RssFile are retained. Process wall includes initialization/work/GC,
not a pure construction benchmark. All controls share the current source wrapper.

| GOGC100 calls | Boxed baseline heap/RSS MiB | Reused256 | Typed64 | Synthetic typed32 |
| --- | --- | --- | --- | --- |
| 0 | 0.450 /8.340 | 0.450 /8.375 | 0.450 /7.953 | 0.450 /7.871 |
| 1 | 1.982 /11.891 | 1.982 /12.062 | 1.216 /9.410 | 0.833 /8.652 |
| 64 | 1.982 /12.988 | 1.982 /12.180 | 1.216 /10.285 | 0.833 /8.953 |

| GOGC50 calls | Boxed baseline heap/RSS MiB | Reused256 | Typed64 | Synthetic typed32 |
| --- | --- | --- | --- | --- |
| 0 | 0.450 /8.344 | 0.450 /8.367 | 0.451 /7.891 | 0.450 /7.879 |
| 1 | 1.982 /13.023 | 1.982 /12.121 | 1.216 /9.410 | 0.833 /8.648 |
| 64 | 1.982 /14.047 | 1.982 /13.277 | 1.216 /9.609 | 0.833 /9.359 |

Root-free boxed factories have no material extra zero-call retained cost; that
supports the intended isolation. Their repeated process walls nevertheless rise
54.72→81.20ms at GC100 and56.33→84.70ms at GC50. Typed controls have no added
interface table in `.data`; numeric backing is in `.noptrdata` and is touched
when copied. All raw samples/ELF sections/source hashes remain in results/.

## Reproduction and disposition

From the pinned repo, generate separate artifact roots with main.go (ordinary,
-reuse, and -typed-controls), build runtime.test with bundled Go `test -c
-mod=vendor -tags=ms_lean program.go program_test.go`, then use the existing
bench-debug-literals/runtime_pairs.py with the Release binaries. Use bundled
`build -trimpath -ldflags="-s -w"` for comparable app size; the synthetic typed
source main is not an executable ABI-parity control. measure_memory.py compiles
fresh memory harnesses using the common instrumentation, then writes120 samples.
No completed Debug work is rerun. No new source/runtime representation is merged.

The active bounded assessment is complete. #238 stays held for runtime regression;
#147 stays open. Later work depends on reviewed typed storage and actual #271
width mapping. Do not begin another residual slice under the user's latest
consolidation-first direction. See [handoff.md](handoff.md) for layer/skills issues
encountered. No broad refactor is started here.
