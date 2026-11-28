// conform: tags=diagnostics
// conform: phase=check
fn both[T, E Error](cause E, r Result[T, E]) Void => return

fn first(cause Error) Void => both(cause: cause, r: f())
// expect-error: MS3000 3:14 a bound must be an interface; write [T SomeInterface], where SomeInterface is declared with 'interface'
// expect-error: MS2001 5:53 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
