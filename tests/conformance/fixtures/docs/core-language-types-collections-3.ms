// conform: tags=diagnostics,lists,numbers,records,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/collections.md:52
nested List[List[Int]] := [[], [1, 2]]
// Rejected: incompatible Int and Float elements.
mixed := [1, 2.0]
// Rejected: no element type can be inferred.
unknown := []
// expect-error: MS3001 6:14 expected Int, found Float (in entry 2 of the literal, whose entries share one type); Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get_or(0)
// expect-error: MS3080 8:12 cannot infer list element type; add an annotation, e.g. xs List[Int] := []
