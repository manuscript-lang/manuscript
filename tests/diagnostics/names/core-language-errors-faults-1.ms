// conform: tags=control-flow,decimal,diagnostics,faults,modules,stdlib-faults,tier-stdlib
// conform: phase=check
// conform: origin=documentation/core-language/errors/faults.md:14
import panic from "@std/core.ms"

fn discount_validated(price Decimal, percent Decimal) Decimal {
	if price <= 0d {
		return panic("Price must be positive")
	}
	if percent <= 0d or percent >= 100d {
		return panic("Percent must be positive and below 100")
	}

	return price * (1d - percent / 100d)
}
// expect-error: MS2001 6:29 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS2001 6:46 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS2001 6:55 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
