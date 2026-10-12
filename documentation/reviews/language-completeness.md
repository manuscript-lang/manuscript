+++
title = "Language completeness review and decision status"
bookHidden = true
bookSearchExclude = true
weight = 122
+++

> Historical review: sharing-proof, shared-view, and State discussions below describe the former design. The current language shares all values freely and uses [Synchronized](../standard-library/data-and-io/synchronized-state.md#synchronized) for explicit critical sections.

# Language completeness review and decision status

[Design index](../_index.md)

The initial review identified missing grammar, type, boundary, and tooling contracts. The follow-up grammar and type pass has adopted concrete v0.1 rules in the concept guides. The [full-design Claude Code review](claude-design-review.md) subsequently closed the critical scalar-runtime, minimum library API, CLI entry, sharing, and adapter-binding gaps. Current outstanding decisions are collected in [scope](../compiler/conformance/scope.md#outstanding-decisions); historical proposals below do not establish current behavior.

This review covers core language semantics, modules and capabilities, data APIs, compiler conformance, and developer tooling. Ownership and concurrency are being developed separately and are excluded from the decisions here. References to those areas identify dependencies only.

**Status:** The decision table below records adopted rules. The detailed findings are retained as the initial review snapshot; their evidence line numbers and proposals describe that earlier draft and may differ from today's pages. The linked concept guides govern current behavior. Unadopted proposals remain proposals. Ownership and concurrency were excluded from this pass.

## Adopted grammar and type decisions

| Review findings | Accepted rules and canonical pages |
| --- | --- |
| CORE-01, CORE-02 | [Grammar](../core-language/basics/grammar.md) and [operators](../core-language/basics/expressions.md): strict layout, closed syntax, declaration-only modules, statement control flow, named calls, and suite-bodied anonymous functions |
| CORE-04 | [String source forms](../core-language/basics/text-and-bytes.md): escapes, Unicode scalars, interpolation eligibility and evaluation, deterministic scalar formatting |
| CORE-05, CORE-07 | [Compatibility](../core-language/types/compatibility.md) and [generics](../core-language/types/generics.md): exact/invariant identity, bounded constructor context, argument-only function inference, and checked generic bodies |
| CORE-06 | [Equality and hashing](../core-language/types/equality-and-hashing.md): closed eligibility, structural equality, mathematical map/set equality, and no Float/collection hashing |
| CORE-08 | [Recursive data](../core-language/types/records.md#recursive-data): regular recursion through immutable collection storage; reject inline storage cycles and expanding applications |
| CORE-09, M02 implementation rules | [Contracts](../core-language/types/contracts.md): implicit self, exact operation signatures, concrete/generic implementations, overlap rejection independent of bounds, defining-module coherence, explicit contract views, and unambiguous dispatch |
| CORE-10 function compatibility, CORE-11 | [Function values](../core-language/functions/function-values-and-closures.md#function-type-compatibility) and [returns](../core-language/functions/declarations-and-calls.md#unit-and-never): exact labels/order/types, Unit value/fallthrough, Never evaluation, and complete non-Unit returns |
| CORE-12, CORE-13 | [Matching](../core-language/control-flow/pattern-matching.md) and [loops](../core-language/control-flow/loops.md): positional payloads, explicit final wildcard, closed iteration domains, MapEntry, and function-local loop control |
| M01, M02 names and visibility | [Modules](../modules-and-capabilities/modules/declarations.md): declaration/name collection, collisions, public type closure, and explicit exclusions for renaming/re-exports |
| TOOL-02 core coverage | [Conformance fixtures](../compiler/conformance/core-language.md) and [checker requirements](../compiler/frontend/type-checker.md): accepted modules, isolated rejection variants, and observable rule checks |

The user selected container-guarded recursive data and explicit concrete-to-contract conversion. The current interface design admits generic implementation blocks and ordinary contract views. Every value may be shared; equality and hashing remain separate derived properties. Existing resource, capture, and concurrent execution policies remain in their separate guides. CORE-03 is now closed as a core design rule: [numeric outcomes](../core-language/basics/numbers-and-booleans.md#runtime-numeric-outcomes) and [conversion APIs](../standard-library/data-and-io/operations.md) define the remaining behavior. Source test bodies have a static Unit contract; test discovery and execution remain tooling work.

## What is already settled

Preserve the existing decisions when closing gaps:

- Functions with exactly one parameter may omit the argument label. Multi-parameter functions and constructors require labels. Unknown labels, duplicate arguments, and missing required arguments are rejected. Arguments evaluate in written order, independently of parameter declaration order.
- Numeric conversions are explicit. Integer literals infer `Int`, fractional literals infer `Float`, and `d` selects `Decimal`.
- Records are nominal and immutable. Alternatives are tagged. Matching must cover alternatives without fallthrough.
- Lists are homogeneous and immutable. Empty list literals can receive their type from an annotation or an expected parameter type. Map and set traversal follows insertion order.
- `Result` represents expected failure. `try` forwards errors without introducing an implicit error union or conversion. `Optional` represents absence.
- A `.ms` file is a module. Relative and alias imports have defined resolution and canonical identity rules; wildcard imports and module cycles are rejected.
- Positional and record binding patterns already define exact list length, record subsets, renaming, nesting, duplicate checks, and single evaluation of the initializer.
- Source remains authoritative. Diagrams and explanations are derived views.

These are existing rules, not missing features. Their remaining work is to fit them into a complete grammar and executable conformance suite.

## Order for closing the gaps

| Order | Decisions to finish | Completion evidence |
| --- | --- | --- |
| 1 | Lexical grammar, indentation, expressions, operators, and accepted declarations | One grammar and positive and negative parse fixtures for every production |
| 2 | Generic definitions, local inference, function compatibility, returns, equality, and operation implementations | Every example has a unique type and operation resolution; nearby invalid examples have an explicit rejection rule |
| 3 | Scalar edge cases and the minimum data API | Exact numeric outcomes and callable signatures for conversions, text, collections, and iteration |
| 4 | Public type visibility, standard names, entry invocation, and contract effects | A small complete multi-module application with explicit host inputs; tests for private type leakage and indirect effects |
| 5 | Adapter conversion and dependency identity | A concrete adapter fixture, reproducible project fixture, and rejection tests for incompatible metadata |
| 6 | Test discovery, diagnostics, formatting, structural edits, and debug metadata | A defined test runner contract, formatting snapshots, guarded multi-file edits, and source metadata fixtures |

The first four groups affect which programs are legal or what they do. Tooling protocols and serialized formats can follow, but need to become concrete before independent tools rely on them. Parser libraries, internal AST layouts, checker data structures, and IR instruction sets remain implementation choices.

## Rules for accepting a design decision

Close each gap with a rule in its authoritative concept page, an accepted example, a rejected or boundary example, and an observable test expectation. Mark excluded syntax as rejected in v0.1 instead of leaving it merely unspecified. If a decision changes an existing rule, update the linked compiler, conformance, and library descriptions together.

Keep the public surface small. An omitted feature needs an explicit exclusion; an included feature needs enough rules to implement without guessing. A heading and a plausible example are insufficient for generics, dynamic contracts, numeric conversion, or application entry.

## Detailed findings

The 32 findings below include source references, concrete design probes, proposed decisions, and acceptance checks. Some findings share a dependency: generic dispatch needs contract coherence, host invocation needs standard names, and test discovery needs a build profile. Their proposals must be reconciled before adoption.

Read [core language](language-completeness.md#core-language), [modules and application boundaries](language-completeness.md#modules-capabilities-and-application-boundaries), or [conformance and tooling](language-completeness.md#conformance-and-developer-tooling).

Module priorities use P1 for decisions needed by a complete application and P2 for later API or tooling milestones. These identify design dependencies, rather than validated implementation bugs.

## Core language

### CORE 01 A normative grammar and lexical layout contract are missing

**Reference:** CORE-01. **Priority:** implementation blocker.

**Evidence.** [core-language/basics/syntax.md lines 5,21-34](../core-language/basics/syntax.md) states `.ms` modules, indentation, four-space formatting, no semicolons, parenthesized continuation, comments, and named calls. [compiler/frontend/pipeline.md lines 13](../compiler/frontend/pipeline.md) deliberately leaves the parser library/AST open; that implementation freedom is fine, but no grammar exists elsewhere in the repository to specify accepted source.

**Example.** Are tabs legal? Is a two-space indentation block legal before formatting? Can a list span lines without parentheses? Does `let café = 1` name a valid identifier? Is `type Empty:` followed by a blank line legal? Can a source module execute `let x = fetch()` at top level?

**Why it matters.** Different compliant parsers can accept different programs. Four-space formatter output does not define input indentation. Examples of top-level bindings in tutorial snippets do not establish module initialization semantics.

**Proposed decision.** Add one normative EBNF plus token rules: UTF-8 source; initially ASCII identifiers; complete reserved-word list; spaces-only indentation with exact four-space increments; blank/comment-only lines do not affect blocks; newline suppression inside `()`, `[]`, and `{}`; commas/trailing commas; `#` comments outside strings; no semicolons or explicit line-escape continuation. List legal module items explicitly. For a small first compiler, allow imports, types, impls, functions, and tests at module scope; defer effectful module initializers and reject executable top-level statements. Decide whether module `let` is excluded or restricted to defined compile-time constants. State that parser-library and AST choices remain implementation details.

**Acceptance cases.** A small valid/invalid corpus covering tabs, unexpected indent/dedent, multiline delimiters, empty bodies, comments, trailing commas, reserved names, and module-level statements.

### CORE 02 Operators and expression classification lack a contract

**Reference:** CORE-02. **Priority:** implementation blocker.

**Evidence.** Arithmetic and comparison appear in [core-language/basics/numbers-and-booleans.md lines 30-32](../core-language/basics/numbers-and-booleans.md), [core-language/control-flow/conditionals.md lines 23](../core-language/control-flow/conditionals.md), and [core-language/errors/results.md lines 19](../core-language/errors/results.md); lowering must preserve short circuit ([compiler/lowering/evaluation-order.md lines 7](../compiler/lowering/evaluation-order.md)). There is no operator inventory, precedence/associativity table, operand typing table, or rule for statement versus expression forms.

**Example.** `not a and b or c`, `1 + 2 * 3`, `try read() + 1`, `a < b < c`, and `let x = if active: ...` cannot be resolved uniformly from the draft. Short circuit is already required, but the words/operators to which it applies are not enumerated.

**Proposed decision.** Freeze only documented/basic operators: postfix field/call, prefix `try` and unary sign, multiplication/division/remainder, addition/subtraction, comparison, equality, `not`, `and`, `or`; publish the exact precedence order. Make arithmetic left-associative, comparisons/equality non-chainable, `and`/`or` left-to-right short circuit with Bool operands/results, `not` Bool-only. Make assignment a statement and `if`, `match`, and loops statement-only in v0.1. Explicitly reject unlisted bitwise, ternary, range, compound-assignment, and overloaded operators. Define where `try` binds relative to unary and binary expressions rather than silently importing another language's rules.

**Acceptance cases.** Parsed-tree fixtures for precedence, side-effect probes for short circuit, and negative cases for chained comparisons and assignment in expressions.

### CORE 03 Numeric representation does not yet determine numeric behavior

**Reference:** CORE-03. **Priority:** semantic portability blocker.

**Evidence.** [core-language/basics/numbers-and-booleans.md lines 14-25](../core-language/basics/numbers-and-booleans.md) fixes representations, decimal precision/rounding, explicit conversions, and faults for overflow/invalid operations. [compiler/lowering/value-representations.md lines 11-12,27](../compiler/lowering/value-representations.md) promises checked Int and a specified decimal implementation. Conversion functions, operator results, exponent limits, and exceptional Float values are not specified.

**Example.** What is `-7 / 3`? What is `-7 % 3`? Is `-9223372036854775808` a legal Int literal despite its positive magnitude being unrepresentable? Does `1.0 / 0.0` fault or yield infinity? Is `0.0 / 0.0` NaN? Does `1e400` exist? What happens when converting `2.9` to Int?

**Proposed decision.** Define supported literal grammar and range checks, including unary-negative Int minimum. Int `/` returns Int truncated toward zero; remainder satisfies `a = (a / b) * b + a % b`; zero divisors and min/-1 overflow fault. Publish explicit conversion signatures and classify checked/expected-failure conversion behavior; do not rely on Go casts. Choose whether Float admits NaN/infinity: preserving IEEE Float behavior is a reasonable choice, but then qualify the blanket sentence about overflow/invalid-operation faults so it does not contradict that choice. Define Float rounding and conversion boundaries. Pin Decimal to an actual finite decimal format, exponent range, subnormal/underflow behavior, zero division, and rounding points; "34 digits" alone is not decimal128. Decide literal errors versus runtime faults separately. Duration/Instant arithmetic can remain a standard-library dependency rather than expand this core review.

**Acceptance cases.** Int min/max, divide/remainder signs, Float signed zero/NaN/infinity policy, Decimal halfway rounding/exponent boundaries, and checked conversion extremes.

### CORE 04 String escaping interpolation eligibility and value identity are missing

**Reference:** CORE-04. **Priority:** implementation blocker.

**Evidence.** [core-language/basics/text-and-bytes.md lines 5,9-18](../core-language/basics/text-and-bytes.md) guarantees valid immutable UTF-8, shows interpolation, and says it formats values. It does not say how to escape quotes, backslashes/braces, encode Unicode, nest interpolation, or choose a formatter. Adapter UTF-8 validation does not define source literals.

**Example.** How does a program spell literal `{name}` or a newline? Is `"{customer}"` valid for a nominal record, function, or capability? Are `"é"` and `"e\u{301}"` equal? Is Float interpolation locale-dependent?

**Proposed decision.** Specify double-quoted single-line strings, a small escape set, Unicode scalar escapes rejecting surrogates/out-of-range values, and an explicit literal-brace escape. Define interpolation parsing with balanced expression delimiters and left-to-right evaluation. Initially permit only a fixed set of built-in formattable scalar types; require an explicit formatting operation for custom records. State locale-independent canonical formatting and exact UTF-8/scalar equality without Unicode normalization. Defer multiline/raw strings and custom interpolation protocols. Bytes literal/construction syntax should be either specified or explicitly a library API.

**Acceptance cases.** Literal braces/quotes, nested calls inside interpolation, invalid escapes/scalars, Unicode normalization distinction, and rejection of unsupported interpolated values.

### CORE 05 Contextual inference for alternative constructors is incomplete

**Reference:** CORE-05. **Priority:** type-checker blocker.

**Evidence.** [core-language/types/optionals.md lines 5-9](../core-language/types/optionals.md) shows annotated `some`/`none`; [core-language/errors/results.md lines 7,18-22](../core-language/errors/results.md) shows `ok`/`error` in an expected Result return. Only local inference and constructor information are described ([core-language/basics/bindings.md lines 17](../core-language/basics/bindings.md)). [core-language/types/alternatives.md lines 20](../core-language/types/alternatives.md) requires qualification for ambiguous names without defining qualified syntax or expected-type disambiguation.

**Example.** `let x = none`, `let y = ok(value: 1)`, `let z = error(cause: InvalidPrice)`, `let values = [none, some(value: "Ada")]`, or two visible types with `case Pending` have multiple possible types. Does an expected type select the case, or is qualification still mandatory?

**Proposed decision.** State a bounded bidirectional rule: expected types flow from binding annotations, parameters, declared fields, and function return types into constructor expressions and list elements. Infer supplied generic payloads but require an annotation when remaining parameters are unconstrained; reject bare `none` and unannotated one-sided Result constructors instead of inventing `Never` parameters. Define `Type.Case(...)` and nullary `Type.Case` as qualification; follow the existing rule by requiring qualification whenever multiple visible case declarations share the name, even if context could choose one. Explain that context checks literal type compatibility and does not enable implicit numeric conversion. Decide whether nested heterogeneous `none`/`some` lists need an annotation; annotation-required is the simpler v0.1 choice.

**Acceptance cases.** Annotated success/absence, rejected unconstrained constructors, qualified duplicate cases, and expected types propagated through record fields and calls.

### CORE 06 Equality Hashable eligibility and generated behavior are undefined

**Reference:** CORE-06. **Priority:** semantic blocker.

**Evidence.** [core-language/types/equality-and-hashing.md lines 7-23](../core-language/types/equality-and-hashing.md) says eligible types get generated value equality/hash and Hashable requires Equal. It never defines "eligible". [core-language/types/collections.md lines 28-34](../core-language/types/collections.md) establishes hash requirements and insertion-order iteration, but not collection equality.

**Example.** Can `Map[Float, String]`, `Set[Customer]`, or `Set[List[Int]]` compile? Do two maps with identical entries but reverse insertion order compare equal? Does a record with a function field support `==`? Are numerically equal Decimals with different scale hash-equivalent?

**Proposed decision.** Publish a closed trait table for primitives and derived recursive rules for records/alternatives/Optional/Result/collections. Functions and authority/resource types do not acquire Equal merely through shareability. Lists compare positionally; maps and sets compare mathematical contents independently of insertion order; nominal type identity must match. Define String/Bytes, Decimal normalization, and Float exceptional-value behavior explicitly, including equal-values-have-equal-hashes. A conservative v0.1 choice is Float Equal with IEEE comparison and no Float Hashable, until the key semantics are designed. Specify whether collection hashing is available; deferring it by rejecting collections as keys is simpler than leaving eligibility implicit. Compiler-defined properties should not be user-implementable through arbitrary impls.

**Acceptance cases.** Nested eligible/ineligible records, map/set order-independent equality, Decimal equal hashes, function-containing records, and the chosen Float-key policy.

### CORE 07 Generics are advertised without declaration instantiation rules

**Reference:** CORE-07. **Priority:** implementation blocker.

**Evidence.** [core-language/types/generics.md lines 7-20](../core-language/types/generics.md) gives applied types and `T: Bound` in parameter lists but no user-defined generic declaration/function example. The frontend must check bounds ([compiler/frontend/type-checker.md lines 19](../compiler/frontend/type-checker.md)).

**Example.** Is `type Box[T]: value: T` legal? Is `fn identity[T](value: T) -> T` legal? How do callers explicitly instantiate it? How do two bounds combine? Can a generic call infer T only from the expected return type? Is `List[Customer]` substitutable for `List[Payments]`?

**Proposed decision.** Specify `type Box[T]: ...`, `fn identity[T](value: T) -> T: ...`, `identity[Int](value: 1)`, and one syntax for multiple bounds. Make generic applications invariant and require exact argument types. Infer function parameters only from supplied argument types, with explicit type arguments required when unconstrained; avoid implicit generic numeric conversion. Require generic bodies to type-check under declared bounds, not merely on each concrete instantiation. Define duplicate/unknown/arity errors and bounded recursive trait derivation. Defer higher-kinded types, default type parameters, associated types, specialization, and polymorphic recursion. Generic contract methods should be explicitly allowed with a dispatch plan or explicitly deferred.

**Acceptance cases.** A generic record/function, constrained calls, unsatisfied bounds, explicit instantiation, conflicting inference, invariance, and unconstrained type parameters.

### CORE 08 Recursive nominal data and declaration order resolution need a decision

**Reference:** CORE-08. **Priority:** implementation blocker.

**Evidence.** Nominal immutable record/alternative types are specified in [core-language/types/records.md lines 5-13](../core-language/types/records.md) and [core-language/types/alternatives.md lines 5-14](../core-language/types/alternatives.md); representation lowering promises generated tags/payloads ([compiler/lowering/value-representations.md lines 16](../compiler/lowering/value-representations.md)). Only intermodule dependency cycles are rejected ([modules-and-capabilities/modules/declarations.md lines 7,40](../modules-and-capabilities/modules/declarations.md)). That says nothing about recursive types/functions within a module.

**Example.** `type Node: next: Optional[Node]` or `type Tree: case Leaf(value: Int); case Branch(children: List[Tree])` cannot lower as unconstrained direct Go-by-value recursion. A forward reference to a type or mutually recursive functions also needs name resolution rules.

**Proposed decision.** Resolve module declaration signatures in a first pass, allowing forward references and ordinary function recursion. Make recursive nominal data an explicit v0.1 choice: the smallest path is to reject recursive type dependency cycles with a useful diagnostic and list them as deferred. If recursive lists/alternatives are needed now, define which edges provide indirection and how immutable recursive values are represented/constructed; do not let Go compiler errors accidentally define the source language.

**Acceptance cases.** Forward references, mutual function recursion, duplicate declarations, direct/mutual type cycles, and any permitted indirection.

### CORE 09 Contract implementation and dispatch syntax are underspecified

**Reference:** CORE-09. **Priority:** implementation blocker.

**Evidence.** [core-language/types/contracts.md lines 10-20](../core-language/types/contracts.md) establishes explicit `impl Contract for DataType`, implicit `self`, and no inheritance/default implementations. [compiler/lowering/value-representations.md lines 18](../compiler/lowering/value-representations.md) promises Go interfaces/wrappers. There is no full impl example, receiver signature, method resolution rule, or concrete-to-contract conversion rule. Contract-typed parameters already appear in [modules-and-capabilities/modules/boundaries.md lines 14-21](../modules-and-capabilities/modules/boundaries.md).

**Example.** Is the body `fn charge(amount: Money) ...` or `fn charge(self: Card, amount: Money) ...`? Can the caller pass Card directly to `payments: Payments`? If Card implements two contracts declaring `charge`, what does `card.charge(...)` mean? What happens with duplicate impls?

**Proposed decision.** Add one complete non-resource impl example. Define self as an implicit receiver binding, excluded from supplied named arguments; exact contract operation names, labels, parameter types, and result types must match. Reject missing/duplicate/extra contract operations. Define whether concrete method calls require a visible uniquely resolvable impl or explicit qualified dispatch. Choose a single contract-value conversion rule (explicit wrapper/conversion is consistent with the language's explicit-boundary aim), and define how runtime dispatch packages the concrete receiver. Define impl coherence and module visibility; module-scoped incoherent copies must not select behavior by import order. Inherent methods, contract-to-contract conversions, and generic contract operations can be deferred explicitly. Ownership of receivers/packaged values remains a dependency for the separate ownership work.

**Acceptance cases.** Exact matching impl, signature/label mismatch, ambiguous method names, concrete-to-contract use, and duplicate impl rejection.

### CORE 10 Function type compatibility and closure capture behavior are incomplete

**Reference:** CORE-10. **Priority:** type-checker blocker.

**Evidence.** [core-language/functions/function-values-and-closures.md lines 7,21](../core-language/functions/function-values-and-closures.md) retains argument names in function types; [core-language/functions/declarations-and-calls.md lines 27](../core-language/functions/declarations-and-calls.md) mandates names on function-value calls. Anonymous functions are demonstrated by [concurrency/parallel.md lines 14-18](../concurrency/parallel.md). No compatibility rule exists for labels/parameter ordering, and ordinary mutable-local closure capture behavior is not described.

**Example.** Can `fn decrement(amount: Int) -> Int` be passed to `transform: fn(value: Int) -> Int`? Are function types with the same labeled parameters in opposite order equal? Does `var n = 0; let f = fn() -> Int: return n; n = 1; f()` return 0 or 1?

**Proposed decision.** Treat labels, declaration order, argument types, and return types as part of function-type identity; require an explicit adapter closure when labels differ. Use invariant compatibility initially instead of implicit variance. Specify anonymous function body grammar and explicit parameter/result annotations. For ordinary immutable captures, define value capture. Ordinary mutable-local capture semantics must also be coordinated with the separate ownership work: the draft does not select snapshot versus shared-cell behavior. Once/borrow compatibility and mutable-capture semantics are dependencies rather than core policy recommendations here.

**Acceptance cases.** Label mismatch and adapter, reordered-label type mismatch, anonymous functions in bindings/calls, and, once the ownership design is settled, chosen mutable-capture behavior.

### CORE 11 Unit Never return completeness and statement scope are not operationally defined

**Reference:** CORE-11. **Priority:** frontend blocker.

**Evidence.** [core-language/types/README.md line 7](../core-language/types/_index.md) and [standard-library/types/catalog.md lines 15-16](../standard-library/types/catalog.md) describe Unit/Never without value or return rules. [core-language/functions/declarations-and-calls.md lines 5,14](../core-language/functions/declarations-and-calls.md) requires explicit signatures and return values. [core-language/errors/faults.md lines 23](../core-language/errors/faults.md) describes panic but not its type. Branch examples always return, leaving fallthrough checking unspecified.

**Example.** How does `fn log(...) -> Unit` return? Is a bare `return` allowed? Can `fn f() -> Int: if cond: return 1` compile? Does `return panic(...)` type-check? Are `if`/`match` branches distinct scopes, so `let` shadowing is permitted? What does `while true` establish for non-returning functions?

**Proposed decision.** Introduce one Unit spelling, e.g. `unit`; permit bare return and implicit fallthrough only for Unit functions. Require every reachable exit of a non-Unit function to return a compatible value. Give panic result type Never and permit Never expressions where any result is expected, while keeping declaration identity distinct. Define a conservative syntactic reachability analysis including exhaustive returning matches and literal-true loops without reachable breaks. Establish branch/match-arm/loop lexical scopes, illegal break/continue outside loops, nearest-loop targeting, and unreachable-code policy. Keep labels, expression-valued branches, and return-value break deferred.

**Acceptance cases.** Missing return rejection, Unit fallthrough, exhaustive returns, Never in return positions, nested scopes, and invalid loop exits.

### CORE 12 Match payload wildcard grammar and invalid arm rules are missing

**Reference:** CORE-12. **Priority:** implementation blocker.

**Evidence.** [core-language/control-flow/pattern-matching.md lines 12-22](../core-language/control-flow/pattern-matching.md) shows single-payload positional case patterns and says wildcards are explicit. [core-language/functions/declarations-and-calls.md lines 31](../core-language/functions/declarations-and-calls.md) correctly distinguishes them from named calls. [core-language/types/alternatives.md lines 20](../core-language/types/alternatives.md) requires qualified ambiguous cases. No wildcard example, multi-field payload, literal patterns, guard syntax, or unreachable-arm policy appears.

**Example.** For `case Point(x: Int, y: Int)`, is the arm `Point(x, y):` or `Point(x: px, y: py):`? How do callers ignore a payload? Is the wildcard `_:`? Can it appear before specific arms? Are duplicate arms errors? Does `match true` require two literal arms?

**Proposed decision.** Keep v0.1 match limited to tagged alternatives. Define declaration-order positional payload bindings, qualified case paths, explicit `_` discarded payloads, and final `_:` wildcard arm. Require exact payload arity. Reject duplicate/unreachable arms, unknown cases, binding-name duplicates, and wildcard-before-case. Explicitly defer guards, literal/range matching, or-patterns, and nested case patterns unless needed now. Nullary cases use bare `Case:`. State that binding destructuring and match patterns are separate grammars.

**Acceptance cases.** Zero/multiple payloads, ignored payloads, qualified duplicates, wildcard placement, missing cases, and rejected guard/literal forms.

### CORE 13 Iteration domain and map element shape are missing

**Reference:** CORE-13. **Priority:** type-checker blocker.

**Evidence.** [core-language/control-flow/loops.md lines 5-18](../core-language/control-flow/loops.md) demonstrates List iteration. [core-language/types/collections.md lines 34](../core-language/types/collections.md) states map/set insertion-order iteration without defining the type a loop variable receives. No Iterable contract, map-entry type, destructuring loop syntax, or iteration-expression evaluation rule is provided.

**Example.** In `for entry in orders_by_id:`, is entry K, V, a positional pair, or a record? Can `for {key, value} in map:` use the binding-pattern grammar? Is a capability exposing `next()` iterable? Does the iterable expression run once?

**Proposed decision.** Define one-time iterable expression evaluation and per-iteration lexical binding. State a closed v0.1 iterable set: List/Set bind T, Map binds a named immutable `MapEntry[K,V]` record with key/value fields, preserving documented insertion order. If adding that standard type is premature, explicitly restrict for to List and defer map/set traversal rather than imply an unspecified protocol. Defer user-defined Iterable, integer ranges, and pattern loop binders; examples can read `entry.key`/`entry.value`.

**Acceptance cases.** Single evaluation, empty traversal, bound element types, map/set order, and rejected unrecognized iterable types.

## Modules capabilities and application boundaries

### M01 Exported type visibility is not closed over the public API

**Reference:** M01. **Priority:** P1.

**Evidence:** [modules-and-capabilities/modules/declarations.md lines 7](../modules-and-capabilities/modules/declarations.md) says declarations are internal unless exported, and imports select individual exported symbols. `:24` says an internal declaration stays within its boundary. [modules-and-capabilities/modules/boundaries.md lines 7](../modules-and-capabilities/modules/boundaries.md) defines boundaries in terms of exported types/operations, errors, and accepted capabilities. [core-language/types/records.md lines 17](../core-language/types/records.md) permits named-field construction; `:21` permits field reads. No rule establishes field visibility, constructor visibility, or whether exported signatures can mention internal types.

**Minimal case:** module A declares internal `type Token: value: String`, then `export fn issue() -> Token`. B imports only `issue`, calls it, and infers `Token`. Can B read `.value`, construct another token, pass the token onward, or write an exported function whose result is the inferred private type? Equally problematic: an exported record has a field of internal type, or an exported operation contract returns an internal domain error.

**Why this blocks tightening:** “internal symbols cannot be imported” does not prevent their types leaking through inference. If leakage is allowed, privacy is effectively naming privacy; if forbidden, public-signature validation is missing. Constructors and fields determine whether module boundaries can enforce domain invariants.

**Recommended v0.1 decision:** reject an exported signature/record/alternative/contract whose transitive public type surface references an internal nominal declaration. Treat all fields, constructors, and alternative cases of an exported data type as public; explicitly defer opaque types and selective member visibility. A public declaration may refer to another module's exported type without automatically re-exporting its name. Add negative tests for private return types and nested private fields, and a positive test for imported public nominal types in exported signatures.

### M02 Import naming declaration collisions re exports and implementation discovery have no module rules

**Reference:** M02. **Priority:** P1.

**Evidence:** [modules-and-capabilities/modules/declarations.md lines 7](../modules-and-capabilities/modules/declarations.md) and `:21` describe one imported symbol. [core-language/types/contracts.md lines 18](../core-language/types/contracts.md) establishes explicit `impl Contract for DataType`, but not its visibility or discovery. [compiler/frontend/pipeline.md lines 11](../compiler/frontend/pipeline.md) says imports discover the module graph. There is no import renaming/qualification form or re-export syntax, no import/local-name collision rule, and no rule connecting implementation availability to imports.

**Minimal cases:** A imports `CustomerId` from two domain modules; an imported `CustomerId` collides with a locally declared type; C defines an implementation for A's contract and B's type, but the application imports A and B without C. Is the implementation usable? Can two separately reachable modules provide the same implementation? Does importing the type bring its implementation automatically?

**Implication:** a name resolver cannot be implemented consistently, and contract behavior might change when an unrelated module becomes reachable. One generated Go application package makes source privacy especially dependent on frontend rules.

**Recommended v0.1 decision:** a single module namespace; duplicate top-level names and import/local collisions are errors. Either explicitly defer import renaming and re-exports (requiring distinct exported names), or add one documented `as` syntax now. Permit implementations only in the defining module of the concrete data type, require exactly one implementation per contract/type pair, and make it available whenever that type's defining module is loaded. Defer orphan implementations and conditional implementations. Coordinate the contract details with the core-type review; the module-specific issue is discovery/coherence, not method syntax.

### M03 Module ownership and root containment are missing despite detailed path resolution

**Reference:** M03. **Priority:** P1.

**Evidence:** [compiler/builds/project-configuration.md lines 20](../compiler/builds/project-configuration.md) defines a source directory; `:37` admits `../`; `:41` gives aliases manifest-relative targets; `:49` canonicalizes symlinks and promises project-relative metadata; `:51` says aliases belong to the project whose source contains the import, and dependencies use their own manifests. No containment rule, owning-project selection algorithm, overlapping-source-root rule, or hard-link/case-sensitivity policy exists.

**Minimal cases:** `src/main.ms` imports `../../shared/util.ms` outside the project; an alias points at a sibling project; a symlink in `src` points into a dependency whose source imports `@domain`; two manifests both claim the same canonical file. Which project's aliases resolve the next import? If a file has no owning project, what relative path identifies it in stable metadata?

**Implication:** relative/symlink identity is specified within a build, but package ownership is not. Alias isolation and checkout-independent identity become ambiguous at exactly the dependency boundary. This is an unresolved dependency between existing promises, not evidence that symlink identity itself is undefined.

**Recommended v0.1 decision:** limit entry files, imports, and alias targets to the canonical source tree of their owning project. Introduce cross-project loading only through an explicit dependency identity; reject path/symlink escapes in the initial local-only compiler. Define ownership from the resolved package root, reject overlapping ownership, and use `(package identity, root-relative canonical path)` as portable nominal/module identity. Within a local build, realpath deduplicates alternate spellings. Explicitly say whether platform-native filename case rules apply; do not silently equate different files by lowercasing names.

### M04 The standard library has no name resolution or packaging contract

**Reference:** M04. **Priority:** P1.

**Evidence:** [standard-library/types/README.md lines 5](../standard-library/types/_index.md) says the catalog includes built-in and library values. [standard-library/types/catalog.md lines 9-24](../standard-library/types/catalog.md) presents them without distinguishing categories. [compiler/builds/project-configuration.md lines 43](../compiler/builds/project-configuration.md) rejects bare logical module names and absolute imports; `:51` leaves dependency/package imports unspecified. Library operations are referenced throughout the design without an import/prelude policy. [core-language/basics/text-and-bytes.md lines 18](../core-language/basics/text-and-bytes.md) promises byte/scalar/grapheme library operations, but gives no names or import path.

**Minimal cases:** can a module name `File`, `Duration`, or `List` without an import? Where is a text-grapheme operation imported from? Is a runtime library identified by a compiler-injected alias, a package import, or a source file bundled into the project? What happens when a local type has the same name as a built-in?

**Implication:** snippets look runnable but lack a mechanism to resolve library declarations. A built-in catalog is not yet a language prelude or dependency design.

**Recommended v0.1 decision:** enumerate the implicit type/operation prelude and say which names are reserved versus shadowable. Separate intrinsic language types (`Int`, `String`, collection/alternative families, etc.) from named runtime/library interfaces. Choose one explicit library import mechanism compatible with path imports—e.g. a compiler-reserved standard-library directory alias—and document its version identity. A reserved standard alias is a proposed exception to today's user-configured alias rules and must be stated as such. Defer third-party package resolution if necessary, but provide a complete path from a fresh `ms.toml` to a library call.

### M05 Capability authority is described conceptually but lacks a source level classification provisioning contract

**Reference:** M05. **Priority:** P1.

**Evidence:** [modules-and-capabilities/capabilities/authority.md lines 7](../modules-and-capabilities/capabilities/authority.md) says external authority is explicit and there is no ambient application access. [core-language/types/contracts.md lines 10-12](../core-language/types/contracts.md) declares an ordinary operation contract and `:24` says capabilities are explicit inputs. [core-language/types/equality-and-hashing.md lines 7](../core-language/types/equality-and-hashing.md) assigns capabilities distinct equality behavior. [modules-and-capabilities/modules/boundaries.md lines 7](../modules-and-capabilities/modules/boundaries.md) expects compiler-visible accepted capabilities. The adapter trust limit is correctly explicit in [modules-and-capabilities/adapters/value-conversion.md lines 7,13](../modules-and-capabilities/adapters/value-conversion.md).

**Minimal cases:** a pure `Formatter` and an externally writing `Payments` both use `type ...: fn ...`; what makes one a capability? Is any contract value a capability, only one backed by a manifest, or a value with an effectful reachable implementation? A closure capturing a `Payments` value has no capability parameter but still carries authority. A record containing the same value can hide it one level deeper.

**Implication:** explicit arguments do not by themselves produce a complete authority diagram or distinguish pure abstractions from authority. The trust boundary is already defined; the missing rule is source/compiler classification and permitted authority transport, not whether adapters are sandboxed.

**Recommended v0.1 decision:** define capability status as manifest-declared authority-bearing contract/type metadata rather than inventing a new syntax without need. Explicitly permit authority to flow through ordinary values, records, and closures; define “accepted authority” over the reachable parameter/capture/type graph, not only direct parameters. Specify host injection as the only root for real external implementations, and ordinary Manuscript implementations as controlled substitutions. If analysis only reports direct capability parameters, document that limitation and stop calling that view complete authority. Ensure equality eligibility remains consistent with the chosen capability classification.

### M06 Inferred effects and operation effect bounds are not implementable from the stated syntax

**Reference:** M06. **Priority:** P1.

**Evidence:** [modules-and-capabilities/capabilities/effects.md lines 7](../modules-and-capabilities/capabilities/effects.md) promises transitive inferred effects and says an operation contract bounds declared behavior. [modules-and-capabilities/adapters/manifests.md lines 7](../modules-and-capabilities/adapters/manifests.md) requires effect summaries. The operation-contract syntax at [core-language/types/contracts.md lines 10-12](../core-language/types/contracts.md) has no effect clause, and no taxonomy/schema for declaring those bounds is specified. [developer-tooling/diagrams/views.md lines 15](../developer-tooling/diagrams/views.md) correctly permits unresolved dynamic behavior, whereas architecture diffs claim changed effects from compiler analysis ([developer-tooling/diagrams/architecture-diffs.md lines 7](../developer-tooling/diagrams/architecture-diffs.md)).

**Minimal case:** `fn use(service: Payments) -> Unit` calls `service.charge(...)`; different implementations write a remote service, modify local state, or only return a fake receipt. A higher-order `fn apply(action: fn() -> Unit)` calls an unknown callback. What effect is inferred? What source declaration supplies a bound, and how is an implementation shown to fit it? Recursive call graphs need a fixed point even though cyclic module graphs are forbidden.

**Implication:** unioning direct adapter effects handles only static calls. Treating unresolved targets as effect-free would understate authority; treating all contracts as maximally effectful preserves safety but weakens the promised diagrams and diffs. “Unresolved target” is an analysis result, not a specified effect lattice.

**Recommended v0.1 decision:** define a small effect set (`external-read`, `external-write`, `external-call`, plus `unknown`) and infer executed effects over statically known calls to a fixed point. Track a closure's latent callable effects separately from the authority carried by its captures. Unknown dispatch must contribute `unknown`, never the empty set. Give adapter operations explicit manifest summaries. Initially defer user-authored effect constraints/purity checking; rewrite the unsupported “operation contract bounds declared behavior” promise as a reporting guarantee unless a real annotation/manifest-bound mechanism is designed. If contracts do bound effects, specify declaration syntax, implementation subeffect checks, closure/function-value propagation, and generic/dynamic dispatch now. Add tests showing a fake implementation does not make unknown production dispatch appear pure.

### M07 Adapter manifests need a minimally closed schema compatibility model and binding mechanism

**Reference:** M07. **Priority:** P1 binding; P2 serialization.

**Evidence:** [modules-and-capabilities/adapters/manifests.md lines 7,11](../modules-and-capabilities/adapters/manifests.md) lists required information and compiler validation; `:13` explicitly leaves serialization unspecified. [compiler/lowering/value-representations.md lines 18](../compiler/lowering/value-representations.md) lowers contracts to Go interfaces/wrappers. [compiler/lowering/function-and-task-calls.md lines 7](../compiler/lowering/function-and-task-calls.md) specifies a hidden context parameter for every generated contract method. [compiler/builds/reproducibility.md lines 7](../compiler/builds/reproducibility.md) requires adapters to be pinned.

**Minimal cases:** an adapter claims to implement `Payments.charge`; how does it identify the source contract (name alone collides across modules), locate its Go package/symbol, identify the schema/runtime ABI version, or express exact named parameter labels? Can a separately compiled adapter implement a type containing an application-defined `Receipt` if the generated application package also imports the adapter? A direct dependency on application-generated types can create a Go package import cycle.

**Implication:** “compiler validates the manifest” has no defined validation target. Serialization can be deferred during experiments, but operation identity, conversion identity, schema compatibility, and Go binding cannot be omitted from the adapter boundary. The package-cycle issue is a design risk, not a proven implementation failure because no implementation exists.

**Recommended v0.1 decision:** publish one tiny versioned schema containing module-qualified contract/type identity, operation name, exact named source signature, Go package/symbol, runtime ABI version, conversion IDs, and declared effect set; retain cross-team lifecycle fields without redesigning them here. Unknown required fields/version mismatches fail before invoking Go. Resolve adapters from explicit project registration, not ambient discovery. Choose wrappers/code generation that do not require adapters to import the generated application package—e.g. generated marshaling at the boundary into adapter-owned transport representations. Emit one fully worked source/manifest/Go example to prove the dependency graph is acyclic.

### M08 Foreign value validation lacks failure semantics and a type by type conversion contract

**Reference:** M08. **Priority:** P1.

**Evidence:** [modules-and-capabilities/adapters/value-conversion.md lines 7,11](../modules-and-capabilities/adapters/value-conversion.md) requires UTF-8/tag validation and immutable storage. [compiler/lowering/value-representations.md lines 11-18](../compiler/lowering/value-representations.md) supplies broad representation promises. [core-language/basics/numbers-and-booleans.md lines 25](../core-language/basics/numbers-and-booleans.md) makes invalid numeric operations programming faults. [compiler/lowering/cleanup-and-faults.md lines 7](../compiler/lowering/cleanup-and-faults.md) already defines recoverable adapter panics as `Crashed`; that is established, not a gap. No rule says whether failed return conversion is a domain result, programming fault, rejected adapter build, replacement value, or host failure.

**Minimal cases:** a Go adapter returns malformed UTF-8, nil where a nonoptional record/contract is required, an unknown alternative tag, a `uint64` outside `Int`, or a map with invalid keys/unstable iteration order. The language forbids implicit numeric conversions but Go wrappers still need a conversion rule. A malformed returned `Result` must not be silently translated into some unrelated application error.

**Implication:** valid source values cannot be guaranteed by saying “validate” without an observable failure path. Expected malformed external bytes are different from a trusted adapter falsely claiming to have produced `String`.

**Recommended v0.1 decision:** generated outbound wrappers validate all invariant-bearing foreign results; failed validation is a programming fault with operation/type/path diagnostics, matching the existing recoverable adapter panic treatment. Expected invalid user data must remain `Bytes` or be decoded through an explicitly fallible library operation. Publish an accepted/rejected conversion table covering `Bool`, `Int`, `Float`, `Decimal`, `String`, `Bytes`, records, alternatives, optionals, results, and ordered collections. Reject nil for nonoptional values; use explicit optional tags. Define collection duplicate-key/order behavior and version the Unicode/decimal implementations used by conversions. Buffer alias safety is already specified; do not reopen ownership transfer in this review.

### M09 Entry execution and host facing signatures are absent

**Reference:** M09. **Priority:** P1.

**Evidence:** [compiler/builds/project-configuration.md lines 20,24](../compiler/builds/project-configuration.md) selects an entry file and follows imports. [standard-library/hosts/cli.md lines 9,13](../standard-library/hosts/cli.md) promises arguments/environment/stdio/signals/status, but `:15` leaves registration/process signatures unspecified. [standard-library/hosts/http.md lines 9,13](../standard-library/hosts/http.md) promises limits/isolation but `:15` leaves registration/configuration unspecified. [core-language/basics/syntax.md lines 5](../core-language/basics/syntax.md) says files contain imports and declarations; examples elsewhere show top-level `let` without an initialization-order contract.

**Minimal cases:** a valid entry file has two exported functions and no `main`; a `main` returns `Result[Int, AppError]`; a module contains a top-level call that needs a clock; a handler needs storage. Which function is called, who constructs its arguments, and what maps its return value to an exit code or HTTP response? How are adapter instances injected without ambient authority?

**Implication:** the compiler can discover and check a graph, but cannot yet turn that graph into a specified executable. “Entry file” is a graph root, not an execution contract. The required CLI and HTTP conformance programs cannot be normative until their host APIs exist.

**Recommended v0.1 decision:** finish a minimal CLI bootstrap first: one required entry name/signature, an explicit host-input record and registered capability bundle, and specified success/domain-failure/fault-to-exit-status mapping. Reject executable module-level initialization in v0.1; permit only declarations or explicitly defined constant forms so there is no hidden cross-module startup. Specify minimal HTTP handler request/response types, header/body representation, and domain-error response mapping if HTTP remains required v0.1 conformance; otherwise explicitly defer that host milestone. Signal/disconnect/task-lifetime details belong to the concurrent-work track and are excluded here.

### M10 Build pinning and test discovery are promises without a reproducible invocation contract

**Reference:** M10. **Priority:** P2 build polish; P1 test discovery.

**Evidence:** [compiler/builds/project-configuration.md lines 22](../compiler/builds/project-configuration.md) leaves manifest-selection CLI unspecified and `:24,51` leaves build/dependency schemas and acquisition unspecified. [compiler/builds/reproducibility.md lines 5,7,9](../compiler/builds/reproducibility.md) defines build identity, required pins, and stable output. [compiler/builds/incremental-compilation.md lines 7,15](../compiler/builds/incremental-compilation.md) defines broad cache keys. [compiler/conformance/semantic-tests.md lines 7,19-25](../compiler/conformance/semantic-tests.md) introduces source tests, but entry-import traversal is the only module discovery rule. [developer-tooling/debugging/metadata.md lines 7](../developer-tooling/debugging/metadata.md) requires identity/source hashes that match the executable.

**Minimal cases:** `src/math.ms` has tests but is unreachable from application entry; a lock pins adapter A but A's Go transitive dependency differs; the same source is built with a different Manuscript compiler version or `GOOS`, `GOARCH`, build tag, Unicode data version, or decimal implementation. Must generated text, executable bytes, metadata, and analysis-cache keys all match? Is the lock authoritative or automatically updated?

**Implication:** deterministic generated symbol order is specified, but a repeatable build cannot be reconstructed from today's project schema. Test examples do not define which tests exist in a run. These are build/test surface gaps, not demands to stabilize every internal AST/cache format.

**Recommended v0.1 decision:** publish exact build/check/test invocations against an explicit manifest, with unknown manifest keys/version mismatches rejected. Start with local projects and explicitly registered adapters if package acquisition is deferred. Record compiler version, source hashes, normalized config, Go toolchain, runtime/adapter versions and content checksums, transitive dependency lock, target tuple, and relevant build flags. Require immutable lock use by ordinary build; lock updates are explicit. Define deterministic generated source/metadata as the initial reproducibility promise; avoid promising byte-identical binaries until the toolchain/environment contract supports it. Define test discovery separately (e.g. all source-root test files), with stable test names and a test-root module graph. Do not infer that entry reachability discovers every test.

### M11 Builder and data facing library operations need a usable surface or explicit deferral

**Reference:** M11. **Priority:** P2.

**Evidence:** [standard-library/data-and-io/builders.md lines 15](../standard-library/data-and-io/builders.md) explicitly leaves constructors/mutation unspecified. [core-language/types/collections.md lines 34](../core-language/types/collections.md) promises insertion-order iteration and `:40` explicitly leaves map/set constructors and updates unspecified; [core-language/basics/text-and-bytes.md lines 18](../core-language/basics/text-and-bytes.md) promises library indexing operations. None publishes a minimal API catalog.

**Minimal case:** an application reads text fragments and needs to build one `String`, or accumulates `List[Int]`. Which builder type and constructor exist? Is there `append(value: ...)`, `append(values: ...)`, an index-replacement operation, or only immutable updates? Does a map builder preserve first-insertion order when replacing an existing key? The builder's lifetime contract alone does not answer data behavior.

**Recommended v0.1 decision:** publish one small data API catalog with exact constructor/method signatures, error contracts, indexing units, out-of-range behavior, and collection ordering; include one builder-to-immutable-result example. Specify text/byte/list builders first if required for complete programs, and defer arbitrary builder families. These are data-facing API decisions; ownership and mutation eligibility remain in the separate ownership work. Verify empty construction, Unicode indexing units, duplicate map-key replacement order, and incompatible element type rejection. At minimum mark builder APIs outside the runnable v0.1 subset until names/signatures are chosen.

## Conformance and developer tooling

### TOOL 01 Test blocks have syntax without a test language contract

**Reference:** TOOL-01. **Priority:** blocking.

**Evidence:** [compiler/conformance/semantic-tests.md lines 7](../compiler/conformance/semantic-tests.md) introduces `test "name":` and ordinary conditional returns for failed checks. Explicit programming faults are described at [core-language/errors/faults.md lines 9](../core-language/errors/faults.md). No other design page defines test discovery, placement, result type, isolation, or authority inputs. [core-language/errors/propagation.md lines 7](../core-language/errors/propagation.md) defines `try` using an enclosing function, leaving its meaning inside test blocks open.

**Missing decisions:** Are tests top-level declarations in any module, or test-only grammar? Can tests nest? Are duplicate names legal? Do tests in imported modules run? Are bodies implicitly `Unit`, and can they `return` or use `try`? How does conformance verify an expected programming fault when source `try` cannot catch faults? How are fake capability values provided without adding ambient authority?

**Proposal:** Define module-level zero-parameter test bodies returning `Unit`, included only in a test build. Specify discovery roots independently of the production entry import graph, deterministic identifiers/order, duplicate-name rules, and per-test outcomes. Reject error-propagating `try` in `Unit` tests unless a supported explicit test result type is chosen. Keep expected-fault checks in a runner-owned fixture mechanism rather than introducing source-level fault catches. Fake capabilities remain ordinary explicitly constructed/supplied values through a test support module.

**Acceptance:** One fault fails its test while unrelated tests still run; aggregate success requires every required test to pass. Cover discovery, duplicate names, nested tests, production exclusion, expected faults, and the chosen `try` behavior.

**Alternative deferral:** Label the block example external harness pseudocode rather than accepted Manuscript syntax until the language contract exists.

### TOOL 02 Conformance coverage has no systematic core language oracle

**Reference:** TOOL-02. **Priority:** high.

**Evidence:** [compiler/conformance/semantic-tests.md lines 7](../compiler/conformance/semantic-tests.md) emphasizes runtime/task coverage; `:11-17` details recent parallel, destructuring, modules, and named-list revisions. The checker requires nominal records, alternatives, exhaustive matches, bounds, implementations, and Result propagation ([compiler/frontend/type-checker.md lines 17-21](../compiler/frontend/type-checker.md)). Representations promise checked Int, Decimal, UTF-8, immutability, ordered collections, alternatives, and generated equality/hashing ([compiler/lowering/value-representations.md lines 11-18](../compiler/lowering/value-representations.md)). Those lack detailed corresponding conformance requirements. The scalar example `3 - 1 > 0` at [compiler/conformance/semantic-tests.md lines 20-22](../compiler/conformance/semantic-tests.md) does not establish checked arithmetic.

**Consequence:** An implementation could pass the enumerated scenarios while accepting mismatched nominal types, implicit numeric conversions, or unchecked overflow. This is missing verification, not missing existing rules: checked arithmetic, 34-digit Decimal/half-even rounding, and explicit conversion already exist at [core-language/basics/numbers-and-booleans.md lines 18-25](../core-language/basics/numbers-and-booleans.md).

**Proposal:** Add a registry mapping each normative rule to accepted/rejected fixtures and an observable oracle. Include scalar boundaries/conversions, Bool-only conditions, binding/shadowing rules, UTF-8 and immutable buffer admission, ordered map/set traversal, nominal constructor validation, alternative qualification/payloads/exhaustiveness, explicit implementations/bounds, function-value calls, and Result error compatibility. Numeric edge expectations must follow core-language decisions, not be invented by test authors.

**Acceptance:** Rejection fixtures distinguish parsing, resolution, and typing. Runtime fixtures check values, calls, or fault categories. Generated-Go snapshots verify generation/source-map stability rather than serve as the semantic oracle. Diagnostic prose remains changeable. Mark settled rules without tests “unverified,” and undecided rules “unresolved.”

### TOOL 03 Complete program evidence is a scenario list not reproducible fixtures

**Reference:** TOOL-03. **Priority:** high.

**Evidence:** [compiler/conformance/programs.md lines 9-16](../compiler/conformance/programs.md) names CLI, HTTP, background-worker, resource, cleanup, and debugger programs with broad outcomes. No source programs, harness inputs, or expected transcripts exist. CLI signatures are explicitly unspecified at [standard-library/hosts/cli.md lines 15](../standard-library/hosts/cli.md); HTTP registration/configuration is unspecified at [standard-library/hosts/http.md lines 15](../standard-library/hosts/http.md).

**Proposal:** For each required program provide complete source, manifest, supplied fake/real capability profile, run procedure, and observable checks. Separate deterministic harness checks from real integration checks. A bounded server fixture must name measurable limits and expected responses rather than merely “slow clients.” Compiler completeness requires an executable-entry/host contract; that decision and the manifest/build shape belong to the modules/build review. Pending runtime scenarios should be labeled dependencies on the in-progress runtime design, without re-deciding them here.

**Acceptance:** A fresh checkout can run each fixture without undocumented source declarations or host registration. “Conformance passed” names profile, version, fixture set, and platform, rather than claiming all v0.1 obligations from a partial suite.

### TOOL 04 Guarded structural edits lack transaction and validation semantics

**Reference:** TOOL-04. **Priority:** high.

**Evidence:** [developer-tooling/source/structural-editing.md lines 7](../developer-tooling/source/structural-editing.md) promises replace-function, rename-symbol, and add-match-case with revision guards; `:11` rejects stale renames; `:13` leaves schema open. Neither project-wide guard coverage, multi-file atomicity, nor validation failure is defined.

**Scenario:** A rename touches a definition and two importing files. A reference file changes after analysis while the definition file stays unchanged. A single-file guard can partially rename the program or edit a reference that now resolves differently. Adding an alternative case can invalidate exhaustive matches; adding an unknown match arm is a different invalid transformation.

**Proposal:** Guard the analyzed project snapshot, or every read/touched file plus configuration/dependency identities. Return one atomic proposed patch with preview/diagnostics; stale input produces no writes. Checked refactors validate the proposed program before commit; failures return the proposal and diagnostics without partial writes. An explicit text-edit operation may permit incomplete source. Resolve symbol identities rather than spellings. Decide exported-name behavior separately from local rename.

**Acceptance:** Cross-file rename, stale referenced file, shadowed spelling, illegal new name, unknown match arm, validation failure, all-or-none writes, and comment preservation. Wire transport can remain open; transaction guarantees cannot.

### TOOL 05 Metadata mixes static descriptions with runtime observations

**Reference:** TOOL-05. **Priority:** high for tooling.

**Evidence:** [developer-tooling/debugging/metadata.md lines 7](../developer-tooling/debugging/metadata.md) says every build emits source spans, statement/local/type mappings, task IDs, relationships, and deadlines; `:13` acknowledges both static/runtime facts. [developer-tooling/diagrams/traces.md lines 13](../developer-tooling/diagrams/traces.md) uses build/runtime metadata for overlays; `:11` correctly distinguishes observations from guaranteed order.

**Missing distinction:** Builds emit descriptors for future observations, not actual future execution identities/timing. Two runs of the same binary need distinct run identities. Source spans also lack coordinate conventions: byte/character offsets, Unicode columns, inclusive/exclusive ends, and original/formatted source.

**Proposal:** Separate static debug manifest (schema/build identity, source hashes, source/statement/symbol/type IDs, generated locations) from runtime records (run identity, observation sequence/time, referenced static ID, state/event). Static IDs are deterministic within a build; observed IDs are unique within a run. Reject mismatched executable/manifest pairs and mixed-run overlays. Adopt UTF-8 byte offsets with half-open source ranges and defined line/column projections. State whether original source bytes are embedded or read from disk. Storage serialization can remain open; identity and coordinates cannot.

**Acceptance:** Repeated runs, edited source after build, moved checkout, wrong executable/schema, Unicode source, unknown static IDs. Runtime-state accuracy depends on active runtime work and is outside this review.

### TOOL 06 Debugger acceptance labels do not define observable stepping rendering

**Reference:** TOOL-06. **Priority:** medium.

**Evidence:** [developer-tooling/debugging/source-mapping.md lines 7,13](../developer-tooling/debugging/source-mapping.md) requires Go line directives and unoptimized symbol-rich debug builds. [developer-tooling/debugging/debugger-integration.md lines 7](../developer-tooling/debugging/debugger-integration.md) chooses Delve DAP plus interpretation; `:13` requires stepping, value rendering, and task inspection. [compiler/conformance/programs.md lines 16](../compiler/conformance/programs.md) repeats those labels without expected stops or renderings.

**Scenario:** A source statement lowers to several temporary operations. Native stepping might repeatedly stop in temporaries, enter hidden context machinery, or display inactive alternative payloads. Line mapping alone does not decide source behavior.

**Proposal:** Write a debugger script with expected statement breakpoints, step-over/into/out behavior, tagged-alternative/collection rendering, explicit unavailable-variable representation, and marked/generated-frame filtering. Inspection must not invoke user code or capability operations. Separate required debug-build behavior from best-effort optimized-release inspection. Task inspection is a dependency on runtime design, not re-decided here.

**Acceptance:** The scripted source stops and values match their expected source semantics. Rich watch evaluation and backend details can be deferred. If source debugging is outside the initial milestone, mark it explicitly; [developer-tooling/README.md lines 7](../developer-tooling/_index.md) currently labels the guide v0.1.

### TOOL 07 Canonical formatter diagnostics need minimal compatibility rules

**Reference:** TOOL-07. **Priority:** medium.

**Evidence:** [README.md lines 7](../_index.md) chooses one canonical formatter; [developer-tooling/source/formatting.md lines 7](../developer-tooling/source/formatting.md) makes it authoritative; [core-language/basics/syntax.md lines 21](../core-language/basics/syntax.md) specifies four spaces. Diagnostics require readable structured locations but leave codes/schema unspecified ([developer-tooling/source/diagnostics.md lines 7,13](../developer-tooling/source/diagnostics.md)).

**Proposal:** Require semantic preservation, deterministic output, idempotence, preserved comment content/attachment, defined line endings/final newline, and no-write failure on invalid input. Pin formatting to compiler/language version. Import/declaration sorting must not accidentally invent execution semantics. Choose exact layout through golden fixtures.

Give machine diagnostics a versioned envelope with stable rule code, severity, primary span, optional related spans, and readable message. Share coordinate conventions with debug metadata. Freeze codes/locations rather than prose. Suggested fixes use structural-edit revision guards.

**Acceptance:** Formatting twice, comments around multiline calls, long named lists, Unicode, unchanged formatted files, invalid source, and stable diagnostic codes/locations despite wording edits.

### TOOL 08 Normative status and completion gates are missing

**Reference:** TOOL-08. **Priority:** high coordination priority.

**Evidence:** [README.md lines 31](../_index.md) says the guides together specify v0.1; compiler/tooling guides repeat that contract claim at `:7`. Chapters mix settled requirements, illustrative snippets, open API shapes, and implementation preferences. [compiler/conformance/scope.md lines 7](../compiler/conformance/scope.md) names deferrals but does not distinguish mandatory compiler/tooling profiles and future aspirations.

**Proposal:** Add accepted/proposed/superseded/deferred status, target version, canonical dependencies, and outstanding decisions to normative chapters. Maintain stable rule IDs, decision register, and conformance matrix. A settled rule needs exact behavior and meaningful accepted/rejected or edge examples with test oracles. Label fragments and publish a smaller complete-program collection. Keep normative behavior in one canonical chapter; other guides link to it. Compiler/tooling references dependent on ongoing ownership/concurrency revisions should be marked pending migration, without deciding those rules here.

**Milestones:** Explicitly gate core compilation/one host profile, structural editing, source debugging, architecture diffs, traces, and richer hosts. Broad v0.1 headings without gates make completion ambiguous.
