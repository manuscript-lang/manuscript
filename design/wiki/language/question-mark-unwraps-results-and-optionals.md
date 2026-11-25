[Wiki](../index.md) › [Language](index.md)

# `?` unwraps Results and Optionals; there is no `?.`

Decision (Chinmay, 2026-11-18, superseding the 2026-11-14 "`?.` stays Optional-only" note): postfix `?` is "the value, or leave the function" for both types, and `a?.b` is just `(a?).b`. An absent Optional returns `none` from an Optional function and simply returns from a `Void` function (lexical: the nearest function or closure). A function cannot mix kinds (Result needs a Result return, Optional needs Optional or `Void`). `?` adds no access of its own: a `var fn` call or change through `x?` lands in the optional place `x` only when `x` is `var`; otherwise it is rejected like any change to that binding.

Why: `f()?.name` was rejected for a Result and 6 of 63 first-build agent runs hit it (#4520); two near-identical tokens with opposite control flow was a standing confusion.

Failure mechanism: in-place changes go through several lowering paths (call receiver, `var` argument, `place_update`, `alias_payload_addr`); each must treat `Unary Try` of an Optional place as that place (`mutation::optional_try`), or the change lands on a copy. The ownership walker's `is_place` and `borrowed_call_root` do the same, and `checked_optionals` skips a repeated test within one statement. the `optional-chain-cannot-call-var-fn` reject fixture and the `question-mark-*` fixtures guard it.

Apply when: designing or changing `?`, Optional or Result syntax, or in-place changes through an Optional.
Evidence: [proposal](../../proposals/question-mark-unwraps-optionals.md), [propagation](../../../documentation/core-language/errors/propagation.md).
