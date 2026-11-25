// conform: tags=diagnostics,lists,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/collections.md:22
values := [1, 2, 3]
empty List[Int] := []
also_empty := List[Int]()
// expect-error: MS3070 6:15 a constant takes literals, operators, collections, and other constants; compute this value in a function
