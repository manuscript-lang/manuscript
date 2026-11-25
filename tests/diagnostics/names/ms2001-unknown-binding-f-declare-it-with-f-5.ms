// conform: tags=diagnostics
// conform: phase=check
fn values[T](r List[Result[T, Error]]) Void => return

fn first() Void => values([f()])
// expect-error: MS2001 5:28 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
