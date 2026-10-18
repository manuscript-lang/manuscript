+++
title = "Type checking and source contracts"
weight = 89
+++

# Type checking and source contracts

The type checker decides whether source obeys Manuscript's rules before Go is generated. Being representable in Go does not make a use legal.

## Required checks

Accept source per the [normative grammar](../../../core-language/basics/grammar.md), then resolve names and check [compatibility](../../../core-language/types/compatibility.md). Each rejection must name the violated source rule; Go acceptance is no substitute.

| Source rule | Checker responsibility |
| --- | --- |
| Explicit function signatures | Check parameters and results against calls and returns |
| Names and scopes | Collect module signatures, reject duplicates, resolve locals in order, fix mutable binding types |
| Operators | Closed precedence and operand table; Bool conditions, short-circuiting, no implicit numeric conversion |
| Function values | Keep labels, order, exact types; require explicit generic specialization and contextual anonymous types |
| Return completeness | Allow Unit fallthrough and bare returns; reject reachable non-Unit fallthrough; track Never and loop/return boundaries |
| Argument labels | Bind labels and positional arguments left to right to unfilled parameters, never by spelling; same rule for constructors, methods, function values; reject unknown labels, duplicates, excess positional, missing required |
| List literals | Canonical prelude List; homogeneous elements; annotations or expected type for empty lists |
| Typed tasks | Infer `Task[T]` from the generic start signature; check joins against `Result[T, ExecutionError]` |
| Destructuring bindings | Check arity, fields, renaming, nesting, duplicates; infer each local; see [destructuring bindings](../../../core-language/types/destructuring.md) |
| Nominal records and tagged alternatives | Preserve identity; check declared fields and cases |
| Expected types | Propagate context through literals, fields, parentheses, generic calls; reject ambiguous or conflicting inference |
| Exhaustive match | Check scrutinee, payload arity and bindings, qualified cases, missing and duplicate arms, final non-redundant wildcard |
| Generic bounds | Check arity, invariant arguments, inference, nested application bounds, and generic bodies under declared assumptions |
| Recursive types and specialization | Permit direct and mutual recursive data; reject expanding specialization of types, functions, and function values |
| Equality and hashing | Derive only specified properties; reject Float or collection keys and ineligible components |
| Explicit implementations | Match substituted names, labels, order, types exactly; check generic bodies; reject overlap ignoring bounds; enforce module-local extension visibility; require explicit contract views |
| Standard bindings | Resolve the intrinsic prelude and `@std` imports by canonical identity; check signatures and contract views. Passing values needs no sharing bound |
| Public signatures | Reject internal nominal types leaking through exports |
| Iteration | List, Set, Map only; fixed iteration names; iterable evaluated once; loop control only inside the current function's loops |
| Result propagation | Recognize the canonical `Result`; `try` needs the same exact error type as the current function; never infer missing operand arguments backward |
| String literals | Validate escapes and scalars, allow universal conversion, keep left-to-right evaluation |

Rules derive from the [core language guide](../../../core-language/_index.md); fixtures are `tests/e2e/testdata/accept/cl-*.ms`. They fix observable inference and compatibility, not checker internals. A module-level `test` body is a zero-parameter Unit function for checking; discovery and running are separate tooling contracts.

Type information feeds [typed IR](typed-ir.md) and [generated representations](../lowering/value-representations.md).
