// conform: tags=decimal,diagnostics,interpolation,strings,tier-core,try-result
// conform: phase=check
// conform: origin=documentation/core-language/errors/propagation.md:12
fn discounted_label(price Decimal, percent Decimal) Result[String, DiscountError] {
	value := discount(price, percent)?
	return ok(f"Discounted price: {value}")
}
// expect-error: MS2001 4:27 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS2001 4:44 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS2001 4:68 unknown type DiscountError; declare it with 'type DiscountError:' / 'enum DiscountError:' / 'interface DiscountError:', declare it as a type parameter, or import it
// expect-error: MS2001 5:14 unknown binding discount; declare it with 'discount := ...' before use, define 'fn discount(...) T { ... }', or import it from a module
