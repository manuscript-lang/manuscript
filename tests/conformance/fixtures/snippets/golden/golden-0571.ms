// conform: tags=diagnostics
// conform: phase=check
callback := fn() Int => values.length()
size := callback()
// expect-error: MS3070 3:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 4:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
