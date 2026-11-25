// conform: tags=control-flow,diagnostics,faults,mutation,tier-core
// conform: phase=check
// conform: origin=tests/e2e/match_bounds_test.go:79 TestBoundedMatchNative
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
// expect-error: MS2001 5:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 10:16 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
