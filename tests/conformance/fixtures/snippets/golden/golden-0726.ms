// conform: tags=diagnostics
// conform: phase=check
enum Wrapped[T] {
	value(r Result[T, Error])
}

fn first() Wrapped[Int] => Wrapped.value(f())
// expect-error: MS2001 7:42 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
