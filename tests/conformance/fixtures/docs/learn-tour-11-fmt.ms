# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:204
import line_total from "./pricing.ms"

export fn checkout_total() Int:
    return line_total(quantity: 3)
