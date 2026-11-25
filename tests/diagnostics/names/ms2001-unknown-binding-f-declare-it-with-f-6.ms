// conform: tags=diagnostics
// conform: phase=check
fn twice[T](r Result[T, Error]??) Void => return

fn first() Void => twice(f())
// expect-error: MS2001 5:26 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
