# conform: tags=decimal,diagnostics,interpolation,strings,tier-core,try-result
# conform: phase=check
# conform: origin=documentation/core-language/errors/propagation.md:12
def discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    let value = try discount(price, percent)
    return ok(f"Discounted price: {value}")
