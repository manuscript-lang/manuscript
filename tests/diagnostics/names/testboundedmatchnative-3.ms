// conform: tags=diagnostics,faults,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/match_bounds_test.go:67 TestBoundedMatchNative
fn unknown(s Shape) Int => return area(s)

export fn main() Int {
	shapes := [Shape.Circle(2)]
	good := area(shapes.get(0))
	return unknown(Shape.Square(9223372036854775807))
}
// expect-error: MS2001 4:14 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 4:35 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 7:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 8:13 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 9:20 unknown binding Shape; did you mean 'shapes'?
// expect-fix: 9:20-9:25 "shapes"
