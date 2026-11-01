# Wrapped results are views of their arguments

## Summary

- Problem: a lent part that leaves a function wrapped (`return ok(r.name)`, `return r.tags[0]` as `String?`, `try f(r)` passing a lent error on) or that is bound wrapped (`let o: Item? = item`) is a move, so callers clone to keep the original. #2199 added 70 `.clone()` calls for the shapes one-owner semantics rejects, and the user rejects both the clones and compiler-inserted copies.
- Change: wrapping a lent value into `Optional` or `Result` keeps it a reference. The checker records the wrapper (`view_wraps`); lowering builds it with `opt.view` or a new `alt.view`, which neither retain nor release their payload, and the function lends as if unwrapped. Nothing changes at runtime: no tag, no new drop path.
- Not changed: converting a lent value to an interface or widening its error type still copies; a lent path beside a new value stays an error; stores, captures and interface implementations keep `.clone()`.

## Status

Implemented in this PR, 2026-11-01, checked against `23477392`. Direction (Chinmay, 2026-11-01): "i cannot pass the variable deep without clone? ... that doesnt make sense"; "the pr seems to be adding clone to more places, which is the opposite intent"; "no i don't want implicit copying". Reverses the clause of `reference-ownership.md` (Results) and `crates/ms-check/OWNERSHIP.md` that a value converted to `Optional` or `Result` on the way out is owned. Skeptical review verdict (subagent, 2026-11-01): revise; ship `Optional`/`Result` views, drop mixed-return views, defer interface views until specified (see Alternatives and Open questions).

## Problem

