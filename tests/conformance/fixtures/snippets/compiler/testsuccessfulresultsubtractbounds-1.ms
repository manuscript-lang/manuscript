// conform: tags=control-flow,diagnostics,mutation,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/result_bounds_test.go:148 TestSuccessfulResultSubtractBounds
fn probe() Int {
	var sum = 0
	var i = 0

	while i < 1000 {
		if found := wrapped(i) {
			sum += found
		}
		i += 1
	}

	return sum
}
// expect-error: MS2001 9:21 unknown binding wrapped; declare it with 'wrapped := ...' before use, define 'fn wrapped(...) T { ... }', or import it from a module
