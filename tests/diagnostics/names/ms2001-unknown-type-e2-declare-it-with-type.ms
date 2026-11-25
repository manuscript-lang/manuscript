// conform: tags=diagnostics
// conform: phase=check
fn domain[T](r Result[T, E2]) Void => return

fn first() Void => domain(f())
// expect-error: MS2001 3:26 unknown type E2; declare it with 'type E2:' / 'enum E2:' / 'interface E2:', declare it as a type parameter, or import it
// expect-error: MS2001 5:27 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
