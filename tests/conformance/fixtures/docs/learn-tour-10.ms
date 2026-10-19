# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/learn/tour.md:195
export let UNIT_PRICE = 12

export fn line_total(quantity: Int) Int:
    return UNIT_PRICE * quantity
