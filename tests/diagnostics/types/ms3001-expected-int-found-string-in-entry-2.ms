// conform: tags=diagnostics
// conform: phase=check
a := [1, "x"]
// expect-error: MS3001 3:10 expected Int, found String (in entry 2 of the literal, whose entries share one type)
