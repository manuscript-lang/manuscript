// conform: tags=control-flow,diagnostics,faults,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/match_bounds_test.go:171 TestBoundedMatchSignedAndEndpointNative
export fn main() Int {
	shapes := [Shape.Circle(2)]
	if area(shapes.get(2, Shape.Tri(7))) != 7 { return 1 }

	return 0
}
// expect-error: MS2001 5:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 6:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
