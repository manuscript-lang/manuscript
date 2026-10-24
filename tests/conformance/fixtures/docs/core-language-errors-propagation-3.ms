# conform: tags=decimal,diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=documentation/core-language/errors/propagation.md:41
def discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    return ok(try discount(price, percent) | label)
