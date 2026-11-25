// conform: tags=control-flow,diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_bounds_test.go:61 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n Int) Int!Cause {
	if n < 0 { return ok(9223372036854775807) }
	return ok(n + 1)
}
// expect-error: MS2001 4:22 unknown type Cause; declare it with 'type Cause:' / 'enum Cause:' / 'interface Cause:', declare it as a type parameter, or import it
