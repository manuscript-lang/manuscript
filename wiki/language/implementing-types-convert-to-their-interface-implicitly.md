[Wiki](../index.md) › [Language](index.md)

# Implementing types convert to their interface implicitly

Decision (Chinmay, reversing the explicit-view rule): a type with a declared `impl I for T` passes wherever `I` is expected; `Error` widening was already implicit and shares the path (`Info.error_source`). The conversion follows the position: a read-only argument borrows the operand, a stored position moves it at its last use; the interface value owns a copy when the operand is borrowed.
