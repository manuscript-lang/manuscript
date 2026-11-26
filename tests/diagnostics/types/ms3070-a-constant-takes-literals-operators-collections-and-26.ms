// conform: tags=diagnostics
// conform: phase=check
wrong := true
value := f(wrong, second: 2)
// expect-error: MS3070 4:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
