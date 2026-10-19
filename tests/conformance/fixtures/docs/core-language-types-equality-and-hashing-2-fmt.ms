# conform: tags=control-flow,formatter,interfaces,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/equality-and-hashing.md:49
type CustomerKey:
    id: Int
    label: String

impl Equal for CustomerKey:
    fn equals(other: Equal) Bool:
        match other:
            CustomerKey(value): return self.id == value.id
            _: return false

impl Hashable for CustomerKey:
    fn hash() Int: self.id
