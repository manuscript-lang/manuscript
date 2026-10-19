# conform: tags=alternatives,formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/alternatives.md:10
type Payment:
    case Paid(receipt: String)
    case Declined(reason: String)
    case Pending(reference: String)
