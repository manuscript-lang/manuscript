# Lazy `split`, `lines` and `fields_by` are look records written in `.ms`

Decision (Chinmay, 2026-11-25, "lets do lazy iterations in ms as well, thats more efficient, and users can build a list if they want to"): `String.split`, `lines` and `fields_by` return `Split`, `Lines` and `Fields`, records whose `fn var next() &String?` yields one borrowed piece. `for` reads them with no list; `.collect()` builds the `List[&String]`. This replaced the name-keyed `source_split` loop lowering (#7105), whose wiki page is deleted.

Verified (2026-11-25, CPU time, min of 15 against the previous `main`): sortrecords, report, logstats, dedupe, csvgroup within 0.98 to 1.03x; wordfreq 0.85x (no 112 MB list). Three pieces make the plain `for` match the old offset walk: `msrt_string_split_end` (find the next separator) with `msrt_string_piece` (an unchecked view), the `opt_splitview` twin rewriting `split(..).collect()[0]` to `split_first` even when the inlined `collect` hands the list through block parameters and unwind-site tests, and closure-field read forwarding in `opt_inline_closure.c` so `fields_by` does not call its predicate through a pointer.

Failure modes found: a function returning `&String?` from a view native had neither `ret_borrowed` nor `ret_view`, so copy elision turned `piece.clone()` into a move and the clone viewed freed text (`e2e/stdlib/split-view-clone-outlives-source`, `lazy-text-iterators`); `reserve` in `lower_func.c` now marks a `&String` or `&String?` result `ret_view`. A list of looks returned from a non-inlined function needs `ret_view` too, or its source is freed early.

Apply when: adding another lazy producer, give it a look record with `next() &T?` and a `hold` constructor; check `.clone()` of an item survives `ms emit --opt`, and callgrind the split-heavy suite programs.
Evidence: `src/stdlib/core/string.ms`, `src/compiler/opt/opt_splitview.c`, `design/proposals/lazy-iterator-chains.md`.
Verify: `conform`, `ctest`, `bench/perf` CPU-time comparison against the previous `main`.
