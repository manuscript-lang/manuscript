# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=documentation/learn/tour.md:204
import line_total from "./pricing.ms"

export fn checkout_total() Int:
    return line_total(quantity: 3)
