// conform: tags=formatter,generics,lists,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/generics.md:115
fn count[T](values: List[T]) Int:
    return 0

known := count[Int]([])
// Rejected: the empty list does not determine T.
unknown := count([])
