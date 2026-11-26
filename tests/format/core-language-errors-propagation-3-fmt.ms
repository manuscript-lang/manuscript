// conform: tags=decimal,formatter,parser,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=documentation/core-language/errors/propagation.md:41
fn discounted_label(price Decimal, percent Decimal) Result[String, DiscountError] {
	return ok(discount(price, percent)? | label)
}
// expect-format: rewritten
// expect-formatted: fn discounted_label(price, percent Decimal) Result[String, DiscountError] {
// expect-formatted: \treturn ok(discount(price, percent)? | label)
// expect-formatted: }
