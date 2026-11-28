// conform: tags=diagnostics
// conform: phase=check
fn same[T, E Error](first Result[T, E], second Result[T, E]) Void => return

fn first() Void => same(first: f(), second: other())
// expect-error: MS3000 3:14 a bound must be an interface; write [T SomeInterface], where SomeInterface is declared with 'interface'
// expect-error: MS2001 5:32 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
// expect-error: MS2001 5:45 unknown binding other; declare it with 'other := ...' before use, define 'fn other(...) T { ... }', or import it from a module
