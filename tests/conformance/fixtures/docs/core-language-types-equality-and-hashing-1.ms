# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/equality-and-hashing.md:15
interface Equal:
    def equals(other: Equal) -> Bool

interface Hashable:
    def hash() -> Int
