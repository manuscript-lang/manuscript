+++
title = "Boundary contracts"
weight = 78
+++

# Boundary contracts

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A module boundary tells callers which data and operations they may use. Keep those exported contracts explicit so a caller can see inputs, outputs, expected errors, and required access to external services.

## Example: ordinary operations

The following uses application-defined `Item`, `Stock`, and `OrderError` types:

```manuscript
interface Inventory:
    fn check(items: List[Item]) -> Result[Stock, OrderError]

fn check_stock(
    inventory: Inventory & Shareable,
    items: List[Item],
) -> Result[Stock, OrderError]:
    return inventory.check(items: items)

let first = fn() -> Result[Stock, OrderError]:
    return check_stock(inventory: inventory, items: items)

let [stock] = try parallel(tasks: [first])
```

The closure/call fragment belongs to an enclosing function returning `Result[U, ExecutionError]`. To propagate OrderError in the same function, first translate it explicitly with `map_error`; [parallel](../../concurrency/parallel.md) gives a complete example.

The operation accepts its capability explicitly and returns the unchanged domain `Result`. In this concurrent example the enclosing function's inventory input has the shared `Inventory & Shareable` type, preserving the receiver proof in the captured capability and across check_stock's parameter. A plain Inventory view would support sequential calls but could not be captured by this concurrent closure. The caller chooses concurrent execution through an ordinary API. The outer `try` handles execution failure; `stock` still contains the inventory domain outcome. The captured data must also meet the API's sharing requirements.

Submitting work to a `Background` service instead chooses that service's fixed lifetime. Passing a reference does not transfer cleanup or keep a scoped resource open.

See [parallel operations](../../concurrency/parallel.md), [fixed work lifetimes](../../concurrency/_index.md#fixed-lifetimes), and [derived effects](../capabilities/effects.md).

[Previous: Modules, exports, and imports](declarations.md) · [Next: Explicit capability authority](../capabilities/authority.md)
