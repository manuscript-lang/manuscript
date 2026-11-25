// conform: tags=diagnostics
// conform: phase=check
fn caller() Result[Int, Error] => operation()
// expect-error: MS2001 3:35 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
