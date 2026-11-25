// conform: tags=diagnostics
// conform: phase=check
big := from_int(1)
// expect-error: MS3070 3:8 a constant takes literals, operators, collections, and other constants; compute this value in a function
