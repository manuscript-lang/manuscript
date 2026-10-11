+++
title = "Errors and validation"
weight = 27
+++

# Errors and validation

[Core language guide](../_index.md) · [Design index](../../_index.md)

Distinguish expected failures, missing values, and programming faults. Return Result for expected failures, use Optional for absence, and assert an invariant when its violation means the program is incorrect. Each has its own handling rules.

| Concept | What you will learn |
| --- | --- |
| [Expected failures with Result](results.md) | Return success or domain errors as ordinary values. |
| [Error propagation with try](propagation.md) | Forward compatible errors without hiding faults or cancellation. |
| [Assertions and programming faults](faults.md) | Check invariants and understand task failure after cleanup. |
