# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=documentation/learn/tour.md:204
from "./pricing.ms" import line_total

export def checkout_total() -> Int:
    return line_total(quantity: 3)
