+++
title = "Scope and implementation order"
weight = 106
+++

# Scope and implementation order

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Implementation order follows the dependencies between the language, library, runtime, compiler, and tooling.

## Implementation order

1. Parse and check the language, including named calls, exact types, contracts, captures, and sharing.
2. Implement lexical cleanup and atomic start, cancellation, completion, and close transitions together.
3. Connect standard imports, data operations, CLI host, streams, and adapters; validate complete programs.
4. Complete the queue, pool, builder, HTTP, and subprocess APIs using the same lifetime and cancellation rules.
5. Build source tools, diagrams, traces, and debugging on checked compiler facts and matching runtime metadata.

Use the [semantic tests](semantic-tests.md) and [complete programs](programs.md) to check that these parts agree. A written acceptance case becomes evidence only when an implementation runs it and records the result.

## Outstanding decisions

These gaps still need concrete contracts.

| Area | Details still needed | Authoritative page |
| --- | --- | --- |
| Test runner | Discovery, test identity, duplicate names, isolation, authority inputs, expected faults, and build inclusion | [Semantic tests](semantic-tests.md#test-runner) |
| Build distribution | External adapter/dependency locks and supported debugger distribution | [Reproducibility](../builds/reproducibility.md) |
| Native adapter ABI | Generated Go declarations, receiver construction, disposer types, and compatibility validation | [Adapter manifests](../../modules-and-capabilities/adapters/manifests.md) |
| Capability analysis | Classification of adapter interfaces, pure contracts, wrappers, and indirect authority | [Authority](../../modules-and-capabilities/capabilities/authority.md) |
| Queue extensions | Fairness and additional channel patterns beyond the bounded FIFO contract | [Queues](../../standard-library/data-and-io/queues.md) |
| Pool extensions | Native resource factories and additional lease contracts | [Synchronized values and pools](../../standard-library/data-and-io/synchronized-state.md) |
| Builder extensions | Additional bulk mutation operations beyond sealed snapshot construction | [Builders](../../standard-library/data-and-io/builders.md) |
| HTTP and subprocess extensions | Streaming, sessions, HTTP clients, and platform descendant supervision | [HTTP hosts](../../standard-library/hosts/http.md), [streams](../../standard-library/data-and-io/streams.md) |
| Source tools | Rich diagnostic spans, transactional structural edits, and failed-write recovery | [Source tools](../../developer-tooling/source/_index.md) |
| Diagrams and debugging | Stable node identity, diff/trace formats, stepping behavior, value rendering, and supported debugger versions | [Developer tooling](../../developer-tooling/_index.md) |

For each gap, add exact signatures or data fields, success and failure behavior, an accepted example, and a boundary or rejected example to its concept page. Then add observable conformance expectations. Other guides should link to the rule rather than repeat it.

## Unsupported features

Actors, detached tasks, task adoption, racing combinators, inheritance, macros, operator overloading, implicit conversions, and user-defined metaprogramming have no supported forms. More specific syntax exclusions appear on the relevant concept pages.

Forced task termination is unsupported. Uncooperative work can delay joining indefinitely; [host escalation](../../concurrency/runtime.md#host-escalation) is an incomplete shutdown, not successful cleanup. See [cancellation](../../concurrency/cancellation.md#propagation-and-checkpoints) and [background shutdown](../../standard-library/tasks/background.md).
