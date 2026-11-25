// conform: tags=diagnostics
// conform: phase=check
values := [1, 2, 3]
read := fn() Int => values.length()
// expect-error: MS3070 4:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
