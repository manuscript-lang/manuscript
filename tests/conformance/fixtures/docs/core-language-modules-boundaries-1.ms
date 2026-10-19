# conform: tags=control-flow,diagnostics,lists,mutation,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/modules/boundaries.md:12

export type Item:
    price: Int
    quantity: Int

export fn total(items: List[Item]) Int:
    var result = 0
    for item in items:
        result += item.price * item.quantity
    return result
