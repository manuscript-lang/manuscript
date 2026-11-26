// conform: tags=diagnostics
// conform: phase=check
alias := values.add(1, 2)
size := alias.length()
// expect-error: MS3070 3:17 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 4:15 a constant takes literals, operators, collections, and other constants; compute this value in a function
