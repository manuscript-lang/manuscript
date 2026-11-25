// conform: tags=diagnostics
// conform: phase=check
fn nested[T](r Result[Result[T, Error], Error]) Void => return

fn first(r Result[Result[Int, E1], E2]) Void => nested(r)
// expect-error: MS2001 5:31 unknown type E1; declare it with 'type E1:' / 'enum E1:' / 'interface E1:', declare it as a type parameter, or import it
// expect-error: MS2001 5:36 unknown type E2; declare it with 'type E2:' / 'enum E2:' / 'interface E2:', declare it as a type parameter, or import it
