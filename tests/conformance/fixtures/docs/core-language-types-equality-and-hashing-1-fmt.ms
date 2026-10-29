# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/equality-and-hashing.md:15
interface Equal:
    fn equals(other: Equal) Bool

interface Hashable:
    fn hash() Int
