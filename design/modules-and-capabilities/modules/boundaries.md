+++
title = "Boundary contracts"
weight = 78
+++

# Boundary contracts

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Review a module boundary by reading its exported types and operations, accepted capabilities, errors, sharing requirements, and resource lifetimes together. The compiler additionally derives external effects and call relationships.

## Example: ordinary operations

The following uses application-defined `Item`, `Stock`, and `OrderError` types:

```text
interface Inventory:
    fn check(items: List[Item]) -> Result[Stock, OrderError]

fn check_stock(
    inventory: Inventory,
    items: List[Item],
) -> Result[Stock, OrderError]:
    return inventory.check(items: items)

let first = fn() -> Result[Stock, OrderError]:
    return check_stock(inventory: inventory, items: items)

let [stock] = try parallel(tasks: [first])
```

The closure/call fragment belongs to an enclosing function returning `Result[U, ExecutionError]`. To propagate OrderError in the same function, first translate it explicitly with `map_error`; [parallel](../../concurrency/parallel.md) gives a complete example.

The operation accepts its capability explicitly and returns the unchanged domain `Result`. Capturing the ordinary Inventory view is safe: every source value is shareable. The caller chooses concurrent execution through an ordinary API. The outer `try` handles execution failure; `stock` still contains the inventory domain outcome.

Submitting work to a `Background` service instead chooses that service's fixed lifetime. Passing a reference does not transfer cleanup or keep a scoped resource open.

See [parallel operations](../../concurrency/parallel.md), [fixed work lifetimes](../../concurrency/_index.md#fixed-lifetimes), and [derived effects](../capabilities/effects.md).

[Previous: Modules, exports, and imports](declarations.md) · [Next: Explicit capability authority](../capabilities/authority.md)
