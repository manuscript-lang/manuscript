[Wiki](../index.md) › [Standard library design](index.md)

# `mean` and `Closeable.close` keep their current shape

Decision (Chinmay, 2026-11-18): keep `mean` as it is, and keep `Closeable.close` returning `Void!` ([why](../runtime/closeable-close-returns-a-result.md)). Do not reopen either in a stdlib consistency pass without a new problem and with/without code examples.

Apply when: a stdlib consistency or API-shape review reaches statistics helpers or the `Closeable` interface.
