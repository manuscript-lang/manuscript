# conform: tags=diagnostics,generics,records,sets,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/generics.md:130
# Rejected at declaration: missing Equal bound.
def unchecked_same[T](left: T, right: T) -> Bool:
    return left == right

type Keys[T: Hashable]:
    values: Set[T]
