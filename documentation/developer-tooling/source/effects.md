+++
title = "Understanding effects"
weight = 3
+++

# Understanding effects

An effect describes external behavior reachable from a function. If a function calls another function that writes to storage, that write is also part of the caller's effect summary.

## Transitive analysis

The compiler follows calls and combines their known effects. The vocabulary is `read`, `write`, `external-call`, and `unknown` (`pkg/checker/effects.go`).

| Call target | How it contributes to the summary |
| --- | --- |
| Known source target | Include its effects, including the effects of its callees. |
| Several known targets | Include the union of their effects. |
| Unresolved function value or contract call | Include `unknown`; do not treat it as having no effects. |

These summaries describe reachable behavior. Manuscript has no source syntax that promises static purity or restricts a function to an effect set.

## Effects and cancellation

Cancellation can stop unfinished work and run cleanup. It cannot undo an external write that already completed. Review both a boundary's returned errors and its external effects when deciding how to retry or recover.
