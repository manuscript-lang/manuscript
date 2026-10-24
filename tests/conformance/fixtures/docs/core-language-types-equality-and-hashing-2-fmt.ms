# conform: tags=control-flow,formatter,interfaces,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/equality-and-hashing.md:49
type CustomerKey:
    id: Int
    label: String

impl Equal for CustomerKey:
    def equals(other: Equal) -> Bool:
        match other:
            case CustomerKey(value): return self.id == value.id
            case _: return False

impl Hashable for CustomerKey:
    def hash() -> Int: self.id
