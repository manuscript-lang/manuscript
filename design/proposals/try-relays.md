# Results own their cases separately, so `try` relays copy nothing

## Summary

- Problem: a function that relays the error of a borrowed `Result` but builds its own `ok` payload copied the error. `fn g(value: String!String) String!String: o := try value; return ok(o + "x")` lowered the error arm to `clone` + `alt.new` (verified with `ms emit` on `a494979b`). The error is a part of a parameter and the ok payload is a new value, so `mixed_returns` withdrew the borrow and the whole result was owned. `expect_ok(actual)` (`ok(value)` beside `error(failure(..))`) copied its payload the same way.
- Change: ownership of a `Result` result is per case. A case that is a part of an argument borrows it; the cases the function builds are owned. The caller holds the sources while the result lives and drops only the owned cases. No runtime tag and no per-value flag: which case owns is a static fact about the function.
- Not changed: lambdas and interface implementations own their results; a borrow beside a path that builds the same case, a resource closed at scope end (its close error is an owned error), or a part with one owner and no `clone` keeps the old withdrawal; `Optional` is not covered yet.

## Status

Implemented 2026-11-04, checked against `a494979b`. Direction (Chinmay): "allow try, we can't litter the codebase with clone, it's fine to have special handling for result optional etc since they're first class language primitives"; "i didn't mean for copy, for lending, as long as it doesn't result in leaks"; "it can return a borrow without own for result and optional"; "this needs to work for result and optional and try, we need to make the language machinery work without copy"; "use the consistent terminology from ownership" (so: borrow and borrowing result). Skeptical review (subagent, 2026-11-04): the first design, a per-value ownership bit, would touch `Val.own`, `result_mode`, `lastuse`, `copyelim` and `inline`; replaced by the type-level mask below. Its counterexamples (`match g(v)`, `try g(v)`, `r := g(v)`, passing the result on, `get(default)` and `err()`, inlining, `copyelim`) each hit a verifier rule or a fixture while building; `tests/e2e/testdata/accept/borrowing-result-cases.ms` covers them with heap strings. Stdlib measurement before building: 0 of 86 error constructions in `@std/data/toml.ms` copied, so the benefit is `expect_ok`/`expect_some` payloads and user code more than that module.

## Design

- Checker (`ownership/walk.rs`): `returned` and `try_return` record the cases a wrapper borrows (`borrowed_cases`) and the cases owned paths build (`owned_cases`, 7 for an unknown shape). `mixed_returns` keeps the wrappers when the masks are disjoint, the wrappers are whole `ok(..)`/`error(..)` constructors or a `try`, the part is clonable and no resource closes at scope end. `Summary.result.borrowed_cases` carries the mask; callers see a view (`returns_borrow` and `view`), so holds, freezing and overlap are unchanged. A call that borrows only the error leaves `try` an owned `ok` payload; `return other_borrowing_call(..)` forwards the mask.
- MIR: `AltDef.borrowed` marks cases; `Module::borrowing_alt(base, mask)` makes the *borrowing variant* (same layout and cases), so one drop glue per type skips the borrowed cases and `lastuse`, `copyelim` and the verifier need no new mode. `alt.view` fills a borrowed case, `alt.new` an owned one. `alt.plain` reads the variant as its ordinary alternative (a borrow, inserted where a call takes the ordinary type). `alt.own` copies it into the ordinary alternative where an owner is needed. `result_views` taints variant results for the passes. The verifier rejects `alt.take`, `alt.release` and a variant-to-variant `clone` of a borrowed case, so a missing conversion is a compile error and not a double free.
- Lowering: a callee with `Fact::BorrowedOk`/`BorrowedError` returns the variant (`borrowing_result_ty`); `ok(..)`/`error(..)` in return position build into it (`Fact::RetCtor`). `try` of a borrowing operand relays a borrowed error with `alt.view` and borrows a borrowed `ok` payload; `match` binds a borrowed case in place; `Result` natives read the receiver through its own alternative and copy only where they return an owned payload (`get(default)`, `err()`). A borrowing result over a temporary source is copied with `alt.own` before the temporary drops, as `OwnedBorrow::Clone` does for plain borrows.

## Evidence

| Check | Result |
| --- | --- |
| `g`, `try g(v)`, `match g(v)`, `r := g(v)`, `print(g(v))` with heap strings under valgrind | no invalid access, no leak; no `clone` in `g`, `relay`, `pass_on` (`ms emit`) |
| `make conform`, `make e2e`, `make leak-check`, `make count-check`, `make copy-check`, crate tests | pass |
| `xs.append(g(v))` | rejected with the existing borrow diagnostic (`tests/ownership/reject/borrowing_result_stored.ms`) |

A `match` on a local bound from a borrowing result binds each arm's payload in place (no copy; `scrutinee_lives` in lowering). A function that returns a borrowed `ok` and a new error (`expect_ok`) changed callers: `tests/e2e/testdata/stdlib/yaml.ms` now clones the child it reassigns into `root`, which the old copy hid.

## Alternatives

- Do nothing: one string or record per error, on the error path only. Rejected by the owner ("we need to make the language machinery work without copy").
- A runtime view bit in the alternative's tag word: every tag reader, drop, copy and native would mask it, and `views.md` found hidden views break `copyelim`, `lastuse` and `strfuse`. Rejected.
- A per-value ownership mask in the verifier and every pass (first design): replaced by the type-level mask.
- Desugar `try` into `match` before analysis: does not remove the copy (`return error(x)` beside `return ok(new)` is the same mixed return) but would delete the `try` special cases; separate cleanup.

## Open questions

- `Optional` has one payload case (`none` has none), so per-case ownership has nothing to split: a function whose paths return a borrowed `x?` and a new value copies the borrowed one, as before. When every path borrows, `opt.view` already lends. `owned_wrap` is deleted (#2540): its sites call `owned`, which the strict gate reports like any other store of a borrowed part. `try` of a named local the function owns moves its error out on the exit path (no copy).
- Generic functions get one variant per instance; `ms check` passes for `wrap[T](value: T!String)`, but only `Result[String, Error]` and `Result[Int, Error]` instances ran.
