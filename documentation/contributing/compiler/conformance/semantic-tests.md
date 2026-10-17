+++
title = "Semantic conformance tests"
weight = 104
+++

# Semantic conformance tests

A conformance test checks a required rule by observing a program. For concurrency, use controlled transitions to exercise specific races and stress tests to exercise real scheduling.

[Core-language fixtures](core-language.md) specify independent accepted modules and rejected variants for the grammar, operators, inference, contracts, and control flow. Their parse/resolution/type outcomes are authoritative for this core pass; the runtime coverage below remains a separate conformance track.

Tests use `test "name":` blocks and ordinary `if`/`return` guards. Import `panic` from `@std/faults.ms` and return `panic(message: ...)` when a check fails; a bare `return` completes a `Unit` test successfully. Control fake I/O, virtual clocks, and barriers around runtime transitions; Go goroutine scheduling remains nondeterministic. Stress and race tests exercise real transitions. Required coverage includes source-order preparation, exact heterogeneous results, domain errors, snapshot captures, universal sharing, synchronized critical sections, `with` registration and cleanup, closed-resource aliases, atomic admission/completion/close races, cleanup faults, and fixed deadline parents.

## Test runner

A source `test` body is checked as a zero-parameter `Unit` function and run by `ms test`; see [commands](../../../developer-tooling/implementation.md) and `ms help test`.

## Tests in source

The TaskGroup API requires empty groups, heterogeneous typed handles, source-order submission, cached results, unchanged domain Results, repeated joins, admission after join/close rejection, and cancellation/fault paths that join all started work. Verify close races with admission and join, parent cancellation takes precedence over Result delivery, fault takes precedence over timeout, zero timeout runs no callback, and group tasks cannot join or close their ancestors. Test automatic work-lifetime shutdown for groups and nested services without lexical with.

Verify ordinary generic inference through Task[T] annotations, fields, collections, and specialized start methods. Direct try in Unit tests is rejected; execution/domain errors require explicit adaptation. CPU loops without explicit checkpoints must unwind at back-edges after cancellation.

[Destructuring conformance](../../../core-language/types/destructuring.md) covers array and record patterns, shorthand, renaming, nesting, `let` and `var`, and single evaluation of the initializer. Reject parenthesized positional bindings, unknown fields, and duplicate local names. Check that dynamic list length mismatches fault rather than introducing missing values or discarding extra elements.

Module conformance covers relative, user-alias, and explicit standard imports, the reserved `@std` alias, standard declaration identity independent of installation path, rejection of missing imports and standard-name collisions, manifest-relative configuration, canonical file identity, project containment after symlink resolution, visibility, and cycle rejection. Check aliases at complete segment boundaries and invalidate cached analysis when relevant configuration changes. [Project configuration](../../../developer-tooling/builds/project-configuration.md) defines the accepted and rejected paths; external Manuscript dependency projects are unsupported.

List-argument conformance covers empty, one-element, and multi-element lists, passing existing lists, multiple list parameters, and calls through function values. Check both labeled and unlabeled single-parameter calls, including generic inference and contextual empty lists. Accept positional, labeled, and mixed multi-parameter calls with bare identifiers binding by position; reject unknown labels, duplicate arguments, missing or excess arguments, incompatible list element types, and incompatible argument types. Accept function and contract-view elements. Use controlled capability calls to verify left-to-right list-element evaluation and source order between arguments, including closure creation and `with` initialization.

```manuscript
import panic from "@std/faults.ms"

test "checked decrement":
    let value = 3
    if not (value - 1 > 0):
        return panic(message: "check failed")
```

This illustrates the test-block syntax and ordinary conditional returns for failed checks. Runtime tests need fake capabilities, virtual clocks, and barriers to arrange meaningful races, rather than assuming a fixed goroutine schedule.

See [completion and acquisition](../../concurrent-runtime.md#completion-and-resource-acquisition).
