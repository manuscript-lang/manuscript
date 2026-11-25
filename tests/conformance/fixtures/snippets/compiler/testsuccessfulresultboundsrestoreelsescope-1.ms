// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_bounds_test.go:127 TestSuccessfulResultBoundsRestoreElseScope
fn probe(found Int) Int {
	var sum = 0
	var i = 0

	while i < 1000 {
		if fresh := affine(i) {
			sum += fresh
		} else {
			sum += found
		}

		i += 1
	}

	return sum
}
// expect-error: MS2001 9:21 unknown binding affine; declare it with 'affine := ...' before use, define 'fn affine(...) T { ... }', or import it from a module
