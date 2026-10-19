# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/alternatives.md:26
let payment = Payment.Paid("receipt-42")
let declined: Payment = Declined("Card rejected")
