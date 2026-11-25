// conform: tags=diagnostics
// conform: phase=check
offset := 7
values := [1, 2].map((outer) => [3, 4].map((inner) => outer + inner + offset))
// expect-error: MS3070 4:18 a constant takes literals, operators, collections, and other constants; compute this value in a function
