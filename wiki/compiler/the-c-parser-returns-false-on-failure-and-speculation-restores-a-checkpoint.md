[Wiki](../index.md) › [Compiler and build](index.md)

# The C parser returns false on failure and speculation restores a checkpoint

Verified 2026-11-20: `src/compiler/src/syntax/lex.c` and `parse.c` began as ports that unwound errors with `longjmp`, which the C style guide bans. Every scanner and parser function that can fail now returns `MS_NODISCARD bool` with the result in a last `out` parameter written only on success, and the `fail*` helpers record the diagnostic and return nothing, so a site reads `fail(...); return false;`. A helper that returned `false` itself made clang's analyzer assume the recursive calls could return true without writing `out`.

Speculation (an `if` expression body, `try` recovery, a bracket that may be type arguments, an interpolation parsed by a nested parser) takes a `Checkpoint` of the scratch and byte stack lengths, `depth` and the three body flags, and restores it on failure. It does not restore `next_id`, `nqueued` or `p->at`: the Rust parser spends node ids on an abandoned attempt, and the differential test (`src/compiler/tests/syntax-diff.sh`, tokens, ast, codes, partial, with mutants) fails the moment ids shift. A failed `enter()` leaves its depth increment, and `checkpoint_restore` keeps that `+1`.

Apply when: adding a parse function (check every call, never `break` out of a loop on failure, and keep the Rust order of `new_id()` against sub-parses), or changing speculation.
Evidence: `sh src/compiler/tests/syntax-diff.sh` passes on 6852 repo files plus mutants (`MS_FUZZ=20000`).
