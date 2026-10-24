# conform: tags=control-flow,decimal,formatter,interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/errors/results.md:40
def discount_message(price: Decimal, percent: Decimal) -> String:
    if let value = discount(price, percent):
        return f"Discounted price: {value}"

    return "Discount could not be calculated."
