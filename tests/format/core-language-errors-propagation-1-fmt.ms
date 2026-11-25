// conform: tags=decimal,formatter,interpolation,parser,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=documentation/core-language/errors/propagation.md:12
fn discounted_label(price Decimal, percent Decimal) Result[String, DiscountError] {
	value := discount(price, percent)?
	return ok(f"Discounted price: {value}")
}
// expect-format: rewritten
// expect-formatted: fn discounted_label(price, percent Decimal) Result[String, DiscountError] {
// expect-formatted: \tvalue := discount(price, percent)?
// expect-formatted: \treturn ok(f"Discounted price: {value}")
// expect-formatted: }
