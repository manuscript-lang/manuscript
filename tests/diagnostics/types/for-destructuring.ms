// conform: tags=testing,tier-core
// conform: phase=check
// A destructuring `for` pattern follows `let` rules: the element must match the
// pattern's shape, and the pattern's names are scoped to the body.
export fn main() Int {
	numbers := [1, 2, 3]

	for [a, b] in numbers {  // error: positional binding requires a list
		print(a)  // error: unknown binding a
	}

	for {x} in [[1, 2]] {  // error: record binding requires a record
		print(x)  // error: unknown binding x
	}

	for [a, b] in [[1, 2]] {
		print(a + b)
	}

	print(b)  // error: unknown binding b
	return 0
}
// expect-error: MS3000 8:9 positional binding requires a list; use [a, b] patterns only with List values
// expect-error: MS2001 9:15 unknown binding a; declare it with 'a := ...' before use, define 'fn a(...) T { ... }', or import it from a module
// expect-error: MS3000 12:9 type binding requires a type; destructure only type values, or bind the whole value to one name
// expect-error: MS2001 13:15 unknown binding x; declare it with 'x := ...' before use, define 'fn x(...) T { ... }', or import it from a module
// expect-error: MS2001 20:11 unknown binding b; declare it with 'b := ...' before use, define 'fn b(...) T { ... }', or import it from a module
