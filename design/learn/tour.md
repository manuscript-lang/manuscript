+++
title = "A language tour"
weight = 2
+++

# A language tour

These small examples introduce the same concepts used in larger applications. The first two blocks are complete modules with executable tests. Later blocks are function-body fragments.

## Bind values and call functions

```text
import panic from "@std/faults.ms"

fn greeting(name: String) -> String:
    return "Hello, {name}!"

test "greeting":
    let message = greeting("Ada")
    if not (message == "Hello, Ada!"):
        return panic(message: "check failed")
```

`fn` declares a function. Parameter and return types are explicit; the local binding's type is inferred. A single-parameter call can omit the label, as above, or use `greeting(name: "Ada")`. Functions with multiple parameters require named arguments. Use `var` when a binding needs reassignment. See [bindings](../core-language/basics/bindings.md) and [functions](../core-language/functions/declarations-and-calls.md).

## Model data and alternatives

```text
import panic from "@std/faults.ms"

type Customer:
    name: String

type Lookup:
    case Found(customer: Customer)
    case Missing

fn describe(result: Lookup) -> String:
    match result:
        Found(customer):
            return customer.name
        Missing:
            return "Unknown customer"

test "lookup":
    let customer = Customer(name: "Ada")
    if not (describe(result: Lookup.Found(customer: customer)) == "Ada"):
        return panic(message: "check failed")
```

Records have named, immutable fields. Alternatives express one of several cases and matching must be exhaustive. Types are nominal: matching field shapes do not make two declarations interchangeable. See [records](../core-language/types/records.md) and [alternatives](../core-language/types/alternatives.md).

## Collections and optional values

```text
import panic from "@std/faults.ms"

let names = ["Ada", "Grace"]
let more = names.append(value: "Linus")
match more.get(index: 0):
    some(name):
        if not (name == "Ada"):
            return panic(message: "check failed")
    none:
        return panic(message: "Unexpected case")
```

Collections create new values rather than mutating existing ones. Looking up an element returns `Optional[T]`, so absence is visible in the type. Complete modules import `Optional` from `@std/optional.ms`; explicit collection type annotations also import `List` from `@std/collections.ms`. See [collections](../core-language/types/collections.md).

## Expected failures

I/O returns `Result[T, E]`. Match `ok(value)` and `error(cause)` when the caller needs to handle both. Within a function returning a compatible `Result`, `?` propagates an error and unwraps success. Imports provide declarations rather than ambient I/O access.

The [hello application](getting-started.md) handles a failed write with an exit code. Read [results](../core-language/errors/results.md) and [propagation](../core-language/errors/propagation.md) for complete signatures and conversion rules.

## Keep execution visible

Ordinary function calls execute sequentially and may suspend. Concurrent work starts through imported APIs such as `parallel`. There is no separate async function kind. Learn the lifetime and authority rules in [features and boundaries](features.md).
