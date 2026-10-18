+++
title = "Error handling"
weight = 5
+++

# Error handling

Use `Result` for an expected failure with a cause, `Optional` for a missing value, and a fault for a broken programming assumption.

| Concept | What you will learn |
| --- | --- |
| [Expected failures with Result](results.md) | Return success or domain errors as ordinary values. |
| [Error propagation with try](propagation.md) | Forward compatible errors without hiding faults or cancellation. |
| [Programming faults](faults.md) | Check invariants and understand task failure after cleanup. |
