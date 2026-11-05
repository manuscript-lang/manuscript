// conform: tags=alternatives,diagnostics,records,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/alternatives.md:10
enum Payment:
    Paid(receipt: String)
    Declined(reason: String)
    Pending(reference: String)
