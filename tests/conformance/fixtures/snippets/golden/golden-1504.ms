// conform: tags=diagnostics
// conform: phase=check
fn unknown(s Shape) Int => return area(s)

export fn main() Int {
	shapes := [Shape.Circle(2)]
	good := area(shapes.get(0))
	return unknown(Shape.Square(9223372036854775807))
}
// expect-error: MS2001 3:14 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 3:35 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 6:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 7:13 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 8:20 unknown binding Shape; did you mean 'shapes'?
// expect-fix: 8:20-8:25 "shapes"
