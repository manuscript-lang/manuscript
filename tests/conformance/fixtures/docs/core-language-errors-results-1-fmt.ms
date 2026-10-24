# conform: tags=alternatives,control-flow,decimal,formatter,interfaces,match,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/results.md:14
type DiscountError:
    case InvalidPrice
    case InvalidPercent

impl Error for DiscountError:
    def message() -> String:
        match self:
            case InvalidPrice: return "invalid price"
            case InvalidPercent: return "invalid percent"

def discount(price: Decimal, percent: Decimal) -> Result[Decimal, DiscountError]:
    if price < 0d:
        return error(InvalidPrice)
    if percent < 0d or percent > 100d:
        return error(InvalidPercent)

    return ok(price * (1d - percent / 100d))
