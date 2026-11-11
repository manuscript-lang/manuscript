// conform: tags=control-flow,formatter,interfaces,match,parser,records,strings,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/equality-and-hashing.md:49
type CustomerKey:
    id: Int
    label: String

fn CustomerKey.equals(other: CustomerKey) Bool:
    return self.id == other.id

fn CustomerKey.hash() Int: self.id
