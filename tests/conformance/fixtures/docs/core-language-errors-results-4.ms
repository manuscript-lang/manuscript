// conform: tags=decimal,diagnostics,modules,optional,stdlib-errors,tier-stdlib,try-result
// conform: phase=check
// conform: origin=documentation/core-language/errors/results.md:75

fn successful_price(outcome Result[Decimal, Error]) Decimal? {
	return outcome.to_optional()
}
// expect-error: MS2001 5:36 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 5:1-5:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS2001 5:53 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 5:1-5:1 "import Decimal from \"@std/math/decimal.ms\"\n"
