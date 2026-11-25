// conform: tags=control-flow,diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_bounds_test.go:82 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n Int) Int!Cause {
	if n < 0 { return error(Cause("negative")) }
	return ok(n + 9223372036854775807)
}
// expect-error: MS2001 4:22 unknown type Cause; declare it with 'type Cause:' / 'enum Cause:' / 'interface Cause:', declare it as a type parameter, or import it
// expect-error: MS2001 5:29 unknown binding Cause; declare it with 'Cause := ...' before use, define 'fn Cause(...) T { ... }', or import it from a module
