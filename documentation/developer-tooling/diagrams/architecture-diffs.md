+++
title = "Architecture diffs"
weight = 115
+++

# Architecture diffs

A small source edit can change what a system can access or how long work runs. An architecture diff highlights those changes to boundaries and behavior, alongside the ordinary text diff.

Architecture diffs report changed boundaries, capabilities, effects, error types, cleanup scopes, concurrency, and deadlines. These facts derive from compiler analysis. Explanations of intent are supplementary.

## Reviewing a changed boundary

For example, adding a capability parameter changes accepted authority. Adding scheduled submission changes a service lifetime boundary. Adding `with` changes an explicit cleanup boundary. Adding a domain error changes the caller’s expected alternatives. These changes belong in the derived architecture view because they follow from checked source.

The draft defines the reported facts, but does not prescribe a diff rendering format. See [boundary contracts](../../core-language/modules/boundaries.md) and [effect summaries](../source/effects.md).
