// conform: tags=diagnostics
// conform: phase=check
fn callback[T](r Result[fn(T) Int, Error]) Void => return

fn first(r Result[fn(Int) Int, E1]) Void => callback(r)
// expect-error: MS2001 5:32 unknown type E1; declare it with 'type E1:' / 'enum E1:' / 'interface E1:', declare it as a type parameter, or import it
