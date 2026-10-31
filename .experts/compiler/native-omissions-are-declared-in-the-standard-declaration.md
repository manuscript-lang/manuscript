[Wiki](../index.md) › [Compiler and build](index.md)

# Native omissions are declared in the standard declaration

Verified: defaults for native functions, methods, and constructor fields are written in the standard `.ms` declaration and checked as ordinary expressions. Constructor omission follows source metadata, application implementations inherit standard interface default permissions and receive concrete values, and native compositions pass `some(n)` through source-defined streams. Inferring permission or default expressions from a field's name would create a second schema; passing raw integers through an Optional interface would break source implementations.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [native default checking](../../crates/ms-check/src/native_defaults.rs), [native defaults fixture](../../tests/e2e/testdata/stdlib/defaults.ms), [stdlib revamp fixture](../../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: exercise stored, bound, and generic calls that omit a defaulted argument and fresh records; omit a limit through an application-defined ReadStream and match `none`.

---
Topics: [Errors and results](../topics/errors-and-results.md)
