// conform: tags=diagnostics,faults,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/match_bounds_test.go:73 TestBoundedMatchNative
fn fail() Int {
	return 1 / "".length()
}

export fn main() Int {
	shapes := [Shape.Circle(2)]
	return area(shapes.get(fail() * 0))
}
// expect-error: MS2001 9:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 10:12 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
