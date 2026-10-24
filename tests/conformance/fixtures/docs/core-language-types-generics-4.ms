# conform: tags=diagnostics,generics,optional,records,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/generics.md:74
type Pair[A, B = A]:
    first: A
    second: B

def parse[T = String](text: String) -> Optional[T]:
    return none

let same: Pair[Int] = Pair[Int](1, 2)  # Pair[Int, Int]
let mixed = Pair[Int, String](1, "x")
