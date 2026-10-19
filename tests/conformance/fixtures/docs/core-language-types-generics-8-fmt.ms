# conform: tags=formatter,generics,parser,records,sets,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/generics.md:130
# Rejected at declaration: missing Equal bound.
fn unchecked_same[T](left: T, right: T) Bool:
    return left == right

type Keys[T: Hashable]:
    values: Set[T]
