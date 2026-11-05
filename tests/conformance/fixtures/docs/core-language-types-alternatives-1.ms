// conform: tags=alternatives,diagnostics,records,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/alternatives.md:10
enum Payment:
    case Paid(receipt: String)
    case Declined(reason: String)
    case Pending(reference: String)
