# conform: tags=diagnostics,interfaces,tier-core,try-result
# conform: phase=check
# conform: origin=documentation/core-language/types/contracts.md:10
interface Payments:
    fn charge(amount: Money) Result[Receipt, PaymentError]
