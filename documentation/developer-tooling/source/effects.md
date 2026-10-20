+++
title = "Understanding effects"
weight = 3
+++

# Understanding effects

An effect is external behavior reachable from a function; a callee's write is part of its caller's summary.

## Transitive analysis

Effects combine along calls. The vocabulary is `read`, `write`, `external-call`, and `unknown` (`crates/ms-check/src/effects.rs`).

| Call target | How it contributes to the summary |
| --- | --- |
| Known source target | Include its effects, including the effects of its callees. |
| Several known targets | Include the union of their effects. |
| Unresolved function value or contract call | Include `unknown`; do not treat it as having no effects. |

Summaries describe reachable behavior; no syntax promises purity or restricts effects.

## Effects and cancellation

Cancellation stops unfinished work and runs cleanup but cannot undo a completed external write. When retrying, review both returned errors and external effects.
