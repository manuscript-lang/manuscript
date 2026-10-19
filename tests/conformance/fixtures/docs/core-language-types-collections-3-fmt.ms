# conform: tags=formatter,lists,numbers,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/collections.md:52
let nested: List[List[Int]] = [[], [1, 2]]
# Rejected: incompatible Int and Float elements.
let mixed = [1, 2.0]
# Rejected: no element type can be inferred.
let unknown = []
