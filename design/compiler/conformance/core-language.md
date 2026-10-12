+++
title = "Core-language conformance fixtures"
weight = 102
+++

# Core-language conformance fixtures

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

These fixtures check whether the compiler accepts or rejects core-language programs and whether executed expressions behave as specified. They complement the [semantic test plan](semantic-tests.md). Host behavior, resource lifetimes, and concurrency have separate fixtures.

Each fenced accepted fixture is an independent `.ms` module, with its application types and helper functions included. Its module-level `test` body has the ordinary `Unit` return contract. A rejected variant replaces or removes exactly the indicated text in that fixture, leaving the rest unchanged. If a variant introduces a standard declaration, add its individual import unless missing-import rejection is the behavior under test. Test each variant independently: combining unrelated errors makes the expected diagnostic ambiguous.

The expected stage identifies the violated contract: **parse** for invalid source structure; **resolution** for an unknown or ambiguous symbol; **type** for incompatible types, shapes, labels, bounds, or control flow after parsing and resolution. A checker may combine its resolution and type passes, but must identify the specified cause at the offending source span. Diagnostic wording and internal pass layout are implementation choices. Accepted fixtures must satisfy the stated checks, rather than merely generate Go that compiles.

## CL-01: Layout and named-call syntax

Contract: [source syntax](../../core-language/basics/syntax.md) and [declarations and calls](../../core-language/functions/declarations-and-calls.md).

```text
import panic from "@std/faults.ms"

fn subtract(amount: Int, deduction: Int) -> Int:
    return amount - deduction

test "named multiline call":
    let remaining = subtract(
        deduction: 2,
        amount: 9,
    )
    if not (remaining == 7):
        return panic(message: "check failed")
```

This accepts trailing commas and multiline calls while mapping labels to declared parameters. Reordering the written labels does not change the parameter mapping.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the call with `subtract(amount: 9, deduction: 2)` | Accept; `remaining` is `Int` and equals 7 |
| Replace it with `subtract(9, 2)` | Parse rejection: supplied arguments require names |
| Replace it with `subtract(amount: 9, amount: 2)` | Type rejection: duplicate supplied argument and missing `deduction` |
| Replace it with `subtract(amount: 9)` | Type rejection: missing required `deduction` |
| Replace it with `subtract(amount: 9, discount: 2)` | Type rejection: unknown argument name `discount` |
| Replace `return amount - deduction` with `return missing` | Resolution rejection: unknown binding `missing` |
| Remove the indentation before the function's `return` | Parse rejection: missing function block/module-level return |

Add lexical rejection fixtures for tabs, inconsistent dedentation, and unterminated delimiters as specified by the syntax chapter. Preserve the error's actual cause rather than reporting a later missing return.

## CL-02: Arithmetic grouping and Boolean short-circuiting

Contract: [expressions and operators](../../core-language/basics/expressions.md) and [numeric operations](../../core-language/basics/numbers-and-booleans.md).

```text
import panic from "@std/faults.ms"

fn invalid_division(zero: Int) -> Bool:
    return 1 / zero == 0

test "grouping and short circuit":
    if not (2 + 3 * 4 == 14):
        return panic(message: "check failed")
    if not ((2 + 3) * 4 == 20):
        return panic(message: "check failed")
    if not (10 - 3 - 2 == 5):
        return panic(message: "check failed")
    if not (true or invalid_division(zero: 0)):
        return panic(message: "check failed")
    if not (not (false and invalid_division(zero: 0))):
        return panic(message: "check failed")
```

Both short-circuit checks must complete without invoking the invalid division. This observes control flow, not only operator result types.

| Independent variant | Expected outcome |
| --- | --- |
| Replace `2 + 3 * 4` with `2 + 3.0 * 4.0` | Type rejection: mixed `Int` and `Float`, without implicit conversion |
| Replace `true or invalid_division(zero: 0)` with `1 or invalid_division(zero: 0)` | Type rejection: logical operand must be `Bool` |
| Replace a comparison with `1 < 2 < 3` | Parse rejection: comparison operators cannot chain |
| Replace `true or invalid_division(zero: 0)` with `true or panic(message: "skipped")` | Accept and evaluate to true: the skipped Never operand is admissible as Bool |
| Replace `false and invalid_division(zero: 0)` with `false and panic(message: "skipped")` | Accept and evaluate to false: the right Never operand is not evaluated |

Integer overflow and division-by-zero fixtures must expect programming faults even if the backend could evaluate a wrapping Go operation. Use parameterized helpers to exercise runtime inputs rather than relying only on constant folding. Literal-range rejection is a separate compile-time fixture.

## CL-03: Nominal constructors and record bindings

Contract: [records](../../core-language/types/records.md) and [destructuring](../../core-language/basics/destructuring.md).

