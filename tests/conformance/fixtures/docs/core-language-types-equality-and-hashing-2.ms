# conform: tags=control-flow,diagnostics,interfaces,match,records,strings,tier-core
# conform: phase=check
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
