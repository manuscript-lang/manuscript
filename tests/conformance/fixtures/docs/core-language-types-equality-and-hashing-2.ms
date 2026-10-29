# conform: tags=control-flow,diagnostics,interfaces,match,records,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/equality-and-hashing.md:49
type CustomerKey:
    id: Int
    label: String

impl Equal for CustomerKey:
    fn equals(other: CustomerKey) Bool:
        return self.id == other.id

impl Hashable for CustomerKey:
    fn hash() Int: self.id
