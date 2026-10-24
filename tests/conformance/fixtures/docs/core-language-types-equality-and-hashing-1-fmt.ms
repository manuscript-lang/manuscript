# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/equality-and-hashing.md:15
interface Equal:
    def equals(other: Equal) -> Bool

interface Hashable:
    def hash() -> Int
