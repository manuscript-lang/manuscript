// conform: tags=diagnostics
// conform: phase=check
first := 1
value := f(first, first: 2, second: 3)
// expect-error: MS3070 4:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
