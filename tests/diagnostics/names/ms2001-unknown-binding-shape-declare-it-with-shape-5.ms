// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	shapes := [Shape.Circle(-3), Shape.Square(4), Shape.Tri(-1)]
	if area(shapes.get(0)) != 4 { return 1 }
	if area(shapes.get(1)) != -8 { return 2 }

	return 0
}
// expect-error: MS2001 4:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 4:34 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 4:51 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 5:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 6:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
