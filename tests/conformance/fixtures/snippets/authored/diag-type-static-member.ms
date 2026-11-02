# conform: tags=diagnostics,types,tier-core
# conform: phase=check
# conform: origin=bug bash: BigInt.from_int(...) reported an empty case list
import BigInt from "@std/math/math.ms"

export fn main() Int:
    let b = BigInt.from_int(2)
    return b.to_int().get(0)
