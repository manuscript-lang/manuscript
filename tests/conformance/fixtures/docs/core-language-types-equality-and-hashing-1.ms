# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/equality-and-hashing.md:15
interface Equal:
    fn equals(other: Equal) Bool

interface Hashable:
    fn hash() Int
