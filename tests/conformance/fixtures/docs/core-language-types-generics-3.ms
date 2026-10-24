# conform: tags=diagnostics,generics,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/generics.md:49
type Box[T]:
    value: T

def identity[T](value: T) -> T:
    return value

def same[T: Equal](left: T, right: T) -> Bool:
    return left == right

let box = Box[Int](1)
let exact = identity[Int](1)
let inferred = identity(1)
