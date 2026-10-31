# conform: tags=formatter,generics,optional,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/generics.md:74
type Pair[A, B = A]:
    first: A
    second: B

fn parse[T = String](text: String) T?:
    return none

let same: Pair[Int] = Pair[Int](1, 2)  # Pair[Int, Int]
let mixed = Pair[Int, String](1, "x")
