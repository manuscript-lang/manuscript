// conform: tags=control-flow,diagnostics,faults,formatter,interfaces,modules,mutation,records,scope-cleanup,stdlib-cleanup,tier-stdlib
// conform: phase=check,parse
// conform: origin=tests/e2e/match_bounds_test.go:32 TestBoundedMatchNative
import Closeable from "@std/core.ms"

type Count {
	total Int
}

type Watch {
	count Count
}

fn move Watch.close() Void! {
	self.count.total += 10
}

fn next(count Count) Int {
	_watch := Watch(count)
	count.total += 1
	return 0
}

fn unknown(s Shape) Int => return area(s)

export fn main() Int {
	shapes := [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
	count := Count(0)
	if area(shapes.get(next(count) * 0)) != 6 { return 1 }
	if count.total != 11 { return 2 }
	if area(shapes.get(next(count))) != 6 { return 5 }
	if count.total != 22 { return 6 }
	if unknown(Shape.Tri(4)) != 4 { return 3 }

	var sum = 0
	var i = 0

	while i < 321 {
		sum += area(shapes.get(i % 3))
		i += 1
	}

	if sum != 2033 { return 4 }

	return 0
}
// expect-error: MS2001 24:14 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 24:35 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 27:16 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 27:33 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 27:50 unknown binding Shape; declare it with 'Shape := ...' before use, define 'fn Shape(...) T { ... }', or import it from a module
// expect-error: MS2001 29:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 31:8 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
// expect-error: MS2001 33:16 unknown binding Shape; did you mean 'shapes'?
// expect-fix: 33:16-33:21 "shapes"
// expect-error: MS2001 39:16 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
