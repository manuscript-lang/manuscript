+++
title = "Errors and validation"
weight = 27
+++

# Errors and validation

[Core language guide](../_index.md) · [Design index](../../_index.md)

Choose the outcome that matches the situation: `Result` for an expected failure with an explanation, `Optional` for a missing value, and a fault for a broken programming assumption. These pages show how callers respond to each one.

| Concept | What you will learn |
| --- | --- |
| [Expected failures with Result](results.md) | Return success or domain errors as ordinary values. |
| [Error propagation with try](propagation.md) | Forward compatible errors without hiding faults or cancellation. |
| [Assertions and programming faults](faults.md) | Check invariants and understand task failure after cleanup. |
