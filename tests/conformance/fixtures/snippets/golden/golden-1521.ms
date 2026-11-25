// conform: tags=diagnostics
// conform: phase=check
update := bytes.with_value
// expect-error: MS3070 3:17 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS2001 3:11 unknown binding bytes; declare it with 'bytes := ...' before use, define 'fn bytes(...) T { ... }', or import it from a module
