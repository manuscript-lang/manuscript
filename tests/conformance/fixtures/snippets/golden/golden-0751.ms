// conform: tags=diagnostics
// conform: phase=check
fn probe(found Int) Int {
	var sum = 0
	var i = 0

	while i < 1000 {
		if found := affine(i) {
			sum += found
		} else {
			sum += found
		}

		i += 1
	}

	return sum
}
// expect-error: MS2001 8:21 unknown binding affine; declare it with 'affine := ...' before use, define 'fn affine(...) T { ... }', or import it from a module
// expect-error: MS3000 8:12 binding found shadows an outer binding of the same name; rename one of them, or assign to the outer 'var'
