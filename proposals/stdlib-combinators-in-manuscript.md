# Write `Optional`, `Result` and `List` combinators in Manuscript

## Summary

- `stdlib/core.ms` and `stdlib/collections.ms` declare ~140 methods with `...` bodies. Lowering implements the combinators among them (`map`, `and_then`, `or_else`, `get_or_else`, `ok_or`, `filter`, ...) as hand-written MIR in Rust.
- Change: write the `Optional`/`Result` combinators as Manuscript method bodies (interface plus `impl`, the shipped `ListIntSum` pattern) and delete their Rust cases once a measured gate shows no regression. `List` is out of scope until `Optional`/`Result` land.
- Blocking work: source methods on `Optional`/`Result` do not resolve today, and the MIR inliner never inlines method bodies. Both are compiler fixes, not stdlib edits.
- Unproven: no measurement yet covers a real stdlib interface method, so stage 0 is a read-only spike that decides go/no-go.
- Decision requested: approve stage 0 (spike and measurement only).

## Status

- Proposal, 2026-10-26, checked against `220cd77`.
- Direction (Chinmay): "We don't want to regress on performance. But we also cannot keep doing special casing for standard library methods in Rust."
- Project rule: implement in Manuscript; Rust only for small general primitives.
- Skeptical review done 2026-10-26 (below); scope narrowed and a spike stage added as a result.

## Problem

- Verified: `Optional.map`, `and_then`, `or_else`, `ok_or`, `ok_or_else`, `get`, `is_some`, `is_none` and the `Result` equivalents are `...` in `stdlib/core.ms` and lowered by name in `ms-lower/src/native.rs` (`opt_method` at line 59, `optional_method` ~200 lines, `result_method` ~205 lines). `List` higher-order methods add `list_higher_order` (~280 lines) and `is_higher_order`.
- Verified: each method needs an entry in `ms-check/src/receivers.rs` (190 pairs) that the loader cross-checks (`unused native receiver binding`).
- Effect: a combinator cannot be read, changed, or tested as Manuscript; every new one needs Rust in two crates.
- Non-goals: `List`/`Map`/`String` storage operations (`append`, `get`, `slice`) stay native; they need runtime layout. Language syntax does not change.

## Design

- Rule: a stdlib method whose behavior is expressible with `if let`, loops and other methods is a source method with a body. Native bodies remain only for operations that touch representation.
- Form: the shipped pattern is an interface plus `impl Iface for Type` (`collections.ms:443`), because `split_mixed` rejects bodied inherent methods on native types. Target for `Optional.map`:

```
interface OptionalMap[T]:
    def map[U](transform: Callable[[T], U]) -> Optional[U]

impl OptionalMap[T] for Optional[T]:
    def map[U](transform: Callable[[T], U]) -> Optional[U]:
        if let value = self:
            return some(transform(value))
        return none
```

  Not checked against current main (it is the open question stage 0 answers); the supported spelling of a generic interface over a prelude type may differ.
- Measured, but only an upper bound on the idea: a user free function (`FuncKind::Normal`) doing the same as `Optional.map`, 400M iterations of `opt.map(lambda x: x + 1).get(0)`, Cranelift and `--build-type Release`: native method 0.45 s, free function 0.45 s. It does not cover the proposed form: `inline.rs` closure specialization requires `FuncKind::Normal` with a borrowed closure parameter, and an interface method may be `FuncKind::Method` (vtable, erased receiver).
- Verified blockers:
  - `impl MapOps for Optional[Int]` in user code is rejected: `implementation receiver must be nominal source data`. Only the stdlib loader (`split_mixed` in `ms-check/src/stdlib.rs`) may attach source methods to native types, as `ListIntSum` does for `List[Int]`.
  - Attempt: giving `Optional.is_some` and `Optional.map` bodies in a separate inherent `impl Optional[T]:` block in `core.ms` and removing their `receivers.rs` entries fails in `@std/io.ms`: `unknown or ambiguous member is_some on Optional[IoError]`. That was the unsupported inherent form, so it does not show the interface form fails. Stage 0 retries with the interface form.
  - `ms-mir/src/opt/inline.rs` header: "closure code and method bodies are never inlined". A source `Optional.map` would be a real call, unlike the free function measured above.
- Fixes:
  - Make source methods on prelude types visible to every module, as the module doc already states for `List`.
  - Let the inliner treat a stdlib source method like a plain function when it is small (same `BASE_THRESHOLD`). Closure-argument specialization then applies unchanged.
