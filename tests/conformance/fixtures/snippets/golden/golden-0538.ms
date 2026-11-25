// conform: tags=diagnostics
// conform: phase=check
values := [1, 2, 3]
alias := values.append(4)
// expect-error: MS3070 4:17 a constant takes literals, operators, collections, and other constants; compute this value in a function
