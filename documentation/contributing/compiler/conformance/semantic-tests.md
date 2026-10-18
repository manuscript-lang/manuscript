+++
title = "Semantic conformance tests"
weight = 104
+++

# Semantic conformance tests

A conformance test checks a rule by observing a program. Concurrency tests use controlled transitions for specific races and stress tests for real scheduling.

Core-language fixtures in `tests/e2e/testdata/accept/` (`cl-*.ms`) hold independent accepted modules and rejected variants for grammar, operators, inference, contracts, and control flow; their parse, resolution, and type outcomes are authoritative.

Tests use `test "name":` blocks and ordinary `if`/`return` guards. Import `panic` from `@std/faults.ms` and return `panic(message: ...)` on failure; a bare `return` passes a `Unit` test. Control fake I/O, virtual clocks, and barriers around runtime transitions, since goroutine scheduling is nondeterministic.

```manuscript
import panic from "@std/faults.ms"

test "checked decrement":
    let value = 3
    if not (value - 1 > 0):
        return panic(message: "check failed")
```

`ms test` runs each `test` body as a zero-parameter `Unit` function; see [commands](../../../developer-tooling/implementation.md) and `ms help test`.

## Required coverage

- Runtime: source-order preparation, exact heterogeneous results, domain errors, snapshot captures, universal sharing, synchronized sections, `with` registration and cleanup, closed-resource aliases, admission/completion/close races, cleanup faults, fixed deadline parents.
- TaskGroup: empty groups, typed handles, source-order submission, cached results, repeated joins, rejection after join/close, and cancellation and fault paths that join all started work. Parent cancellation beats Result delivery, fault beats timeout, zero timeout runs no callback, and tasks cannot join or close their ancestors. Work-lifetime shutdown works without lexical `with`.
- Inference: `Task[T]` through annotations, fields, collections, and start methods. Direct `try` in Unit tests is rejected, and CPU loops unwind at back-edges after cancellation.
- [Destructuring](../../../core-language/types/destructuring.md): array and record patterns, shorthand, renaming, nesting, `let` and `var`, single initializer evaluation. Reject parenthesized positional bindings, unknown fields, and duplicate names; dynamic length mismatches fault.
- Modules: relative, alias, and `@std` imports; the reserved `@std` alias; standard identity independent of install path; missing imports and name collisions; canonical identity and symlink containment; visibility; cycles; aliases at whole-segment boundaries; cache invalidation on configuration change. See [project configuration](../../../developer-tooling/builds/project-configuration.md); external Manuscript dependency projects are unsupported.
- List arguments: empty, single, and multi-element lists, existing lists, function-value calls, labeled and unlabeled calls, generic inference, contextual empty lists. Reject unknown labels, duplicates, missing or excess arguments, and incompatible types; accept function and contract-view elements. Verify left-to-right evaluation, including closure creation and `with` initialization.

See [completion and acquisition](../../concurrent-runtime.md#completion-and-resource-acquisition).
