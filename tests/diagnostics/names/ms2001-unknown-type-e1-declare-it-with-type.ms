// conform: tags=diagnostics
// conform: phase=check
fn bounded[T Equal](r Result[T, Error]) Void => return

fn first(r Result[Error, E1]) Void => bounded(r)
// expect-error: MS2001 5:26 unknown type E1; declare it with 'type E1:' / 'enum E1:' / 'interface E1:', declare it as a type parameter, or import it