```text
import panic from "@std/faults.ms"

type CustomerId:
    value: String

type OrderId:
    value: String

type Customer:
    id: CustomerId
    name: String

fn customer_name(customer: Customer) -> String:
    let {id: {value}, name: display_name} = customer
    return "{value}: {display_name}"

test "nominal record and nested binding":
    let customer = Customer(id: CustomerId(value: "c1"), name: "Ada")
    if not (customer_name(customer: customer) == "c1: Ada"):
        return panic(message: "check failed")
```

| Independent variant | Expected outcome |
| --- | --- |
| Use `OrderId(value: "c1")` for the customer's `id` | Type rejection: nominal `OrderId` is not `CustomerId` |
| Omit `name` in `Customer(...)` | Type rejection: missing field |
| Add `active: true` to `Customer(...)` | Type rejection: unknown field |
| Supply `name` twice | Type rejection: duplicate field |
| Bind `{email}` from `customer` | Type rejection: unknown record field |
| Bind `{id: value, name: value}` | Type rejection: duplicate local binding |
| Assign `customer.name = "Grace"` after construction | Parse rejection: assignment accepts a binding name, not a field target |

Public-surface rejection fixture:

```text
import List from "@std/collections.ms"

type PrivateId:
    value: String

export type PublicRecord:
    ids: List[PrivateId]
```

Reject at type checking: the exported field exposes the internal nominal `PrivateId` through a nested application. Changing `type PrivateId` to `export type PrivateId` accepts the module. Public closure is not satisfied merely because the outer standard `List` type is public.

## CL-04: Positional bindings and list shape

Contract: [collections](../../core-language/types/collections.md) and [destructuring](../../core-language/basics/destructuring.md).

```text
import panic from "@std/faults.ms"

import List from "@std/collections.ms"

fn difference(values: List[Int]) -> Int:
    let [first, second] = values
    return first - second

test "list binding":
    if not (difference(values: [9, 4]) == 5):
        return panic(message: "check failed")
    let empty: List[Int] = []
    let {value: label} = Label(value: "ready")
    if not (label == "ready"):
        return panic(message: "check failed")

type Label:
    value: String
```

The empty literal gets its type from the annotation. `difference`'s binding is checked against `List[Int]`; its exact length is validated when the function runs.

| Independent variant | Expected outcome |
| --- | --- |
| Replace `[9, 4]` with `[9, 4.0]` | Type rejection: heterogeneous numeric list without explicit conversion |
| Replace `let empty: List[Int] = []` with `let empty = []` | Type rejection: insufficient element-type information |
| Replace the binding with `let (first, second) = values` | Parse rejection: parenthesized positional binding is unsupported |
| Replace the test call with `difference(values: [9])` | Function accepts `List[Int]`; evaluation faults at dynamic destructuring |
| Replace the empty declaration with `let [only] = [1, 2]` | Type rejection: statically known length mismatch; no extra value is discarded |
| Annotate `let [first, second]: List[Int] = values` | Parse rejection: only simple name bindings accept annotations |

A literal-length mismatch in the binding itself is a compile-time shape error; a list parameter's runtime length is a programming-fault check. Optional optimization must not turn acceptance of the parameterized function into an invented fixed-length parameter type.

## CL-05: Function values retain parameter labels

Contract: [function values](../../core-language/functions/function-values-and-closures.md).

```text
import panic from "@std/faults.ms"

fn increase(value: Int) -> Int:
    return value + 1

fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int:
    return transform(value: value)

test "function label compatibility":
    let transform: fn(value: Int) -> Int = increase
    if not (apply(value: 4, transform: transform) == 5):
        return panic(message: "check failed")
```

| Independent variant | Expected outcome |
| --- | --- |
| Rename only `increase`'s parameter and body binding to `item` | Type rejection: `fn(item: Int) -> Int` is incompatible with `fn(value: Int) -> Int` |
| Call `transform(item: value)` in `apply` | Type rejection: unknown function-value argument label |
| Change `increase` to return `Float` with body `return 1.0` | Type rejection at assignment/call: function result contract differs |
| Change it to return `Never` with body `panic(message: "stop")` | Type rejection at assignment: `Never` expression compatibility does not make function result types covariant |
| Change the `apply` call to omit `transform` | Type rejection: required function argument is missing |

## CL-06: Return completeness and Boolean conditions

Contract: [declarations and calls](../../core-language/functions/declarations-and-calls.md), [conditionals](../../core-language/control-flow/conditionals.md), and [faults](../../core-language/errors/faults.md).

```text
import panic from "@std/faults.ms"

fn positive(value: Int) -> Int:
    if value > 0:
        return value
    else:
        panic(message: "positive value required")

fn discard(value: Int) -> Unit:
    if not (value > 0):
        return panic(message: "check failed")

test "return contracts":
    if not (positive(value: 3) == 3):
        return panic(message: "check failed")
    discard(value: 1)
```

The faulting branch has no normal successor. `discard` accepts normal fallthrough because it returns `Unit`.

