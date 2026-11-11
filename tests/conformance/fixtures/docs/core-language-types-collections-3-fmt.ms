// conform: tags=formatter,lists,numbers,parser,records,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/collections.md:52
nested: List[List[Int]] := [[], [1, 2]]
// Rejected: incompatible Int and Float elements.
mixed := [1, 2.0]
// Rejected: no element type can be inferred.
unknown := []
