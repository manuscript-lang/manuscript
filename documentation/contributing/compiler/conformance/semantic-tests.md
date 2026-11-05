+++
title = "Semantic conformance tests"
weight = 104
+++

# Semantic conformance tests

A conformance test checks a rule by observing a program.

Start with a small accepted program or a single rejected use. Place successful core-language examples under `tests/e2e/testdata/accept/` (`cl-*.ms` and related fixtures), and rejection cases under `tests/e2e/testdata/reject/`. The e2e runner executes accepted files with `ms test` and requires rejected files to fail `ms check`. Use a test body when the regression depends on execution; a declaration alone only checks acceptance.

For example, save this as `decrement.ms`. Tests use `test "name":` blocks and assertions from `@std/test/test.ms`. Propagate their `Result` with `try` so a failed assertion fails the test.

<!-- manuscript-example: {"mode":"test","filename":"decrement.ms","stdout":"RUN decrement.ms::checked decrement\nPASS decrement.ms::checked decrement\n1 tests, 0 failed\n"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

test "checked decrement":
    let value = 3
    try expect_equal(value - 1, 2)
```

Run it with the compiler built from your checkout:

```sh
target/release/ms test decrement.ms
```

```text
RUN decrement.ms::checked decrement
PASS decrement.ms::checked decrement
1 tests, 0 failed
```

A test follows `Result[Unit, Error]` return rules; normal completion succeeds. `ms test` runs each selected test in a separate process. See [testing](../../../learn/testing.md) for fixtures, selection and reporting.

## Required coverage

- Runtime: source-order preparation, exact heterogeneous results, domain errors, borrowed and owned captures, moves, deep copies, exclusive mutation, scope-end registration and cleanup, closed-resource aliases, cleanup faults.
- Errors and cancellation: `try` propagates compatible Result errors from tests; cancellation arrives at waits, not CPU-loop back edges. Test cleanup on cancellation and faults separately.
- [Destructuring](../../../core-language/types/destructuring.md): array and record patterns, shorthand, renaming, nesting, `let` and `var`, single initializer evaluation. Reject parenthesized positional bindings, unknown fields, and duplicate names; dynamic length mismatches fault.
- Modules: relative, alias, and `@std` imports; the reserved `@std` alias; standard identity independent of install path; missing imports and name collisions; canonical identity and symlink containment; visibility; cycles; aliases at whole-segment boundaries; cache invalidation on configuration change. See [project configuration](../../../developer-tooling/builds/project-configuration.md); external Manuscript dependency projects are unsupported.
- List arguments: empty, single, and multi-element lists, existing lists, function-value calls, labeled and unlabeled calls, generic inference, contextual empty lists. Reject unknown labels, duplicates, missing or excess arguments, and incompatible types; accept function and contract-view elements. Verify left-to-right evaluation, including closure creation and resource initialization.
