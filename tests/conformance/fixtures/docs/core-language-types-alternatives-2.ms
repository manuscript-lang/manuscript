# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/alternatives.md:26
let payment = Payment.Paid("receipt-42")
let declined: Payment = Declined("Card rejected")
