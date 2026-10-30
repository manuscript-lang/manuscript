# conform: tags=diagnostics,sets,interfaces,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
import Lock from "@std/lock.ms"

type K:
    cell: Lock[Int]

impl Equal for K:
    fn equals(other: K) Bool: return true

impl Hashable for K:
    fn hash() Int: return 1

export fn main() Int:
    let s = Set[K]()
    return 0
