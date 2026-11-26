// conform: tags=alternatives,control-flow,decimal,formatter,interfaces,match,parser,records,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=documentation/core-language/errors/results.md:14
import Decimal from "@std/math/decimal.ms"

enum DiscountError {
	InvalidPrice
	InvalidPercent
}

fn discount(price Decimal, percent Decimal) Result[Decimal, DiscountError] {
	if price < 0d {
		return error(InvalidPrice)
	}
	if percent < 0d or percent > 100d {
		return error(InvalidPercent)
	}

	return ok(price * (1d - percent / 100d))
}
// expect-format: rewritten
// expect-formatted: import Decimal from "@std/math/decimal.ms"
// expect-formatted:
// expect-formatted: enum DiscountError {
// expect-formatted: \tInvalidPrice
// expect-formatted: \tInvalidPercent
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn discount(price, percent Decimal) Result[Decimal, DiscountError] {
// expect-formatted: \tif price < 0d {
// expect-formatted: \t\treturn error(InvalidPrice)
// expect-formatted: \t}
// expect-formatted: \tif percent < 0d or percent > 100d {
// expect-formatted: \t\treturn error(InvalidPercent)
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn ok(price * (1d - percent / 100d))
// expect-formatted: }
