+++
title = "Error handling"
weight = 5
+++

# Error handling

Use `Result` for an expected failure with a cause, `Optional` for a missing value, and a fault for a broken programming assumption.

| Concept | What you will learn |
| --- | --- |
| [Expected failures with Result](results.md) | Return success or domain errors as ordinary values. |
| [Error propagation with ?](propagation.md) | Forward compatible errors without hiding faults or cancellation. |
| [Programming faults](faults.md) | Check invariants and understand task failure after cleanup. |

## Choosing a failure in the standard library

The standard library picks the failure by its cause. Your own functions can follow the same rule.

| Cause | Result | Examples |
| --- | --- | --- |
| A value is missing | `null` from a `T?` | `first()` on an empty list, `Map.get(key)`, `parse_int` on text that is not a number |
| The caller passes a bad value: a size, count, radix, budget or other argument | An `Error` of kind `EINVAL` when the function already returns `Error`, else `null` when it already returns an optional | `rate_limiter` with a nonpositive rate, `to_string_radix(1)`, `weighted_choice` with all-zero weights |
| A count has a natural meaning at zero | That meaning, not a failure | `take(0)`, `chunks(0)` and `repeated(0)` give nothing; a shift count of 64 or more shifts every bit out |
| The environment refuses: files, network, processes | An `Error` with the matching kind (`ENOENT`, `ETIMEDOUT`) | `read_file`, `connect` |
| The code is wrong | A fault | an index out of range with `[]`, integer overflow, a negative shift count, `clamp` with `low` above `high`, reading a flag the schema never declared |

A function does not change its return type to report a bad argument. If it returns a plain value, a bad argument is a bug and faults; if it already returns `T?` or `T!`, a bad argument returns `null` or `EINVAL`. A caller who cannot tell whether a value is valid checks it first or calls the form that returns an error, such as `get(index, default: x)` for `[]`.
