// conform: tags=diagnostics,lists,numbers,records,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/collections.md:52
nested: List[List[Int]] = [[], [1, 2]]
// Rejected: incompatible Int and Float elements.
mixed := [1, 2.0]
// Rejected: no element type can be inferred.
unknown := []
