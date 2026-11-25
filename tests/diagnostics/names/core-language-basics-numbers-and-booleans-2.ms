// conform: tags=decimal,diagnostics,formatter,numbers,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/basics/numbers-and-booleans.md:36
fn literals() Void {
	smallest Int := -9223372036854775808
	exponent Float := 1e3
	precise Decimal := 1e3d

	// Rejected: an Int token does not become Float from context.
	mismatch Float := 1
}
// expect-error: MS2001 7:13 unknown type Decimal; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
// expect-error: MS3001 10:23 expected Float, found Int (in the initializer of 'mismatch'); Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value
// expect-fix: 10:23-10:24 "1.0"
