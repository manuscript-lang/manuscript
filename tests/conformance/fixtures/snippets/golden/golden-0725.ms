// conform: tags=diagnostics
// conform: phase=check
type Holder[T] {
	r Result[T, Error]
}

fn first() Holder[Int] => Holder(f())
// expect-error: MS2001 7:34 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
