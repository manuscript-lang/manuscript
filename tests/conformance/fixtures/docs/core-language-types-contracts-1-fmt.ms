# conform: tags=formatter,interfaces,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/types/contracts.md:10
interface Payments:
    fn charge(amount: Money) Result[Receipt, PaymentError]
