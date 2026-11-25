// conform: tags=diagnostics
// conform: phase=check
read := fn(value String = b.freeze()) String => value
// expect-error: MS3070 3:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
