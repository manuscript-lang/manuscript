// conform: tags=diagnostics
// conform: phase=check
fn probe() Int {
	shapes := [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
	var sum = 0
	var i = 0

	while i < 321 {
		sum += area(shapes.get(i % 3))
		i += 1
	}

	return sum
}
// expect-error: MS2001 4:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 4:33 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 4:50 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 9:16 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