Measured (`23477392`, the 70 `.clone()` lines #2199 added removed, debug `ms check` over the changed files): 59 rejections in four shapes.

| Shape | Sites | Example |
| --- | --- | --- |
| wrapped or converted on the way out, or at a binding: `ok(inner)`, `try visit(r)`, `return cause` as `Error`, `let view: Counter = tally` | 25 | `tests/conformance/fixtures/e2e/accept/result-argument-inference.ms`, `try-result-payloads.ms`, `tests/e2e/testdata/projects/error_boundaries` |
| lent path next to a new value | 16 | `stdlib/data/toml.ms:1071` `if bare: return key` / `return quote_text(key)` |
| lent value stored or captured: `names.append(first_tag(..))`, `m.add(original, 1)`, `fn() Error: cause` | 15 | `map_add_scope/first.ms:15`, `core_parity/first.ms:54` |
| interface implementation returning a lent value | 3 | `stdlib/collections/ordering.ms:196` `return lesser(self, other)` |

```manuscript
fn named(r: Row) String!Missing:
    return ok(r.name)               # moved `r.name`; callers wrote ok(r.name.clone())

fn tail(result: Row!Bad) String!Bad:
    let row = try relay(result)     # `relay` lends; the try's error path moved it
    return ok(row.name)
```

Lowering already had the first half: `opt.view` lends a container entry as an optional. The checker's move was what made the payload owned.

## Design

A view is a wrapper whose payload belongs to another value. The checker holds the owner borrowed while the view lives, exactly as for the arguments of a lending call; lowering never drops a view.

- Returns. In `returned`, `wrapped_lend(e)` recognizes `x?`-style wrapping (`Info.wrap_some` without an error conversion) and `ok(x)` / `error(x)` (a `Result` constructor with one unlabeled `Move`-class argument). Such an expression lends when its payload does; the node goes into `view_wraps` and the call's constructor arguments are forced to `Borrow`. `lend_source` and `pure_origins` see through the wrapper, so the callers' holds and overlap rules are unchanged.
- `try`. `try_return` treats the implicit error return of `try e` like `return error(err)`: when `e` lends and its error type is `Move`-class, the try lends (and `tail` above lends `result`); when the error is owned, the function owns its result, and a plain lent path beside it is the existing mixed-return error. A `try` whose payload type is `Copy` reads its operand.
- Bindings. `let o: Item? = item`, `let k = ok(x)` and `let v: T? = r.f` bind a shared borrow of the source (`bind`, "binding of a borrowed value"); changing the source while the binding lives is the usual error.
- Withdrawal. A wrapped lend beside a path that returns a new value is withdrawn (`plain_lent` false): the function owns its result and lowering copies the payload as today, so `ok(p.name)` beside `try risky(n)` with an owned error keeps compiling. Only an unwrapped lend beside a new value is an error.
- Lowering. `expr` emits `opt.view` and `construct` emits `alt.view` (`Op::AltView`: Borrow operands, `result_mode` Borrow, verifier rejects a boxed alternative, interpreter shares the fields) when the node is in `view_wraps` and the payload is not owned; `try_expr`'s error path in a `ret_borrowed` function returns `alt.view` of the lent error. Otherwise the previous owned paths run.

| Before (`23477392`) | After |
| --- | --- |
| `let outer: Result[Int!Failure, Tagged[Int]] = ok(inner.clone())` | `ok(inner)`; `outer` borrows `inner` |
| `let value = try visit(result, var visits).clone()` | `try visit(result, var visits)`; `visit` lends `result` and the error passes through |

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/ownership/{walk,mod}.rs`, `checker.rs`, `lib.rs` | `wrapped_lend`, `result_payload`, `try_return`, `plain_lent` withdrawal, `view_wraps` facts | `tests/ownership/accept/wrapped_lends.ms`, `reject/wrapped_lend_held.ms` |
| `crates/ms-mir` (`ir.rs`, `builder.rs`, `verify.rs`, `interp.rs`) | `Op::AltView` | `cargo test -p ms-mir`, verifier rule |
| `crates/ms-clif/src/lower.rs` | `AltView` lowers like `AltNew` | `make count-check`, `make leak-check`, valgrind on the e2e fixture, Debug and Release |
| `crates/ms-lower` (`cx.rs`, `expr.rs`, `call.rs`, `matching.rs`) | view ops where `view_wraps` says so | `tests/e2e/testdata/accept/wrapped-lends.ms`, conformance `e2e/accept/wrapped-lends` |
| fixtures | 12 `.clone()` removed (`result-argument-inference.ms`, `try-result-payloads.ms`) | `make conform`, `make e2e` |
| `OWNERSHIP.md`, `crates/DESIGN.md`, `references.md`, wiki | the wrapping rule and what still clones | `make docs-check`, `make repo-check` |

## Alternatives

- Do nothing: the clones stay; the user rejected this ("opposite intent").
- Compiler-inserted copies at these sites: zero diagnostics, hidden allocations; rejected ("no i don't want implicit copying").
- Mixed returns as runtime-tagged views (prototyped: a `view` op, string `STR_VIEW` tag, `Lend.view` making lowering return owned values): covers the 16 stdlib/tools sites, but `Own`-mode results that hide views break `copyelim`, `lastuse` and `strfuse` and `try` on such a result dangles, and the result's callers then store a value that borrows the arguments, so `parts.append(inline_value(item))` needed `.clone()` where the callee arm had one before. It moves clones to callers instead of removing them. Rejected.
- Records of scalars copy like scalars: `reference-ownership.md` reversed exactly this rule for uniformity.
- Report instead of withdraw a wrapped lend beside an owned path: breaks existing code that mixes `ok(p.name)` with `try risky(n)`; withdrawal keeps `main`'s behaviour there.

## Open questions

- Interface views (`return cause` as `Error`, `error(cause)` widened, `let view: Counter = tally`, 25 sites): would need a tagged vtable word (box of borrowed leaves, drop frees the box only, `copy`/dispatch/`iface.is` mask the tag), `iface.view` restricted to `Borrow` positions, `OwnedLend::Whole` disabled for them and the `try` paths specified. Pending the user's decision; the review found no non-fixture evidence yet.
- Closures returning a capture (`fn() Error: cause`): a sound rule needs the result of calling any `fn` value to hold that value, which would force `.clone()` in `out.append(transform(x))`-shaped code. Keep `.clone()`.
- Storing a lent value (`m.add(original, 1)`, `Box(v: a)`): the store outlives the source, so the copy is intentional. Keep `.clone()`.
