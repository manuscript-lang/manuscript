// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	shapes := [
		Shape.Square(3037000499),
		Shape.Square(-3037000499),
		Shape.Circle(-3037000499),
	]
	if area(shapes.get(0)) != 9223372030926249001 { return 1 }
	if area(shapes.get(1)) != 9223372030926249001 { return 2 }
	if area(shapes.get(2)) != -9111001497 { return 3 }

	return 0
}
// expect-error: MS2001 5:9 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 6:9 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 7:9 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 9:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 10:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 11:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
