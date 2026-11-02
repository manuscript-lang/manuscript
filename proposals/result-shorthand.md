# `T!` shorthand for `Result`

Status: proposal, 2026-10-31. Owner direction: "let's use ! for result, instead of full Result[T, E] we should be able to write T! as short form".

## Problem

`Result[T, Error]` is the most common fallible return type, and `T?` already abbreviates `Optional[T]`. The long spelling dominates signatures in `stdlib/` and the book.

## Design

A type suffix, parsed with `?` left to right:

- `T!` is `Result[T, Error]`.
- `T!E` (`E` directly after the bang, no space) is `Result[T, E]`, for example `Bytes!ArchiveError`.
- Suffixes compose: `Int?!` is `Result[Int?, Error]`, `Int!?` is `Optional[Result[Int, Error]]`, `Int!E?` is `Optional[Result[Int, E]]`.
- A function type needs parentheses, as with `?`: `(fn() Int)!`.
- `Result[T, E]` stays valid; the shorthand is sugar resolved in the parser, so the checker, lowering and diagnostics see the same `Named` type as before.

Lexing: `!` directly after a name character, `]`, `)`, `?` or `!` is the suffix token. Elsewhere it remains the rejected negation with the "write 'not x'" hint. `!=` is unchanged, so `Int!= x` is not a shorthand; write `Int! = x`.

## Evidence and alternatives

Code removed: every `Result[X, Error]` in signatures shrinks to `X!`. Doing nothing leaves the verbose spelling. A different marker (`T!!`, `Result` keyword form) was not considered; `!` mirrors `?` and is free in type position.

No runtime, ABI or checker change.
