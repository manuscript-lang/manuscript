// conform: tags=diagnostics
// conform: phase=check
cell := Cell(0)
read := fn() Int => cell.total
// expect-error: MS3070 3:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 4:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