| Independent variant | Expected outcome |
| --- | --- |
| Remove the `else` branch in `positive` | Type rejection: a reachable path falls through a non-`Unit` function |
| Replace `if value > 0` with `if value` | Type rejection: condition must be `Bool` |
| Replace `return value` with `return true` | Type rejection: returned value is not `Int` |
| Replace `discard`'s body with `return 1` | Type rejection: `Int` result in a `Unit` function |
| Replace it with `return` or `return unit` | Accept: explicit Unit return, like fallthrough |

Unreachable statements must still parse, resolve, and type-check; they do not repair a missing return on a reachable path.

## CL-07: Alternatives, positional payload patterns, and exhaustiveness

Contract: [alternatives](../../core-language/types/alternatives.md) and [pattern matching](../../core-language/control-flow/pattern-matching.md).

```text
import panic from "@std/faults.ms"

type Outcome:
    case Ready(value: Int)
    case Failed(reason: String)

fn score(outcome: Outcome) -> Int:
    match outcome:
        Ready(value):
            return value
        Failed(_):
            return 0

test "alternative result":
    if not (score(outcome: Outcome.Ready(value: 8)) == 8):
        return panic(message: "check failed")
    if not (score(outcome: Outcome.Failed(reason: "unavailable")) == 0):
        return panic(message: "check failed")
```

Constructors name payload fields; payload patterns bind positions in declaration order. Matching has no fallthrough.

| Independent variant | Expected outcome |
| --- | --- |
| Remove `Failed` arm | Type rejection: non-exhaustive match |
| Add another `Ready(other)` arm | Type rejection: duplicate/unreachable arm |
| Replace `Ready(value)` with `Ready(value, extra)` | Type rejection: payload arity mismatch |
| Replace `Ready(value)` with `Ready(value: local)` | Parse rejection: payload patterns are positional, not named-call syntax |
| Use `Outcome.Ready(amount: 8)` in the constructor | Type rejection: wrong payload field name |
| Add a final `_:` arm instead of `Failed` | Accept; wildcard covers the remaining case |
| Add `_:` with body `return 0` after both existing arms | Type rejection: every case is already covered, so the wildcard is unreachable |

Add ambiguity fixtures with two visible alternative types declaring `Ready`: unqualified construction must be rejected at resolution even when an expected result type could identify one; qualified construction succeeds. Match-case lookup is governed by the scrutinee type.

## CL-08: Iteration and nearest-loop control flow

Contract: [loops](../../core-language/control-flow/loops.md).

```text
import panic from "@std/faults.ms"

import List from "@std/collections.ms"

fn selected_sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        if value == 0:
            continue
        if value < 0:
            break
        total = total + value
    return total

test "iteration control":
    if not (selected_sum(values: [2, 0, 3, -1, 9]) == 5):
        return panic(message: "check failed")
    if not (selected_sum(values: []) == 0):
        return panic(message: "check failed")
```

| Independent variant | Expected outcome |
| --- | --- |
| Replace the iterable `values` with `3` | Type rejection: `Int` is not an admitted iterable |
| Assign `value = 4` in the loop body | Type rejection: iteration binding is immutable |
| Put `break` in the test body outside a loop | Type rejection: no enclosing loop |
| Put `continue` inside a nested anonymous function without its own loop | Type rejection: loop control cannot cross a function boundary |

For nested loops, verify that `break` and `continue` select the nearest enclosing loop. For `while`, verify that the condition is reevaluated and must have type `Bool`.

## CL-09: Generic declaration, inference, and bounds

Contract: [generics](../../core-language/types/generics.md) and [equality](../../core-language/types/equality-and-hashing.md).

```text
import panic from "@std/faults.ms"

type Box[T: Shareable]:
    value: T

fn unwrap[T: Shareable](box: Box[T]) -> T:
    return box.value

fn same[T: Shareable & Equal](left: T, right: T) -> Bool:
    return left == right

test "generic argument inference":
    let box = Box[Int](value: 6)
    if not (unwrap(box: box) == 6):
        return panic(message: "check failed")
    if not (unwrap[Int](box: box) == 6):
        return panic(message: "check failed")
    if not (same(left: 6, right: 6)):
        return panic(message: "check failed")
```

Inference uses independently typed supplied arguments. Explicit and inferred applications must select the same substitution. Generic bodies are checked against declared bounds, not only the concrete types used by these tests.

| Independent variant | Expected outcome |
| --- | --- |
| Use `Box[Int, String](value: 6)` | Type rejection: generic arity mismatch |
| Use `Box[String](value: 6)` | Type rejection: field is not the substituted `String` type |
| Use `unwrap[String](box: box)` | Type rejection: invariant `Box[Int]` is not `Box[String]` |
| Use `same(left: 6, right: 6.0)` | Type rejection: supplied types do not yield one exact `T` |
| Remove `Equal` from `same`'s bound | Type rejection in generic body: `T` does not establish equality |
| Use the undeclared type parameter `U` in `Box`'s field | Resolution rejection: unknown type `U` |

Separate fixture:

```text
import Optional from "@std/optional.ms"

fn absent[T: Shareable]() -> Optional[T]:
    return none

test "result context does not infer function arguments":
    let value: Optional[Int] = absent[Int]()
```

