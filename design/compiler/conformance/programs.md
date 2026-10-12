+++
title = "Complete-program conformance"
weight = 105
+++

# Complete-program conformance

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A feature can pass an isolated test and still fail when combined with other features. These complete-program checks combine cleanup, concurrency, external I/O, and tooling to catch those interactions.

Validate these complete programs as their APIs become concrete:

| Program | Required evidence |
| --- | --- |
| CLI argument output and bounded file reads | exact Process entry, explicit authority, specified stream signatures, cleanup, and exit behavior |
| CLI draining subprocess stdout/stderr | concurrent streaming and deterministic resource release |
| Bounded HTTP server with slow clients | admission, backpressure, limits, failure isolation |
| Background worker surviving a submitting helper's completion | fixed service parent, bounded admission, error observation, and joined shutdown |
| Cancellation during resource acquisition | atomic completion and disposal of undelivered resources |
| Nested cleanup with a fault | every remaining cleanup runs exactly once; secondary diagnostics retained |
| Debug session through parallel, Background, and with | source stepping, value rendering, and task inspection |

## Fixture contents

Each fixture includes complete source, `ms.toml`, adapter inputs, arguments and environment, and an expected transcript and exit outcome. Race fixtures also specify controlled barriers, allowed outcomes, and which resources must be released. Debug fixtures specify source stops and the values visible at each stop. A scenario description alone is not executable evidence.

The subprocess, HTTP, and debugger fixtures depend on the [outstanding API and tooling decisions](scope.md#outstanding-decisions).

See [semantic coverage](semantic-tests.md) and [implementation priorities](scope.md).

[Previous: Semantic conformance tests](../conformance/semantic-tests.md) · [Next: Scope and implementation order](../conformance/scope.md)
