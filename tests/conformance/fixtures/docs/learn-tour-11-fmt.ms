# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:204
from "./pricing.ms" import line_total

export def checkout_total() -> Int:
    return line_total(quantity: 3)
