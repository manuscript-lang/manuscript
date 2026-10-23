# String unique ownership and views (owned-values stages 4 and 5)

Status: proposal, revised 2026-10-23 after a skeptical review. Builds on `owned-values.md` (decisions 1 to 3) and needs #994 (the three-word `{ptr, len, cap}` String) landed.

## Problem

After stage 3 a String is shaped like `List` and `Bytes`, but its buffer is still a refcounted block: copy is a retain, drop is a release, and a 24-byte header (count, scalar-count cache) precedes every dynamic string. Against the owner's direction ("follow borrow and ownership", Rust as the model) that leaves three gaps:

1. A String copy is invisible and shared, while every other owned value is copied explicitly with `.clone()`.
2. Reads such as `trim`, `split`, `get` and `basename` allocate a new string because the result cannot point into the source.
3. Every dynamic string pays 24 header bytes plus a count update on each copy and drop.

The owner has decided the direction (2026-10-23). This note argues the order and the gates, and says what is still unmeasured.

## Two separable changes

**Views (stage 5) do not need the count removed.** A view is a borrow of its source, and the checker already guarantees the source outlives it (`OWNERSHIP.md`, "Borrowed results": lexical borrows, a `.clone()` fix when a borrowed result reaches an owning position). A view therefore carries no retain, so it can ship with the count still in place. It needs a native lending marker in the stdlib declaration and a `StrView` type in MIR so provenance is static; there is no runtime flag and no `&mut str`. This removes the allocation from `trim`, `split`, `slice` and `basename`.

**Unique ownership (stage 4) removes the count and the header.** A dynamic string block becomes the bytes plus one NUL; `cap >= 1` marks an owned heap buffer and `cap == 0` a static one (as in #994). Copy allocates and copies, drop frees, `StrVal` stops being implicitly copyable. Costs it adds: non-ASCII `length()` becomes an O(n) scalar count (the cache lived in the header), and every remaining string copy (closure capture, interface boxing, a collection getter result) allocates.

Order: **views first, then unique ownership**, because views deliver the largest allocation saving at lower risk and the data below shows the retain and release cost itself is small. Stage 4 then needs its own go decision on measured dynamic copy counts.

## Evidence and what is not yet measured

Measured (callgrind and `bench/perf/copy-report.sh` on #994 at 24afe08):
- Static `str` copies in optimized MIR: competence 4 copies, 2 of them `str` (`str <- str`, `str <- opt.get`); programs 3 `opt<str>` and 1 `str`; the stdlib-bench program (json, yaml, toml, csv, html) 3 direct `str` or `opt<str>` copies plus about 8 collection or record copies that hold strings.
- Instruction share of `trim`, `trim_start`, `trim_end` (with the shared `trimmed`) plus `split` in the yaml micro-benchmark: about 42M of 384M, 11% (callgrind, `ms-rt` symbols). What part of that is allocating the result is unsplit.
- Memory arithmetic, not measured: a 28-byte string block (32-byte size class) becomes 4 bytes (16-byte class) without the header, about 16 MB for the 1M names in `records_1M_x20`.

Measured dynamically (`bench/perf/str-counts.sh`, which compiles with `MS_COUNT_STR=1` against the counting runtime; on #994 at its head):
- `competence`: 21.0M owned string copies (plus 1.0M static), 23.9M owned drops. Nearly all of it is `strmap_10M`, which executes two owned copies per iteration: the `let w = words.get(...)` binding and the `.clone()` the map keeps as its key. The map's copy is required (Rust clones there too); the `let` copy is a borrow the lowering still materializes, so about 10M of the 21M allocations are avoidable without any ownership change.
- stdlib bench (json, yaml, toml, csv, html, strings): 0.36M owned copies against 2.6M owned drops, so copies are rare next to temporaries.
- `programs` and `kernels`: no string copies.

Not measured, and required before stage 4 is approved:
- Wall time of `strmap_10M`, `text_1M` and `records_1M_x20` under a prototype of stage 4.
- Allocation share of `trim` and `split`, measured on the first view PR.

## Alternatives

- **Do nothing (stay refcounted, no views).** Smallest risk. Keeps copies implicit, `trim` and `split` allocating, and the 24-byte header. The owner has rejected it as the end state, not as a step: stopping after views is a valid outcome of this plan if the stage 4 gate fails.
- **Counted views (Swift-style slices that retain the source).** Rejected: a second string representation that keeps implicit sharing and costs a retain per view, when lexical borrows already prove the source lives.
- **Inline small strings.** Compatible later optimization (`cap` flag); out of scope.

## Plan (small PRs, each with auto-merge)

1. **Dynamic copy counts.** Counter and report for `Str` copy and drop per benchmark; record the numbers in this note. No behavior change.
2. **First view, `basename`.** Lending marker in `bindings.json`, checker rule and accept and reject fixtures, `StrView` in MIR and the lowering coercions, with the MIR interpreter modeling views as borrowed `Rc<str>` slices so it stays an oracle. Measure the allocation saving.
3. **`trim`, `split`, `slice` and the rest of the view family**, one stdlib function family per PR.
4. **Stage 4 audit while still refcounted.** Remove `Clone, Copy` from `StrVal` so the compiler finds every bitwise copy (`*s`, struct copies, `AbiSlot::duplicate`, the `StringList` and `RecList` duplicates, split iterator state at `string.rs:1530`, map-key paths, the `ms-std-*` ports), and make each one an explicit `dup()` (a retain) or a move. Behavior is identical because `dup()` is the retain that exists today; the compile errors are the audit, not a grep for `retained(`.
5. **Go or no-go for stage 4** on the step 1 counts and a throwaway prototype's wall times (`records_1M_x20`, `strmap_10M`, `text_1M`, parser benches). If it passes: drop the header and count, copy allocates, drop frees, non-ASCII `length()` counts scalars; make the leak-check runtime poison freed blocks so a missed sharing site fails loudly (the arena allocator hides use-after-free from valgrind and ASan-style tools).

`copyelim` needs no prior re-proof: it only removes copies, and `str_source_stable` already returns false for anything but literals and list reads, so an allocating copy leaves the same copies in place and only makes the existing removals worth more. Extending it (for example to `alt.unbox` and `opt.get` sources) is a separate optimization gated by the step 1 counts.

## Gates

Per PR: `make verify`, conformance, leak sweep with zero new leaks, `bench/perf` tables with no regression above noise against the previous main. Stage 4 PR additionally: `records_1M_x20`, `strmap_10M` and `text_1M` at or below the #994 numbers, and the dynamic `str` copy count not above the step 1 record.

## Risks and open questions

1. A stdlib function that stores its argument without copying becomes a use-after-free once the count is gone; step 4 (compiler-driven) and poisoning in step 5 exist for this.
2. Provenance for `StrView` must reach every native that keeps its input; each such native is marked as consuming, never lending.
3. Non-ASCII `length()` becoming O(n) may surprise a text-heavy program; measure the parser benches before stage 4.
4. Closure captures and interface boxing copy strings today through `Op::Copy`; each becomes a visible allocation and needs the dynamic count gate.
5. `StrView` in every `Str` position (generics, `Shared[String]`, map keys, match payloads, `Optional`, records, boxing, returns) needs a coercion or rejection rule; the first PR is deliberately one function to find the shape.
