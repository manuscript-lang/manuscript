// conform: tags=control-flow,diagnostics,formatter,match,optional,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_bounds_test.go:73 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n Int) Int!Cause {
	if n < 0 {
		return error(
			Cause(
				match n {
					value => {
						return ok(9223372036854775807)
					} null => "negative"
				}
			)
		)
	}
	return ok(n + 1)
}
// expect-error: MS2001 4:22 unknown type Cause; declare it with 'type Cause:' / 'enum Cause:' / 'interface Cause:', declare it as a type parameter, or import it
// expect-error: MS2001 7:13 unknown binding Cause; declare it with 'Cause := ...' before use, define 'fn Cause(...) T { ... }', or import it from a module