- Semantics to preserve, one test each: `none` and `error` short-circuit without calling the closure; the closure runs exactly once; the payload moves rather than copies when the receiver is a temporary; no extra retain/release or box versus `opt_get`/`opt_some`.
- Out of scope: `get` and `err` (they return `ref T` borrowing a temporary the native code extends, `native.rs:2054`); they stay native.
- Rust to delete is only the migrated cases of `optional_method`, `optional_ok_or` and `result_method` (~400 lines before shared helpers); `two_ways`, `finish` and `owned` stay because `List` and others use them.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/src/stdlib.rs` | source methods on prelude types resolve everywhere | conformance: call `Optional.map` from two modules |
| `ms-mir/src/opt/inline.rs` | inline small stdlib method bodies | MIR unit test: `Optional.map` inlined at a direct call |
| `stdlib/core.ms`, `stdlib/collections.ms` | bodies replace `...` per method | existing conformance and e2e fixtures |
| `ms-check/src/receivers.rs` | remove the migrated entries | loader check `unused native receiver binding` |
| `ms-lower/src/native.rs` | delete the migrated cases | `make conform`, perf gate |
| `bench/perf` | add `Optional`/`Result`/`List` combinator kernels | committed result page |
| Parser, formatter, LSP, docs | unchanged; `ms search_symbol` output unchanged | `make docs` freshness |

## Alternatives

- Do nothing: no performance risk, but every combinator stays two crates of Rust and cannot be tested as Manuscript. Rejected by the stated direction, and not by evidence: the benefit is maintainability, not speed.
- Table-driven lowering inside Rust (one generic "map over payload" helper): removes duplication but remains special-casing by name. Rejected by the stated direction.
- Keep Rust lowering, generate it from the `.ms` body at build time: a second compiler for stdlib; larger than the inliner change.
- Add an `inline` attribute: new syntax for one use. Rejected: the default design is no new syntax; an inliner size rule covers it.
- Drawback of the chosen design: compile time grows if inlining many bodies; gated below.

## Staging and verification

0. Spike, no merge: `Optional.map`, `is_some`, `is_none` via the interface form. Record the `FuncKind` the method gets, the MIR before and after (`ms emit`), instruction counts (callgrind) and wall time for temporary and variable receivers, `Int` and `String` payloads, Cranelift (debug) and LLVM Release. Go only if MIR matches or is within 2% instructions and the debug build is not slower in time.
1. Compiler fixes the spike shows are needed (prelude visibility, inlining small stdlib method bodies), with those three methods migrated and their Rust cases deleted. Gate: `make verify`, `make conform`, the stage-0 measurements committed under `bench/perf/` as a dated section, and compile time for `bench/perf/programs` within 2% (the specialization budget is module-wide, so measure many call sites).
2. Remaining `Optional`/`Result` combinators, one PR each, same gate per PR.
3. `List` higher-order methods only after stage 2, under a separate proposal: `list_higher_order` pre-sizes with `list_new(n)`, and looped bodies inline only from a loop call site, so a source form may lose.
4. Add a repo check that fails when a `...` function has no native binding.
- No-go: any measured regression above the gate, or a platform-specific skip. Keep the Rust case for exactly the methods that regress; migrated methods stay migrated.

## Open questions

- None that change user-visible behavior. Recommendation for the owner: approve stage 1.

## Skeptical review

Independent reviewer, given the file only. Findings and response:

- The perf measurement used a `FuncKind::Normal` free function, not the proposed method form: accepted, now stated as an upper bound and stage 0 measures the real form.
- The inherent-impl example is not the supported form: accepted, example changed to interface plus `impl`.
- The "hypothesis" about the `io.ms` failure was unverified and likely the same cause: accepted, rewritten.
- "~700 lines" ignored shared helpers: accepted, costed only the migrated cases.
- `get`/`err` ownership (`ref T` of a temporary) unaddressed: accepted, kept native.
- `List` is riskier (pre-sizing, loop-only inlining, module-wide specialization budget): accepted, moved to a later separate proposal.
- Gates lacked MIR diff, instruction counts, debug-build timing, ownership and leak checks: accepted, added to stage 0.
- No-go rule was vague: accepted, now per method.
- Do-nothing was rejected by assertion: accepted, now says the benefit is maintainability, not speed, and adds the table-driven alternative.
- Docs and `search_symbol` unchanged: not yet verified; stage 1 checks `make docs` freshness.
