# Postfix `?` as `try`

## Summary

- Problem: `try` is a prefix, so nested calls stack it (`try expect_equal(try collect(...), [1, 2])`), and the leading `try` hides the call.
- Change: postfix `expr?` means `try expr`. It is a language change, not tooling.
- Decision requested: `?` replaces prefix `try` (owner direction); approve the `?.` rule below.

## Status

Proposal, 2026-11-10, checked against `origin/main`. Owner approved reversing the old `?` rule and removing `try`. Not yet reviewed by a skeptical reviewer.

## Problem

Today `?` after a call is rejected on purpose (`ms check`, verified):

```
a := parse(s)?
a.ms:4:18: parse: expected end of statement, found '?'; '?' is not a postfix unwrap, '??' or 'c ? a : b': ...
```

The repo's own tests show the cost:

```manuscript
first := try collect(ReadStream[Int](Counting(0, 0)) | take(3), none)
try expect_equal(first, [1, 2, 3])
try expect_equal(try collect(from_list([1, 2]) | take(5), none), [1, 2])
```

Every fallible call needs a keyword before it, and a call inside a call needs two. Pipes already have a postfix form, `x | try`.

## Design

`expr?` is exactly `try expr`: unwraps `ok`, returns the error from the enclosing function, same error-compatibility and `Unit!` rules as [propagation](../documentation/core-language/errors/propagation.md).

```manuscript
fn label(s: String) String!:
    n := parse(s)?
    check(n)?
    return ok("n={n}")

expect_equal(collect(from_list([1, 2]) | take(5), none)?, [1, 2])?
check(n)?
```

- Binds as a postfix link: `f(a)?` is `try f(a)`. A gapless `?.` is always optional chaining, so `load(7)?.name` on a Result is a type error with a hint; write `u := load(7)?` then `u.name`, or `(load(7)?).name`.
- `place[key]?` in an `if var` head stays the in-place borrow ([conditionals](../documentation/core-language/control-flow/conditionals.md)); elsewhere `x[i]?` propagates a Result element.
- Operand must be a Result; the existing `try` diagnostics apply. An Optional operand is rejected, not unwrapped: `?` never turns `none` into an early return.
- Standalone `call()?` is a call statement with `Unit` success, like `try call()`.
- Inside a lambda, `?` returns from the lambda, as `try` does.
- `try` is removed: `try f(x)` becomes `f(x)?`, `x | try step` becomes `x | step?`, `x | try` becomes `x?`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` (`parser.rs` `postfix`, `lexer.rs`, `format.rs`) | parse `?` link as `UnaryOp::Try`; replace the "not a postfix unwrap" message | parser accept and reject cases |
| `crates/ms-check` | none: lowers to the existing `Try` | conformance fixture using `?` |
| `documentation/core-language/{errors/propagation,basics/grammar,basics/expressions}.md` | grammar and precedence row | `make docs-check` |
| `ms fmt` | no space before `?` | formatter round trip |
| stdlib, tests, docs | stage 2 migration | `make verify` |

## Alternatives

- Do nothing: nested `try` stays. The cost is syntax noise only.
- `x | try` already exists, but reads left to right only inside pipes.
- Rust-style `?` that also unwraps Optional: rejected, mixes two meanings and the diagnostic above rules it out.
- Keep `try` beside `?`: two spellings for one thing; owner chose removal.

## Stages

1. Parser, formatter, checker, docs, fixtures: `?` works and `try` still parses.
2. Mechanical migration of every `.ms` file, doc and diagnostic from `try` to `?` with `ms fmt`-style tooling, then remove the `try` keyword and its diagnostics.

## Open questions

- `?.` on a Result: A (error with hint, proposed) or B (type-directed propagate then access).
