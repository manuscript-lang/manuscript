// conform: tags=diagnostics,faults,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/match_bounds_test.go:83 TestBoundedMatchUnionAndCaseLimits
fn other() Int {
	shapes := [Shape.Square(9223372036854775807)]
	return area(shapes.get(0))
}
// expect-error: MS2001 5:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 6:12 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
