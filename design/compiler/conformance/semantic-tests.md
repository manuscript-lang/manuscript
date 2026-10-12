+++
title = "Semantic conformance tests"
weight = 104
+++

# Semantic conformance tests

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A conformance test checks a required rule by observing a program. For concurrency, use controlled transitions to exercise specific races and stress tests to exercise real scheduling.

[Core-language fixtures](core-language.md) specify independent accepted modules and rejected variants for the grammar, operators, inference, contracts, and control flow. Their parse/resolution/type outcomes are authoritative for this core pass; the runtime coverage below remains a separate conformance track.

Tests use `test "name":` blocks and ordinary `if`/`return` guards. Import `panic` from `@std/faults.ms` and return `panic(message: ...)` when a check fails; a bare `return` completes a `Unit` test successfully. Control fake I/O, virtual clocks, and barriers around runtime transitions; Go goroutine scheduling remains nondeterministic. Stress and race tests exercise real transitions. Required coverage includes source-order preparation, exact heterogeneous results, domain errors, snapshot captures, sharing bounds, `with` registration and cleanup, closed-resource aliases, atomic admission/completion/close races, cleanup faults, and fixed deadline parents.

## Test runner

A source `test` body is checked as a zero-parameter `Unit` function. Discovery and execution are still unspecified: the runner needs a command, file selection rules, stable test identities, duplicate-name handling, isolation, authority inputs, and a way to expect a programming fault. It must also define whether test bodies enter ordinary builds. The examples here fix expected behavior without assuming those runner decisions.

## Tests in source

The [parallel API](../../concurrency/parallel.md) requires coverage for empty, one-position, and heterogeneous literal task packs; source-order preparation; result ordering despite reversed completion; unchanged domain results; and cancellation/fault paths that join all started work.

Cover each row of the [joining outcome table](../../concurrency/joining.md#group-lifecycle) with a virtual timer: caller cancellation during a group timeout unwinds the caller, a cleanup fault after a timeout reports `Crashed`, an empty pack with a zero timeout succeeds, and a nonempty pack with a zero timeout reports `TimedOut` without running any body. Verify that a `while` loop with no explicit checkpoint unwinds at its next back-edge after cancellation. Reject non-function task entries and functions requiring arguments.

Verify that `let [resA, resB] = try parallel(tasks: [first, second])` preserves each result's type inside a helper returning `Result[Unit, ExecutionError]`; the Unit test matches that helper's result and checks success. Direct `try parallel(...)` in a Unit test is rejected. Mixed domain/execution errors use `map_error`, as in the complete parallel example.

[Destructuring conformance](../../core-language/basics/destructuring.md) covers array and record patterns, shorthand, renaming, nesting, `let` and `var`, and single evaluation of the initializer. Reject parenthesized positional bindings, fixed-pack arity mismatches, unknown fields, and duplicate local names. Check that dynamic list length mismatches fault rather than introducing missing values or discarding extra elements.

Module conformance covers relative, user-alias, and explicit standard imports, the reserved `@std` alias, standard declaration identity independent of installation path, rejection of missing imports and standard-name collisions, manifest-relative configuration, canonical file identity, project containment after symlink resolution, visibility, and cycle rejection. Check aliases at complete segment boundaries and invalidate cached analysis when relevant configuration changes. [Project configuration](../builds/project-configuration.md) defines the accepted and rejected paths; external Manuscript dependency projects are unsupported.

List-argument conformance covers empty, one-element, and multi-element lists, passing existing lists, multiple list parameters, and calls through function values. Check both labeled and unlabeled single-parameter calls, including generic inference and contextual empty lists. Require labels for multi-parameter functions; reject unknown labels, duplicate arguments, missing arguments, incompatible list element types, and nonshareable list elements. Use controlled capability calls to verify left-to-right list-element evaluation and source order between arguments, including closure creation and `with` initialization.

```manuscript
import panic from "@std/faults.ms"

test "checked decrement":
    let value = 3
    if not (value - 1 > 0):
        return panic(message: "check failed")
```

This illustrates the test-block syntax and ordinary conditional returns for failed checks. Runtime tests need fake capabilities, virtual clocks, and barriers to arrange meaningful races, rather than assuming a fixed goroutine schedule.

For an acquisition race, verify that the adapter closes a newly acquired resource if delivery loses to cancellation, and that `with` registers a delivered resource without a cancellation gap. Never recursively close arbitrary parallel result fields or captures. Test aliases invoked after scope exit, concurrent operation/close races, stale pooled leases, reverse close order, and idempotent shutdown. Background tests cover bounded rejection, closed admission, independent siblings, observed domain errors and faults, bounded reporting state, optional drain, cancellation, and joining. A captured `var` keeps its creation-time value; assignment to an outer captured local is rejected.

See [completion and acquisition](../../concurrency/runtime.md#completion-and-resource-acquisition) and [complete-program evidence](programs.md).

[Previous: Caching and Go package boundaries](../builds/incremental-compilation.md) · [Next: Complete-program conformance](../conformance/programs.md)
