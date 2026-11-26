// conform: tags=diagnostics
// conform: phase=check
fn fail() Int {
	return 1 / 0
}

export fn main() Int {
	shapes := [Shape.Circle(2)]
	return area(shapes.get(fail() * 0))
}
// expect-error: MS3000 4:14 division by zero always faults; guard the divisor or use a nonzero constant
// expect-error: MS2001 8:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 9:12 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
