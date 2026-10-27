# conform: tags=diagnostics,sets,interfaces,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
from "@std/shared.ms" import Shared
type K:
    cell: Shared[Int]
impl Equal for K:
    def equals(other: K) -> Bool: return True
impl Hashable for K:
    def hash() -> Int: return 1
export def main() -> Int:
    let s = Set[K]()
    return 0
