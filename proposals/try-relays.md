# Results own their cases separately, so `try` relays copy nothing

## Summary

- Problem: a function that relays the error of a borrowed `Result` but builds its own `ok` payload copies the error. `fn g(value: String!String) String!String: let o = try value; return ok(o + "x")` lowers the error arm to `clone 1` + `alt.new` (verified, `ms emit`, `a494979b`). The error arm is a part of a parameter and the ok arm is a new value, so `mixed_returns` withdraws the borrow (`walk.rs`, `plain_borrowed` false) and the whole result is owned. `ok(o)` alone, or `try` with only borrowed returns, already uses `alt.view` and copies nothing (verified).
- Change (recommended): ownership of a `Result` result (and later any enum) is per case. `Summary.result` records which cases lend and from which sources; the others are owned. The caller drops only the owned cases with the existing case-masked `alt.release` and holds the sources while the result lives, like a view lender. No tag bit, no runtime flag: which arm owns is a static function of the case.
- Not changed: lambdas and interface implementations still own results; a plain lent path beside a new value in a non-`Result` function stays an error; no copy is ever inserted: the lent case stays a borrow, and storing the whole result where it outlives its sources is rejected with a `.clone()` remedy, like any other borrow.

## Status

Draft, 2026-11-04, `a494979b`. Direction (Chinmay, this project): "allow try, we can't litter the codebase with clone, it's fine to have special handling for result optional etc since they're first class language primitives"; "these are simple helpers to make life easy, they don't need to follow allocation semantics of other types"; "we can convert try etc into regular if else first and then do analysis"; "what if we de sugar result itself". Not yet implemented.

## Problem

Evidence: the repro above; `proposals/views.md` withdrawal rule ("a wrapped lend beside an owned path is withdrawn"); `mixed_returns` in `crates/ms-check/src/ownership/walk.rs`; `try_expr` in `crates/ms-lower/src/matching.rs` (error arm: `alt.view` only under `ret_borrowed`, otherwise `owned(x)`). Inferred, not measured: how many stdlib `try` relays copy today. First step of implementation is counting `clone` on error arms in `ms emit` of stdlib.

## Options

1. Desugar `try e` to `match e: error(x): return error(x)` before ownership analysis (Chinmay's first idea). Verified by reading the code that it deletes `try_return` and the Try cases in `moved.rs` and `walk.rs`, but it does not fix the problem: `return error(x)` beside `return ok(new)` is the same mixed return. Worth doing anyway as cleanup once option 2 exists; inferred, not prototyped.
2. Per-case ownership (recommended). `Result` is already an ordinary alternative (`stdlib/core.ms`, `Builtin::Result`); `ResultBorrow` gains `lent_cases` (bitmask over cases) beside `returns_borrow` and `view`; `mixed_returns` stops withdrawing a wrapper when the lent paths are whole cases. Lowering: `Func.ret_cases` (mask of lent cases); callers bind the result as `Own` with a `release` mask of owned cases; `lastuse`/`copyelim` treat it like `result_views` (sources stay alive, no move out of a masked register). Generalizes to user enums, since only the case index matters.
3. Runtime view bit in the tag word. Rejected: every tag reader, drop, copy and native that touches an alternative must mask it, and `views.md` already found hidden views break `copyelim`, `lastuse` and `strfuse`.
4. Do nothing: the copy is one string or record per error, on the error path only; callers pay no extra. Honest cost: allocation on a cold path. The user's rule is no compiler-inserted copies, so this keeps a copy the source never wrote.

## Open questions

- Storing a masked result whole (`results.append(g(v))`): decided (Chinmay, 2026-11-04: "i didn't mean for copy, for lending, as long as it doesn't result in leaks"): lend, never copy; an escaping store is a checker error with a `.clone()` remedy. Leak freedom is the acceptance bar (`make leak-check`, valgrind).
- Inlining a masked callee: `inline.rs` reads `ret_borrowed`; the mask must travel with it (inferred from `inline.rs` reading that flag; not checked).
- `Optional` is the same shape (`opt.view`); do it in the same change or after? Recommend after, once `Result` ships.

## Verification

`ms emit` of the repro shows no `clone` on the error arm; `make copy-check`, `make leak-check`, valgrind Debug and Release on a fixture mixing `try` of a borrowed `Result` with an owned ok; the frozen conformance fixtures `testtailresultidentity*` unchanged; `make verify`.
