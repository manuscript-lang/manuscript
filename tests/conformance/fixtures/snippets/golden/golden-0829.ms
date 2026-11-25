// conform: tags=diagnostics
// conform: phase=check
fn work() Int => return step % d(1)
// expect-error: MS2001 3:25 unknown binding step; declare it with 'step := ...' before use, define 'fn step(...) T { ... }', or import it from a module
// expect-error: MS2001 3:32 unknown binding d; declare it with 'd := ...' before use, define 'fn d(...) T { ... }', or import it from a module
