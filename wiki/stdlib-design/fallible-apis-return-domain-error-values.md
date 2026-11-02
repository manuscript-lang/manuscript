[Wiki](../index.md) › [Standard-library design](index.md)

# Fallible APIs return domain error values

Decision (2026-10-31): `Result[T, E]` has no reporting bound. Prefer named domain records/cases for public APIs; primitive errors are also legal. Standard errors retain their optional `Error.message()` implementations for common reporting boundaries.

Apply when: writing a Result-returning API, adapter, example, or test.
Evidence: [core.ms](../../stdlib/core.ms), [Result decision](../language/result-error-values-do-not-require-error.md).
Verify: domain errors propagate through exact-`E` functions without an impl; only helpers using `.message()` or Error widening require `E: Error`.
