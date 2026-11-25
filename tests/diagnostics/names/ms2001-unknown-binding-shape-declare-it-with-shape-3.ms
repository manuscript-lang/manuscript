// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	shapes := [Shape.Circle(2)]
	var sum = 9223372036854775807
	var i = 0

	while i < 2 {
		sum += area(shapes.get(0))
		i += 1
	}

	return sum
}
// expect-error: MS2001 4:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 9:16 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
