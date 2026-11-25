// conform: tags=diagnostics
// conform: phase=check
names := [1].map((item) => missing)
next := names.map[String]
// expect-error: MS3070 3:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 4:15 a constant takes literals, operators, collections, and other constants; compute this value in a function
