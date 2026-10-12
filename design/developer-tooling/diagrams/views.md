+++
title = "System, flow, and detail views"
weight = 113
+++

# System, flow, and detail views

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Choose a diagram based on the question you need to answer: which modules depend on each other, how work runs, or how data changes. These views come from checked source, so reviewers can follow links back to the code.

The compiler emits three views:

| View | Contents |
| --- | --- |
| System | Modules, exported operations, capabilities, external resources |
| Flow | Calls, branches, loops, parallel groups, background admission, joins, errors, cancellation, deadlines |
| Detail | Data transformations, types, implementations, source locations |

Nodes link to typed source and contracts. System and detailed flow views label execution-lifetime and cancellation edges separately from value dependencies. Loops remain loops; the compiler does not expand them into hypothetical executions. Dynamic dispatch shows a contract and known targets; unresolved behavior remains explicitly unresolved.

## Choosing the view

Start with the system view to inspect dependencies and authority. Use a flow view to examine concurrent APIs, errors, and cleanup. Use detail to connect transformations and types back to source.

See [a concurrent-flow example](flow.md), [architecture diffs](architecture-diffs.md), and [observed execution overlays](traces.md).

[Previous: Readable and structured diagnostics](../source/diagnostics.md) · [Next: Reading a concurrent-flow diagram](../diagrams/flow.md)
