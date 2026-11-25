// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	shapes := [Shape.Circle(2)]
	if area(shapes.get(2, Shape.Tri(7))) != 7 { return 1 }

	return 0
}
// expect-error: MS2001 4:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 5:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