Accept the explicit call. Replacing `absent[Int]()` with `absent()` is a type rejection: result context cannot infer a generic function's type arguments. An expected constructor payload type may provide context for `none` or an empty list without introducing result-context function inference.

Intrinsic-name rejection fixture:

```text
type Box[Int]:
    value: Int
```

Reject at resolution: a type parameter cannot redefine the intrinsic `Int` identity. `Int` is a resolved name rather than a lexical keyword, so this is not a grammar rejection. Apply the same namespace check to module declarations/imports and fixed compiler-bound names, without prohibiting ordinary local shadowing where the module rules permit it.

## CL-10: Explicit implementations and contract conversion

Contract: [operation contracts](../../core-language/types/contracts.md).

```text
import panic from "@std/faults.ms"

interface Increment:
    fn apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) -> Int:
        return value + self.delta

fn use_increment(operation: Increment) -> Int:
    return operation.apply(value: 4)

test "explicit contract conversion":
    let offset = Offset(delta: 1)
    let operation = Increment(value: offset)
    let same_view = Increment(value: operation)
    if not (use_increment(operation: same_view) == 5):
        return panic(message: "check failed")
```

`self` is implicit in the implementation body, never a source call argument. Conversion retains the concrete value; applying the same view constructor to an existing exact contract value is an identity conversion. The contract cannot be constructed without a value providing its declared implementation or already having that exact contract type.

| Independent variant | Expected outcome |
| --- | --- |
| Pass `offset` directly as `operation` | Type rejection: conversion to the contract must be explicit |
| Remove the `impl` declaration | Type rejection at conversion: `Offset` does not implement `Increment` |
| Rename implementation parameter/body binding from `value` to `item` | Type rejection: operation labels do not match the contract |
| Change implementation result/body to `Float`/`return 1.0` | Type rejection: result signature mismatch |
| Add `self: Offset` to the implementation parameter list | Parse rejection: reserved `self` cannot be declared as a parameter |
| Repeat the same `impl Increment for Offset` declaration | Type rejection: duplicate implementation |
| Replace `Increment(value: offset)` with `Increment()` | Type rejection: conversion requires the concrete `value` argument |

Add a multi-module rejection fixture for an implementation outside the concrete type's defining module; path/import mechanics follow [module conformance](semantic-tests.md). Contract method ambiguity on a concrete value is resolved by explicit conversion to the selected contract.

## CL-10a: Generic implementations and nonoverlap

