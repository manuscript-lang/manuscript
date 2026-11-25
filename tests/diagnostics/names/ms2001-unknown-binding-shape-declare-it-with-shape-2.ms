// conform: tags=diagnostics
// conform: phase=check
fn probe() Int {
	shapes := [Shape.Circle(2)]
	return area(shapes.get(2))
}

export fn main() Int {
	return probe()
}
// expect-error: MS2001 4:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 5:12 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
