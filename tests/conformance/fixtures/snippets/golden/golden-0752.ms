// conform: tags=diagnostics
// conform: phase=check
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
// expect-error: MS2001 8:21 unknown binding wrapped; declare it with 'wrapped := ...' before use, define 'fn wrapped(...) T { ... }', or import it from a module
