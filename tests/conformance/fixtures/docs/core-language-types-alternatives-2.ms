// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/alternatives.md:26
payment := Payment.Paid("receipt-42")
declined: Payment = Declined("Card rejected")
