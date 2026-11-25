// conform: tags=diagnostics
// conform: phase=check
fn failed[T]() Result[T, Failure] => error(Failure("empty"))

fn first() Result[Int, Error] => failed()
// expect-error: MS2001 3:26 unknown type Failure; declare it with 'type Failure:' / 'enum Failure:' / 'interface Failure:', declare it as a type parameter, or import it
// expect-error: MS2001 3:44 unknown binding Failure; declare it with 'Failure := ...' before use, define 'fn Failure(...) T { ... }', or import it from a module
