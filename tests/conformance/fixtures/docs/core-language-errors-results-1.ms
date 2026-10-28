# conform: tags=alternatives,control-flow,decimal,diagnostics,interfaces,match,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=documentation/core-language/errors/results.md:14
type DiscountError:
    case InvalidPrice
    case InvalidPercent

impl Error for DiscountError:
    fn message() String:
        match self:
            InvalidPrice: return "invalid price"
            InvalidPercent: return "invalid percent"

fn discount(price: Decimal, percent: Decimal) Result[Decimal, DiscountError]:
    if price < 0d:
        return error(InvalidPrice)
    if percent < 0d or percent > 100d:
        return error(InvalidPercent)

    return ok(price * (1d - percent / 100d))
