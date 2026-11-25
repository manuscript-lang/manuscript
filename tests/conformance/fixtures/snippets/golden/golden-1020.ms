// conform: tags=diagnostics
// conform: phase=check
values := [0]
operation := () => values.append(1)
_result := operation()
// expect-error: MS3070 4:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 5:12 a constant takes literals, operators, collections, and other constants; compute this value in a function
