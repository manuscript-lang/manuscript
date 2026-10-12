+++
title = "Type checking and source contracts"
weight = 89
+++

# Type checking and source contracts

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The type checker decides whether source operations satisfy Manuscript's rules before the compiler generates Go. The fact that a value can be represented in Go does not make every use of it legal in Manuscript.

## Required checks

Accept source according to the [normative grammar](../../core-language/basics/grammar.md); then resolve names and check the [compatibility rules](../../core-language/types/compatibility.md). Each rejected program must identify the violated source rule. Backend assignability and Go compiler acceptance are not substitutes for those checks.

| Source rule | Checker responsibility |
| --- | --- |
| Explicit function signatures | Check parameter and result types against calls and returns |
| Names and scopes | Collect module signatures, reject duplicate names, resolve locals in declaration order, and check assignments against fixed mutable binding types |
| Operators | Use the closed precedence and operand table; enforce Bool conditions and short-circuit evaluation without implicit numeric conversion |
| Function values | Preserve parameter labels/order and exact types; require explicit specialization of generic function values and explicit anonymous signatures |
| Return completeness | Allow Unit fallthrough/bare returns; reject reachable non-Unit fallthrough; track Never and function-local loop/return boundaries |
| Argument labels | Resolve an omitted label for a single-parameter function; require labels for multi-parameter functions and constructors; reject unknown labels, duplicate arguments, and missing required arguments, including function-value calls |
| List literals | Require the canonical standard List import; check homogeneous element types and use annotations or the expected parameter type for empty lists |
| Parallel API packs | Check zero-argument functions in literal `tasks: [...]` packs and preserve each position's exact return type; see [parallel operations](../../concurrency/parallel.md) |
| Destructuring bindings | Check positional arity, record fields, renaming, nesting, and duplicate bindings; infer each local's type independently; see [destructuring bindings](../../core-language/basics/destructuring.md) |
| Nominal records and tagged alternatives | Preserve type identity and check declared fields and cases |
| Expected types | Propagate annotations/substituted constructor context through literals, fields, and parentheses; reject incomplete types and avoid result-context inference for generic calls |
| Exhaustive match | Check the scrutinee alternative, positional payload arity/bindings, exact qualified cases, missing alternatives, duplicate arms, and final nonredundant wildcard |
| Generic bounds | Check arity, invariant arguments, argument-only inference, every nested application's bounds, and generic bodies under their declared assumptions |
| Recursive types and specialization | Reject inline storage cycles and expanding generic type/function specialization, including mutual calls and specialized function values; permit regular recursion guarded by collection storage |
| Equality and hashing | Derive only the specified properties; reject Float/collection keys and data containing ineligible components |
| Explicit implementations | Match substituted operation names/labels/order/types exactly, check generic bodies and receiver-determined parameters, reject overlap ignoring bounds, enforce module-local extension visibility, and require explicit contract views |
| Standard bindings | Resolve the minimal intrinsic prelude and explicit standard imports by canonical identity; check ordinary function signatures and exact contract views. Passing values requires no sharing bound; queue synchronization is the caller's responsibility |
| Public signatures | Reject internal nominal types leaking through exported fields, signatures, bounds, or operation surfaces |
| Iteration | Admit List/Set/Map only, bind fixed iteration names for elements/MapEntry references, evaluate iterable once, and reject loop control outside the current function's loops |
| Result propagation | Recognize the canonical standard Result identity; require the same exact error type at a try expression in the current function; do not infer missing operand type arguments backward |
| String literals | Validate escape/scalar syntax, support universal value conversion, and preserve left-to-right evaluation |

These requirements derive from the [core language guide](../../core-language/_index.md), with accepted and rejected modules in [core conformance](../conformance/core-language.md). The rules specify observable inference and compatibility; checker data structures and internal pass organization remain implementation choices. A module-level `test` body is a zero-parameter Unit function for static checking: ordinary local scopes, bare-return/fallthrough rules, and Result propagation restrictions apply. Test discovery and runner execution remain separate tooling contracts.

Type information feeds [typed IR](typed-ir.md), [generated representations](../lowering/value-representations.md), and [structural tools](../../developer-tooling/source/structural-editing.md).

[Previous: Compilation pipeline](pipeline.md) · [Next: Scope and capture checking](scope-checker.md)
