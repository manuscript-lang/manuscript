// conform: tags=diagnostics,faults,tier-core
// conform: phase=check
// conform: origin=tests/e2e/match_bounds_test.go:176 TestBoundedMatchSignedAndEndpointNative
export fn main() Int {
	shapes := [Shape.Square(3037000500)]
	return area(shapes.get(0))
}
// expect-error: MS2001 5:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 6:12 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
