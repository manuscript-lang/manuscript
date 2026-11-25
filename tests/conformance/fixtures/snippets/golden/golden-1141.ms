// conform: tags=diagnostics
// conform: phase=check
m := Map[String, Int]()
s := Set[Int]()
// expect-error: MS3070 3:6 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 4:6 a constant takes literals, operators, collections, and other constants; compute this value in a function
