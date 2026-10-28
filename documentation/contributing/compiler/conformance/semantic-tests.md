+++
title = "Semantic conformance tests"
weight = 104
+++

# Semantic conformance tests

A conformance test checks a rule by observing a program.

Core-language fixtures in `tests/e2e/testdata/accept/` (`cl-*.ms`) hold independent accepted modules and rejected variants for grammar, operators, inference, contracts, and control flow; their parse, resolution, and type outcomes are authoritative.

Tests use `test "name":` blocks and ordinary `if`/`return` guards. Import `panic` from `@std/core.ms` and return `panic(message: ...)` on failure; a bare `return` passes a `Unit` test. Control fake I/O and virtual clocks around runtime transitions.

```manuscript
from "@std/core.ms" import panic

test "checked decrement":
    let value = 3
    if not (value - 1 > 0):
        return panic(message: "check failed")
```

`ms test` runs each `test` body as a zero-parameter `Unit` function; see [commands](../../../developer-tooling/implementation.md) and `ms help test`.

## Required coverage

- Runtime: source-order preparation, exact heterogeneous results, domain errors, borrowed and owned captures, moves, deep copies, exclusive mutation, scope-end registration and cleanup, closed-resource aliases, cleanup faults.
- Inference: direct `try` in Unit tests is rejected, and CPU loops unwind at back-edges after cancellation.
- [Destructuring](../../../core-language/types/destructuring.md): array and record patterns, shorthand, renaming, nesting, `let` and `var`, single initializer evaluation. Reject parenthesized positional bindings, unknown fields, and duplicate names; dynamic length mismatches fault.
- Modules: relative, alias, and `@std` imports; the reserved `@std` alias; standard identity independent of install path; missing imports and name collisions; canonical identity and symlink containment; visibility; cycles; aliases at whole-segment boundaries; cache invalidation on configuration change. See [project configuration](../../../developer-tooling/builds/project-configuration.md); external Manuscript dependency projects are unsupported.
- List arguments: empty, single, and multi-element lists, existing lists, function-value calls, labeled and unlabeled calls, generic inference, contextual empty lists. Reject unknown labels, duplicates, missing or excess arguments, and incompatible types; accept function and contract-view elements. Verify left-to-right evaluation, including closure creation and resource initialization.