Contract: [generic implementations](../../core-language/types/contracts.md#generic-implementations).

```text
import panic from "@std/faults.ms"

interface ReadValue[T]:
    fn get() -> T

interface SameValue[T: Equal]:
    fn same(other: T) -> Bool

type Box[T]:
    value: T

impl ReadValue[T] for Box[T]:
    fn get() -> T:
        return self.value

impl SameValue[T] for Box[T]:
    fn same(other: T) -> Bool:
        return self.value == other

fn compare[T: Equal](box: Box[T], other: T) -> Bool:
    return box.same(other: other)

test "generic implementations":
    let number = Box[Int](value: 7)
    let text = Box[String](value: "hello")
    let number_view = ReadValue[Int](value: number)
    let text_view = ReadValue[String](value: text)
    if not (number_view.get() == 7):
        return panic(message: "check failed")
    if not (text_view.get() == "hello"):
        return panic(message: "check failed")
    if not (compare(box: number, other: 7)):
        return panic(message: "check failed")
    if not (not compare(box: number, other: 8)):
        return panic(message: "check failed")
```

The first block needs no bound to read and return its field. The second inherits `Equal` from the `SameValue` interface to compare it. `compare` proves that implementation's availability while checking its generic body, without waiting for a concrete instantiation.

| Independent variant | Expected outcome |
| --- | --- |
| Add a concrete `impl ReadValue[Int] for Box[Int]` supplying `get() -> Int` | Type rejection at declaration: overlap with the generic block, even if the body is identical |
| Add another `impl ReadValue[T] for Box[T]` supplying `get() -> T` | Type rejection at declaration: bounds cannot distinguish overlapping blocks |
| Replace the first block's `ReadValue[T]` with `ReadValue[Int]` | Type rejection at declaration: `get() -> T` does not match the substituted contract result `Int` |
| Remove `Equal` from `SameValue`'s interface parameters | Type rejection at declaration: unconstrained field values cannot be compared |
| Remove `Equal` from `compare`'s parameters | Type rejection in the generic function body: the implementation's bound is not proved |
| Replace the first block's receiver `Box[T]` with bare `T` | Type rejection at declaration: receiver must have a defining nominal data declaration |
| Add `[U]` to an implementation method | Parse rejection: methods cannot introduce their own parameters |

Also accept disjoint concrete implementations for different receiver applications when no generic block covers them, and two different contract applications for one receiver. For the latter, use explicit views to disambiguate equal operation names. Reject expanding recursive implementation specialization under the ordinary finite-application check. The defining-module rule applies equally to concrete and generic blocks.

## CL-10b: Plain and shared contract views

Contract: [shared contract views](../../core-language/types/contracts.md#shared-contract-views) and [sharing](../../ownership-and-cleanup/values/sharing.md).

```text
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Optional from "@std/optional.ms"

interface ReadValue[T]:
    fn get() -> T

type Box[T]:
    value: T

type SharedReader:
    reader: ReadValue[Int] & Shareable

type CallbackReader:
    read_value: fn() -> Int

impl ReadValue[T] for Box[T]:
    fn get() -> T:
        return self.value

impl ReadValue[Int] for CallbackReader:
    fn get() -> Int:
        return self.read_value()

fn seven() -> Int:
    return 7

fn local_view[T: ReadValue[Int]](source: T) -> ReadValue[Int]:
    return ReadValue[Int](value: source)

fn shared_view[T: ReadValue[Int] & Shareable](source: T) -> ReadValue[Int] & Shareable:
    return (ReadValue[Int] & Shareable)(value: source)

fn consume_shared[T: ReadValue[Int] & Shareable](source: T) -> Int:
    return source.get()

test "plain and shared views":
    let box = Box[Int](value: 7)
    let plain = local_view(source: box)
    let shared = shared_view(source: box)
    let identity = (ReadValue[Int] & Shareable)(value: shared)
    let erased = ReadValue[Int](value: identity)
    let holder = SharedReader(reader: identity)
    let readers: List[ReadValue[Int] & Shareable] = [holder.reader]
    let optional: Optional[ReadValue[Int] & Shareable] = some(value: shared)
    let callback = CallbackReader(read_value: seven)
    let local_callback = ReadValue[Int](value: callback)
    if not (plain.get() == 7):
        return panic(message: "check failed")
    if not (erased.get() == 7):
        return panic(message: "check failed")
    if not (local_callback.get() == 7):
        return panic(message: "check failed")
    if not (consume_shared(source: holder.reader) == 7):
        return panic(message: "check failed")
```

`local_view` must be accepted with no sharing bound on its generic receiver. `shared_view` retains its proof through the returned type and the record field; the same implementation supplies every view. CallbackReader's bare function field carries no callable-sharing promise, so the record is nonshareable even though this particular initializer is a safe named function. Its plain view and sequential call are accepted. View conversion evaluates the receiver once and neither copies nor closes native state. The collection and optional declarations exercise refined types inside generic arguments.

| Independent variant | Expected outcome |
| --- | --- |
| Remove `Shareable` from `shared_view`'s generic bound | Type rejection in its body: receiver sharing is not proved |
| Construct `(ReadValue[Int] & Shareable)(value: plain)` or use `erased` instead | Type rejection: a plain view cannot recover its hidden receiver's sharing guarantee |
| Replace the callback's plain view constructor with `(ReadValue[Int] & Shareable)(value: callback)` | Type rejection: the bare function field gives its receiver no sharing proof |
| Pass `plain` to `consume_shared` | Type rejection at the generic application: named contract bound holds, sharing bound does not |
| Change the list to `List[ReadValue[Int]] = [plain]` | Type rejection: plain contract type fails the collection element bound |
| Initialize `SharedReader(reader: plain)` | Type rejection: plain and shared field types differ |
| Replace `ReadValue[Int](value: identity)` with `identity` | Accepted: the inferred local retains the shared type rather than erasing it |
| Annotate that replacement as `let erased: ReadValue[Int] = identity` | Type rejection: discarding sharing is not implicit |
| Replace the shared constructor in `shared_view` with `ReadValue[Int](value: source)` | Type rejection at return: expected shared type cannot refine a plain constructor |
| Replace `ReadValue[Int] & Shareable` in the record field with `Int & Shareable` | Type rejection: only an operation contract can have this refinement |
| Replace the field type with `Shareable & ReadValue[Int]` | Parse rejection: reversed order is not a value-type form |
| Replace the field type with `ReadValue[Int] & Equal` | Parse rejection: only the `Shareable` refinement is admitted |

With a trusted native nonshareable receiver fixture, accept a plain view and sequential calls, reject its shared view construction, and reject concurrently used closures retaining its plain view or bound method. A shared receiver's method supplies receiver-sharing proof, subject to the existing callable-boundary rules. Verify that a shared service may return a nonshareable local result without making that result shareable. These checks must use frontend proofs rather than Go interface assignability or runtime receiver inspection.

## CL-11: Recursive records require immutable-container indirection

Contract: [records](../../core-language/types/records.md) and [generics](../../core-language/types/generics.md).

```text
import panic from "@std/faults.ms"

import List from "@std/collections.ms"

type Tree[T: Shareable]:
    value: T
    children: List[Tree[T]]

test "recursive immutable collection":
    let leaf = Tree[Int](value: 1, children: [])
    let root = Tree[Int](value: 2, children: [leaf])
    if not (root.value == 2):
        return panic(message: "check failed")
```

Accept: removing the `List` storage edge leaves no inline record/alternative cycle, and recursive applications preserve `T` unchanged.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the `children` field type with `Tree[T]` | Type rejection at declaration: unguarded inline cycle |
| Replace it with `Optional[Tree[T]]` | Type rejection at declaration: `Optional` does not provide storage indirection |
| Replace it with `Result[Tree[T], String]` | Type rejection at declaration: `Result` does not provide storage indirection |
| Replace it with `List[Tree[List[T]]]` | Type rejection at declaration: recursive application expands the type parameter |

The declaration check must reject the offending type before constructor errors in the test obscure the cycle. Mutual-recursion fixtures within one module must apply the same graph rule across every participating record/alternative. An import cycle is a separate module rejection, not a substitute for the inline-layout check.

## CL-12: Collection iteration has concrete element types

Contract: [loops](../../core-language/control-flow/loops.md) and [collections](../../core-language/types/collections.md).

```text
import panic from "@std/faults.ms"

import Map from "@std/collections.ms"
import MapEntry from "@std/collections.ms"
import Set from "@std/collections.ms"

fn map_total(values: Map[String, Int]) -> Int:
    var total = 0
    for entry in values:
        let {key, value} = entry
        let label: String = key
        total = total + value
    return total

fn set_total(values: Set[Int]) -> Int:
    var total = 0
    for value in values:
        total = total + value
    return total

test "map entry type":
    let entry = MapEntry[String, Int](key: "a", value: 3)
    if not (entry.key == "a"):
        return panic(message: "check failed")
    if not (entry.value == 3):
        return panic(message: "check failed")
```

Accept these functions with the [minimum collection API](../../standard-library/data-and-io/operations.md). The map loop element is `MapEntry[String, Int]`, whose record fields are `key: String` and `value: Int`; the set loop element is `Int`.

| Independent variant | Expected outcome |
| --- | --- |
| Replace map-loop `entry` with `[key, value]` | Parse rejection: a loop introduces one identifier, not a destructuring pattern |
| Bind `{missing}` from `entry` | Type rejection: unknown map-entry record field |
| Declare `let label: Int = key` | Type rejection: map key is `String`, not `Int` |
| Replace `Set[Int]` with `Set[Float]` | Type rejection: `Float` is not `Hashable` |
| Replace `Map[String, Int]` with `Map[List[Int], Int]` | Type rejection: collections are not hashable keys |

Runtime collection fixtures use the minimum constructor/update API: verify insertion-order traversal for maps and sets, and evaluate an effectful iterable expression exactly once. The concrete expectations are in [runtime bindings](runtime-bindings.md).

## CL-13: Lexical text forms and declaration-only modules

Contract: [source grammar](../../core-language/basics/grammar.md) and [text](../../core-language/basics/text-and-bytes.md).

```text
import panic from "@std/faults.ms"

fn echo(value: String) -> String:
    return value

test "text source forms":
    if not (echo(value: "\{literal\}") == "\{literal\}"):
        return panic(message: "check failed")
    if not ("\u{1F600}" == "😀"):
        return panic(message: "check failed")
    if not ("value: {3}" == "value: 3"):
        return panic(message: "check failed")
    let no_value: Unit = unit
```

Escaped braces are literal text; unescaped braces select interpolation. Source UTF-8 encoding and Unicode scalar validation are part of parsing text, independent of later text-conversion APIs.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the scalar escape with `"\u{D800}"` | Parse rejection: surrogate is not a Unicode scalar |
| Replace it with `"\u{110000}"` | Parse rejection: scalar exceeds the Unicode range |
| Replace an escape with `"\q"` | Parse rejection: unknown escape |
| Replace `echo`'s function name with the reserved word `if` | Parse rejection: reserved word is not an identifier |
| Add module-level `let extra = 1` after the test | Parse rejection: executable bindings belong in a block |
| Replace `let no_value: Unit = unit` with `let no_value: Unit = 0` | Type rejection: `Int` is not `Unit` |
| Replace it with `let smallest: Int = -9223372036854775808` | Accept: directly negated minimum Int literal |
| Replace it with `let too_large = 9223372036854775808` | Type rejection: positive literal is outside Int range |
| Replace it with `let too_large = 1e400` | Type rejection: Float literal would round to infinity |
| Replace it with `let unknown = 01` | Parse rejection: leading-zero numeric spelling is not supported |

Equivalent LF and CRLF encodings must produce the same parsed structure after documented newline normalization. Invalid UTF-8 input must be rejected rather than silently replaced. Blank/comment-only lines do not introduce suites, and comment markers within text remain text.

## CL-14: Result propagation preserves the declared error type

Contract: [Result](../../core-language/errors/results.md) and [try propagation](../../core-language/errors/propagation.md).

```text
import panic from "@std/faults.ms"

import Result from "@std/result.ms"

type Problem:
    case Missing(reason: String)

type OtherProblem:
    case Invalid(reason: String)

fn checked(value: Int) -> Result[Int, Problem]:
    if value < 0:
        return error(cause: Problem.Missing(reason: "negative"))
    return ok(value: value)

fn doubled(value: Int) -> Result[Int, Problem]:
    let accepted = try checked(value: value)
    return ok(value: accepted * 2)

fn summarize(outcome: Result[Int, Problem]) -> Int:
    match outcome:
        ok(value):
            return value
        error(_):
            return -1

test "unchanged propagated error":
    if not (summarize(outcome: doubled(value: 3)) == 6):
        return panic(message: "check failed")
    if not (summarize(outcome: doubled(value: -1)) == -1):
        return panic(message: "check failed")
```

Successful construction obtains the complete `Result[Int, Problem]` type from the declared return contract. Propagation leaves the remaining body unexecuted on an expected error; it does not introduce an implicit error union or conversion.

| Independent variant | Expected outcome |
| --- | --- |
| Change only `doubled`'s declared error type to `OtherProblem` | Type rejection at `try`: incompatible propagated error |
| Change `doubled` to return `Int`, and its final return to `return accepted * 2` | Type rejection at `try`: enclosing function must return compatible `Result` |
| Replace `ok(value: value)` with `ok(value: true)` | Type rejection: wrong successful payload type |
| Replace the error payload with `OtherProblem.Invalid(reason: "negative")` | Type rejection: wrong declared error payload type |
| Replace the `try` operand with `value` | Type rejection: operand is not `Result` |
| Replace the local binding with `let accepted: Int = try ok(value: 3)` | Type rejection: annotation does not propagate through `try` to infer the missing error type |
| Replace the local binding with `let accepted = try Result[Int, Problem].ok(value: value)` | Accept: qualification establishes both Result arguments before propagation |

An anonymous function establishes its own propagation boundary. Test that an inner `Unit` closure cannot use `try` merely because its enclosing function returns `Result`; the inner function's signature controls compatibility.

## CL-15: Equality eligibility does not imply hashing eligibility

Contract: [equality and hashing](../../core-language/types/equality-and-hashing.md).

```text
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Decimal from "@std/decimal.ms"
import Optional from "@std/optional.ms"

type Callback:
    handler: fn(value: Int) -> Int

fn increment(value: Int) -> Int:
    return value + 1

fn preserve_key[K: Hashable](value: K) -> K:
    return value

test "derived value equality":
    let present: Optional[Int] = some(value: 1)
    let same: Optional[Int] = some(value: 1)
    let missing: Optional[Int] = none
    if not (present == same):
        return panic(message: "check failed")
    if not (present != missing):
        return panic(message: "check failed")
    if not (1.00d == 1d):
        return panic(message: "check failed")
    if not ([1, 2] == [1, 2]):
        return panic(message: "check failed")
    if not ([1, 2] != [2, 1]):
        return panic(message: "check failed")
    if not (preserve_key(value: "key") == "key"):
        return panic(message: "check failed")
    let callback = Callback(handler: increment)
```

Optional equality compares its tag and eligible payload. Decimal equality compares numeric values despite different trailing zeroes. List equality observes positions rather than treating a list as a set. Eligibility is checked recursively on record fields.

| Independent variant | Expected outcome |
| --- | --- |
| Add `if callback == callback:` with a `return` body | Type rejection: a function field makes `Callback` ineligible for equality |
| Add `if increment == increment:` with a `return` body | Type rejection: function values have no equality |
| Use `preserve_key(value: [1, 2])` | Type rejection: equal lists are not hashable |
| Use `preserve_key(value: 1.0)` | Type rejection: `Float` is equal-comparable but not hashable |
| Declare `let wrong: Optional[Float] = present` | Type rejection: invariant optional applications differ |

Test generated record/alternative equality with eligible scalar leaves and reject derivations containing a noneligible leaf. Do not treat sharing eligibility, identical object references, or a user-written marker implementation as evidence of equality.

## CL-16: Expected data types supply constructor context

Contract: [compatibility and expected types](../../core-language/types/compatibility.md), [Optional](../../core-language/types/optionals.md), and [Result](../../core-language/errors/results.md).

```text
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

type Input:
    names: List[Optional[String]]

fn outcome_value(outcome: Result[Int, String]) -> Int:
    match outcome:
        ok(value):
            return value
        error(_):
            return -1

test "data constructor context":
    let input = Input(names: [none, some(value: "Ada")])
    let success: Result[Int, String] = ok(value: 3)
    let failure: Result[Int, String] = error(cause: "unavailable")
    let absent: Optional[Int] = none
    let nested: List[List[Int]] = [[], [1]]
    if not (outcome_value(outcome: success) == 3):
        return panic(message: "check failed")
    if not (outcome_value(outcome: failure) == -1):
        return panic(message: "check failed")
```

The field, binding annotation, or substituted parameter determines missing data arguments; it does not convert an independently known incompatible type. Forward declarations and contextual list elements do not require module-level execution.

| Independent variant | Expected outcome |
| --- | --- |
| Remove `: Result[Int, String]` from `success` | Type rejection: `ok`'s payload does not determine the error type |
| Remove it from `failure` | Type rejection: `error`'s payload does not determine the success type |
| Remove `: Optional[Int]` from `absent` | Type rejection: `none` supplies no payload type |
| Change `some(value: "Ada")` to `some(value: 3)` | Type rejection: independently known payload conflicts with expected `String` |
| Replace `none` for `absent` with `3` | Type rejection: no implicit Optional wrapping |
| Replace `ok(value: 3)` for `success` with `3` | Type rejection: no implicit Result wrapping |

Add a nonempty-list fixture `[none, some(value: 1)]`: the independently typed `some` determines `Optional[Int]` for the absent element. Reject `[some(value: 1), some(value: "one")]`; no implicit union is formed. These data-constructor rules do not infer a missing generic function specialization from its result context; CL-09 checks that separate boundary.

## CL-17: Nonreturning subexpressions determine control-flow exits

Contract: [Unit and Never](../../core-language/functions/declarations-and-calls.md#unit-and-never).

The following independent module is a type-checking fixture; its faulting functions are not invoked as passing tests.

```text
import panic from "@std/faults.ms"

fn failed_initializer() -> Never:
    let impossible: Int = panic(message: "initializer cannot return")

fn returned_failure() -> Int:
    return panic(message: "result cannot return")

fn endless() -> Int:
    while true:
        continue
```

Accept: the initializer and return expression cannot produce values; the literal-true loop has no reachable break and therefore no normal exit. An expected annotation does not make a `Never` expression return an `Int` at runtime.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the initializer with `0` | Type rejection: the `Never` function now reaches normal fallthrough |
| Replace the binding with `let impossible: Int = 1 + panic(message: "stop")` | Accept: the operator result is Int, but its required right operand cannot return |
| Replace the binding with `let impossible: Bool = not panic(message: "stop")` | Accept: `not` selects Bool, but its required operand cannot return |
| Replace the binding with `let impossible: Int = panic(message: "left") + panic(message: "right")` | Type rejection: two Never operands supply no numeric candidate, even under an Int annotation |
| Replace the binding with `let impossible: Int = -panic(message: "stop")` | Type rejection: unary numeric selection requires an independently known numeric operand |
| Replace the binding with `let possible: Bool = false and panic(message: "skipped")` | Type rejection: the Never function has reachable fallthrough because the right operand is skipped |
| Replace the binding with `let possible: Bool = true or panic(message: "skipped")` | Type rejection: short circuiting permits normal fallthrough |
| Add `return unit` after its initializer | Type rejection: unreachable returns still must match the declared result type |
| Replace `return panic(...)` with bare `return` | Type rejection: a non-Unit function requires a value |
| Replace `while true` with `while not false` | Type rejection: nonliteral conditions retain a possible exit; no constant folding proves return completeness |
| Add a reachable `break` inside `endless` | Type rejection: the loop can exit and the `Int` function then falls through |

Extend the fixture with a nested loop whose own break does not exit the outer literal-true loop. A closure's return likewise does not return from its enclosing function. Nonreturning callable/argument evaluation prevents later arguments and the outer call from running, under the ordinary evaluation-order contract.

## CL-18: Suite-bodied function expressions resume the enclosing layout

Contract: [anonymous-function suites](../../core-language/basics/grammar.md#anonymous-function-suites-inside-delimiters) and [function values](../../core-language/functions/function-values-and-closures.md).

```text
import panic from "@std/faults.ms"

fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int:
    return transform(value: value)

test "function suite boundaries":
    let dormant = fn() -> Int:
        return panic(message: "body is not run at creation")
    let grouped = apply(
        transform: (
            fn(value: Int) -> Int:
                if value > 0:
                    return value - 1
                return 0
        ),
        value: 3,
    )
    let final_argument = apply(
        value: 3,
        transform: fn(value: Int) -> Int:
            return value - 1
    )
    if not (grouped == 2):
        return panic(message: "check failed")
    if not (final_argument == 2):
        return panic(message: "check failed")
```

The unused closure's body must not run. Its dedent terminates both the function expression and the surrounding binding statement, so the next binding does not require an extra blank line. The grouped closure ends before the outer argument comma; the final ungrouped closure resumes the still-open call's continuation when its body dedents. The nested `if` dedents within the active function suite rather than ending the enclosing call.

| Independent variant | Expected outcome |
| --- | --- |
| Replace `dormant`'s function expression with `fn() -> Int: 1` | Parse rejection: a function body requires a statement suite |
| Indent the final call-closing `)` to the closure-body level | Parse rejection: a delimiter opened outside the function body cannot close at body indentation |
| Add `let after = 1` at the next test-body indentation without a blank line after `dormant` | Accept: synthetic statement boundary follows the function-expression suite |
| Replace the anonymous expression with a nested named `fn dormant() -> Int:` declaration | Parse rejection: named functions are not local statements |

## Coverage and evidence

Maintain one independently checked fixture for each accepted module and each rejected variant. Record actual compiler results separately from the expected outcomes here. Scalar conversions, collection construction, and numeric edge behavior have [runtime acceptance cases](runtime-bindings.md).
