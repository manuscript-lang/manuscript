// conform: tags=diagnostics
// conform: phase=check
cell := Cell(0)
alias := cell
// expect-error: MS3070 3:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
