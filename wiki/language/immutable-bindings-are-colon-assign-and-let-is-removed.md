[Wiki](../index.md) › [Language](index.md)

# Immutable bindings are `:=`; `let` and `let (` are removed

Decision (Chinmay, 2026-11-10): `x := e` is the immutable binding and `let` no longer exists; `var x = e` stays the mutable one, so `:=` only ever means immutable. Typed immutable is `x: T = e`; destructuring is `[a, b] := xs` and `{name} := rec`; `if v := opt:` replaces `if v := x`; module constants are `NAME := e` / `NAME: T = e`. `let (` groups were layout only and are gone; `var (` remains.

Why: one keyword fewer and about one token fewer per binding. Statement-start `[`/`{` is a binding only when its matching close is followed by `:=`, and a leading `Name :` is a typed binding, so neither collides with expression statements.

Apply when: changing binding grammar, the formatter's token-based wrapping (it looks for `=` or `:=` after the pattern), partial-parse recovery roots (`constant_start` in `partial.rs`), or export-name hints in `ms-driver`.
Evidence: [bindings](../../documentation/core-language/basics/bindings.md), [grammar](../../documentation/core-language/basics/grammar.md), [destructuring](../../documentation/core-language/types/destructuring.md).
Verify: `let x = 1` fails with the "'let' was removed" diagnostic; `if let v = o:` fails likewise; `[a, b] := [1, 2]` parses; a column-zero `name: Int,` stays a multiline-parameter continuation, not a constant.
