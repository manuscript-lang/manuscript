// conform: tags=control-flow,decimal,diagnostics,interpolation,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/errors/results.md:40
fn discount_message(price Decimal, percent Decimal) String {
	if value := discount(price, percent) {
		return f"Discounted price: {value}"
	}
	return "Discount could not be calculated."
}
// expect-error: MS2001 4:27 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS2001 4:44 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS2001 5:17 unknown binding discount; declare it with 'discount := ...' before use, define 'fn discount(...) T { ... }', or import it from a module
