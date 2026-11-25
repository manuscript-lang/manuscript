// conform: tags=diagnostics
// conform: phase=check
cell := Cell(0)
bump := cell.bump
// expect-error: MS3070 3:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 4:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
