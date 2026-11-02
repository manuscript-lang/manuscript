# conform: tags=alternatives,control-flow,decimal,formatter,interfaces,match,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/results.md:14
import Decimal from "@std/math/decimal.ms"

type DiscountError:
    case InvalidPrice
    case InvalidPercent

fn discount(price: Decimal, percent: Decimal) Result[Decimal, DiscountError]:
    if price < 0d:
        return error(InvalidPrice)
    if percent < 0d or percent > 100d:
        return error(InvalidPercent)

    return ok(price * (1d - percent / 100d))
